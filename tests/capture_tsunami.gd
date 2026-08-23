extends Node

## Captura la secuencia del tsunami en los instantes que importan, disparando
## por SEGUNDOS HASTA EL IMPACTO en vez de por reloj. Es la misma telegrafia que
## usa el HUD: si la captura sale en el momento correcto, la telegrafia funciona.
##
##   godot --path . tests/capture_tsunami.tscn -- --shots-dir=<carpeta>

## Segundos hasta el impacto en los que se saca foto.
const MARKS: Array[float] = [42.0, 20.0, 8.0, 1.0, -4.0]

const LEAD := 55.0
const CELERITY := 60.0
const WIDTH := 70.0
const AMPLITUDE := 20.0

var _dir: String = "user://shots"
var _boat: Node3D
var _cam: Camera3D
var _pending: Array[float] = []


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots-dir="):
			_dir = arg.substr("--shots-dir=".length())
	DirAccess.make_dir_recursive_absolute(_dir)

	var scene: Node3D = load("res://game/world/tsunami.tscn").instantiate()
	add_child(scene)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# El director se apaga: aqui queremos control exacto de los tiempos.
	var director := scene.get_node_or_null(^"TsunamiDirector") as TsunamiDirector
	if director != null:
		director.stop()

	_boat = scene.get_node(^"FishingBoat")

	_cam = Camera3D.new()
	_cam.fov = 68.0
	_cam.far = 4000.0
	add_child(_cam)
	_cam.current = true

	Ocean.set_fury_immediate(7.0)
	for _i in 180:
		await get_tree().process_frame

	# Viene del +Z (from_direction_deg = 90) y avanza hacia -Z.
	Ocean.spawn_tsunami(_boat.global_position, 90.0, LEAD, AMPLITUDE, CELERITY, WIDTH)
	_pending = MARKS.duplicate()

	while not _pending.is_empty():
		await get_tree().process_frame
		_track_camera()
		var eta := Ocean.time_until_tsunami(_boat.global_position)
		if eta <= _pending[0]:
			var mark: float = _pending.pop_front()
			await RenderingServer.frame_post_draw
			_shoot(mark, eta)

	print("capturas en: ", ProjectSettings.globalize_path(_dir))
	get_tree().quit(0)


func _track_camera() -> void:
	# Detras del barco y algo por encima, mirando hacia donde viene el muro.
	var b := _boat.global_position
	_cam.global_position = Vector3(b.x + 15.0, maxf(b.y + 6.0, 2.0), b.z - 26.0)
	_cam.look_at(b + Vector3(0.0, 1.0, 14.0), Vector3.UP)


func _shoot(mark: float, eta: float) -> void:
	var img := get_viewport().get_texture().get_image()
	var label := "impacto" if absf(mark) < 2.0 else ("t%+03d" % int(mark))
	var path := "%s/tsunami_%s.png" % [_dir, label]
	var err := img.save_png(path)
	var boat_y := _boat.global_position.y
	var water := Ocean.get_height(_boat.global_position)
	print("%s  marca %+6.1f s  (real %+6.1f)  agua %+6.2f m  barco %+6.2f m  rompiendo=%s" % [
		"OK  " if err == OK else "FALLO",
		mark, eta, water, boat_y,
		"si" if Ocean.is_breaking(_boat.global_position) else "no"])
