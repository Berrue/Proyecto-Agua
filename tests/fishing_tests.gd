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
	_test_fish_takes_line()
	_test_hold_click_is_not_a_strategy()
	_test_slack_spits_with_warning()
	_test_fish_tires()
	await _test_fish_body()
	await _test_wiring()
	_test_sfx_library()
	_test_nibble_plan()
	await _test_camera_feedback()
	await _test_fishing_hud()
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


## EL PEZ SE LLEVA SEDAL: durante el tiron sin contra el progreso BAJA, y la
## contra correcta lo frena a un cuarto. Sin esto no hay tira-y-afloja.
func _test_fish_takes_line() -> void:
	var free := FightModel.new()
	free.start(_atun(), _rng(31))
	var held := FightModel.new()
	held.start(_atun(), _rng(31)) # misma semilla: mismas fases

	var opposite: FightModel.Pull = FightModel.Pull.LEFT 		if free.pull_dir == FightModel.Pull.RIGHT else FightModel.Pull.RIGHT
	free.progress = 0.5
	held.progress = 0.5
	# Un segundo de tiron: uno lo deja correr, el otro contra bien.
	for _i in 60:
		if not free.is_pulling():
			break
		free.step(1.0 / 60.0, false, FightModel.Pull.NONE, 0.0)
		held.step(1.0 / 60.0, false, opposite, 0.0)
	_check(free.progress < 0.5, "el pez sin contra se lleva sedal",
		"progreso %.3f" % free.progress)
	_check(held.progress > free.progress, "la contra frena la sangria",
		"contra %.3f vs libre %.3f" % [held.progress, free.progress])


## LA QUEJA DEL PLAYTEST, convertida en test: mantener el clic sin hacer nada
## mas NO puede ganar rapido. Con un bacalao la tension de recoger contra el
## tiron tiene que acercarse a la rotura incluso en calma.
func _test_hold_click_is_not_a_strategy() -> void:
	var m := FightModel.new()
	m.start(FishSpecies.SPECIES[3], _rng(41)) # Bacalao, pull 0.55
	var peak: float = 0.0
	var t: float = 0.0
	while not m.landed and not m.snapped and not m.escaped and t < 25.0:
		m.step(1.0 / 60.0, true, FightModel.Pull.NONE, 0.0) # solo mantener clic
		if m.is_pulling():
			peak = maxf(peak, m.tension)
		t += 1.0 / 60.0
	_check(peak >= FightModel.SNAP_TENSION,
		"recoger a lo bruto contra un bacalao roza la rotura incluso en calma",
		"pico %.2f" % peak)
	_check(m.snapped or t > 20.0, "y mantener clic no gana rapido",
		"landed=%s en %.1f s" % [m.landed, t])


## NO recoger tambien pierde: sedal flojo sostenido = el pez escupe, y el aviso
## llega ANTES del fallo (la regla de justicia, ahora tambien por defecto).
func _test_slack_spits_with_warning() -> void:
	var m := FightModel.new()
	m.start(_sardina(), _rng(51))
	var warned_before_escape := false
	var t: float = 0.0
	while not m.escaped and t < 30.0:
		if m.is_spit_warning() and not m.escaped:
			warned_before_escape = true
		m.step(1.0 / 60.0, false, FightModel.Pull.NONE, 0.0) # ignorar la caña
		t += 1.0 / 60.0
	_check(m.escaped, "ignorar la caña pierde el pez", "t=%.1f" % t)
	_check(warned_before_escape, "y el aviso llego ANTES del fallo")
	_check(not m.snapped, "escupir no es romper: fallo blando")


## El pez se cansa TIRANDO: los tirones se debilitan y se ve ganar sin barras.
func _test_fish_tires() -> void:
	var m := FightModel.new()
	m.start(_atun(), _rng(61))
	for _i in 600: # 10 s de lucha activa
		var counter: FightModel.Pull = FightModel.Pull.LEFT 			if m.pull_dir == FightModel.Pull.RIGHT else FightModel.Pull.RIGHT
		m.step(1.0 / 60.0, not m.is_pulling(), counter, 0.0)
		if m.landed or m.snapped or m.escaped:
			break
	_check(m.stamina < 0.9, "el pez se cansa peleando", "fuelle %.2f" % m.stamina)


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


## Cableado: el pescador esta montado, en primera persona solo se le ven las
## manos (ni cuerpo ni cuello), la caña cuelga de la camara con su escena de pez
## asignada, y las manos ocupadas bloquean el movimiento de verdad.
func _test_wiring() -> void:
	var scene: Node3D = load("res://game/world/toybox.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame

	var player := scene.get_node(^"Player") as Player
	var model := player.get_node_or_null(^"Pescador")
	_check(model != null, "el pescador esta montado en el jugador")
	if model != null:
		var solo_sombra := GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		var drawn: Array[String] = []
		for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			if mesh.visible and mesh.cast_shadow != solo_sombra:
				drawn.append(mesh.name)
		_check(drawn.is_empty(), "no se dibuja ni una pieza del cuerpo en primera persona",
			"se dibujan: %s" % ", ".join(drawn))
		var neck := model.find_child("cuello", true, false) as MeshInstance3D
		_check(neck != null and neck.cast_shadow == solo_sombra,
			"el cuello tampoco (era lo que mas cantaba al mirar abajo)")
		var torso := model.find_child("chubasquero_cuerpo", true, false) as MeshInstance3D
		_check(torso != null and torso.cast_shadow == solo_sombra,
			"pero el cuerpo sigue proyectando sombra en cubierta")

		_check(player.hands.size() == 2, "las dos manos existen como viewmodel",
			"hay %d" % player.hands.size())
		for hand: MeshInstance3D in player.hands:
			_check(hand.visible and hand.is_inside_tree(), "la mano %s se dibuja" % hand.name)
			_check(hand.get_parent() != null and hand.get_parent().name == "RodPivot",
				"y cuelga del mango de la caña, no de la camara")

		# El toggle de tercera persona (capturas y, manana, los demas jugadores).
		player.set_body_visible(true)
		var back: MeshInstance3D = model.find_child("chubasquero_cuerpo", true, false)
		_check(back != null and back.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
			"en tercera persona vuelve el cuerpo entero")
		_check(not player.hands[0].visible, "y se apagan las manos del viewmodel")
		player.set_body_visible(false)

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


# =============================================================================
#  Game feel
# =============================================================================

## La fabrica de sonidos: todo generado, formato correcto, y el loop de buzz
## con su bucle cerrado (es el sustituto del scheduler a alta tasa).
func _test_sfx_library() -> void:
	_check(SfxLibrary.reel_clicks.size() >= 4, "hay variantes de click de carrete",
		"%d" % SfxLibrary.reel_clicks.size())
	var all_ok := true
	var pools: Array = [SfxLibrary.reel_clicks, SfxLibrary.creak_pulses,
		SfxLibrary.splashes, SfxLibrary.jingles,
		[SfxLibrary.plip, SfxLibrary.chomp, SfxLibrary.snap, SfxLibrary.thud,
		SfxLibrary.lap, SfxLibrary.reel_buzz]]
	for pool in pools:
		for wav in pool:
			var w := wav as AudioStreamWAV
			if w == null or w.data.is_empty() or w.mix_rate != SfxLibrary.RATE 					or w.format != AudioStreamWAV.FORMAT_16_BITS:
				all_ok = false
	_check(all_ok, "todos los sonidos generados en 16 bits a 22050 Hz")
	_check(SfxLibrary.reel_buzz.loop_mode == AudioStreamWAV.LOOP_FORWARD
		and SfxLibrary.reel_buzz.loop_end > 0, "el buzz es un loop cerrado")
	_check(SfxLibrary.jingles.size() == 3
		and SfxLibrary.jingles[2].data.size() > SfxLibrary.jingles[0].data.size(),
		"3 jingles y el epico dura mas que el comun")

	# La curva del click train: silencio = vas bien; el maximo ronda 22 Hz.
	_check(SfxLibrary.click_rate_for(0.2) == 0.0, "bajo 30% de tension, silencio")
	_check(SfxLibrary.click_rate_for(0.5) > 3.0, "a media tension, clicks")
	var top := SfxLibrary.click_rate_for(1.0)
	_check(absf(top - 22.0) < 0.5, "a tension maxima ~22 Hz", "%.1f" % top)

	_check(AudioServer.get_bus_index("Reel") != -1 and AudioServer.get_bus_index("SFX") != -1,
		"los buses Reel y SFX existen")


## El plan de nibbles: 1-4 toques falsos, separados 0.5-1.5 s. Tras el ultimo,
## el mordisco esta garantizado (eso lo hace la maquina de estados).
func _test_nibble_plan() -> void:
	var rng := _rng(77)
	var ok := true
	for _i in 200:
		var plan := FishingRod.plan_nibbles(rng)
		if plan.size() < 1 or plan.size() > 4:
			ok = false
		for d in plan:
			if d < 0.5 or d > 1.5:
				ok = false
	_check(ok, "el plan de nibbles respeta 1-4 toques de 0.5-1.5 s")


## La camara: el trauma decae solo, el FOV vuelve a su base, y nada rota jamas.
func _test_camera_feedback() -> void:
	var cam := CameraFeedback.new()
	cam.fov = 78.0
	add_child(cam)
	await get_tree().process_frame

	var base_rot := cam.rotation
	cam.add_trauma(0.6)
	var moved := false
	for _i in 20:
		await get_tree().process_frame
		if cam.position.length() > 0.001:
			moved = true
	_check(moved, "el trauma mueve la camara (traslacion)")
	_check(cam.rotation == base_rot, "y JAMAS la rota (regla anti-mareo)")

	for _i in 60:
		await get_tree().process_frame
	_check(cam.position.length() < 0.002, "el trauma decae solo",
		"offset %.4f" % cam.position.length())

	cam.kick_fov(4.0, 0.05, 0.0, 0.1)
	await get_tree().create_timer(0.08).timeout
	var kicked: float = cam.fov
	await get_tree().create_timer(0.4).timeout
	_check(kicked > 78.5, "el kick de FOV empuja", "%.1f" % kicked)
	_check(absf(cam.fov - 78.0) < 0.2, "y vuelve solo a la base", "%.1f" % cam.fov)

	cam.kick_fov(20.0, 0.01, 0.0, 0.01)
	await get_tree().create_timer(0.05).timeout
	_check(cam.fov <= 83.1, "el tope duro de +-5 grados aguanta", "%.1f" % cam.fov)

	cam.queue_free()
	await get_tree().process_frame


## La UI de pesca del playtest: "!" al picar, flecha con la tecla correcta en
## la lucha, RECOGE en la pausa, y resultados con su color.
func _test_fishing_hud() -> void:
	var scene: Node3D = load("res://game/world/toybox.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame

	var rod := scene.get_node(^"Player/Camera3D/FishingRod") as FishingRod
	var hud: FishingHud = rod._hud
	_check(hud != null, "la caña tiene HUD de pesca")
	if hud == null:
		scene.queue_free()
		return

	hud.show_bite()
	_check(hud._bite_mark.visible, "al picar aparece el ! en pantalla")

	hud.on_hooked()
	_check(not hud._bite_mark.visible and hud._fight_box.visible,
		"al clavar el ! se va y entra el panel de lucha")

	# El pez tira a la IZQUIERDA -> la flecha pide D (->).
	hud.update_fight(FightModel.Pull.LEFT, false, 0.4, 0.5, false, false)
	_check(hud._arrow.visible and hud._arrow.text.contains("D"),
		"pez tirando IZQ pide la tecla D", hud._arrow.text)
	hud.update_fight(FightModel.Pull.RIGHT, false, 0.4, 0.5, false, false)
	_check(hud._arrow.text.contains("A"), "pez tirando DER pide la tecla A")

	# En la pausa: RECOGE; con el anzuelo soltandose: RECOGE YA.
	hud.update_fight(FightModel.Pull.NONE, true, 0.1, 0.5, false, false)
	_check(not hud._arrow.visible and hud._action.text.contains("RECOGE"),
		"la pausa pide RECOGER")
	hud.update_fight(FightModel.Pull.NONE, true, 0.1, 0.5, true, false)
	_check(hud._action.text.contains("SE SUELTA"), "el aviso de escupida grita")

	# Tension critica mientras recoges: SUELTA en rojo.
	hud.update_fight(FightModel.Pull.LEFT, false, 0.9, 0.5, false, true)
	_check(hud._action.text.contains("SUELTA"), "la tension critica pide SOLTAR")

	# Resultado: aparece y se desvanece solo.
	hud.show_result("¡Bacalao · 12 kg!", Color.GOLD)
	_check(hud._result.visible and not hud._fight_box.visible,
		"el resultado se planta y la lucha se esconde")
	await get_tree().create_timer(2.3).timeout
	_check(not hud._result.visible, "y se desvanece solo")

	scene.queue_free()
	await get_tree().process_frame
