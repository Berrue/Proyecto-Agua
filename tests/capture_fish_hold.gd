extends Node3D

## Captura la bodega como pieza autónoma: una toma general comprueba volumen,
## lectura y escala; el primer plano comprueba el contador desde la dirección de
## aproximación del jugador. No es un test, es la revisión visual.
##
##   godot --path . tests/capture_fish_hold.tscn -- --shots-dir=<carpeta>

const FISH_SCENE: PackedScene = preload("res://game/fishing/fish.tscn")
var _cargo_species: PackedInt32Array = PackedInt32Array([0, 1, 2])
var _cargo_positions: PackedVector3Array = PackedVector3Array([
	Vector3(-0.48, 0.9, -0.18),
	Vector3(0.0, 0.92, 0.02),
	Vector3(0.46, 0.94, -0.2),
])
var _cargo_rotations: PackedVector3Array = PackedVector3Array([
	Vector3(0.0, -0.68, 1.42),
	Vector3(0.15, 0.34, 1.62),
	Vector3(-0.12, 0.92, 1.36),
])

var _dir: String = "user://fish_hold_shots"

@onready var _hold := $Bodega as Bodega
@onready var _camera := $Camera3D as Camera3D


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots-dir="):
			_dir = arg.substr("--shots-dir=".length())
	DirAccess.make_dir_recursive_absolute(_dir)
	_populate_hold()

	for _frame in 8:
		await get_tree().physics_frame
	print("bodega: %.1f kg, %d peces" % [_hold.kg, _hold.cantidad_peces()])

	await _capture(
		"fish_hold_overview",
		Vector3(2.8, 3.0, 3.45),
		Vector3(0.0, 1.16, -0.12),
		45.0)
	await _capture(
		"fish_hold_cargo",
		Vector3(2.1, 5.0, 2.5),
		Vector3(0.0, 0.92, 0.0),
		40.0)
	await _capture(
		"fish_hold_counter",
		Vector3(0.0, 2.45, 2.8),
		Vector3(0.0, 1.92, -0.63),
		42.0)
	print("capturas de la bodega en: ", ProjectSettings.globalize_path(_dir))
	get_tree().quit(0)


func _populate_hold() -> void:
	for index in _cargo_species.size():
		var fish := FISH_SCENE.instantiate() as Fish
		fish.setup(FishSpecies.SPECIES[_cargo_species[index]])
		fish.freeze = true
		fish.position = _cargo_positions[index]
		fish.rotation = _cargo_rotations[index]
		add_child(fish)


func _capture(
	label: String,
	position: Vector3,
	target: Vector3,
	fov: float,
) -> void:
	_camera.position = position
	_camera.fov = fov
	_camera.look_at(target, Vector3.UP)
	_camera.current = true
	_camera.force_update_transform()
	# El cambio brusco entre toma general y cenital necesita varios frames de
	# render completos; de otro modo el driver puede entregar un frame intermedio.
	for _frame in 24:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png("%s/%s.png" % [_dir, label])
	print("%s  %s" % ["OK  " if error == OK else "FALLO", label])
