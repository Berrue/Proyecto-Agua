extends Node

## AUTOLOAD `WeatherAudio` — el mezclador del clima (docs/CLIMA.md §5, fase B).
##
## Los WAV de `game/audio/weather/` (ElevenLabs + clips, regla 10 del repo) por
## fin suenan en el juego. Arquitectura del doc, sin inventos:
##
## - Las camas corren SIEMPRE; nunca play/stop (hace click). Solo se mueve
##   `volume_db`, con -80 dB como apagado y ventanas solapadas equal-power.
## - Todos los volumenes son funcion pura de (rain01, viento, racha) leidos de
##   Ocean cada frame: cero estado acumulado — una reconexion reproduce la
##   mezcla exacta, y la fase de cada loop se ancla a sim_time al arrancar.
## - La lluvia sigue a rain01 (INDEPENDIENTE de la furia); el viento si sigue
##   al dial via wind_speed(), y la racha lo hace respirar ±2 dB.
## - Interior de cabina = lowpass + recorte de volumen en el bus Clima. El
##   "estoy bajo techo" se decide contra el MISMO volumen que ya corta las
##   gotas (RainShelterCabin): un solo techo para ojos y oidos.
## - Trueno: one-shots por distancia con ducking de las camas. El QUE y CUANDO
##   determinista es del LightningDirector (fase C); aqui vive solo el COMO
##   suena, y la tecla T del HUD lo dispara para probar.

const DB_SILENT := -80.0
## Techos de mezcla por capa, sobre archivos normalizados a -34.4 dB RMS
## (§5: la referencia comun — el escalon lo pone esta curva, no el WAV).
const RAIN_DB := -6.0
const WIND_DB := -5.0
const THUNDER_DB := -2.0
## Cuanto se hunden las camas bajo un trueno y en el interior de la cabina.
const DUCK_DB := -6.0
const INTERIOR_DB := -9.0
const INTERIOR_LPF_HZ := 750.0
const EXTERIOR_LPF_HZ := 20500.0

## Ventanas de crossfade (equal-power) sobre rain01: la calma vive sola hasta
## ~0.45 y la intensa toma el relevo hacia 0.85 — nunca un hueco de silencio.
const CALM_IN_LO := 0.02
const CALM_IN_HI := 0.30
const HEAVY_IN_LO := 0.40
const HEAVY_IN_HI := 0.85

## El viento entra con brisa inaudible y satura cerca del temporal pleno
## (tabla Beaufort: furia 8 ≈ 26 m/s de base).
const WIND_MS_LO := 5.0
const WIND_MS_HI := 26.0

var _rain_calm: AudioStreamPlayer
var _rain_heavy: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _thunder: AudioStreamPlayer
var _thunder_pb: AudioStreamPlaybackPolyphonic
var _lpf: AudioEffectLowPassFilter
var _interior: float = 0.0
var _ruido01: float = 0.0
var _duck: float = 0.0
var _shelter: Node3D
var _shelter_next_scan: float = 0.0

const _CALM_STREAMS: Array[AudioStream] = [
	preload("res://game/audio/weather/lluvia_calma_loop.wav"),
	preload("res://game/audio/weather/lluvia_calma_2_loop.wav"),
]
const _HEAVY_STREAM := preload("res://game/audio/weather/lluvia_intensa_loop.wav")
const _WIND_STREAM := preload("res://game/audio/weather/viento_temporal_loop.wav")
const _THUNDER_NEAR := preload("res://game/audio/weather/trueno_seco.wav")
const _THUNDER_CLOSE := preload("res://game/audio/weather/trueno_cercano.wav")
const _THUNDER_MID := preload("res://game/audio/weather/trueno_medio.wav")
const _THUNDER_FAR := preload("res://game/audio/weather/trueno_rodante.wav")


func _ready() -> void:
	_setup_bus()
	_rain_calm = _make_bed(_pick_calm_variant())
	_rain_heavy = _make_bed(_HEAVY_STREAM)
	_wind = _make_bed(_WIND_STREAM)
	# La variante de calma depende de la semilla: si el mar se regenera con
	# otra, la cama acompaña (misma variante en todos los clientes, gratis).
	Ocean.waves_regenerated.connect(_on_waves_regenerated)

	_thunder = AudioStreamPlayer.new()
	_thunder.bus = &"Clima"
	var poly := AudioStreamPolyphonic.new()
	poly.polyphony = 4
	_thunder.stream = poly
	add_child(_thunder)
	_thunder.play()
	_thunder_pb = _thunder.get_stream_playback() as AudioStreamPlaybackPolyphonic


## Bus Clima -> Master con un lowpass transparente que la cabina cierra.
## Idempotente, como SfxLibrary._setup_buses().
func _setup_bus() -> void:
	if AudioServer.get_bus_index("Clima") == -1:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, "Clima")
		AudioServer.set_bus_send(idx, "Master")
		_lpf = AudioEffectLowPassFilter.new()
		_lpf.cutoff_hz = EXTERIOR_LPF_HZ
		AudioServer.add_bus_effect(idx, _lpf)
	else:
		var idx := AudioServer.get_bus_index("Clima")
		if AudioServer.get_bus_effect_count(idx) > 0:
			_lpf = AudioServer.get_bus_effect(idx, 0) as AudioEffectLowPassFilter


func _make_bed(stream: AudioStream) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = &"Clima"
	p.volume_db = DB_SILENT
	add_child(p)
	# Fase anclada al reloj de simulacion: dos clientes (o un late join)
	# arrancan el loop en el MISMO punto (§7: evaluar, nunca reproducir).
	p.play(fmod(Ocean.sim_time, maxf(stream.get_length(), 0.01)))
	return p


func _pick_calm_variant() -> AudioStream:
	return _CALM_STREAMS[absi(Ocean.ocean_seed) % _CALM_STREAMS.size()]


func _on_waves_regenerated() -> void:
	if _rain_calm == null:
		return
	var wanted := _pick_calm_variant()
	if _rain_calm.stream != wanted:
		_rain_calm.stream = wanted
		_rain_calm.play(fmod(Ocean.sim_time, maxf(wanted.get_length(), 0.01)))


func _process(delta: float) -> void:
	var rain: float = Ocean.rain01
	# Equal-power: la suma de potencias se mantiene en el cruce calma-intensa.
	var calm_gain: float = _ep(rain, CALM_IN_LO, CALM_IN_HI) \
		* (1.0 - _ep(rain, HEAVY_IN_LO, HEAVY_IN_HI))
	var heavy_gain: float = _ep(rain, HEAVY_IN_LO, HEAVY_IN_HI)
	var wind_gain: float = _ep(Ocean.wind_speed(), WIND_MS_LO, WIND_MS_HI)

	_duck = maxf(_duck - delta * 0.5, 0.0) # release ~2 s tras el trueno
	_interior = move_toward(_interior, 1.0 if _is_sheltered() else 0.0, delta * 3.0)
	var common_db: float = DUCK_DB * _duck + INTERIOR_DB * _interior

	_rain_calm.volume_db = _to_db(calm_gain, RAIN_DB) + common_db
	_rain_heavy.volume_db = _to_db(heavy_gain, RAIN_DB) + common_db
	# La racha hace respirar el viento ±2 dB: el mismo gust01 determinista que
	# mueve las manchas del agua — imagen y sonido respiran juntos.
	_wind.volume_db = _to_db(wind_gain, WIND_DB) + common_db \
		+ (Ocean.gust01() - 0.5) * 4.0

	# El ruido que tapa la voz NO se calcula aparte: es esta misma mezcla. Suma
	# equal-power, igual que se cruzan las camas entre si, porque lo que enmascara
	# es la POTENCIA que llega al oido y no la suma de dos volumenes.
	var lluvia_gain: float = maxf(calm_gain, heavy_gain)
	_ruido01 = clampf(sqrt(wind_gain * wind_gain + lluvia_gain * lluvia_gain), 0.0, 1.0)

	if _lpf != null:
		_lpf.cutoff_hz = lerpf(EXTERIOR_LPF_HZ, INTERIOR_LPF_HZ, _interior)


## Cuanto ruido ambiente tapa la voz AHORA, 0..1.
##
## Es literalmente la mezcla de camas que este autoload acaba de calcular, no una
## curva paralela: la mecanica de enmascaramiento de voz (docs/CLIMA.md §3.5)
## pide que la voz se pierda con LO QUE SE OYE. Dos curvas que dicen lo mismo se
## separan en cuanto alguien afina una, y entonces la voz se perderia sin que el
## jugador oyera nada raro — feedback que miente (regla 8).
##
## Nota: la furia entra por el VIENTO (`Ocean.wind_speed()` sale de la tabla de
## Douglas), no por un termino propio. El dia que exista una cama de MAR se suma
## aqui y la voz se entera sola.
func ruido01() -> float:
	return _ruido01


## 0 = a la intemperie, 1 = dentro de la cabina, ya suavizado. El refugio baja el
## ruido, o sea que dentro se vuelve a hablar.
func interior01() -> float:
	return _interior


## Dispara un trueno ya oido a [param distance_m] metros: la distancia elige el
## clip (cerca = crack, lejos = solo rumble — el aire come los agudos) y ducka
## las camas. El retardo flash→trueno (d/343) es del que llama (fase C).
func play_thunder(distance_m: float) -> void:
	if _thunder_pb == null:
		return
	var stream: AudioStream
	if distance_m < 250.0:
		stream = _THUNDER_NEAR if randf() < 0.5 else _THUNDER_CLOSE
	elif distance_m < 900.0:
		stream = _THUNDER_CLOSE
	elif distance_m < 1800.0:
		stream = _THUNDER_MID
	else:
		stream = _THUNDER_FAR
	var vol: float = THUNDER_DB - 14.0 * _ep(distance_m, 150.0, 3000.0)
	# Pitch con variacion: RNG global permitido — es presentacion (regla 4).
	_thunder_pb.play_stream(stream, 0.0, vol, randf_range(0.96, 1.04))
	_duck = 1.0


## ¿La camara esta bajo el techo de la cabina? Se pregunta al MISMO volumen que
## corta las gotas (RainShelterCabin): un solo techo para todo el clima.
func _is_sheltered() -> bool:
	if _shelter == null or not is_instance_valid(_shelter):
		# Busqueda perezosa y espaciada: el barco puede no existir (menu, tests).
		if Ocean.sim_time < _shelter_next_scan:
			return false
		_shelter_next_scan = Ocean.sim_time + 2.0
		var root := get_tree().root
		_shelter = root.find_child("RainShelterCabin", true, false) as Node3D
		if _shelter == null:
			return false
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return false
	var local: Vector3 = _shelter.global_transform.affine_inverse() * cam.global_position
	var half: Vector3 = (_shelter as GPUParticlesCollisionBox3D).size * 0.5
	return absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z


## Rampa 0..1 con curva equal-power (seno): dos camas cruzadas con esta curva
## suman potencia constante y el cruce no se hunde.
func _ep(x: float, lo: float, hi: float) -> float:
	var t: float = clampf((x - lo) / maxf(hi - lo, 0.001), 0.0, 1.0)
	return sin(t * PI * 0.5)


func _to_db(gain: float, max_db: float) -> float:
	if gain < 0.001:
		return DB_SILENT
	return linear_to_db(gain) + max_db
