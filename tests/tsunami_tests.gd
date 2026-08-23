extends Node

## Pruebas del modo tsunami.
##
##   godot --headless --path . tests/tsunami_tests.tscn
##
## La comprobacion central es la de "consultar el futuro": todo el diseño (la
## telegrafia, el HUD, el audio de aviso, la sincronizacion en red con 50 bytes)
## depende de que el oceano sea una funcion PURA de t. Si eso se rompe, se rompe
## el climax del juego y no hay ningun error que lo avise.

var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0


func _ready() -> void:
	print_rich("[b]--- Pruebas del modo tsunami ---[/b]")
	_test_future_query_matches_reality()
	_test_telegraph_is_accurate()
	_test_retreat_precedes_crest()
	_test_front_registers_as_breaking()
	_test_determinism()
	_test_water_pushes_then_pulls()
	await _test_boat_survives_a_tsunami()
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


func _fresh() -> OceanEvents:
	var ev := OceanEvents.new()
	# Origen 4 km al este, avanzando hacia -X, cresta pasando por el origen en t=0.
	ev.spawn(Vector2(4000.0, 0.0), Vector2(-1.0, 0.0), 18.0, 45.0, 90.0, 0.0)
	return ev


# =============================================================================


## LA COMPROBACION QUE SOSTIENE EL DISEÑO. Preguntar hoy "que altura habra aqui
## dentro de 60 s" tiene que dar exactamente lo que se mide cuando llegue ese
## momento. Es lo que permite telegrafiar el tsunami sin ningun sistema de
## prediccion, y lo que hace que 6 clientes coincidan replicando 50 bytes.
func _test_future_query_matches_reality() -> void:
	var ev := _fresh()
	var p := Vector2(0.0, 0.0)
	var worst: float = 0.0
	for i in 200:
		var future_t: float = float(i) * 0.85
		# "Prediccion" hecha en t=0 frente a la evaluacion real en ese instante.
		var predicted := ev.height_at(p, future_t)
		var actual := ev.height_at(p, future_t)
		worst = maxf(worst, absf(predicted - actual))
	# Y ademas contra la API completa de Ocean, que suma oleaje base + evento.
	var pos := Vector3(12.0, 0.0, -30.0)
	Ocean.clear_events()
	Ocean.spawn_tsunami(pos, 90.0, 40.0, 18.0, 45.0, 90.0)
	var t_future: float = Ocean.sim_time + 25.0
	var predicted_full := Ocean.get_height_at(pos, t_future)
	var saved := Ocean.sim_time
	Ocean.sim_time = t_future
	var actual_full := Ocean.get_height(pos)
	Ocean.sim_time = saved
	worst = maxf(worst, absf(predicted_full - actual_full))
	Ocean.clear_events()
	_check(worst < 1e-4, "consultar el futuro da exactamente lo que pasara",
		"desviacion maxima %.8f m" % worst)


## El contador que ve el jugador tiene que corresponder con la ola de verdad.
func _test_telegraph_is_accurate() -> void:
	var ev := _fresh()
	var p := Vector2(0.0, 0.0)
	var predicted := ev.time_until_crest(p, 0.0)

	# Buscar cuando ocurre de verdad la altura maxima en ese punto.
	var best_t: float = 0.0
	var best_h: float = -INF
	var t: float = predicted - 40.0
	while t < predicted + 40.0:
		var h := ev.height_at(p, t)
		if h > best_h:
			best_h = h
			best_t = t
		t += 0.05
	_check(absf(best_t - predicted) < 1.5, "la telegrafia coincide con la ola real",
		"predicho %.2f s, real %.2f s" % [predicted, best_t])
	_check(best_h > 12.0, "el muro llega con altura de muro", "pico %.2f m" % best_h)


## La retirada del mar no esta scripteada: sale de que la depresion viaja por
## delante de la cresta. Si esto falla, el mejor momento del modo desaparece.
func _test_retreat_precedes_crest() -> void:
	var ev := _fresh()
	var p := Vector2(0.0, 0.0)
	var crest_t := ev.time_until_crest(p, 0.0)

	var min_t: float = 0.0
	var min_h: float = INF
	var t: float = crest_t - 120.0
	while t < crest_t + 20.0:
		var h := ev.height_at(p, t)
		if h < min_h:
			min_h = h
			min_t = t
		t += 0.05

	_check(min_h < -5.0, "el mar se retira de verdad", "bajada maxima %.2f m" % min_h)
	_check(min_t < crest_t, "la retirada ocurre ANTES del muro",
		"minimo en %.1f s, cresta en %.1f s" % [min_t, crest_t])
	_check(crest_t - min_t > 15.0, "hay tiempo de reaccion entre retirada e impacto",
		"solo %.1f s" % (crest_t - min_t))


## La cara del muro tiene que contar como rotura, o no se pintaria blanca y el
## jugador no podria leer donde le va a doler.
func _test_front_registers_as_breaking() -> void:
	var ev := _fresh()
	var p := Vector2(0.0, 0.0)
	var crest_t := ev.time_until_crest(p, 0.0)
	var worst_penalty: float = 0.0
	var t: float = crest_t - 12.0
	while t < crest_t + 12.0:
		worst_penalty = maxf(worst_penalty, ev.break_penalty_at(p, t))
		t += 0.05
	# El Jacobiano del oleaje ronda 1.0; la penalizacion tiene que poder
	# empujarlo por debajo de cero.
	_check(worst_penalty > 1.15, "la cara del muro cuenta como rotura",
		"penalizacion maxima %.3f" % worst_penalty)


func _test_determinism() -> void:
	var a := _fresh()
	var b := _fresh()
	var worst: float = 0.0
	for i in 400:
		var p := Vector2(float(i) * 7.3 - 1000.0, float(i) * -3.1)
		var t: float = float(i) * 0.31
		worst = maxf(worst, absf(a.height_at(p, t) - b.height_at(p, t)))
		worst = maxf(worst, (a.velocity_at(p, t) - b.velocity_at(p, t)).length())
	_check(worst < 1e-9, "el evento es determinista", "desviacion %.12f" % worst)


## Durante la retirada el agua tira de ti MAR ADENTRO; con la cresta te EMPUJA.
## Es lo que convierte la retirada en una trampa en vez de en una pausa.
func _test_water_pushes_then_pulls() -> void:
	var ev := _fresh()
	var p := Vector2(0.0, 0.0)
	var crest_t := ev.time_until_crest(p, 0.0)
	var dir := Vector2(-1.0, 0.0) # direccion de avance del tsunami

	var pull: float = 0.0
	var push: float = 0.0
	var t: float = crest_t - 120.0
	while t < crest_t + 10.0:
		var v := ev.velocity_at(p, t)
		var along: float = Vector2(v.x, v.z).dot(dir)
		pull = minf(pull, along)
		push = maxf(push, along)
		t += 0.05

	_check(push > 3.0, "la cresta empuja con fuerza", "empuje maximo %.2f m/s" % push)
	_check(pull < -3.0, "la retirada arrastra mar adentro", "arrastre maximo %.2f m/s" % pull)


## Un tsunami completo con el barco y la carga encima: nada puede explotar, salir
## disparado ni producir NaN, y el barco tiene que SUBIR de verdad con el muro.
func _test_boat_survives_a_tsunami() -> void:
	Ocean.clear_events()
	Ocean.set_fury_immediate(6.0)

	var boat: FloatingBody3D = load("res://game/boat/fishing_boat.tscn").instantiate()
	add_child(boat)
	boat.global_position = Vector3(0, 2, 0)

	var barrels: Array[FloatingBody3D] = []
	var barrel_scene := load("res://game/boat/barrel.tscn")
	for i in 6:
		var b: FloatingBody3D = barrel_scene.instantiate()
		add_child(b)
		b.global_position = Vector3(float(i) * 1.0 - 2.5, 3.0, 0.8)
		barrels.append(b)

	for _i in 240:
		await get_tree().physics_frame

	# Parametros comprimidos para que el barrido quepa en un test: mismo perfil,
	# escala temporal mas corta.
	Ocean.spawn_tsunami(boat.global_position, 90.0, 20.0, 19.0, 90.0, 45.0)

	var min_y: float = INF
	var max_y: float = -INF
	var worst_speed: float = 0.0
	var any_nan := false

	for _i in 3600:
		await get_tree().physics_frame
		var y := boat.global_position.y
		if not is_finite(y):
			any_nan = true
			break
		min_y = minf(min_y, y)
		max_y = maxf(max_y, y)
		worst_speed = maxf(worst_speed, boat.linear_velocity.length())
		for b in barrels:
			worst_speed = maxf(worst_speed, b.linear_velocity.length())

	_check(not any_nan, "el tsunami no produce NaN")
	_check(max_y - min_y > 8.0, "el barco sube de verdad con el muro",
		"recorrido vertical %.1f m" % (max_y - min_y))
	_check(min_y < -3.0, "el barco baja con la retirada", "minimo %.1f m" % min_y)
	_check(worst_speed < 60.0, "nada sale disparado durante el tsunami",
		"pico %.1f m/s" % worst_speed)

	Ocean.clear_events()
	boat.queue_free()
	for b in barrels:
		b.queue_free()
