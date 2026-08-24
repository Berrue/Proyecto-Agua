extends Node

## Harness visual aislado para revisar la cara del pescador suave.
##
## Instancia el GLB directamente (sin Player ni AnimationTree corporal), agrega
## PlayerFaceAnimator y fuerza poses reproducibles. Renderiza en un SubViewport
## cuadrado para que todas las capturas tengan exactamente el mismo encuadre.
##
##   godot --rendering-method gl_compatibility --path . \
##     tests/capture_player_face.tscn -- --shots-dir=<carpeta>

const MODEL_PATH := "res://game/player/pescador_smooth.glb"
const FACE_SCRIPT := preload("res://game/player/player_face_animator.gd")

var _dir: String = "res://../character_qa_runtime_472"
var _absolute_dir: String = ""
var _viewport: SubViewport = null
var _model: Node3D = null
var _face: PlayerFaceAnimator = null
var _failed: bool = false


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shots-dir="):
			_dir = arg.substr("--shots-dir=".length())
	_absolute_dir = _global_path(_dir)
	var mkdir_error := DirAccess.make_dir_recursive_absolute(_absolute_dir)
	if mkdir_error != OK:
		_fail("no se pudo crear %s (error %d)" % [_absolute_dir, mkdir_error])
		return

	_build_studio()
	if not _load_face():
		return

	print("CAPACIDADES_FACIALES  ", _face.capabilities())
	for shot: Dictionary in [
		{"name": "01_neutral", "smile": 0.0, "tense": 0.0, "talk": 0.0,
			"effort": 0.0, "gaze": Vector2.ZERO, "blink": 0.0},
		{"name": "02_sonrisa", "smile": 1.0, "tense": 0.0, "talk": 0.0,
			"effort": 0.0, "gaze": Vector2.ZERO, "blink": 0.0},
		{"name": "03_habla", "smile": 0.0, "tense": 0.0, "talk": 1.0,
			"effort": 0.0, "gaze": Vector2.ZERO, "blink": 0.0},
		{"name": "04_preocupado", "smile": 0.0, "tense": 1.0, "talk": 0.0,
			"effort": 0.0, "gaze": Vector2(0.0, -0.28), "blink": 0.0},
		{"name": "05_esfuerzo", "smile": 0.0, "tense": 0.0, "talk": 0.0,
			"effort": 1.0, "gaze": Vector2.ZERO, "blink": 0.0},
		{"name": "06_parpadeo", "smile": 0.0, "tense": 0.0, "talk": 0.0,
			"effort": 0.0, "gaze": Vector2.ZERO, "blink": 1.0},
		{"name": "07_mirada_izquierda", "smile": 0.0, "tense": 0.0,
			"talk": 0.0, "effort": 0.0, "gaze": Vector2(-1.0, 0.0),
			"blink": 0.0},
		{"name": "08_sonrisa_hablando", "smile": 0.72, "tense": 0.0,
			"talk": 0.82, "effort": 0.0, "gaze": Vector2(0.18, 0.08),
			"blink": 0.0},
	]:
		_face.force(float(shot["smile"]), float(shot["tense"]),
			float(shot["talk"]), float(shot["effort"]), shot["gaze"],
			float(shot["blink"]))
		# Da tiempo a que Godot suba los pesos de morph al backend de render.
		for _frame: int in 3:
			await get_tree().process_frame
		await _shoot(String(shot["name"]))

	print("CAPTURAS_FACIALES  ", _absolute_dir)
	var exit_code: int = 1 if _failed else 0
	_face.teardown()
	_viewport.queue_free()
	await get_tree().process_frame
	get_tree().quit(exit_code)


func _global_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path


func _build_studio() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "FaceViewport"
	_viewport.size = Vector2i(900, 900)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_4X
	add_child(_viewport)

	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#b6c3c4")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#dce7e4")
	environment.ambient_light_energy = 0.82
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	_viewport.add_child(environment_node)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-34.0, 154.0, -12.0)
	key_light.light_color = Color("#fff2dc")
	key_light.light_energy = 1.25
	key_light.shadow_enabled = true
	_viewport.add_child(key_light)

	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-18.0, -42.0, 8.0)
	fill_light.light_color = Color("#b8d9e4")
	fill_light.light_energy = 0.48
	fill_light.shadow_enabled = false
	_viewport.add_child(fill_light)

	var camera := Camera3D.new()
	camera.name = "FaceCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.06
	# El GLB sin el giro de player.tscn mira a +Z.
	camera.position = Vector3(0.0, 1.43, 2.2)
	camera.current = true
	_viewport.add_child(camera)
	camera.look_at(Vector3(0.0, 1.43, 0.0), Vector3.UP)


func _load_face() -> bool:
	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		_fail("no se pudo cargar %s" % MODEL_PATH)
		return false
	_model = packed.instantiate() as Node3D
	if _model == null:
		_fail("la raiz de %s no es Node3D" % MODEL_PATH)
		return false
	_model.name = "PescadorSmooth"
	_viewport.add_child(_model)

	# Ningun clip facial embebido debe competir con las poses forzadas.
	for raw_player: Node in _model.find_children("*", "AnimationPlayer", true, false):
		var animation_player := raw_player as AnimationPlayer
		animation_player.stop()
		animation_player.active = false

	_face = FACE_SCRIPT.new() as PlayerFaceAnimator
	_face.name = "PlayerFaceAnimator"
	_viewport.add_child(_face)
	if not _face.setup(_model, 472):
		_fail("el modelo no expone canales faciales reconocibles")
		return false
	_face.set_process(false)
	return true


func _shoot(label: String) -> void:
	# frame_post_draw no se emite con el display driver headless de Windows. Los
	# tres frames previos ya sincronizan el renderer real y este camino tambien
	# permite que una corrida headless falle rapido, en vez de quedar colgada.
	var image := _viewport.get_texture().get_image()
	if image == null or image.is_empty():
		_failed = true
		print("FALLO  %s (viewport sin imagen; ejecutar con renderer compatibility)" % label)
		return
	var output_path := _absolute_dir.path_join("%s.png" % label)
	var error := image.save_png(output_path)
	if error == OK:
		print("OK  %s  %s" % [label, output_path])
	else:
		_failed = true
		print("FALLO  %s  error=%d  %s" % [label, error, output_path])


func _fail(message: String) -> void:
	_failed = true
	push_error("CapturePlayerFace: %s" % message)
	get_tree().quit(1)
