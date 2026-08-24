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

	# --- 1b. La misma toma CAMINANDO con el clip de Mixamo retargeteado: la
	# prueba visual de que el circuito animacion->rig esta vivo ---------------
	var skel := player.get_node(^"Pescador").find_children(
		"*", "Skeleton3D", true, false)[0] as Skeleton3D
	var anim: Animation = (load("res://game/player/animations/walk_retargeted.res")
		as Animation).duplicate(true)
	var rel := String(player.get_node(^"Pescador").get_path_to(skel))
	for t in anim.get_track_count():
		anim.track_set_path(t, NodePath(rel + ":" + String(anim.track_get_path(t)).split(":")[-1]))
	var lib := AnimationLibrary.new()
	lib.add_animation(&"walk", anim)
	var ap := AnimationPlayer.new()
	player.get_node(^"Pescador").add_child(ap)
	ap.root_node = ap.get_path_to(player.get_node(^"Pescador"))
	ap.add_animation_library(&"", lib)
	ap.play(&"walk")
	ap.seek(anim.length * 0.25, true)
	for _i in 5:
		await get_tree().process_frame
	await _shoot("0b_pescador_caminando")
	ap.queue_free()
	skel.reset_bone_poses()
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
	for _i in 140:
		await get_tree().process_frame
	await _shoot("4_pov_lucha_furia5")

	# --- 6. El forcejeo: manteniendo A, la caña (y las manos) se van con la
	# contra, y el pez corriendo arrastra la camara ----------------------------
	Input.action_press(&"move_left")
	for _i in 50:
		await get_tree().process_frame
	await _shoot("5_pov_forcejeo_contra_A")
	Input.action_release(&"move_left")

	print("capturas en: ", ProjectSettings.globalize_path(_dir))
	get_tree().quit(0)


func _shoot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png("%s/%s.png" % [_dir, label])
	print("%s  %s" % ["OK  " if err == OK else "FALLO", label])

