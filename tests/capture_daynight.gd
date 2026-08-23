extends Node

## Captura el juguete a cuatro horas del dia, para revisar el ciclo de un
## vistazo sin jugar.
##
##   godot --path . tests/capture_daynight.tscn -- --shots-dir=<carpeta>

const HOURS: Array[float] = [6.6, 12.0, 17.5, 23.5]
const LABELS: Array[String] = ["amanecer", "mediodia", "atardecer", "noche"]

var _dir: String = "user://shots"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots-dir="):
			_dir = arg.substr("--shots-dir=".length())
	DirAccess.make_dir_recursive_absolute(_dir)

	var scene: Node3D = load("res://game/world/toybox.tscn").instantiate()
	add_child(scene)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var cycle := scene.get_node(^"DayNightCycle") as DayNightCycle
	var boat := scene.get_node(^"FishingBoat") as Node3D

	var cam := Camera3D.new()
	cam.fov = 66.0
	cam.far = 4000.0
	add_child(cam)
	cam.current = true

	Ocean.set_fury_immediate(4.0)
	for _i in 150:
		await get_tree().process_frame

	for i in HOURS.size():
		# Se fija la hora ajustando el offset de debug contra la hora actual:
		# sim_time no se toca (moveria las olas).
		var delta_h: float = fposmod(HOURS[i] - cycle.hour(), 24.0)
		cycle.advance_hours(delta_h)
		for _j in 40:
			await get_tree().process_frame
			var b := boat.global_position
			cam.global_position = Vector3(b.x + 13.0, maxf(b.y + 5.0, 2.0), b.z + 18.0)
			cam.look_at(b + Vector3(0.0, 1.5, -6.0), Vector3.UP)
		await RenderingServer.frame_post_draw

		var img := get_viewport().get_texture().get_image()
		var path := "%s/dn_%d_%s.png" % [_dir, i, LABELS[i]]
		var err := img.save_png(path)
		print("%s  %-9s reloj=%s  sol=%.2f  noche=%s" % [
			"OK  " if err == OK else "FALLO", LABELS[i], cycle.clock_text(),
			(scene.get_node(^"Sun") as DirectionalLight3D).light_energy,
			"si" if cycle.is_night() else "no"])

	print("capturas en: ", ProjectSettings.globalize_path(_dir))
	get_tree().quit(0)
