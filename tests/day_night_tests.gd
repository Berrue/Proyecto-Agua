extends Node

## Pruebas del ciclo dia/noche.
##
##   godot --headless --path . tests/day_night_tests.tscn
##
## Lo que de verdad se protege aqui es la REGLA DEL RELOJ: la hora es funcion
## pura de Ocean.sim_time. Si alguien la engancha a un reloj propio, cada
## cliente tendria su propio atardecer, y como cada pantalla se ve bien por
## separado, nadie lo notaria hasta un playtest en red.

var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0


func _ready() -> void:
	print_rich("[b]--- Pruebas del ciclo dia/noche ---[/b]")
	_test_phase_is_pure()
	_test_hour_mapping()
	_test_energies()
	_test_future_query()
	_test_debug_offset_leaves_sim_time_alone()
	await _test_scene_wiring("res://game/world/toybox.tscn")
	await _test_scene_wiring("res://game/world/tsunami.tscn")
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


## El color del cenit, venga del cielo propio (game/world/sky.gdshader) o del
## ProceduralSkyMaterial. El test comprueba la HORA, no que material se use.
func _sky_top(we: WorldEnvironment) -> Color:
	var mat: Material = we.environment.sky.sky_material
	var shader_mat := mat as ShaderMaterial
	if shader_mat != null:
		return shader_mat.get_shader_parameter(&"sky_top_color")
	return (mat as ProceduralSkyMaterial).sky_top_color


## El cielo propio dibuja los astros a partir de direcciones EXPLICITAS. Si
## alguien añade una DirectionalLight3D al mundo (paso con la luz del rayo), el
## cielo NO puede inventarse un disco por ella.
func _test_sky_has_no_stray_discs(scene: Node) -> void:
	var lights: Array = scene.find_children("*", "DirectionalLight3D", true, false)
	for l in lights:
		var dl := l as DirectionalLight3D
		if dl.name == "Sun" or dl.name == "Moon":
			continue
		_check(dl.sky_mode == DirectionalLight3D.SKY_MODE_LIGHT_ONLY,
			"%s no pinta disco en el cielo" % dl.name,
			"sky_mode = %d" % dl.sky_mode)


func _make_cycle(start_hour: float) -> DayNightCycle:
	var c := DayNightCycle.new()
	c.profile = load("res://resources/day_night/profile_default.tres")
	c.start_hour = start_hour
	return c


# =============================================================================


## Mismo sim_time -> misma hora, en cualquier instancia. Es la garantia de que
## el cielo se sincroniza gratis con el reloj que ya replicamos.
func _test_phase_is_pure() -> void:
	var a := _make_cycle(9.0)
	var b := _make_cycle(9.0)
	var worst: float = 0.0
	for i in 200:
		var t: float = float(i) * 37.3
		worst = maxf(worst, absf(a.phase(t) - b.phase(t)))
	_check(worst < 1e-9, "la hora es funcion pura de sim_time", "desviacion %.12f" % worst)

	# Y envuelve: un dia entero despues, la misma hora.
	var day: float = a.profile.day_length_seconds
	var wrap: float = absf(a.phase(100.0) - a.phase(100.0 + day))
	_check(wrap < 1e-6, "el ciclo envuelve a las 24 h", "diferencia %.9f" % wrap)


## start_hour=12 con sim_time=0 tiene que ser mediodia exacto, y 0 medianoche.
func _test_hour_mapping() -> void:
	var noon := _make_cycle(12.0)
	_check(absf(noon.phase(0.0) - 0.5) < 1e-6, "start_hour=12 arranca a mediodia",
		"fase %.4f" % noon.phase(0.0))

	var midnight := _make_cycle(0.0)
	_check(absf(midnight.phase(0.0)) < 1e-6, "start_hour=0 arranca a medianoche")

	# Un cuarto de dia despues de medianoche es el amanecer.
	var quarter: float = midnight.profile.day_length_seconds * 0.25
	_check(absf(midnight.phase(quarter) - 0.25) < 1e-6, "6 horas despues amanece")


## De dia manda el sol; de noche, la luna. Y la noche nunca es negra del todo.
func _test_energies() -> void:
	var c := _make_cycle(0.0)
	var p: DayNightProfile = c.profile

	var sun_noon: float = p.sample_energy(p.sun_energy, 0.5, p.sun_energy_max)
	var moon_noon: float = p.sample_energy(p.moon_energy, 0.5, p.moon_energy_max)
	_check(sun_noon > 1.0 and moon_noon < 0.01, "a mediodia manda el sol",
		"sol %.2f, luna %.2f" % [sun_noon, moon_noon])

	var sun_night: float = p.sample_energy(p.sun_energy, 0.0, p.sun_energy_max)
	var moon_night: float = p.sample_energy(p.moon_energy, 0.0, p.moon_energy_max)
	_check(sun_night < 0.05 and moon_night > 0.1, "a medianoche manda la luna",
		"sol %.2f, luna %.2f" % [sun_night, moon_night])

	var ambient_night: float = p.sample_energy(p.ambient_energy, 0.0, p.ambient_energy_max)
	_check(ambient_night > 0.08, "la noche es jugable, no negra",
		"ambiente nocturno %.3f" % ambient_night)


## El cielo es consultable en el futuro, igual que el oceano: "¿sera de noche
## cuando llegue el tsunami?" tiene respuesta exacta.
func _test_future_query() -> void:
	# Arrancamos a las 17:00 con dia de 1200 s: la puesta (t01=0.77 -> 18:29)
	# queda a ~74 s de simulacion.
	var c := _make_cycle(17.0)
	Ocean.sim_time = 0.0
	_check(not c.is_night(), "a las 17:00 es de dia")
	_check(c.will_be_night_in(120.0), "y sabe que sera de noche en 2 minutos")
	_check(not c.will_be_night_in(10.0), "pero no en 10 segundos")


## El salto de horas del debug NUNCA puede tocar sim_time: adelantar el reloj
## del oceano teletransportaria las olas y todo lo que flota.
func _test_debug_offset_leaves_sim_time_alone() -> void:
	var c := _make_cycle(9.0)
	Ocean.sim_time = 500.0
	var before: float = Ocean.sim_time
	var phase_before: float = c.time_of_day()
	c.advance_hours(6.0)
	_check(Ocean.sim_time == before, "avanzar horas no toca sim_time")
	var moved: float = fposmod(c.time_of_day() - phase_before, 1.0)
	_check(absf(moved - 0.25) < 1e-6, "y si mueve la hora 6/24",
		"movio %.4f de dia" % moved)


## Cableado real en las dos escenas: el nodo existe, tiene perfil, y al saltar
## a la noche el sol se apaga, la luna se enciende y el cielo cambia de color.
func _test_scene_wiring(path: String) -> void:
	var label := path.get_file()
	# La hora incluye sim_time (esa es exactamente la regla que protegemos), asi
	# que para fijar "mediodia" hay que congelar el reloj primero: los tests
	# anteriores dejaron sim_time avanzado y Ocean sigue sumando cada tick.
	Ocean.set_paused(true)
	Ocean.sim_time = 0.0
	var scene: Node3D = load(path).instantiate()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame

	var cycle := scene.get_node_or_null(^"DayNightCycle") as DayNightCycle
	_check(cycle != null, "%s tiene DayNightCycle" % label)
	if cycle == null:
		scene.queue_free()
		return
	_check(cycle.profile != null, "%s tiene perfil asignado" % label)

	var sun := scene.get_node(^"Sun") as DirectionalLight3D
	var moon := scene.get_node_or_null(^"Moon") as DirectionalLight3D
	var we := scene.get_node(^"WorldEnvironment") as WorldEnvironment
	_check(moon != null, "%s tiene luna" % label)
	_test_sky_has_no_stray_discs(scene)
	# El cielo propio muta cada frame (nubes que corren, encapotado por furia).
	# En AUTOMATIC Godot elige INCREMENTAL cuando el shader usa uniforms propios,
	# y ese modo amortigua el muestreo sobre varios frames: con un cielo que
	# cambia siempre, la luz ambiente queda desfasada y BOMBEA. REALTIME usa el
	# filtrado rapido, que es justo el caso de uso de un cielo animado.
	_check(we.environment.sky.process_mode == Sky.PROCESS_MODE_REALTIME,
		"%s: el cielo se procesa en REALTIME" % label,
		"process_mode = %d" % we.environment.sky.process_mode)

	# A las 12:00 exactas: reloj congelado en 0 y hora de arranque 12.
	cycle.start_hour = 12.0
	await get_tree().process_frame
	var day_sky: Color = _sky_top(we)
	var sun_day: float = sun.light_energy
	_check(sun_day > 1.0, "%s: sol pleno a mediodia" % label, "energia %.2f" % sun_day)
	_check(not cycle.is_night(), "%s: mediodia no es noche" % label)

	# Salto a medianoche.
	cycle.advance_hours(12.0)
	await get_tree().process_frame
	var night_sky: Color = _sky_top(we)
	_check(sun.light_energy < 0.05, "%s: el sol se apaga de noche" % label,
		"energia %.3f" % sun.light_energy)
	_check(not sun.shadow_enabled, "%s: y sus sombras tambien" % label)
	if moon != null:
		_check(moon.light_energy > 0.1, "%s: la luna se enciende" % label,
			"energia %.3f" % moon.light_energy)
	_check(cycle.is_night(), "%s: medianoche es noche" % label)
	_check(day_sky.get_luminance() > night_sky.get_luminance() * 2.0,
		"%s: el cielo nocturno es mas oscuro" % label,
		"dia %.3f vs noche %.3f" % [day_sky.get_luminance(), night_sky.get_luminance()])

	Ocean.clear_events()
	Ocean.set_paused(false)
	scene.queue_free()
	await get_tree().process_frame
