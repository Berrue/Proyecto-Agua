extends Node

## Capturas de la pesca: el POV con la caña en cada estado + un plano del
## pescador en tercera persona (verifica orientacion y proporciones del modelo).
##
##   godot --path . tests/capture_fishing.tscn -- --shots-dir=<carpeta>

var _dir: String = "user://shots"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots-dir="):
			_dir = arg.substr("--shots-dir=".length())
	DirAccess.make_dir_recursive_absolute(_dir)

	var scene: Node3D = load("res://game/world/toybox.tscn").instantiate()
	add_child(scene)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var player := scene.get_node(^"Player") as Player
	var rod := player.get_node(^"Camera3D/FishingRod") as FishingRod
	var player_cam := player.get_node(^"Camera3D") as Camera3D

	Ocean.set_fury_immediate(2.0)
	for _i in 150:
		await get_tree().process_frame

	# --- 1. Tercera persona: el pescador entero (en partida solo se ven las
	# manos, asi que hay que encender el cuerpo a proposito para la foto) -------
	player.set_body_visible(true)
	var ext_cam := Camera3D.new()
	ext_cam.fov = 55.0
	add_child(ext_cam)
	var p := player.global_position
	# Delante del jugador (su forward es -Z local), mirando hacia el.
	var fwd := -player.global_transform.basis.z
	ext_cam.global_position = p + fwd * 3.2 + Vector3(1.2, 0.6, 0)
	ext_cam.look_at(p + Vector3(0, 0.1, 0), Vector3.UP)
	ext_cam.current = true
	for _i in 30:
		await get_tree().process_frame
	await _shoot("0_pescador_tercera")
	player.set_body_visible(false)
	player_cam.current = true

	# --- 2. POV: caña lista ----------------------------------------------------
	for _i in 30:
		await get_tree().process_frame
	await _shoot("1_pov_lista")

	# --- 3. Lanzada, esperando (boya + sedal) ---------------------------------
	rod._charge = 0.75
	rod._cast()
	for _i in 90:
		await get_tree().process_frame
	await _shoot("2_pov_esperando")

	# --- 4. La picada: chomp + boya hundida + "!" sobre la boya ---------------
	Ocean.set_fury_immediate(5.0)
	rod._start_bite()
	for _i in 25:
		await get_tree().process_frame
	await _shoot("3_pov_pica")

	# --- 5. Lucha con el mar picado: caña doblada, sedal tenso ----------------
	rod._hook()
	# Forzamos tension alta un instante para fotografiar el sedal en ambar/rojo.
	for _i in 140:
		await get_tree().process_frame
	await _shoot("4_pov_lucha_furia5")

	print("capturas en: ", ProjectSettings.globalize_path(_dir))
	get_tree().quit(0)


func _shoot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png("%s/%s.png" % [_dir, label])
	print("%s  %s" % ["OK  " if err == OK else "FALLO", label])
