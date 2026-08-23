extends Node

## Herramienta de captura. Carga el juguete, deja que el mar se asiente y saca
## una foto en varios puntos del dial de furia. Sirve para revisar el aspecto
## sin tener que jugar, y para comparar antes/despues al tocar el shader.
##
##   godot --path . tests/capture_shots.tscn -- --shots-dir=<carpeta>

const FURY_STEPS: Array[float] = [1.0, 4.0, 7.0, 10.0]
const SETTLE_FRAMES := 150
const SHOT_FRAMES := 90

var _dir: String = "user://shots"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots-dir="):
			_dir = arg.substr("--shots-dir=".length())
	DirAccess.make_dir_recursive_absolute(_dir)

	var toybox: Node3D = load("res://game/world/toybox.tscn").instantiate()
	add_child(toybox)

	# La camara del jugador captura el raton en _ready; para una captura
	# automatica eso solo molesta.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var cam := Camera3D.new()
	cam.fov = 62.0
	cam.far = 4000.0
	add_child(cam)
	cam.global_position = Vector3(11, 3.0, 15)
	cam.look_at(Vector3(0, 1, 0), Vector3.UP)
	cam.current = true

	# Marcadores de paridad ENCENDIDOS: si la rejilla de esferas (CPU) queda
	# clavada en la superficie (GPU), las dos implementaciones coinciden.
	var markers := toybox.get_node_or_null(^"ParityMarkers")
	if markers != null:
		markers.visible = false

	Ocean.set_fury_immediate(FURY_STEPS[0])
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame

	for fury in FURY_STEPS:
		Ocean.set_fury_immediate(fury)
		for _i in SHOT_FRAMES:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw

		var img := get_viewport().get_texture().get_image()
		var path := "%s/furia_%02d.png" % [_dir, int(fury)]
		var err := img.save_png(path)
		print("%s  furia %.0f  Hs objetivo %.2f  Hs medido %.2f  steepness %.3f" % [
			"OK  " if err == OK else "FALLO",
			fury, Ocean.target_hs(), Ocean.measured_hs(), Ocean.steepness_sum()])

	print("capturas en: ", ProjectSettings.globalize_path(_dir))
	get_tree().quit(0)
