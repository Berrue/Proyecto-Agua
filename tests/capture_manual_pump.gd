extends Node

## Captura retraida y desplegada del modulo standalone. No agrega la bomba al
## barco: muestra escala, testigo de cadencia y continuidad manguera-cabezal.
##
##   godot --path . tests/capture_manual_pump.tscn -- --shots-dir=<carpeta>

var _dir: String = "res://docs/images/manual_pump_validation"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots-dir="):
			_dir = arg.substr("--shots-dir=".length())
	_dir = ProjectSettings.globalize_path(_dir)
	DirAccess.make_dir_recursive_absolute(_dir)

	var demo_scene := load("res://tests/manual_pump_demo.tscn") as PackedScene
	if demo_scene == null:
		push_error("No se pudo cargar el banco de la bomba manual.")
		get_tree().quit(1)
		return
	var demo := demo_scene.instantiate() as Node3D
	add_child(demo)
	var pump := demo.get_node(^"ManualBilgePump") as ManualBilgePump
	var grip := demo.get_node(^"GripTarget") as Marker3D
	var grip_visual := demo.get_node(^"GripTarget/DebugHand") as MeshInstance3D
	var camera := demo.get_node(^"Camera3D") as Camera3D
	# La esfera naranja existe para operar el banco manualmente; no forma parte
	# del activo ni debe confundirse con el interior de la cesta-colador.
	grip_visual.visible = false

	for _frame in 90:
		await get_tree().physics_frame
	await _capture(
		camera,
		"manual_pump_stowed",
		Vector3(2.05, 1.48, -2.45),
		Vector3(-0.02, 0.62, 0.0),
		46.0
	)

	grip.global_position = pump.posicion_toma_global()
	pump.tomar_manguera(grip)
	grip.global_position = pump.to_global(Vector3(2.30, 0.18, -0.90))
	for _frame in 240:
		await get_tree().physics_frame
	await _capture(
		camera,
		"manual_pump_extended",
		Vector3(3.60, 1.90, -4.10),
		Vector3(0.75, 0.45, -0.35),
		50.0
	)

	print("capturas de bomba manual en: ", ProjectSettings.globalize_path(_dir))
	get_tree().quit(0)


func _capture(
	camera: Camera3D,
	label: String,
	position: Vector3,
	target: Vector3,
	fov: float,
) -> void:
	camera.fov = fov
	camera.global_position = position
	camera.look_at(target, Vector3.UP)
	for _frame in 16:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png("%s/%s.png" % [_dir, label])
	print("%s  %s" % ["OK" if error == OK else "FALLO", label])
