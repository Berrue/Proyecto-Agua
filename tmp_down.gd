extends Node

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
	var cam := player.get_node(^"Camera3D") as Camera3D
	Ocean.set_fury_immediate(2.0)
	for _i in 150:
		await get_tree().process_frame
	for shot: Array in [[-0.5, "mira_abajo_30"], [-1.0, "mira_abajo_57"], [-1.4, "mira_abajo_80"], [0.0, "mira_al_frente"]]:
		cam.rotation.x = shot[0]
		for _i in 10:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		print("OK  ", shot[1], "  ", img.save_png("%s/%s.png" % [_dir, shot[1]]))
	get_tree().quit(0)
