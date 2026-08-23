extends Node

## Arnes de pruebas de F1. Se ejecuta headless y devuelve codigo de salida != 0
## si algo falla, para poder colgarlo de CI:
##
##   godot --headless --path . tests/f1_tests.tscn
##
## Cubre los fallos que en este proyecto son SILENCIOSOS, que son los unicos que
## de verdad hacen daño: determinismo roto entre clientes, la inversion de
## Gerstner que deja de converger justo en tormenta, y el "barril cohete".

const SAMPLE_POINTS := 512
const SETTLE_TICKS := 1400

var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0


func _ready() -> void:
	print_rich("[b]--- Pruebas F1 ---[/b]")
	_test_determinism()
	_test_inversion_converges()
	_test_fury_sweep_is_finite()
	_test_steepness_guard()
	await _test_boat_floats()
	await _test_no_rocket_barrels()
	_report()


func _check(condition: bool, label: String, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("  ok    %s" % label)
	else:
		var line := "  FALLO %s%s" % [label, ("  ->  " + detail) if detail != "" else ""]
		print(line)
		_failures.append(label + (" :: " + detail if detail != "" else ""))


func _report() -> void:
	print("")
	if _failures.is_empty():
		print_rich("[color=green][b]%d/%d comprobaciones OK[/b][/color]" % [_checks, _checks])
		get_tree().quit(0)
	else:
		print_rich("[color=red][b]%d de %d comprobaciones han fallado:[/b][/color]" % [
			_failures.size(), _checks])
		for f in _failures:
			print("   - " + f)
		get_tree().quit(1)


# =============================================================================


## Dos maquinas con la misma semilla tienen que calcular el MISMO mar. Si esto
## se rompe, en multijugador el barco esta en sitios distintos en cada pantalla
## y no salta ningun error: cada cliente se ve perfecto por separado.
func _test_determinism() -> void:
	var a := OceanWaveProxy.new()
	var b := OceanWaveProxy.new()
	a.generate(123456789, 10, 30.0)
	b.generate(123456789, 10, 30.0)
	a.set_sea_state(6.0, 0.6)
	b.set_sea_state(6.0, 0.6)

	var worst: float = 0.0
	for i in SAMPLE_POINTS:
		var p := Vector2(sin(float(i) * 12.9898) * 900.0, cos(float(i) * 78.233) * 900.0)
		var t: float = float(i) * 0.37
		worst = maxf(worst, absf(a.height_at(p, t) - b.height_at(p, t)))
	_check(worst < 1e-6, "determinismo con la misma semilla", "error maximo %.9f m" % worst)

	var c := OceanWaveProxy.new()
	c.generate(987654321, 10, 30.0)
	c.set_sea_state(6.0, 0.6)
	var diff: float = absf(a.height_at(Vector2(10, 10), 5.0) - c.height_at(Vector2(10, 10), 5.0))
	_check(diff > 1e-4, "semillas distintas dan mares distintos", "diferencia %.4f m" % diff)


## La inversion del desplazamiento horizontal por punto fijo tiene que converger
## incluso con choppiness al maximo. Si no converge, el objeto flota AL LADO de
## la ola en vez de encima, y falla justo en tormenta.
func _test_inversion_converges() -> void:
	var proxy := OceanWaveProxy.new()
	proxy.generate(42, 10, 0.0)
	proxy.set_sea_state(14.0, OceanWaveProxy.STEEPNESS_LIMIT)

	var worst: float = 0.0
	for i in 256:
		var target := Vector2(float(i) * 3.7 - 400.0, float(i) * 1.3 - 200.0)
		var t: float = float(i) * 0.21
		# Resolver, y comprobar que el punto resuelto vuelve al objetivo.
		var p := target
		for _iter in 3:
			var d := proxy.displacement(p, t)
			p = target - Vector2(d.x, d.z)
		var back := proxy.displacement(p, t)
		var landed := p + Vector2(back.x, back.z)
		worst = maxf(worst, landed.distance_to(target))
	_check(worst < 0.75, "la inversion de Gerstner converge en tormenta",
		"desviacion maxima %.3f m" % worst)


## Ningun valor de furia puede producir NaN, infinitos ni alturas absurdas.
func _test_fury_sweep_is_finite() -> void:
	var proxy := OceanWaveProxy.new()
	proxy.generate(7, 10, 45.0)

	var all_finite := true
	var worst_ratio: float = 0.0
	for step in 101:
		var fury: float = float(step) * 0.1
		var hs := _hs_for(fury)
		proxy.set_sea_state(hs, lerpf(0.15, OceanWaveProxy.STEEPNESS_LIMIT, fury / 10.0))
		for i in 64:
			var p := Vector2(float(i) * 17.0, float(i) * -23.0)
			var h := proxy.height_at(p, float(i) * 0.5)
			if not is_finite(h):
				all_finite = false
			elif hs > 0.05:
				worst_ratio = maxf(worst_ratio, absf(h) / hs)
	_check(all_finite, "el barrido de furia no produce NaN ni infinitos")
	# Una ola individual puede pasar de Hs, pero no por un factor absurdo.
	_check(worst_ratio < 2.5, "las alturas se quedan en un rango fisico",
		"pico observado %.2f x Hs" % worst_ratio)


## Por encima del limite de steepness la superficie se auto-intersecta.
func _test_steepness_guard() -> void:
	var proxy := OceanWaveProxy.new()
	proxy.generate(99, 10, 0.0)
	var worst: float = 0.0
	for step in 101:
		var fury: float = float(step) * 0.1
		proxy.set_sea_state(_hs_for(fury), lerpf(0.15, 2.0, fury / 10.0)) # pedimos de mas a proposito
		worst = maxf(worst, proxy.steepness_sum())
	_check(worst <= OceanWaveProxy.STEEPNESS_LIMIT + 1e-4,
		"el guard de steepness aguanta aunque se pida de mas",
		"maximo alcanzado %.4f" % worst)


## El barco tiene que asentarse a un calado estable en mar plano, sin hundirse ni
## salir volando, y sin temblar.
func _test_boat_floats() -> void:
	Ocean.set_fury_immediate(0.0)
	var boat: FloatingBody3D = load("res://game/boat/fishing_boat.tscn").instantiate()
	add_child(boat)
	boat.global_position = Vector3(0, 4, 0)

	for _i in SETTLE_TICKS:
		await get_tree().physics_frame

	var y := boat.global_position.y
	var speed := boat.linear_velocity.length()
	_check(is_finite(y) and absf(y) < 5.0, "el barco se asienta en vez de hundirse o salir volando",
		"y = %.2f m" % y)
	_check(speed < 0.35, "el calado es estable, sin temblor", "velocidad residual %.3f m/s" % speed)
	_check(boat.submerged_fraction > 0.05 and boat.submerged_fraction < 0.95,
		"el calado es razonable", "sumergido %.0f%%" % (boat.submerged_fraction * 100.0))
	boat.queue_free()


## El detector del "bug del barril cohete": sin el clamp de profundidad, un
## cuerpo que cae desde la cresta de una ola grande sale disparado.
func _test_no_rocket_barrels() -> void:
	var bodies: Array[FloatingBody3D] = []
	var boat: FloatingBody3D = load("res://game/boat/fishing_boat.tscn").instantiate()
	add_child(boat)
	boat.global_position = Vector3(0, 2, 0)
	bodies.append(boat)

	var barrel_scene := load("res://game/boat/barrel.tscn")
	for i in 12:
		var barrel: FloatingBody3D = barrel_scene.instantiate()
		add_child(barrel)
		# A proposito: algunos empiezan muy por debajo del agua, que es el caso
		# exacto que dispara el bug.
		# Lejos del casco: si nacen dentro, el pico de velocidad que mide el
		# test es el de Jolt resolviendo la penetracion, no el de la flotabilidad.
		var ang: float = TAU * float(i) / 12.0
		barrel.global_position = Vector3(cos(ang) * 22.0, -8.0 + float(i) * 0.6, sin(ang) * 22.0)
		bodies.append(barrel)

	var worst_speed: float = 0.0
	var worst_owner := ""
	# Barrido completo de furia con todo en el agua a la vez.
	for step in 40:
		Ocean.set_fury_immediate(float(step) * 0.25)
		for _i in 25:
			await get_tree().physics_frame
			for body in bodies:
				var s := body.linear_velocity.length()
				if s > worst_speed:
					worst_speed = s
					worst_owner = body.name

	_check(worst_speed < 45.0, "nada sale disparado durante el barrido de furia",
		"pico %.1f m/s en %s" % [worst_speed, worst_owner])

	for body in bodies:
		body.queue_free()


func _hs_for(fury: float) -> float:
	var f: float = clampf(fury, 0.0, 10.0)
	var i: int = int(floor(f))
	if i >= Ocean.DOUGLAS_HS.size() - 1:
		return Ocean.DOUGLAS_HS[-1]
	return lerpf(Ocean.DOUGLAS_HS[i], Ocean.DOUGLAS_HS[i + 1], f - float(i))
