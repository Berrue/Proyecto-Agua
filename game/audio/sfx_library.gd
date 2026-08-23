extends Node

## AUTOLOAD `SfxLibrary` — fabrica de sonidos 100% procedurales.
##
## No tenemos assets de audio ni artista de sonido, y no hacen falta: todos los
## sonidos de la caña se SINTETIZAN aqui al arrancar (~4 s de audio total,
## generacion instantanea) como AudioStreamWAV de 16 bits a 22050 Hz. Licencia
## limpia garantizada: lo fabricamos nosotros.
##
## Regla de la critica: NADA de AudioStreamGenerator en vivo desde GDScript (los
## docs lo desaconsejan — cracking). Todo pre-generado; los trenes de clicks se
## disparan por acumulador, y por encima de ~25 Hz se cruza a un LOOP pre-cocido
## cuyo pitch mapea la tasa (la fusion psicoacustica se hornea, no se espera del
## scheduler).
##
## Cada one-shot pasa por play_varied(): pitch ±6% y volumen -2..0 dB, sin
## repetir la variante anterior — o suena a metralleta de alarma.

const RATE := 22050

## Ritmo del tren de clicks del freno por tension normalizada. Silencio bajo
## 0.3: el silencio ES la señal de "vas bien" (regla Sea of Thieves).
static func click_rate_for(tension_norm: float) -> float:
	var t: float = clampf(tension_norm, 0.0, 1.0)
	if t < 0.3:
		return 0.0
	return 22.0 * pow(t, 1.5)


var reel_clicks: Array[AudioStreamWAV] = []
var reel_buzz: AudioStreamWAV ## loop de 40 Hz; pitch_scale = rate/40
var creak_pulses: Array[AudioStreamWAV] = []
var plip: AudioStreamWAV ## toque falso: chirp ASCENDENTE agudo
var chomp: AudioStreamWAV ## mordisco real: grave, chirp DESCENDENTE
var splashes: Array[AudioStreamWAV] = []
var snap: AudioStreamWAV ## crack + twang Karplus-Strong + thump
var thud: AudioStreamWAV ## pez contra la cubierta
var lap: AudioStreamWAV ## boya en reposo
var jingles: Array[AudioStreamWAV] = [] ## captura: comun/raro/epico

var _last_variant: Dictionary = {}


func _ready() -> void:
	_setup_buses()

	for i in 5:
		reel_clicks.append(_make_click(2500.0 + 300.0 * i, 750.0 + 40.0 * i))
	reel_buzz = _make_buzz_loop()
	for i in 4:
		creak_pulses.append(_make_creak_pulse(1.0 + 0.08 * i))
	plip = _make_plip()
	chomp = _make_chomp()
	for i in 3:
		splashes.append(_make_splash(i * 7 + 1))
	snap = _make_snap()
	thud = _make_thud()
	lap = _make_lap()
	jingles = [_make_jingle(3), _make_jingle(4), _make_jingle(5)]


## Crea buses si faltan: Master(limiter) <- Reel, SFX. Idempotente.
func _setup_buses() -> void:
	for bus_name in ["Reel", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	if AudioServer.get_bus_effect_count(0) == 0:
		AudioServer.add_bus_effect(0, AudioEffectHardLimiter.new())


## Dispara un one-shot con variacion (pitch ±6%, volumen -2..0 dB) sobre una
## playback polifonica, vetando la variante anterior del mismo grupo.
func play_varied(playback: AudioStreamPlaybackPolyphonic, pool: Array[AudioStreamWAV],
		group: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if playback == null or pool.is_empty():
		return
	var idx: int = randi() % pool.size()
	if pool.size() > 1 and idx == int(_last_variant.get(group, -1)):
		idx = (idx + 1) % pool.size()
	_last_variant[group] = idx
	playback.play_stream(pool[idx], 0.0,
		volume_db + randf_range(-2.0, 0.0),
		pitch * randf_range(0.94, 1.06))


func play_one(playback: AudioStreamPlaybackPolyphonic, stream: AudioStreamWAV,
		volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if playback == null or stream == null:
		return
	playback.play_stream(stream, 0.0, volume_db, pitch * randf_range(0.96, 1.04))


# =============================================================================
#  Sintesis — helpers
# =============================================================================

func _to_wav(frames: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(frames.size() * 2)
	for i in frames.size():
		bytes.encode_s16(i * 2, clampi(int(frames[i] * 32767.0), -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	return wav


## Seno con barrido exponencial de frecuencia y envolvente ataque/decay.
func _sweep(f0: float, f1: float, dur: float, tau: float, amp: float,
		attack: float = 0.001) -> PackedFloat32Array:
	var n: int = int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase: float = 0.0
	for i in n:
		var t: float = float(i) / RATE
		var f: float = f0 * pow(f1 / maxf(f0, 1.0), t / dur)
		phase += TAU * f / RATE
		out[i] = sin(phase) * minf(t / attack, 1.0) * exp(-t / tau) * amp
	return out


## Ruido blanco modulado por un seno portador (aproxima un bandpass barato).
func _noise_ring(cf: float, dur: float, tau: float, amp: float,
		seed_val: int = 1) -> PackedFloat32Array:
	var n: int = int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var phase: float = 0.0
	for i in n:
		var t: float = float(i) / RATE
		phase += TAU * cf / RATE
		out[i] = rng.randf_range(-1.0, 1.0) * sin(phase) * exp(-t / tau) * amp
	return out


func _mix(dst: PackedFloat32Array, src: PackedFloat32Array, at_seconds: float = 0.0) -> void:
	var off: int = int(at_seconds * RATE)
	var need: int = off + src.size()
	if need > dst.size():
		dst.resize(need)
	for i in src.size():
		dst[off + i] += src[i]


# =============================================================================
#  Recetas (del plan de investigacion, con las correcciones del critico)
# =============================================================================

## Click del freno del carrete: transiente de ruido + cuerpo de seno, 15 ms.
func _make_click(noise_cf: float, body_f: float) -> AudioStreamWAV:
	var out := _noise_ring(noise_cf, 0.004, 0.0015, 0.7, int(noise_cf))
	_mix(out, _sweep(body_f, body_f * 0.92, 0.012, 0.009, 0.3))
	return _to_wav(out)


## Tren de 40 Hz horneado en loop: la fusion en "zing" no se le pide al
## scheduler de frames (correccion del critico), se pre-cocina y se pitchea.
func _make_buzz_loop() -> AudioStreamWAV:
	var dur: float = 0.5
	var out := PackedFloat32Array()
	out.resize(int(dur * RATE))
	var step: float = 1.0 / 40.0
	var t: float = 0.0
	var k: int = 0
	while t < dur - 0.016:
		var click := _noise_ring(2600.0 + 200.0 * (k % 3), 0.004, 0.0015, 0.5, 17 + k)
		_mix(out, click, t)
		_mix(out, _sweep(760.0, 700.0, 0.012, 0.008, 0.22), t)
		t += step
		k += 1
	var wav := _to_wav(out)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = out.size()
	return wav


## Pulso de crujido stick-slip del sedal (nylon): 3 bandas ring-mod, 10 ms.
## El pitch-bend por tension se aplica en pitch_scale al dispararlo.
func _make_creak_pulse(f_scale: float) -> AudioStreamWAV:
	var out := _noise_ring(900.0 * f_scale, 0.010, 0.004, 0.5, int(f_scale * 100))
	_mix(out, _noise_ring(1600.0 * f_scale, 0.010, 0.003, 0.35, int(f_scale * 200)))
	_mix(out, _noise_ring(2600.0 * f_scale, 0.008, 0.002, 0.25, int(f_scale * 300)))
	return _to_wav(out)


## Toque falso: chirp ASCENDENTE agudo ("cosa pequeña"), inconfundible del chomp.
func _make_plip() -> AudioStreamWAV:
	var out := _noise_ring(3000.0, 0.006, 0.003, 0.15, 5) # el contacto
	_mix(out, _sweep(1000.0, 1400.0, 0.06, 0.05, 0.5), 0.004)
	return _to_wav(out)


## Mordisco real: polaridad OPUESTA al plip — grave y descendente. Tres capas.
func _make_chomp() -> AudioStreamWAV:
	var out := _sweep(160.0, 55.0, 0.22, 0.09, 0.9) # golpe kick-drum
	_mix(out, _sweep(260.0, 90.0, 0.14, 0.08, 0.4)) # burbuja grande
	_mix(out, _sweep(130.0, 45.0, 0.14, 0.08, 0.3)) # su octava
	_mix(out, _noise_ring(800.0, 0.03, 0.012, 0.35, 9)) # burst de agua
	return _to_wav(out)


## Splash: cuerpo de ruido con barrido descendente + espuma de mini-chirps a
## tiempos aleatorios (sin paneo horneado: el player 3D lo colapsaria).
func _make_splash(seed_val: int) -> AudioStreamWAV:
	var out := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	# Cuerpo: barrido de la banda 2500 -> 700 aproximado en tres tramos.
	_mix(out, _noise_ring(2200.0, 0.12, 0.06, 0.5, seed_val))
	_mix(out, _noise_ring(1300.0, 0.18, 0.09, 0.45, seed_val + 1), 0.06)
	_mix(out, _noise_ring(750.0, 0.25, 0.12, 0.4, seed_val + 2), 0.14)
	_mix(out, _sweep(120.0, 90.0, 0.06, 0.04, 0.3)) # golpe sordo inicial
	# Espuma: 6-9 gotitas en los primeros 300 ms.
	for _i in rng.randi_range(6, 9):
		_mix(out, _sweep(rng.randf_range(500.0, 1100.0), rng.randf_range(1200.0, 1700.0),
			0.05, 0.04, 0.18), rng.randf_range(0.02, 0.3))
	return _to_wav(out)


## Rotura: crack seco + twang Karplus-Strong (F0 fija 180 Hz, feedback 0.985 —
## el pitch-drop es polish v2 segun el critico) + thump grave.
func _make_snap() -> AudioStreamWAV:
	var out := PackedFloat32Array()
	# Crack: impulso + ruido agudo brevisimo.
	var crack := PackedFloat32Array()
	crack.resize(int(0.017 * RATE))
	crack[0] = 1.0
	crack[1] = -0.8
	_mix(out, crack)
	_mix(out, _noise_ring(3500.0, 0.015, 0.004, 0.8, 13), 0.001)
	# Twang KS.
	var d: int = int(RATE / 180.0)
	var n: int = int(0.4 * RATE)
	var buf := PackedFloat32Array()
	buf.resize(d)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in d:
		buf[i] = rng.randf_range(-0.6, 0.6)
	var tw := PackedFloat32Array()
	tw.resize(n)
	for i in n:
		var a: float = buf[i % d]
		var b: float = buf[(i + 1) % d]
		tw[i] = a
		buf[i % d] = (a + b) * 0.5 * 0.985
	_mix(out, tw, 0.008)
	_mix(out, _sweep(85.0, 60.0, 0.1, 0.06, 0.5), 0.002) # thump
	return _to_wav(out)


## Pez contra la cubierta: pitch drop grave. El pitch_scale al dispararlo baja
## con el peso (pez gordo = thud mas grave).
func _make_thud() -> AudioStreamWAV:
	var out := _noise_ring(600.0, 0.01, 0.005, 0.3, 21)
	_mix(out, _sweep(110.0, 50.0, 0.15, 0.07, 0.8))
	return _to_wav(out)


## Lap-lap de boya en reposo: sin este fondo no existe el contraste que hace
## sorprender al plip y al chomp.
func _make_lap() -> AudioStreamWAV:
	var out := _noise_ring(380.0, 0.12, 0.05, 0.25, 31)
	return _to_wav(out)


## Jingle de captura: onda cuadrada al 25% de duty, notas solapadas. 3/4/5 notas
## segun rareza (C5-E5-G5-C6-E6).
func _make_jingle(notes: int) -> AudioStreamWAV:
	const FREQS: Array[float] = [523.25, 659.25, 783.99, 1046.5, 1318.5]
	var out := PackedFloat32Array()
	for k in mini(notes, FREQS.size()):
		var f: float = FREQS[k]
		var note := PackedFloat32Array()
		var n: int = int(0.21 * RATE)
		note.resize(n)
		for i in n:
			var t: float = float(i) / RATE
			var duty: float = fmod(t * f, 1.0)
			var sq: float = 0.6 if duty < 0.25 else -0.2
			note[i] = sq * minf(t / 0.005, 1.0) * exp(-t / 0.12) * 0.35
		_mix(out, note, k * 0.06)
	return _to_wav(out)
