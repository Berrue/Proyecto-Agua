class_name RainSplashes3D
extends GPUParticles3D

## Anillos de impacto de la lluvia sobre el mar (docs/CLIMA.md §1.2): la señal
## que dice "esto es agua cayendo sobre agua" y no niebla.
##
## Anillos y NO puntos: el moteado de chispazos se probo en el shader del
## oceano y se retiro por feedback ("parecen puntos sin sentido"). Un aro que
## crece y se apaga es una forma reconocible; un punto es ruido.
##
## Los aros se clavan en la superficie desde el vertex shader (ver
## rain_splash.gdshader). Aqui solo se los coloca en el plano de reposo y se
## empujan los uniforms de ola por la MISMA tuberia que usa el oceano.
##
## Presentacion local pura: no existen para la fisica ni para la red.

## Semilado de la losa de emision. Mas alla de ~25 m el aro es sub-pixel y el
## shader ya lo apaga: emitir mas lejos seria pagar por nada.
const AREA := 24.0
## Vida del aro. Corta: el impacto es un parpadeo, no una onda persistente.
const LIFE := 0.55
## Diametro final del aro, en metros.
const RING_SIZE := 0.62

var _draw_mat: ShaderMaterial


func _ready() -> void:
	amount = 900
	lifetime = LIFE
	preprocess = LIFE
	fixed_fps = 30
	local_coords = false
	explosiveness = 0.0
	visibility_aabb = AABB(Vector3(-AREA, -30.0, -AREA), Vector3(AREA * 2.0, 60.0, AREA * 2.0))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitting = false

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	# Losa PLANA en el nivel de reposo del agua: el shader se encarga de subir
	# cada aro a su ola.
	pm.emission_box_extents = Vector3(AREA, 0.02, AREA)
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 0.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.0
	pm.gravity = Vector3.ZERO
	# El aro CRECE: es lo que lo hace leer como impacto y no como mancha.
	pm.scale_min = RING_SIZE * 0.9
	pm.scale_max = RING_SIZE * 1.35
	pm.scale_curve = _grow_curve()
	# Y se apaga: nace de golpe y muere lento (COLOR.a en el shader).
	pm.color_ramp = _fade_ramp()
	process_material = pm

	var plane := PlaneMesh.new()
	plane.size = Vector2(1.0, 1.0)
	plane.orientation = PlaneMesh.FACE_Y
	_draw_mat = ShaderMaterial.new()
	_draw_mat.shader = load("res://game/world/rain_splash.gdshader")
	plane.material = _draw_mat
	draw_pass_1 = plane

	Ocean.sea_state_changed.connect(_push_wave_uniforms)
	Ocean.waves_regenerated.connect(_push_wave_uniforms)
	Ocean.events_changed.connect(_push_wave_uniforms)
	_push_wave_uniforms()


## De pequeño a pleno: el aro se abre durante toda su vida.
func _grow_curve() -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.25))
	c.add_point(Vector2(1.0, 1.0))
	var tex := CurveTexture.new()
	tex.curve = c
	return tex


## Ataque rapido y cola larga: el impacto aparece y se desvanece.
func _fade_ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.set_offset(0, 0.0)
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.set_offset(1, 1.0)
	g.set_color(1, Color(1, 1, 1, 0.0))
	g.add_point(0.12, Color(1, 1, 1, 1.0))
	var tex := GradientTexture1D.new()
	tex.gradient = g
	return tex


func _push_wave_uniforms() -> void:
	if _draw_mat != null:
		Ocean.apply_to_material(_draw_mat)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# La losa sigue a la camara EN EL PLANO DE REPOSO (y = 0), no a su altura:
	# los aros viven en el agua, no alrededor del ojo.
	global_position = Vector3(cam.global_position.x, 0.0, cam.global_position.z)

	var rain: float = Ocean.rain01
	emitting = rain > 0.01
	amount_ratio = rain
	if _draw_mat != null:
		_draw_mat.set_shader_parameter(&"ocean_time", Ocean.sim_time)
