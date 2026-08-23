@tool
class_name OceanParityMarkers
extends MultiMeshInstance3D

## Comprobador VISUAL de paridad CPU/GPU. Es la herramienta de debug mas
## importante del proyecto y cuesta 60 lineas.
##
## Coloca una rejilla de esferas usando [method Ocean.get_height] (o sea, la
## implementacion de CPU) sobre el oceano que dibuja el shader (o sea, la
## implementacion de GPU). Si ambas coinciden, las esferas quedan clavadas en la
## superficie. En cuanto alguien toque una formula en un sitio y no en el otro,
## las esferas se despegan y se ve al instante.
##
## Sin esto, la deriva entre `wave_proxy.gd` y `ocean_waves.gdshaderinc` es
## COMPLETAMENTE SILENCIOSA: el oceano se ve perfecto, los objetos flotan medio
## metro por encima del agua y nadie entiende por que hasta semanas despues.

@export var grid_size: int = 24:
	set(value):
		grid_size = clampi(value, 2, 64)
		_rebuild()

@export var spacing: float = 4.0

@export var marker_radius: float = 0.16:
	set(value):
		marker_radius = maxf(value, 0.01)
		_rebuild()

@export var follow_camera: bool = true

## Se muestra tambien la normal analitica, para cazar errores en `normal_at()`.
@export var show_normals: bool = false


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = marker_radius
	sphere.height = marker_radius * 2.0
	sphere.radial_segments = 6
	sphere.rings = 3

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.16, 0.42)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = false
	sphere.material = mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = sphere
	mm.instance_count = grid_size * grid_size
	multimesh = mm

	extra_cull_margin = 200.0


func _process(_delta: float) -> void:
	# Cada marcador cuesta una consulta completa de altura (3 iteraciones de
	# punto fijo x N olas). Con la rejilla por defecto son ~23.000 evaluaciones
	# trigonometricas por frame: medido, son mas de 100 ms de CPU. Es una
	# herramienta de diagnostico, no algo que pueda correr de fondo.
	if not visible or Engine.is_editor_hint() or multimesh == null:
		return

	var center := Vector3.ZERO
	if follow_camera:
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			center = cam.global_position

	var half: float = float(grid_size - 1) * spacing * 0.5
	var i: int = 0
	for gx in grid_size:
		for gz in grid_size:
			var pos := Vector3(
				snappedf(center.x, spacing) - half + float(gx) * spacing,
				0.0,
				snappedf(center.z, spacing) - half + float(gz) * spacing
			)
			pos.y = Ocean.get_height(pos)

			var xform := Transform3D(Basis(), pos)
			if show_normals:
				var n := Ocean.get_normal(pos)
				xform.basis = Basis.looking_at(n, Vector3.FORWARD).scaled(Vector3(1, 1, 3))
			multimesh.set_instance_transform(i, xform)
			i += 1
