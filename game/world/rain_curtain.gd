class_name RainCurtain3D
extends Node3D

## Cortina de lluvia lejana: capas de cilindros invertidos pegados a la camara
## con trazos de agua en scroll (docs/CLIMA.md §1.1 — la capa de media/larga
## distancia; las gotas de RainParticles3D solo cubren ~15 m).
##
## La estructura admite VARIAS capas a distinta distancia (la tecnica del velo
## de Remember Me, que usaba cuatro): capas con densidad y velocidad distintas
## dan parallax de profundidad y evitan que el ojo reconstruya el cilindro.
## Hoy queda UNA sola, la lejana: la capa cercana de 135 m se probo y se
## descarto por feedback del playtest — a esa distancia sus trazos todavia se
## leian como una superficie proxima en vez de como lluvia. Si alguna vez hace
## falta mas cuerpo, se añade otra fila a LAYERS (mas lejos y mas tenue que
## esta, no mas cerca).
##
## Presentacion local pura, como las gotas: lo unico compartido es rain01 y
## sim_time. Sigue la POSICION de la camara, jamas su rotacion.

## Por capa: radio (m), altura (m), alfa base, velocidad relativa, columnas.
## La lejana es mas fina, mas tenue y mas lenta — las tres cosas leen "lejos".
##
## Alejar una capa NO cambia su densidad angular (el espaciado entre trazos es
## 2*PI/columnas, independiente del radio): lo que cambia es el LARGO angular
## del trazo, porque el ciclo mide metros fijos. Por eso alejar acorta los
## trazos y eso es justo lo que lee como distancia. La altura acompaña al radio
## para que la franja siga cubriendo el mismo arco vertical.
##
## La velocidad es una TRAMPA DELIBERADA. Lo fisico seria que la capa lejana
## bajara despacio (a 225 m, lluvia real a 9 m/s son ~2 grados/s: por eso la
## lluvia lejana de verdad parece un velo quieto). Pero entonces se lee como
## niebla, no como agua — se noto en playtest. El 1.20 la pone en ~8-14 grados
## por segundo: sigue siendo mas lenta que las gotas cercanas, pero cae.
const LAYERS: Array = [
	[225.0, 210.0, 0.065, 1.60, 1300.0],
]
## Cuanto se eleva el centro de cada capa sobre la camara, en fraccion de radio
## (equivale a los 6 m sobre 45 de la primera version).
const LIFT_RATIO := 0.133
## Mismo acople a la luz ambiente que las gotas (ver rain_particles.gd: la
## historia de por que ni unshaded fijo ni material sombreado).
const BASE_TINT := Color(0.78, 0.82, 0.87)
const NIGHT_FLOOR := 0.24
const DAY_AMBIENT_REF := 0.5

var _mats: Array[ShaderMaterial] = []
var _layers: Array[MeshInstance3D] = []
var _lifts: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	var shader: Shader = load("res://game/world/rain_curtain.gdshader")
	for i in LAYERS.size():
		var spec: Array = LAYERS[i]
		var radius: float = spec[0]
		var height: float = spec[1]

		var cyl := CylinderMesh.new()
		cyl.top_radius = radius
		cyl.bottom_radius = radius
		cyl.height = height
		cyl.radial_segments = 64
		cyl.rings = 1
		cyl.cap_top = false
		cyl.cap_bottom = false

		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter(&"base_alpha", spec[2])
		mat.set_shader_parameter(&"speed_scale", spec[3])
		mat.set_shader_parameter(&"columns", spec[4])
		mat.set_shader_parameter(&"half_height", height * 0.5)
		mat.set_shader_parameter(&"layer_seed", float(i) * 37.0)

		var mi := MeshInstance3D.new()
		mi.mesh = cyl
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# El cilindro rodea a la camara: sin margen, Godot lo cullearia al
		# mirar fuera de su AABB en reposo.
		mi.extra_cull_margin = radius * 0.4
		# La capa lejana se dibuja primero: sin orden explicito, dos
		# transparentes se ordenan por posicion de nodo y parpadean al mezclar.
		mi.sorting_offset = -float(i)
		# Diferido: en _ready() la escena aun se esta instanciando y add_child()
		# directo falla con "parent is busy setting up children" — la cortina
		# se quedaba sin capas y en silencio.
		add_child.call_deferred(mi)

		_layers.append(mi)
		_mats.append(mat)
		_lifts.append(radius * LIFT_RATIO)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return

	var lum: float = 1.0
	var tint := Color.WHITE
	var env := get_world_3d().environment
	if env != null:
		lum = clampf(env.ambient_light_energy / DAY_AMBIENT_REF, NIGHT_FLOOR, 1.0)
		tint = env.ambient_light_color.lerp(Color.WHITE, 0.65)
	var rgb := Vector3(
		BASE_TINT.r * lum * tint.r,
		BASE_TINT.g * lum * tint.g,
		BASE_TINT.b * lum * tint.b)

	for i in _mats.size():
		(get_child(i) as Node3D).global_position = \
			cam.global_position + Vector3(0.0, _lifts[i], 0.0)
		var mat: ShaderMaterial = _mats[i]
		mat.set_shader_parameter(&"curtain_time", Ocean.sim_time)
		mat.set_shader_parameter(&"rain01", Ocean.rain01)
		mat.set_shader_parameter(&"tint", rgb)
