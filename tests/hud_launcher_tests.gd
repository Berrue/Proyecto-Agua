extends Node

## Pruebas del lanzador de tsunamis del HUD de debug.
##
##   godot --headless --path . tests/hud_launcher_tests.tscn
##
## Un lanzador de debug parece algo que no merece test, pero lo que se rompe aqui
## es el CABLEADO: exports sin asignar en una de las dos escenas, botones que no
## se crean, o teclas que nunca llegan porque otro nodo se come el evento. Todo
## eso falla en silencio y solo se descubre en mitad de un playtest, que es justo
## cuando no quieres estar depurando.

var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0


func _ready() -> void:
	print_rich("[b]--- Pruebas del lanzador del HUD ---[/b]")
	_test_tecla_ene()
	await _test_scene("res://game/world/toybox.tscn", false)
	await _test_scene("res://game/world/tsunami.tscn", true)
	_report()


## Las tres vias por las que puede llegar la Ñ. Se prueban sueltas porque el
## fallo que esconden es MUDO: en un teclado que no es el del que programo esto,
## la tecla simplemente no abre nada y no hay ni un error que mirar.
func _test_tecla_ene() -> void:
	var escribe := InputEventKey.new()
	escribe.unicode = 241 # ñ
	_check(OceanDebugHUD.es_tecla_menu(escribe), "la ñ que se escribe abre el menu")

	var mayus := InputEventKey.new()
	mayus.unicode = 209 # Ñ, con bloq. mayus o con shift
	_check(OceanDebugHUD.es_tecla_menu(mayus), "y la Ñ mayuscula tambien")

	var etiqueta := InputEventKey.new()
	etiqueta.key_label = 241 as Key
	_check(OceanDebugHUD.es_tecla_menu(etiqueta), "y la etiqueta localizada de la tecla")

	# Quien no tiene Ñ en el teclado: la POSICION de la Ñ española es la del
	# `;` en un QWERTY US. Sin esto se quedaria sin menu de debug.
	var fisica := InputEventKey.new()
	fisica.physical_keycode = KEY_SEMICOLON
	_check(OceanDebugHUD.es_tecla_menu(fisica), "y su posicion fisica en un QWERTY US")

	# Y no se abre con cualquier cosa: las teclas del propio HUD no son la puerta.
	var otra := InputEventKey.new()
	otra.keycode = KEY_3
	otra.unicode = 51 # '3'
	_check(not OceanDebugHUD.es_tecla_menu(otra), "y una tecla cualquiera no la abre")


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


## Una tecla por el camino REAL (`Input.parse_input_event`): es lo unico que
## comprueba que el evento llega al HUD y no se lo come otro nodo antes.
func _pulsar(keycode: Key) -> void:
	var key := InputEventKey.new()
	key.keycode = keycode
	key.pressed = true
	Input.parse_input_event(key)


## La Ñ no tiene constante en `Key`, asi que se manda como la manda un teclado
## español: por el caracter que ESCRIBE.
func _pulsar_ene() -> void:
	var key := InputEventKey.new()
	key.unicode = 241
	key.pressed = true
	Input.parse_input_event(key)


func _find_hud(root: Node) -> OceanDebugHUD:
	for child in root.get_children():
		if child is OceanDebugHUD:
			return child
	return null


func _test_scene(path: String, has_director: bool) -> void:
	var label := path.get_file()
	Ocean.clear_events()

	var scene: Node3D = load(path).instantiate()
	add_child(scene)
	for _i in 10:
		await get_tree().process_frame

	var hud := _find_hud(scene)
	_check(hud != null, "%s tiene HUD" % label)
	if hud == null:
		scene.queue_free()
		return

	# 0) LA PUERTA. El menu nace cerrado y sus atajos no existen hasta abrirlo:
	#    si la Ñ fuera solo un interruptor de visibilidad, `3` seguiria lanzando
	#    un tsunami con el panel apagado y cerrarlo no serviria de nada.
	_check(not hud.visible, "%s: el menu de debug nace cerrado" % label)
	_pulsar(KEY_3)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not Ocean.has_tsunami(),
		"%s: cerrado, la tecla 3 no lanza nada" % label)

	_pulsar_ene()
	await get_tree().process_frame
	_check(hud.visible, "%s: la Ñ abre el menu" % label)

	# 1) Los exports estan asignados EN LA ESCENA. Es el fallo mas probable:
	#    funciona en una escena y en la otra el array esta vacio.
	_check(hud.tsunami_tiers.size() == 3 and not hud.tsunami_tiers.has(null),
		"%s tiene los 3 tiers asignados" % label,
		"%d asignados" % hud.tsunami_tiers.size())

	# 2) Un boton por tier, mas el de limpiar.
	var buttons := hud.get_node("%TsunamiButtons")
	_check(buttons.get_child_count() == 4, "%s crea 3 botones + limpiar" % label,
		"%d botones" % buttons.get_child_count())

	# 3) Pulsar un boton lanza EL tier correcto, con el aviso que marca el slider.
	var lead_slider: HSlider = hud.get_node("%LeadSlider")
	lead_slider.value = 33.0
	var boat: Node3D = scene.get_node("FishingBoat")

	(buttons.get_child(1) as Button).pressed.emit() # el segundo tier: COLOSO
	await get_tree().physics_frame

	_check(Ocean.has_tsunami(), "%s: el boton lanza un tsunami" % label)
	_check(Ocean.current_tier != null and Ocean.current_tier.tier_name == "COLOSO",
		"%s: lanza el tier del boton pulsado" % label,
		"salio %s" % (Ocean.current_tier.tier_name if Ocean.current_tier else "nada"))

	var eta := Ocean.time_until_tsunami(boat.global_position)
	_check(absf(eta - 33.0) < 1.0, "%s: respeta el aviso del deslizador" % label,
		"pedidos 33 s, salen %.1f s" % eta)

	# 4) En la escena con director, lanzar a mano lo DETIENE: si no, su ciclo
	#    llamaria a clear_events() y el tsunami del jugador desapareceria solo.
	if has_director:
		var director: TsunamiDirector = scene.get_node("TsunamiDirector")
		_check(not director.is_running(),
			"%s: lanzar a mano detiene al director" % label)

	# 5) La tecla 0 cancela. Va por `Input.parse_input_event` a proposito, para
	#    comprobar el camino real: que el evento LLEGA al HUD y no se lo come
	#    antes el jugador.
	var key := InputEventKey.new()
	key.keycode = KEY_0
	key.pressed = true
	Input.parse_input_event(key)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not Ocean.has_tsunami(), "%s: la tecla 0 cancela el tsunami" % label)

	# 6) Y las teclas 1..3 lanzan.
	var key3 := InputEventKey.new()
	key3.keycode = KEY_3
	key3.pressed = true
	Input.parse_input_event(key3)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(Ocean.has_tsunami() and Ocean.current_tier != null
			and Ocean.current_tier.tier_name == "LEVIATAN",
		"%s: la tecla 3 lanza el tier 3" % label,
		"salio %s" % (Ocean.current_tier.tier_name if Ocean.current_tier else "nada"))

	# 7) Y la Ñ vuelve a cerrarlo.
	_pulsar_ene()
	await get_tree().process_frame
	_check(not hud.visible, "%s: la Ñ vuelve a cerrar el menu" % label)

	Ocean.clear_events()
	scene.queue_free()
	await get_tree().process_frame
