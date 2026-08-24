extends Node

## Pruebas del clima (fase A de docs/CLIMA.md): lluvia y viento.
##
##   godot --headless --path . tests/weather_tests.tscn
##
## Lo que de verdad se protege aqui es que el clima cumple LA MISMA regla que
## el agua: funcion de (sim_time, semilla, furia), sin relojes propios y sin
## RNG global. Si alguien engancha una racha a Time.get_ticks o a randf(),
## cada cliente veria sus propias manchas de viento — y como cada pantalla se
## ve bien por separado, nadie lo notaria hasta un playtest en red.

var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0


func _ready() -> void:
	print_rich("[b]--- Pruebas de clima (lluvia y viento) ---[/b]")
	_test_gust_is_pure_and_bounded()
	_test_gust_follows_seed()
	_test_wind_table()
	_test_rain_independent_of_fury()
	_test_rain_rate_limit()
	_test_frame_uniforms()
	_test_weather_audio_mixer()
	_test_thunder()
	_test_lightning_deterministic()
	_test_lightning_photosensitive()
	_test_lightning_rate_by_fury()
	await _test_hud_wiring("res://game/world/toybox.tscn")
	_restore_ocean()
	_report()


func _check(condition: bool, label: String, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("  ok    %s" % label)
	else:
		print("  FALLO %s%s" % [label, ("  ->  " + detail) if detail != "" else ""])
		_failures.append(label + (" :: " + detail if detail != "" else ""))


func _report() -> void:
	print("")
	if _failures.is_empty():
		print_rich("[color=green][b]%d/%d comprobaciones OK[/b][/color]" % [_checks, _checks])
		get_tree().quit(0)
	else:
		print_rich("[color=red][b]%d de %d han fallado:[/b][/color]" % [_failures.size(), _checks])
		for f in _failures:
			print("   - " + f)
		get_tree().quit(1)


## Los tests mueven el estado global de Ocean; se deja como estaba al salir
## para que un runner que encadene escenas no herede un mar raro.
func _restore_ocean() -> void:
	Ocean.rain_level = 0.0
	Ocean.rain_scale = 1.0
	Ocean.set_fury_immediate(3.0)
	Ocean.regenerate(0)


# =============================================================================


## Misma t -> misma racha, y consultar el futuro no perturba nada: es la
## garantia de que el silbido y las manchas pueden ANTICIPAR la racha.
func _test_gust_is_pure_and_bounded() -> void:
	Ocean.regenerate(1234)
	var worst: float = 0.0
	var lo: float = 1.0
	var hi: float = 0.0
	for i in 300:
		var t: float = float(i) * 3.7
		var a: float = Ocean.gust01_at(t)
		var b: float = Ocean.gust01_at(t)
		worst = maxf(worst, absf(a - b))
		lo = minf(lo, a)
		hi = maxf(hi, a)
	_check(worst < 1e-9, "la racha es funcion pura de t", "desviacion %.12f" % worst)
	_check(lo >= 0.0 and hi <= 1.0, "gust01 vive en [0,1]", "rango [%.3f, %.3f]" % [lo, hi])
	_check(hi - lo > 0.3, "y de verdad respira (no es constante)",
		"excursion %.3f" % (hi - lo))

	var before: float = Ocean.sim_time
	var _future: float = Ocean.gust01_at(Ocean.sim_time + 300.0)
	_check(Ocean.sim_time == before, "consultar el futuro no toca sim_time")


## Misma semilla -> mismas rachas; semilla distinta -> rachas distintas.
## Es lo que hace que 6 clientes vean la misma mancha en el mismo sitio.
func _test_gust_follows_seed() -> void:
	Ocean.regenerate(42)
	# Float64: guardar en 32 bits y comparar contra el calculo fresco en 64
	# metia un error de cuantizacion mayor que la tolerancia del test.
	var a := PackedFloat64Array()
	for i in 50:
		a.append(Ocean.gust01_at(float(i) * 1.7))
	Ocean.regenerate(42)
	var same: bool = true
	for i in 50:
		if absf(a[i] - Ocean.gust01_at(float(i) * 1.7)) > 1e-9:
			same = false
			break
	_check(same, "misma semilla -> misma secuencia de rachas")

	Ocean.regenerate(43)
	var diff: float = 0.0
	for i in 50:
		diff = maxf(diff, absf(a[i] - Ocean.gust01_at(float(i) * 1.7)))
	_check(diff > 0.05, "semilla distinta -> rachas distintas", "max delta %.4f" % diff)


## La tabla Beaufort: sin furia no hay viento, y el viento crece monotono con
## el dial — un dial que baja viento al subir furia seria un bug silencioso.
func _test_wind_table() -> void:
	Ocean.set_fury_immediate(0.0)
	_check(Ocean.wind_base_speed() < 0.01, "furia 0 = calma chicha",
		"%.2f m/s" % Ocean.wind_base_speed())

	var prev: float = -1.0
	var monotonic: bool = true
	for f in 11:
		Ocean.set_fury_immediate(float(f))
		var v: float = Ocean.wind_base_speed()
		if v < prev:
			monotonic = false
		prev = v
	_check(monotonic, "el viento crece monotono con la furia")
	_check(absf(prev - Ocean.WIND_MS[-1]) < 0.01, "furia 10 da el tope de la tabla")


## La lluvia es INDEPENDIENTE de la furia (decision de diseño): furia 9 con
## cielo seco es valida, y llueve solo si el parte (rain_level) lo dice. La
## RETIRADA (rain_scale=0) corta la lluvia aunque este lloviendo.
func _test_rain_independent_of_fury() -> void:
	Ocean.rain_level = 0.0
	Ocean.rain_scale = 1.0
	Ocean.set_fury_immediate(9.0)
	_check(Ocean.rain_target() < 0.001, "furia 9 sin parte de lluvia: seco")
	Ocean.set_fury_immediate(0.0)
	Ocean.rain_level = 0.8
	_check(absf(Ocean.rain_target() - 0.8) < 0.001, "rain_level 0.8 con furia 0: llueve igual")
	Ocean.rain_scale = 0.0
	_check(Ocean.rain_target() < 0.001, "la RETIRADA corta la lluvia en curso")
	Ocean.rain_scale = 1.0
	Ocean.rain_level = 0.0


## rain01 llega a su objetivo por rampa, nunca de golpe: el moteado del shader
## haria pop. (Se tickea la fisica a mano: en _ready no corren frames.)
func _test_rain_rate_limit() -> void:
	Ocean.rain_level = 0.0
	for i in 60:
		Ocean._physics_process(1.0 / 60.0)
	_check(Ocean.rain01 < 0.001, "arranca seco")

	Ocean.rain_level = 1.0
	var before: float = Ocean.rain01
	Ocean._physics_process(0.1)
	var step: float = Ocean.rain01 - before
	_check(step > 0.0 and step <= Ocean.RAIN_RATE_LIMIT * 0.1 + 1e-6,
		"la lluvia sube con rampa acotada", "paso %.4f en 0.1 s" % step)
	for i in 300:
		Ocean._physics_process(1.0 / 60.0)
	_check(Ocean.rain01 > 0.999, "y alcanza el objetivo")
	Ocean.rain_level = 0.0


## Los uniforms de clima salen por la MISMA tuberia que el resto (regla: nunca
## dos listas). Aqui solo se comprueba que la llamada no revienta y que el
## material recibe los nombres que el shader declara.
func _test_frame_uniforms() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://addons/ocean/shaders/ocean_surface.gdshader")
	Ocean.apply_to_material(mat)
	Ocean.apply_frame_to_material(mat)
	var rain: Variant = mat.get_shader_parameter(&"rain01")
	var wdir: Variant = mat.get_shader_parameter(&"wind_dir")
	_check(rain != null and typeof(rain) == TYPE_FLOAT, "el shader recibe rain01")
	_check(wdir != null and (wdir as Vector2).length() > 0.99,
		"el shader recibe wind_dir unitario")


## El mezclador de clima: camas siempre sonando, volumenes como funcion pura
## del estado. Si alguien las engancha a play/stop o a un tween con estado,
## este test es el que lo delata.
func _test_weather_audio_mixer() -> void:
	_check(AudioServer.get_bus_index("Clima") != -1, "existe el bus Clima")
	_check(WeatherAudio._rain_calm != null and WeatherAudio._rain_calm.playing,
		"la cama de lluvia calma esta sonando (siempre)")
	_check(WeatherAudio._wind != null and WeatherAudio._wind.playing,
		"la cama de viento esta sonando (siempre)")

	# Sin lluvia y sin furia: todo en silencio (-80), nada parado.
	Ocean.rain_level = 0.0
	Ocean.rain_scale = 1.0
	Ocean.set_fury_immediate(0.0)
	for i in 120:
		Ocean._physics_process(1.0 / 60.0)
	WeatherAudio._process(1.0 / 60.0)
	_check(WeatherAudio._rain_calm.volume_db <= -60.0, "rain01=0: lluvia muda",
		"%.1f dB" % WeatherAudio._rain_calm.volume_db)
	_check(WeatherAudio._wind.volume_db <= -40.0, "furia 0: viento casi mudo",
		"%.1f dB" % WeatherAudio._wind.volume_db)
	_check(WeatherAudio._rain_calm.playing, "muda pero SONANDO (nunca stop: click)")

	# Llovizna: la calma abre, la intensa sigue muda.
	Ocean.rain_level = 0.3
	for i in 60:
		Ocean._physics_process(1.0 / 60.0)
	WeatherAudio._process(1.0 / 60.0)
	_check(WeatherAudio._rain_calm.volume_db > -30.0, "rain 0.3: la calma abre",
		"%.1f dB" % WeatherAudio._rain_calm.volume_db)
	_check(WeatherAudio._rain_heavy.volume_db <= -60.0, "rain 0.3: la intensa muda")

	# Aguacero: la intensa manda sobre la calma.
	Ocean.rain_level = 1.0
	for i in 200:
		Ocean._physics_process(1.0 / 60.0)
	WeatherAudio._process(1.0 / 60.0)
	_check(WeatherAudio._rain_heavy.volume_db > WeatherAudio._rain_calm.volume_db,
		"rain 1.0: la intensa manda",
		"intensa %.1f vs calma %.1f dB" % [
			WeatherAudio._rain_heavy.volume_db, WeatherAudio._rain_calm.volume_db])

	# Temporal: el viento abre con la furia.
	Ocean.set_fury_immediate(8.0)
	WeatherAudio._process(1.0 / 60.0)
	_check(WeatherAudio._wind.volume_db > -25.0, "furia 8: el viento abre",
		"%.1f dB" % WeatherAudio._wind.volume_db)

	Ocean.rain_level = 0.0
	Ocean.set_fury_immediate(3.0)


## El trueno: suena y hunde las camas (ducking) con release.
func _test_thunder() -> void:
	WeatherAudio._duck = 0.0
	WeatherAudio.play_thunder(200.0)
	_check(WeatherAudio._thunder.playing, "el trueno suena")
	_check(WeatherAudio._duck > 0.99, "y ducka las camas")
	WeatherAudio._process(1.0)
	_check(WeatherAudio._duck < 0.6, "el ducking se relaja solo")
	WeatherAudio._duck = 0.0


## Los rayos se DERIVAN de (semilla, slot): dos maquinas ven el mismo rayo sin
## replicar nada. Si alguien mete un randf() o un Timer, esto lo caza.
func _test_lightning_deterministic() -> void:
	var a := LightningDirector.new()
	var b := LightningDirector.new()
	add_child(a)
	add_child(b)
	Ocean.regenerate(2024)
	Ocean.set_fury_immediate(9.0)

	var same: bool = true
	var strikes: int = 0
	for i in 400:
		var sa: Dictionary = a.strike_at_slot(i)
		var sb: Dictionary = b.strike_at_slot(i)
		if bool(sa.get(&"active", false)):
			strikes += 1
			if not bool(sb.get(&"active", false)) 					or absf(float(sa[&"t0"]) - float(sb[&"t0"])) > 1e-9 					or absf(float(sa[&"distance"]) - float(sb[&"distance"])) > 1e-6:
				same = false
				break
		elif bool(sb.get(&"active", false)):
			same = false
			break
	_check(same, "dos directores derivan EL MISMO rayo de la misma semilla")
	_check(strikes > 40, "con furia 9 hay actividad electrica de sobra",
		"%d rayos en 400 slots" % strikes)

	# Semilla distinta -> otra tormenta.
	Ocean.regenerate(2025)
	var diff: int = 0
	for i in 400:
		if bool(a.strike_at_slot(i).get(&"active", false)) != bool(b.strike_at_slot(i).get(&"active", false)):
			diff += 1
	_check(diff == 0, "y siguen coincidiendo entre si con la semilla nueva")

	# --- Divergencia de red. La furia NO es un valor replicado: es estado
	# integrado local que el host gotea a 10 Hz, asi que entre paquetes las
	# maquinas difieren hasta ~0.04. Sin cuantizar, CUALQUIER diferencia
	# volteaba decisiones booleanas; cuantizada, solo importa si las dos furias
	# caen a lados distintos de un escalon.
	#
	# El test mide el residuo REAL en vez de fingir que es cero: la solucion
	# definitiva es el guion comprometido de furia (FuryTrack, CLIMA.md fase D).
	Ocean.regenerate(2024)
	var pares: int = 0
	var flips: int = 0
	for f in 300:
		var base: float = 3.0 + float(f) * 0.02
		Ocean.set_fury_immediate(base)
		var con_a: Array = []
		for i in 40:
			con_a.append(bool(a.strike_at_slot(i).get(&"active", false)))
		Ocean.set_fury_immediate(base + 0.04)
		for i in 40:
			pares += 1
			if bool(a.strike_at_slot(i).get(&"active", false)) != con_a[i]:
				flips += 1
	var tasa: float = 100.0 * float(flips) / float(maxi(pares, 1))
	_check(tasa < 3.0,
		"deriva de red de 0.04: menos del 3 por ciento de los rayos difieren",
		"medido %.2f %% (sin cuantizar seria ~100 %% durante toda la rampa)" % tasa)

	# El cruce a "tormenta encima" ya no es un escalon entre rangos DISJUNTOS.
	# Antes: furia 5.99 daba 1400-3000 m y 6.01 daba 180-2200 m, o sea que el
	# mismo destello podia dar truenos separados varios segundos y con clip
	# distinto. Ahora el salto entre dos escalones contiguos esta acotado.
	var salto_max: float = 0.0
	for i in 400:
		Ocean.set_fury_immediate(5.9)
		var s1: Dictionary = a.strike_at_slot(i)
		if not bool(s1.get(&"active", false)):
			continue
		Ocean.set_fury_immediate(6.1)
		var s2: Dictionary = a.strike_at_slot(i)
		if not bool(s2.get(&"active", false)):
			continue
		salto_max = maxf(salto_max, absf(float(s1[&"distance"]) - float(s2[&"distance"])))
	_check(salto_max < 500.0,
		"cruzar furia 6 no teletransporta el rayo (cruce continuo)",
		"salto maximo %.0f m (con el escalon duro llegaba a ~1400 m)" % salto_max)

	# --- El trueno sale del rayo CONGELADO, no de re-derivar el slot.
	Ocean.set_fury_immediate(9.0)
	Ocean.sim_time = 600.0
	a._reset_state()
	a._process(0.0) # congela el slot en curso
	var frozen: int = a._slots.size()
	Ocean.set_fury_immediate(0.0) # el jugador tira el dial a cero
	a._process(0.0)
	_check(a._slots.size() >= frozen and frozen > 0,
		"bajar la furia no borra el rayo ya congelado",
		"antes %d, ahora %d" % [frozen, a._slots.size()])
	Ocean.set_fury_immediate(9.0)

	# --- El boton de debug tampoco puede saltarse el techo fotosensible.
	# (El test viejo era VACIO: pasaba igual con y sin la guarda, porque no
	# movia el reloj ni comprobaba el caso que SI debe dejar pasar.)
	a._reset_state()
	Ocean.set_fury_immediate(0.0) # sin secuencia natural que interfiera
	Ocean.sim_time = 1000.0
	a.force_strike(400.0)
	var t_first: float = a._forced_t0
	_check(t_first == 1000.0, "el primer rayo forzado entra")

	Ocean.sim_time = 1000.4
	a.force_strike(400.0)
	_check(a._forced_t0 == t_first, "otro a los 0.4 s se RECHAZA (techo fotosensible)")

	Ocean.sim_time = 1000.0 + LightningDirector.MIN_FORCED_GAP + 0.1
	a.force_strike(400.0)
	_check(a._forced_t0 > t_first, "pasado el intervalo minimo, SI entra",
		"_forced_t0 = %.2f" % a._forced_t0)

	# Y no puede apilarse encima de un rayo programado.
	a._reset_state()
	Ocean.set_fury_immediate(10.0)
	var natural_t0: float = -1.0
	for i in 200:
		var st: Dictionary = a.strike_at_slot(i)
		if bool(st.get(&"active", false)):
			natural_t0 = float(st[&"t0"])
			break
	if natural_t0 > 0.0:
		Ocean.sim_time = natural_t0 + 0.05 # justo encima del destello natural
		a._process(0.0)
		a.force_strike(400.0)
		_check(a._forced_t0 < 0.0,
			"un forzado encima de uno programado se rechaza (3+3 pulsos)",
			"_forced_t0 = %.2f" % a._forced_t0)

	# --- Un salto de reloj (unirse a una partida) invalida lo congelado.
	a._reset_state()
	Ocean.sim_time = 2000.0
	a._process(0.0)
	_check(a._slots.size() > 0, "hay slots congelados antes del salto")
	Ocean.sim_time = 50.0 # el host manda su reloj
	a._process(0.0)
	var stale: int = 0
	for key in a._slots.keys():
		if int(key) > 100:
			stale += 1
	_check(stale == 0, "tras el salto de reloj no quedan slots viejos",
		"%d claves rancias" % stale)

	# --- El destello del rayo no debe iluminar el agua (borraria las bandas).
	_check(LightningDirector.FLASH_CULL_MASK & 0b10 == 0,
		"la luz del destello excluye la capa del oceano")

	# La consulta al futuro no toca el reloj.
	var before: float = Ocean.sim_time
	var _next: float = a.seconds_to_next_strike()
	_check(Ocean.sim_time == before, "consultar el proximo rayo no toca sim_time")

	a.queue_free()
	b.queue_free()


## EL LIMITE QUE NO SE NEGOCIA (XAG 118 / WCAG 2.3.1): jamas mas de 3 destellos
## en una ventana de 1 s. Se cuentan los PICOS de la envolvente, que es lo que
## el ojo registra como destello.
func _test_lightning_photosensitive() -> void:
	var d := LightningDirector.new()
	add_child(d)
	Ocean.regenerate(77)
	Ocean.set_fury_immediate(10.0) # el peor caso: maxima actividad

	# Muestreo fino de 5 minutos de tormenta al maximo.
	const STEP := 1.0 / 120.0
	var peaks: PackedFloat32Array = PackedFloat32Array()
	var prev: float = 0.0
	var rising: bool = false
	for i in int(300.0 / STEP):
		var t: float = float(i) * STEP
		var v: float = d.intensity_at(t)
		if v > prev + 1e-6:
			rising = true
		elif rising and v < prev - 1e-6:
			# Un pico cuenta si el destello es perceptible (>=10 % de delta,
			# el criterio de XAG 118).
			if prev >= 0.10:
				peaks.append(t)
			rising = false
		prev = v

	var worst: int = 0
	for i in peaks.size():
		var n: int = 0
		for j in range(i, peaks.size()):
			if peaks[j] - peaks[i] <= 1.0:
				n += 1
			else:
				break
		worst = maxi(worst, n)
	_check(worst <= 3, "nunca mas de 3 destellos en una ventana de 1 s",
		"maximo encontrado: %d" % worst)
	_check(peaks.size() > 20, "y aun asi la tormenta destella de verdad",
		"%d destellos en 5 min" % peaks.size())

	# El modo accesible sustituye el multi-pulso por UNA rampa suave.
	d.reduce_flashes = true
	var single: int = 0
	prev = 0.0
	rising = false
	for i in int(60.0 / STEP):
		var v: float = d.intensity_at(float(i) * STEP)
		if v > prev + 1e-6:
			rising = true
		elif rising and v < prev - 1e-6:
			if prev >= 0.10:
				single += 1
			rising = false
		prev = v
	_check(d.intensity_at(0.0) <= 1.0, "el modo reducido sigue acotado a 1")
	_check(single <= 12, "modo reducido: un destello por rayo, no una tanda",
		"%d picos en 60 s" % single)
	d.queue_free()


## Sin furia no hay tormenta electrica, y la actividad crece con el dial.
func _test_lightning_rate_by_fury() -> void:
	var d := LightningDirector.new()
	add_child(d)
	Ocean.regenerate(5150)

	Ocean.set_fury_immediate(1.0)
	var calm: int = 0
	for i in 300:
		if bool(d.strike_at_slot(i).get(&"active", false)):
			calm += 1
	_check(calm == 0, "furia 1: cielo sin actividad electrica", "%d rayos" % calm)

	Ocean.set_fury_immediate(5.0)
	var mid: int = 0
	var bolts_mid: int = 0
	for i in 300:
		var s: Dictionary = d.strike_at_slot(i)
		if bool(s.get(&"active", false)):
			mid += 1
			if bool(s.get(&"bolt", false)):
				bolts_mid += 1
	_check(mid > 0, "furia 5: ya hay rayos lejanos")
	_check(bolts_mid == 0, "pero por debajo de furia 6 son solo resplandor lejano",
		"%d bolts" % bolts_mid)

	Ocean.set_fury_immediate(9.0)
	var high: int = 0
	for i in 300:
		if bool(d.strike_at_slot(i).get(&"active", false)):
			high += 1
	_check(high > mid, "la actividad crece con la furia",
		"furia 5: %d  ·  furia 9: %d" % [mid, high])
	d.queue_free()


## La escena real lleva el HUD con los controles de lluvia y horario cableados.
## Un nodo renombrado aqui es exactamente el fallo silencioso que estos tests
## existen para cazar.
func _test_hud_wiring(scene_path: String) -> void:
	var packed := load(scene_path) as PackedScene
	var root := packed.instantiate()
	add_child(root)
	await get_tree().process_frame

	var hud := root.find_children("*", "OceanDebugHUD", true, false)
	if hud.is_empty():
		_check(false, "toybox tiene OceanDebugHUD")
	else:
		var h: Node = hud[0]
		_check(h.get_node_or_null("%RainSlider") != null, "el HUD tiene deslizador de lluvia")
		_check(h.get_node_or_null("%HourSlider") != null, "el HUD tiene deslizador de horario")
		_check(h.get_node_or_null("%ReduceFlashToggle") != null,
			"el HUD tiene el toggle de reducir destellos")
		var bolts: Node = h.get_node_or_null("%BoltButtons")
		_check(bolts != null and bolts.get_child_count() == OceanDebugHUD.BOLT_PRESETS.size(),
			"el HUD tiene los botones de rayo",
			"hijos: %d" % (bolts.get_child_count() if bolts != null else -1))
		var thunder: Node = h.get_node_or_null("%ThunderButtons")
		_check(thunder != null and thunder.get_child_count() == OceanDebugHUD.THUNDER_PRESETS.size(),
			"el HUD tiene los %d botones de trueno" % OceanDebugHUD.THUNDER_PRESETS.size(),
			"hijos: %d" % (thunder.get_child_count() if thunder != null else -1))
		var buttons: Node = h.get_node_or_null("%HourButtons")
		_check(buttons != null and buttons.get_child_count() == 3,
			"los botones de horario existen (-1/+1/+3 h)",
			"hijos: %d" % (buttons.get_child_count() if buttons != null else -1))
	var rain := root.find_children("*", "RainParticles3D", true, false)
	_check(not rain.is_empty(), "toybox tiene el nodo de lluvia visible")
	var splash := root.find_children("*", "RainSplashes3D", true, false)
	_check(not splash.is_empty(), "toybox tiene los anillos de impacto")
	if not splash.is_empty():
		# Los aros se clavan en la ola evaluando la suma Gerstner en su vertex
		# shader: sin los uniforms de ola saldrian planos al nivel de reposo.
		var mat: ShaderMaterial = ((splash[0] as GPUParticles3D).draw_pass_1 as PlaneMesh).material
		_check(mat != null and mat.get_shader_parameter(&"wave_count") != null,
			"los anillos reciben los uniforms de ola")

	var ld := root.find_children("*", "LightningDirector", true, false)
	_check(not ld.is_empty(), "toybox tiene el director de rayos")

	var curtain := root.find_children("*", "RainCurtain3D", true, false)
	_check(not curtain.is_empty(), "toybox tiene la cortina de lluvia lejana")
	if not curtain.is_empty():
		# Que el NODO exista no basta: sus capas se crean con add_child
		# diferido y una vez se quedaron en cero sin que nada fallara.
		var layers: int = (curtain[0] as Node).get_child_count()
		_check(layers == RainCurtain3D.LAYERS.size(),
			"la cortina tiene sus %d capas" % RainCurtain3D.LAYERS.size(),
			"encontradas %d" % layers)

	root.queue_free()
	await get_tree().process_frame
