extends Node

## Captura los tres tiers desde la MISMA camara y en el MISMO instante relativo,
## para poder compararlos de un vistazo.
##
##   godot --path . tests/capture_tiers.tscn -- --shots-dir=<carpeta>

const TIER_PATHS: Array[String] = [
	"res://resources/tsunami_tiers/tier_1_muro.tres",
	"res://resources/tsunami_tiers/tier_2_coloso.tres",
	"res://resources/tsunami_tiers/tier_3_leviatan.tres",
]

## Segundos hasta el impacto en los que se saca foto.
const MARKS: Array[float] = [8.0, 0.5]

var _dir: String = "user://shots"
var _boat: Node3D
var _cam: Camera3D


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots-dir="):
			_dir = arg.substr("--shots-dir=".length())
	DirAccess.make_dir_recursive_absolute(_dir)

	var scene: Node3D = load("res://game/world/tsunami.tscn").instantiate()
	add_child(scene)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var director := scene.get_node_or_null(^"TsunamiDirector") as TsunamiDirector
	if director != null:
		director.stop()

	_boat = scene.get_node(^"FishingBoat")
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.far = 4000.0
	add_child(_cam)
	_cam.current = true

	Ocean.set_fury_immediate(7.0)
	for _i in 150:
		await get_tree().process_frame

	for path in TIER_PATHS:
		await _run_tier(load(path) as TsunamiTier)

	print("capturas en: ", ProjectSettings.globalize_path(_dir))
	get_tree().quit(0)


func _run_tier(tier: TsunamiTier) -> void:
	Ocean.clear_events()
	# Se deja asentar entre tiers para que la comparacion sea justa.
	for _i in 120:
		await get_tree().process_frame
		_track_camera()

	Ocean.spawn_tsunami_tier(_boat.global_position, 90.0, 42.0, tier)
	var pending := MARKS.duplicate()

	while not pending.is_empty():
		await get_tree().process_frame
		_track_camera()
		var eta := Ocean.time_until_tsunami(_boat.global_position)
		if eta <= pending[0]:
			var mark: float = pending.pop_front()
			await RenderingServer.frame_post_draw
			_shoot(tier, mark)


func _track_camera() -> void:
	var b := _boat.global_position
	_cam.global_position = Vector3(b.x + 17.0, maxf(b.y + 8.0, 2.5), b.z - 32.0)
	_cam.look_at(b + Vector3(0.0, 3.0, 16.0), Vector3.UP)


func _shoot(tier: TsunamiTier, mark: float) -> void:
	var img := get_viewport().get_texture().get_image()
	var slot := "retirada" if mark > 2.0 else "muro"
	var path := "%s/tier_%.0f_%s_%s.png" % [
		_dir, tier.size_multiplier * 10.0, tier.tier_name.to_lower(), slot]
	var err := img.save_png(path)
	print("%s  %-9s %-9s  agua %+7.2f m  barco %+7.2f m" % [
		"OK  " if err == OK else "FALLO", tier.tier_name, slot,
		Ocean.get_height(_boat.global_position), _boat.global_position.y])
