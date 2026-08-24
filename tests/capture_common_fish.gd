extends Node3D

## Catalogo renderizado por Godot, no por Blender: demuestra que los tres GLB
## importados atraviesan Fish.setup y mantienen escala, materiales y orientacion.
##
##   Godot --path . tests/capture_common_fish.tscn -- --shots-dir=<carpeta>

var _dir: String = "user://shots"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots-dir="):
			_dir = arg.substr("--shots-dir=".length())
	DirAccess.make_dir_recursive_absolute(_dir)
	_build_stage()
	for _frame in 24:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/common_fish_runtime.png" % _dir
	var error := image.save_png(path)
	print("%s  %s" % ["OK" if error == OK else "FALLO", path])
	get_tree().quit(0 if error == OK else 1)


func _build_stage() -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("102b36")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("8dc2cf")
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	add_child(environment_node)

	var floor := MeshInstance3D.new()
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(3.4, 0.10, 1.25)
	floor.mesh = floor_mesh
	floor.position = Vector3(0.0, -0.52, 0.0)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("183f48")
	floor_material.roughness = 0.9
	floor.material_override = floor_material
	add_child(floor)

	var key := DirectionalLight3D.new()
	key.light_color = Color("ffe0ad")
	key.light_energy = 1.15
	key.rotation_degrees = Vector3(-48.0, -28.0, 0.0)
	key.shadow_enabled = true
	add_child(key)

	var fill := OmniLight3D.new()
	fill.light_color = Color("70b9d0")
	fill.light_energy = 5.0
	fill.omni_range = 5.0
	fill.position = Vector3(-1.7, 1.3, 1.4)
	add_child(fill)

	var common: Array[Dictionary] = []
	for species in FishSpecies.SPECIES:
		if is_zero_approx(float(species[&"min_fury"])):
			common.append(species)
	for index in common.size():
		var species := common[index]
		var fish := load("res://game/fishing/fish.tscn").instantiate() as Fish
		add_child(fish)
		fish.freeze = true
		fish.setup(species)
		fish.position = Vector3(-0.90 + float(index) * 0.90, 0.05, 0.0)
		fish.rotation_degrees.y = 90.0

		var label := Label3D.new()
		label.text = String(species[&"name"]).to_upper()
		label.font_size = 48
		label.pixel_size = 0.0025
		label.outline_size = 8
		label.modulate = Color("f0e5c9")
		label.no_depth_test = true
		label.position = Vector3(fish.position.x, -0.31, 0.25)
		add_child(label)

	var camera := Camera3D.new()
	camera.fov = 38.0
	add_child(camera)
	camera.position = Vector3(0.0, 0.52, 2.75)
	camera.look_at(Vector3(0.0, -0.02, 0.0), Vector3.UP)
	camera.current = true
