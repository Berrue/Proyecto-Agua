extends Node

## Pruebas de la caña.
##
##   godot --headless --path . tests/fishing_tests.tscn
##
## FightModel esta separado del nodo justo para esto: la matematica de la lucha
## se prueba directa, sin simular teclas. Lo que se protege: que el MAR entra de
## verdad en la tension (la tesis del juego), que la contra funciona, que la
## rotura avisa antes de romper (justicia), y que una lucha bien jugada TERMINA.

var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0


func _ready() -> void:
	print_rich("[b]--- Pruebas de pesca ---[/b]")
	_test_sea_enters_tension()
	_test_counter_works()
	_test_warn_before_snap()
	_test_snap_on_sustained_greed()
	_test_clean_fight_lands()
	_test_species_bands()
	await _test_fish_body()
	await _test_wiring()
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


func _rng(seed_val: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_val
	return r


func _sardina() -> Dictionary:
	return FishSpecies.SPECIES[0]


func _atun() -> Dictionary:
	return FishSpecies.SPECIES[-1]


# =============================================================================


## LA TESIS: el mismo pez con el mismo input tensa mas el sedal cuanto mas se
## mueve la cubierta. Si esto falla, la pesca y el mar son dos juegos separados.
func _test_sea_enters_tension() -> void:
	var calm := FightModel.new()
	calm.start(_sardina(), _rng(7))
	var storm := FightModel.new()
	storm.start(_sardina(), _rng(7)) # misma semilla: mismas fases del pez

	calm.step(0.1, false, FightModel.Pull.NONE, 0.0)
	storm.step(0.1, false, FightModel.Pull.NONE, 8.0) # borda de furia 7-8

	var diff: float = storm.tension - calm.tension
	_check(absf(diff - FightModel.SEA_K * 8.0) < 1e-6,
		"la aceleracion de la borda entra directa en la tension",
		"delta %.3f (esperado %.3f)" % [diff, FightModel.SEA_K * 8.0])


func _test_counter_works() -> void:
	var against := FightModel.new()
	against.start(_atun(), _rng(11))
	var with_it := FightModel.new()
	with_it.start(_atun(), _rng(11))

	# Misma semilla: ambos peces tiran en la misma direccion. Uno contra bien,
	# el otro contra MAL (a favor del tiron).
	var dir: FightModel.Pull = against.pull_dir
	var opposite: FightModel.Pull = FightModel.Pull.LEFT if dir == FightModel.Pull.RIGHT else FightModel.Pull.RIGHT
	against.step(0.1, false, opposite, 0.0)
	with_it.step(0.1, false, dir, 0.0)

	_check(against.tension < with_it.tension, "contrar bien reduce la tension",
		"contra %.2f vs error %.2f" % [against.tension, with_it.tension])
	_check(against.tension > 0.1, "pero no la anula: el pez sigue siendo un pez",
		"%.2f" % against.tension)


## JUSTICIA: entre "el carrete chirria" y "el sedal rompe" tiene que haber
## margen real de reaccion, en cualquier condicion.
func _test_warn_before_snap() -> void:
	_check(FightModel.WARN_TENSION < FightModel.SNAP_TENSION,
		"el aviso llega antes que la rotura")
	# Y la rotura exige SOSTENER la sobrecarga, no un pico de un frame.
	var m := FightModel.new()
	m.start(_atun(), _rng(3))
	m.step(0.1, true, FightModel.Pull.NONE, 20.0) # un solo tick brutal
	_check(not m.snapped, "un pico de un frame no rompe el sedal",
		"T=%.2f" % m.tension)


## La codicia rompe: recoger contra un atun que tira, con la cubierta de furia
## alta, tiene que partir el sedal en menos de dos segundos de insistencia.
func _test_snap_on_sustained_greed() -> void:
	var m := FightModel.new()
	m.start(_atun(), _rng(5))
	var t: float = 0.0
	while not m.snapped and t < 10.0:
		# Siempre recogiendo, siempre contrando MAL, mar de furia 7.
		m.step(1.0 / 60.0, true, m.pull_dir, 7.0)
		t += 1.0 / 60.0
	_check(m.snapped, "la codicia sostenida rompe el sedal")
	_check(not m.landed, "y el pez se pierde")


## Una lucha bien jugada (contrar el tiron, recoger solo en la pausa) TIENE que
## terminar con el pez fuera del agua, sin romper, en tiempo razonable.
func _test_clean_fight_lands() -> void:
	var m := FightModel.new()
	m.start(_sardina(), _rng(21))
	var t: float = 0.0
	while not m.landed and not m.snapped and t < 60.0:
		var counter := FightModel.Pull.NONE
		if m.pull_dir == FightModel.Pull.LEFT:
			counter = FightModel.Pull.RIGHT
		elif m.pull_dir == FightModel.Pull.RIGHT:
			counter = FightModel.Pull.LEFT
		m.step(1.0 / 60.0, not m.is_pulling(), counter, 1.0) # mar tranquilo
		t += 1.0 / 60.0
	_check(m.landed and not m.snapped, "la lucha limpia termina en captura",
		"landed=%s snapped=%s t=%.1f" % [m.landed, m.snapped, t])
	_check(t > 3.0 and t < 30.0, "y dura lo que una lucha (3-30 s)", "%.1f s" % t)


## Las bandas de especies respetan la furia: el pez caro vive en el mar malo.
func _test_species_bands() -> void:
	var rng := _rng(99)
	var calm_ok := true
	for _i in 300:
		var s := FishSpecies.choose(1.0, rng)
		if float(s[&"min_fury"]) > 1.0:
			calm_ok = false
	_check(calm_ok, "con furia 1 solo pican especies de calma")

	var saw_tuna := false
	for _i in 300:
		var s := FishSpecies.choose(7.5, rng)
		if String(s[&"name"]) == "Atun":
			saw_tuna = true
	_check(saw_tuna, "con furia 7.5 el atun existe")


## El pez fisico: masa real, escala por peso, y FLOTA si cae al agua.
func _test_fish_body() -> void:
	Ocean.set_fury_immediate(0.0)
	var fish: Fish = load("res://game/fishing/fish.tscn").instantiate()
	add_child(fish)
	fish.setup(_atun())
	fish.global_position = Vector3(50, 2, 50)

	_check(fish.mass == 60.0, "el atun pesa 60 kg de verdad", "%.0f" % fish.mass)
	_check(fish.species_name == "Atun" and fish.value == 450, "especie y valor")

	for _i in 500:
		await get_tree().physics_frame
	var y := fish.global_position.y
	_check(is_finite(y) and absf(y) < 2.0, "el pez flota en vez de hundirse o volar",
		"y=%.2f" % y)
	fish.queue_free()


## Cableado: el pescador esta montado, la cabeza oculta en primera persona, la
## caña cuelga de la camara con su escena de pez asignada, y las manos ocupadas
## bloquean el movimiento de verdad.
func _test_wiring() -> void:
	var scene: Node3D = load("res://game/world/toybox.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame

	var player := scene.get_node(^"Player") as Player
	var model := player.get_node_or_null(^"Pescador")
	_check(model != null, "el pescador esta montado en el jugador")
	if model != null:
		var head := model.find_child("cabeza", true, false) as Node3D
		var hat := model.find_child("sombrero", true, false) as Node3D
		_check(head != null and not head.visible, "la cabeza esta oculta en primera persona")
		_check(hat != null and not hat.visible, "el sombrero tambien")
		var torso := model.find_child("torso", true, false) as Node3D
		_check(torso != null and torso.visible, "el cuerpo sigue visible (te ves al mirar abajo)")

	var rod := player.get_node_or_null(^"Camera3D/FishingRod") as FishingRod
	_check(rod != null, "la caña cuelga de la camara")
	if rod != null:
		_check(rod.fish_scene != null, "con su escena de pez asignada")
		_check(rod.get_node_or_null(^"RodPivot/Tip") != null, "y su punta para el sedal")

	player.hands_busy = true
	_check(player._input_direction() == Vector3.ZERO,
		"con las manos ocupadas no se puede andar")
	player.hands_busy = false

	var hud := scene.get_node(^"OceanDebugHUD")
	_check(hud.get_node_or_null(hud.rod_path) != null, "el HUD encuentra la caña")

	scene.queue_free()
	await get_tree().process_frame
