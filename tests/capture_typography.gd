extends Node

## Captura la tipografia sobre fondos extremos sin cargar el mundo completo.
## Aislar el HUD permite revisar glifos, ancho y contorno aunque otro sistema
## del juguete este en construccion.
##
##   godot --path . tests/capture_typography.tscn -- --shots-dir=<carpeta>

var _dir: String = "user://typography-shots"
var _hud: FishingHud
var _capture_failed := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots-dir="):
			_dir = arg.substr("--shots-dir=".length())
	var absolute_dir := ProjectSettings.globalize_path(_dir)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_dir)
	if directory_error != OK:
		push_error("No se pudo crear la carpeta de capturas: %s (error %d)" % [
			absolute_dir, directory_error])
		get_tree().quit(1)
		return
	_build_ocean_backdrop()
	_hud = FishingHud.new()
	add_child(_hud)
	_hud.on_hooked()
	await get_tree().process_frame

	_hud.update_fight(FightModel.Pull.LEFT, false, 0.92, 0.58, false, true)
	await _shoot("hud_1_suelta")
	_hud.update_fight(FightModel.Pull.NONE, true, 0.35, 0.72, false, false)
	await _shoot("hud_2_recoge")
	_hud.show_result("¡CABALLA  ·  12 kg!", Color(1.0, 0.85, 0.35))
	await _shoot("hud_3_captura")

	if _capture_failed:
		push_error("Una o más capturas tipográficas no pudieron guardarse")
		get_tree().quit(1)
	else:
		print("capturas tipograficas en: ", absolute_dir)
		get_tree().quit(0)


func _build_ocean_backdrop() -> void:
	var sky := ColorRect.new()
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	sky.color = Color("#0c4055")
	add_child(sky)
	var deep := ColorRect.new()
	deep.position = Vector2(0.0, 470.0)
	deep.size = Vector2(1600.0, 430.0)
	deep.color = Color("#071b27")
	add_child(deep)
	var foam := Polygon2D.new()
	foam.polygon = PackedVector2Array([
		Vector2(0.0, 390.0), Vector2(420.0, 430.0), Vector2(880.0, 365.0),
		Vector2(1280.0, 445.0), Vector2(1600.0, 390.0), Vector2(1600.0, 505.0),
		Vector2(1180.0, 520.0), Vector2(760.0, 470.0), Vector2(320.0, 530.0),
		Vector2(0.0, 485.0),
	])
	foam.color = Color(0.91, 0.94, 0.91, 0.82)
	add_child(foam)
	var hull := ColorRect.new()
	hull.position = Vector2(0.0, 790.0)
	hull.size = Vector2(1600.0, 110.0)
	hull.color = Color("#9c4037")
	add_child(hull)


func _shoot(label: String) -> void:
	for _i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png("%s/%s.png" % [_dir, label])
	if error == OK:
		print("OK  ", label)
	else:
		_capture_failed = true
		push_error("FALLO  %s (error %d)" % [label, error])
