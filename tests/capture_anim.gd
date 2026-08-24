extends Node

## Retrato del arbol de animacion: idle, caminando, y las dos con la caña. La
## ultima es la prueba visual del FILTRO (brazos en la caña, piernas caminando).
##
## Toma de estudio a proposito: el pescador solo, con su luz y su cielo. En
## cubierta la caseta se come el encuadre y lo deja a contraluz, y aca lo que
## hay que poder juzgar es la POSE, no la escena.
##
##   godot --path . tests/capture_anim.tscn -- --shots-dir=<carpeta>

var _dir: String = "user://shots"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots-dir="):
			_dir = arg.substr("--shots-dir=".length())
	DirAccess.make_dir_recursive_absolute(_dir)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	e.sky = Sky.new()
	e.sky.sky_material = ProceduralSkyMaterial.new()
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.7
	env.environment = e
	add_child(env)
	var sol := DirectionalLight3D.new()
	sol.rotation_degrees = Vector3(-40, 212, 0)  # de frente al pescador, no a su nuca
	sol.shadow_enabled = true
	add_child(sol)

	var player: Player = load("res://game/player/player.tscn").instantiate()
	add_child(player)
	await get_tree().process_frame
	await get_tree().process_frame
	player.set_body_visible(true)
	# Congelado: si no, su _feed_animator() de cada frame deshace el force() y
	# las fotos salen a medio camino entre dos poses.
	player.set_physics_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	# El jugador mira a -Z (convencion de Godot), asi que la camara va de ese
	# lado o le sacamos la nuca.
	cam.position = Vector3(1.9, 0.45, -3.5)
	cam.look_at(Vector3(0, -0.05, 0), Vector3.UP)
	cam.current = true

	# La caña es un viewmodel de la camara del jugador: desde fuera flota sola y
	# solo distrae. Lo que hay que ver aca es el cuerpo.
	var cana := player.get_node_or_null(^"Camera3D/FishingRod") as Node3D
	if cana != null:
		cana.visible = false

	if player.animator == null:
		print("FALLO  el jugador no tiene animator")
		get_tree().quit(1)
		return

	for toma: Dictionary in [
			{"nombre": "1_idle", "vel": 0.0, "agua": 0.0, "cana": false},
			{"nombre": "2_caminando", "vel": 1.0, "agua": 0.0, "cana": false},
			{"nombre": "3_cana_parado", "vel": 0.0, "agua": 0.0, "cana": true},
			{"nombre": "4_cana_caminando", "vel": 1.0, "agua": 0.0, "cana": true},
			{"nombre": "5_nadando", "vel": 0.0, "agua": 1.0, "cana": false},
			{"nombre": "6_nadando_con_cana", "vel": 0.0, "agua": 1.0, "cana": true}]:
		player.animator.force(float(toma["vel"]), float(toma["agua"]), bool(toma["cana"]))
		for _f in 26:
			await get_tree().process_frame
		await _shoot(String(toma["nombre"]))

	print("capturas en: ", ProjectSettings.globalize_path(_dir))
	get_tree().quit(0)


func _shoot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png("%s/%s.png" % [_dir, label])
	print("%s  %s" % ["OK  " if err == OK else "FALLO", label])
