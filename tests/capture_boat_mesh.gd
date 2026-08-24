extends Node

## Captura el asset integrado en el océano real desde el exterior y el puesto
## de mando. No es un test: sirve para revisar silueta, acceso, visibilidad y
## lectura de la madera tras cada reexportación desde Blender.
##
##   godot --path . tests/capture_boat_mesh.tscn -- --shots-dir=<carpeta>

var _dir: String = "user://boat_mesh_shots"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots-dir="):
			_dir = arg.substr("--shots-dir=".length())
	DirAccess.make_dir_recursive_absolute(_dir)

	var toybox := load("res://game/world/toybox.tscn").instantiate() as Node3D
	add_child(toybox)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Ocean.set_fury_immediate(1.0)

	var player := toybox.get_node_or_null(^"Player") as Node3D
	if player != null:
		player.process_mode = Node.PROCESS_MODE_DISABLED
		player.visible = false
		# El brazo del viewmodel usa top-level para no heredar transformaciones;
		# se oculta de forma explicita para que no entre en la toma externa.
		for node in player.find_children("*", "VisualInstance3D", true, false):
			var visual := node as VisualInstance3D
			if visual != null:
				visual.visible = false
	var hud := toybox.get_node_or_null(^"OceanDebugHUD") as CanvasLayer
	if hud != null:
		hud.visible = false

	for _frame in 180:
		await get_tree().process_frame

	var boat := toybox.get_node(^"FishingBoat") as Node3D
	var camera := Camera3D.new()
	camera.fov = 54.0
	camera.far = 4000.0
	add_child(camera)
	camera.current = true

	await _capture(camera, boat, "godot_stern_3q", Vector3(-10.5, 5.2, 14.5))
	await _capture(camera, boat, "godot_profile", Vector3(15.5, 4.2, 0.0))
	await _capture(camera, boat, "godot_deck", Vector3(7.0, 12.5, -4.0))
	# La primera cámara externa puede compartir un frame con la cámara del
	# jugador recién desactivada; la toma canónica de proa va al final.
	await _capture(camera, boat, "godot_bow_3q", Vector3(10.5, 5.2, -14.5))
	await _capture_local(
		camera, boat, "godot_wheelhouse_entry",
		Vector3(0.0, 1.90, 5.34), Vector3(0.12, 1.68, 2.72), 62.0)
	await _capture_local(
		camera, boat, "godot_helm_pov",
		Vector3(0.0, 2.35, 3.60), Vector3(0.12, 1.78, 2.58), 72.0)
	await _capture_local(
		camera, boat, "godot_deck_wood_close",
		Vector3(1.50, 2.65, 0.20), Vector3(0.70, 0.82, -0.25), 48.0)
	# La bomba manual, montada en PumpPort. La cámara va POR DELANTE del mamparo
	# de proa de la caseta (Z 2,23): un palmo más a popa quedaba dentro de la
	# cabina y la toma salía a través del parabrisas ahumado, teñida de azul.
	await _capture_local(
		camera, boat, "godot_bomba_babor",
		Vector3(0.40, 2.05, 1.55), Vector3(-1.3, 1.3, 0.75), 50.0)
	# El pizarrón se lee desde PROA: la bodega va rotada 180° en su socket.
	await _capture_local(
		camera, boat, "godot_bodega_medieval",
		Vector3(0.0, 2.48, -1.75), Vector3(0.0, 1.92, 0.58), 44.0)
	# El cubo de cebo: se revisa que apoye en la tabla (ni hundido ni flotando)
	# y que el nivel del contenido se lea desde la altura de los ojos.
	await _capture_local(
		camera, boat, "godot_cubo_cebo",
		Vector3(-0.62, 1.98, -0.32), Vector3(-1.15, 1.16, -1.0), 50.0)

	print("capturas del barco en: ", ProjectSettings.globalize_path(_dir))
	get_tree().quit(0)


func _capture(camera: Camera3D, boat: Node3D, label: String, offset: Vector3) -> void:
	camera.fov = 54.0
	var target := boat.global_position + Vector3(0.0, 0.85, 0.0)
	camera.global_position = boat.global_position + offset
	camera.look_at(target, Vector3.UP)
	for _frame in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png("%s/%s.png" % [_dir, label])
	print("%s  %s" % ["OK  " if error == OK else "FALLO", label])


func _capture_local(
	camera: Camera3D,
	boat: Node3D,
	label: String,
	local_position: Vector3,
	local_target: Vector3,
	fov: float,
) -> void:
	camera.fov = fov
	camera.global_position = boat.to_global(local_position)
	camera.look_at(boat.to_global(local_target), boat.global_basis.y.normalized())
	for _frame in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png("%s/%s.png" % [_dir, label])
	print("%s  %s" % ["OK  " if error == OK else "FALLO", label])
