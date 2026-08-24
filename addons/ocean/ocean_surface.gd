@tool
class_name OceanSurface3D
extends MeshInstance3D

## Malla del oceano. Sigue a la camara y empuja los uniforms del shader.
##
## [b]El snapping a rejilla no es opcional.[/b] Si la malla sigue a la camara con
## posiciones continuas, cada vertice cae en un punto distinto de la ola cada
## frame y la superficie "nada": aparece un hervidero de moire que no se arregla
## despues con nada. Anclando la malla a multiplos exactos del tamaño de celda,
## cada vertice sigue muestreando el mismo sitio y el mar se queda quieto.
##
## En F1 esto es un unico plano con niebla que esconde el borde. El clipmap con
## anillos concentricos y morph entra en F2.

## Lado del plano en metros.
@export var size: float = 512.0:
	set(value):
		size = maxf(value, 8.0)
		_rebuild()

## Celdas por lado. El tamaño de celda (y por tanto el paso de snapping) sale de
## dividir [member size] entre esto.
@export var subdivisions: int = 255:
	set(value):
		subdivisions = clampi(value, 1, 511)
		_rebuild()

@export var follow_camera: bool = true

var _cell_size: float = 2.0


func _ready() -> void:
	_rebuild()
	if not Engine.is_editor_hint():
		# Los uniforms de las olas solo cambian cuando cambia el estado del mar,
		# no cada frame.
		Ocean.sea_state_changed.connect(_push_wave_uniforms)
		Ocean.waves_regenerated.connect(_push_wave_uniforms)
		Ocean.events_changed.connect(_push_wave_uniforms)
		_push_wave_uniforms()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return

	var mat := _shader_material()
	if mat != null:
		# Tiempo y clima si van cada frame: son un puñado de floats.
		Ocean.apply_frame_to_material(mat)

	if not follow_camera:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return

	# SNAPPING. El shader asume ademas que esta malla solo se traslada (usa
	# MODEL_MATRIX[3] para pasar a coordenadas de mundo), asi que aqui nunca se
	# toca la rotacion ni la escala.
	var cam_pos := cam.global_position
	global_position = Vector3(
		snappedf(cam_pos.x, _cell_size),
		0.0,
		snappedf(cam_pos.z, _cell_size)
	)


func _rebuild() -> void:
	_cell_size = size / float(subdivisions + 1)

	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	plane.subdivide_width = subdivisions
	plane.subdivide_depth = subdivisions
	plane.orientation = PlaneMesh.FACE_Y
	mesh = plane

	# Los vertices se desplazan en el shader, asi que la AABB real no coincide
	# con la de la malla en reposo y Godot cullearia el oceano al mirar hacia
	# arriba desde un valle. Un margen generoso lo evita.
	extra_cull_margin = 64.0


## El material vive en `material_override` y se edita en la escena.
##
## OJO con no volver a mezclarlo con `surface_override_material`: Godot RENDERIZA
## `material_override` con prioridad, asi que si los uniforms se escriben en el
## surface override el oceano se queda completamente PLANO sin dar ni un error.
func _shader_material() -> ShaderMaterial:
	return material_override as ShaderMaterial


func _push_wave_uniforms() -> void:
	var mat := _shader_material()
	if mat != null:
		Ocean.apply_to_material(mat)


## Tamaño de celda actual, en metros. Util para el HUD de debug.
func cell_size() -> float:
	return _cell_size
