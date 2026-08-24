class_name RainParticles3D
extends GPUParticles3D

## Lluvia visible: trazos toon cayendo en una losa pegada a la CAMARA. Es el
## patron estandar de la industria (docs/CLIMA.md §1.1): solo se paga lo que
## hay delante del jugador y las gotas se reciclan al salir de vista.
##
## Todo el nodo es PRESENTACION local: las gotas no existen para la fisica ni
## para la red. La unica verdad compartida es Ocean.rain01 y el viento, que ya
## derivan de (sim_time, semilla) — dos clientes ven "la misma lluvia" en lo
## estadistico, que es lo unico que el ojo puede comparar (§1.2: Lagarde da
## permiso explicito para no sincronizar gota a gota).
##
## Sigue la POSICION de la camara, jamas su rotacion: heredar rotacion arrastra
## la cortina al girar la vista y delata el truco — y sobre un barco que
## cabecea, la lluvia entera se inclinaria con la cubierta.
##
## Se configura entero por codigo (sin .tres) para que los numeros vivan junto
## a su porque; el look fino (color, grosor) puede migrar a uniforms cuando
## haya pase de arte.

## Altura de la losa de emision sobre la camara. Con ~9 m la gota ya cruza la
## mirada a su velocidad final y el preprocess llena el volumen al arrancar.
const EMITTER_HEIGHT := 9.0
## Cuanto viento aparente se lleva la gota. 1.0 seria lo fisico para gotas
## minusculas; con las gordas de juego 0.45 inclina la cortina de forma legible
## sin volverla horizontal en el temporal.
const WIND_FACTOR := 0.45
## Tope del empuje lateral (m/s²): por encima, la cortina a 60-70 grados deja
## de leerse como lluvia y parece nieve en ventisca.
const WIND_PUSH_MAX := 14.0
const FALL_GRAVITY := 22.0
## Color y alfa del trazo a plena luz de dia.
const BASE_COLOR := Color(0.88, 0.92, 0.97)
const BASE_ALPHA := 0.78
## Brillo minimo nocturno del trazo, como fraccion del diurno: visible contra
## el cielo negro sin volver al blanco quemado que molestaba (feedback).
const NIGHT_FLOOR := 0.24
## Energia ambiente que se considera "pleno dia" (ambient_energy del perfil
## por defecto). Solo normaliza la curva: si arte cambia el perfil, esto
## acompaña o se recalibra a ojo.
const DAY_AMBIENT_REF := 0.5


var _mat: StandardMaterial3D


func _ready() -> void:
	# Dimensionado para aguacero pleno; la densidad real la pone amount_ratio
	# cada frame (cambiar amount en caliente RESETEA el sistema — docs Godot).
	amount = 4000
	lifetime = 0.9
	preprocess = 0.9
	# 60 Hz y no 30: la colision se evalua por tick de simulacion, y a 30 Hz
	# una gota empujada por el viento (hasta ~26 m/s en diagonal) penetraba
	# medio metro DENTRO de la cabina antes de morir — llovia adentro
	# (feedback del playtest). A 60 Hz la penetracion queda escondida en el
	# margen exterior de la caja del refugio.
	fixed_fps = 60
	use_fixed_seed = true
	seed = 7331 # cosmetico: replays parecidos; las gotas no son estado de mundo
	local_coords = false
	transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	# El default (8 m) cullea la cortina al girar la camara Y apaga cualquier
	# colision GPU futura fuera de la caja (issue #93567).
	visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitting = false

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(10.0, 0.5, 10.0)
	pm.direction = Vector3(0.0, -1.0, 0.0)
	pm.spread = 0.0
	pm.initial_velocity_min = 14.0
	pm.initial_velocity_max = 18.0
	pm.gravity = Vector3(0.0, -FALL_GRAVITY, 0.0)
	# Tamaños variados: la mezcla de trazos cortos y largos vende profundidad
	# sin capas extra (los pequeños se leen como gotas lejanas).
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	# La gota MUERE al tocar un GPUParticlesCollision* (el RainShelterCabin del
	# barco): asi no llueve dentro de la cabina. Cajas analiticas y moviles —
	# un heightfield re-renderizaria profundidad cada frame en un barco que
	# cabecea, y el SDF no puede hornearse para una pose que rota (CLIMA §1.3).
	pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	process_material = pm
	# La caja de la cabina es un VOLUMEN de 2.4 m de alto, no una lamina: a
	# 20 m/s y 30 Hz la gota da >3 pasos dentro — sin tunel aunque el tamaño de
	# colision sea modesto. (Propiedad del NODO, no del material.)
	collision_base_size = 0.25

	# El trazo. La fisica manda aqui (MSR-TR-2006-102 / Garg-Nayar): en video
	# real la lluvia es una mezcla FRACCIONAL con el fondo — la gota cruza el
	# pixel una fraccion de la exposicion — asi que un trazo creible es
	# semitransparente, fino y con las puntas difuminadas (motion blur
	# horneado, como Remember Me). La primera version opaca de borde duro leia
	# como barras molestas: exactamente el error que esa literatura predice.
	var quad := QuadMesh.new()
	quad.size = Vector2(0.03, 0.65)
	_mat = StandardMaterial3D.new()
	var mat := _mat
	# UNSHADED con brillo acoplado a la LUZ AMBIENTE (se actualiza por frame).
	# Historia completa, para que nadie repita el ciclo: (1) unshaded fijo
	# brillaba a tope de noche; (2) material sombreado invertia la POLARIDAD
	# segun el fondo (gotas mas oscuras que el cielo al mirar arriba, claras
	# contra el casco — el brillo dependia del angulo sol↔billboard). La gota
	# real refracta el CIELO entero (~165 grados, Lagarde), no un sol puntual:
	# la aproximacion correcta es un velo SIEMPRE un poco mas claro que el
	# fondo, cuyo brillo global sigue a la luz de la escena — ambiente que el
	# ciclo dia/noche ya escribe en el Environment.
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = _make_streak_texture()
	# Alfa bajo (Cyanilux: "transparent with a low alpha value"): la cortina se
	# lee como velo, no como granizo. Quads finos: el overdraw transparente
	# total es minusculo aunque haya 4000 (el peligro de Forward+ son los quads
	# GRANDES con alfa, issue #97903).
	mat.albedo_color = Color(BASE_COLOR.r, BASE_COLOR.g, BASE_COLOR.b, BASE_ALPHA)
	# OJO: nada de distance_fade para esconder las gotas pegadas a camara — en
	# Godot, min > max no "oculta lo cercano": INVIERTE el fade entero y solo
	# renderiza lo que esta a menos de min metros (se comprobo midiendo el
	# capture_aabb: las 4000 gotas existian y solo se veian las de <2 m, con
	# el dither leyendose como cuentas). Las puntas suaves de la textura y el
	# alfa bajo ya evitan el barron cercano.
	quad.material = mat
	draw_pass_1 = quad


## Textura del trazo, horneada al arrancar (misma filosofia que el audio: cero
## assets): velo blanco con puntas y bordes difuminados — el motion blur de la
## gota viene en la textura, no se calcula.
func _make_streak_texture() -> ImageTexture:
	const W := 16
	const H := 64
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	for y in H:
		var v: float = float(y) / float(H - 1)
		var fade_v: float = pow(sin(PI * v), 1.3)
		for x in W:
			var u: float = float(x) / float(W - 1)
			var fade_u: float = pow(sin(PI * u), 1.6)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, fade_v * fade_u))
	# Con mipmaps la lejania FUNDE el trazo en vez de romperlo en chispas de
	# aliasing: es el fade de distancia gratis.
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	global_position = cam.global_position + Vector3(0.0, EMITTER_HEIGHT, 0.0)

	var rain: float = Ocean.rain01
	emitting = rain > 0.01
	amount_ratio = rain
	# El viento inclina la cortina. Cambia suave gratis: wind_speed deriva de
	# la furia rate-limited y de la racha, ambas continuas.
	var push := Ocean.wind_dir_vector() * minf(Ocean.wind_speed() * WIND_FACTOR, WIND_PUSH_MAX)
	(process_material as ParticleProcessMaterial).gravity = Vector3(push.x, -FALL_GRAVITY, push.y)

	# Brillo del trazo = luz ambiente de la escena (la escribe DayNightCycle),
	# con piso nocturno y un toque del tinte ambiente (noche = azulada).
	var env := get_world_3d().environment
	if env != null and _mat != null:
		var lum: float = clampf(env.ambient_light_energy / DAY_AMBIENT_REF, NIGHT_FLOOR, 1.0)
		var tint: Color = env.ambient_light_color.lerp(Color.WHITE, 0.65)
		_mat.albedo_color = Color(
			BASE_COLOR.r * lum * tint.r,
			BASE_COLOR.g * lum * tint.g,
			BASE_COLOR.b * lum * tint.b,
			BASE_ALPHA)
