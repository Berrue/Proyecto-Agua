class_name Player
extends CharacterBody3D

## Jugador en primera persona. Su trabajo en F1 es responder UNA pregunta:
## ¿es divertido intentar mantenerse de pie sobre algo que se mueve?
##
## Estados: EN CUBIERTA -> NADANDO -> BAJO EL AGUA. El revolcon por rompiente
## entra en F4 junto con el ragdoll.
##
## Regla de diseño que no se negocia: las corrientes se SUMAN a tu velocidad,
## nunca la sustituyen. Si el input deja de producir efecto visible, el juego se
## siente roto, no dificil.

enum State { DECK, SWIMMING, UNDERWATER }

@export var walk_speed: float = 4.2
@export var swim_speed: float = 2.0
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.0022

## Por encima de esta inclinacion de cubierta dejas de agarrar y resbalas. Es
## literalmente el pilar de diseño del juego, asi que es un numero que se toca
## mucho en playtest.
@export var deck_grip_angle_deg: float = 38.0

## Aceleracion en cubierta. Baja = te cuesta corregir = mas comedia.
@export var deck_acceleration: float = 9.0
@export var air_acceleration: float = 2.0

@export var eye_height: float = 1.55

## Cuanto de la altura del cuerpo tiene que estar bajo el agua para nadar.
@export var swim_threshold: float = 0.55

@export var body_height: float = 1.8

## El brazo en primera persona: UN miton del PROPIO modelo, estirado a lo largo
## del mango hasta que deja de ser un muñon. `arm_grip` es donde queda la mano
## sobre el mango; el codo se va por el borde de abajo. Numeros de playtest.
@export var arm_grip: float = 0.05
@export var arm_length: float = 0.6
@export var arm_radius: float = 0.07

var state: State = State.DECK
var submersion: float = 0.0
var submerged_fraction: float = 0.0

## Manos ocupadas por lo que PORTAS (0, 1 o 2): el farol ocupa una, un pez
## grande las dos. Lo escriben el Portador y las herramientas, nunca player.gd.
## Con las dos manos llenas caminas (lento — lo decide el portador via
## `carry_slowdown`) pero no saltas ni puedes lanzar la caña.
var hands_used: int = 0

## La herramienta ha CAPTURADO el input (la lucha de la caña): A/D son suyos y
## no se salta. Es LA apuesta fisica del diseño: pescar te quita el agarre.
## NO es lo mismo que llevar las dos manos llenas — con un fletan al pecho
## caminas trastabillando; peleando un pez, no te moves.
var input_captured: bool = false

## El contrato historico "las dos manos ocupadas". La caña lo ESCRIBE al entrar
## y salir de la lucha (captura el input Y llena las manos); el resto del juego
## lo LEE como "no hay manos libres", venga de la lucha o de un porteo a dos
## manos.
var hands_busy: bool:
	get:
		return input_captured or hands_used >= 2
	set(value):
		input_captured = value
		hands_used = 2 if value else 0

## Factor de velocidad por la carga (1 = libre). Lo escribe el Portador segun
## el peso: la sardina no se nota, el atun te convierte en procesion.
var carry_slowdown: float = 1.0

## El brazo del viewmodel. Publico porque las capturas de tercera persona (y
## manana la vista de los demas jugadores) tienen que apagarlo.
var arm: MeshInstance3D = null

## El cuerpo animado. Publico porque tests y capturas plantan poses concretas.
var animator: PlayerAnimator = null

## Gesticulacion facial aditiva: parpadeo, mirada, habla y expresiones. Vive
## separada del AnimationTree corporal para no competir por Head/Neck.
var face_animator: PlayerFaceAnimator = null

@onready var _camera: Camera3D = $Camera3D

var _pitch: float = 0.0
var _gravity: float = 9.81


func _ready() -> void:
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.81))
	floor_max_angle = deg_to_rad(deck_grip_angle_deg)
	# Imprescindible sobre una cubierta que cabecea: sin esto el jugador se
	# despega de la superficie en cuanto el barco baja de golpe.
	floor_snap_length = 0.5
	floor_stop_on_slope = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_setup_first_person_body()
	_setup_animator()


## En primera persona solo se ve UN BRAZO: ni cuerpo, ni cuello, ni botas.
## El pescador entero pasa a "solo sombra" — se sigue proyectando en cubierta,
## que es informacion util (te dice donde estas parado y hacia donde miras),
## pero deja de recortar la camara y de taparte la caña con el chubasquero.
func _setup_first_person_body() -> void:
	var model := get_node_or_null(^"Pescador") as Node3D
	if model == null:
		return
	for mesh: MeshInstance3D in _body_meshes(model):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	_build_arm(model)


## Un unico brazo: la bola del miton derecho estirada a lo largo del mango hasta
## que deja de ser un muñon y entra en cuadro por abajo como un antebrazo. Se
## queda con el material del pescador (misma piel, mismo low poly). Cuelga del
## PIVOTE de la caña y no de la camara: asi sigue el doblado y el latigazo sin
## animar una sola linea.
func _build_arm(model: Node3D) -> void:
	# Pedimos por tipo: el modelo historico tenia un BoneAttachment3D con este
	# mismo nombre y el nuevo conserva la malla como contrato de material.
	var found := model.find_children("palma_R", "MeshInstance3D", true, false)
	var src: MeshInstance3D = found[0] if not found.is_empty() else null
	if src == null or src.mesh == null:
		return
	var mount := get_node_or_null(^"Camera3D/FishingRod/RodPivot") as Node3D
	if mount == null:
		mount = _camera
	arm = MeshInstance3D.new()
	arm.name = "BrazoPrimeraPersona"
	# La bola del miton estirada a secas acaba en punta (un elipsoide 4:1 parece
	# un cono). Capsula: mismo largo, mismo material del pescador, pero con el
	# extremo REDONDO, que es lo que lee como brazo.
	var capsule := CapsuleMesh.new()
	capsule.radius = arm_radius
	capsule.height = maxf(arm_length, arm_radius * 2.0 + 0.001)
	capsule.radial_segments = 8
	capsule.rings = 2
	arm.mesh = capsule
	# La mano cae en el mango y el brazo tira hacia atras (-Y del pivote), que es
	# justo hacia donde estaria tu hombro.
	arm.position = Vector3(0.0, arm_grip - capsule.height * 0.5, 0.0)
	# Un brazo flotando delante de la camara no proyecta sombra: la sombra buena,
	# la del cuerpo entero, ya la esta tirando el modelo.
	arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# ...y tampoco la RECIBE. El cuerpo invisible te sigue tapando el sol, y sin
	# esto el brazo se pone gris justo cuando mas lo miras (peleando).
	var mat := src.get_active_material(0)
	if mat is StandardMaterial3D:
		var view_mat := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
		view_mat.disable_receive_shadows = true
		arm.material_override = view_mat
	else:
		arm.material_override = mat
	mount.add_child(arm)


## Monta el arbol de animacion sobre el modelo. Si faltara un clip el jugador
## tiene que seguir jugable: te quedas en T-pose, que es feo pero no rompe nada.
func _setup_animator() -> void:
	var model := get_node_or_null(^"Pescador") as Node3D
	if model == null:
		return
	var a: PlayerAnimator = PlayerAnimator.new()
	a.name = "Animator"
	add_child(a)
	if a.setup(model):
		animator = a
	else:
		a.queue_free()

	# La cara tambien funciona si faltan clips corporales: en ese caso conserva
	# los microgestos autonomos y simplemente no recibe contexto de locomocion.
	var facial := PlayerFaceAnimator.new()
	facial.name = "FaceAnimator"
	add_child(facial)
	if facial.setup(model):
		face_animator = facial
		if animator != null:
			face_animator.bind_body_animator(animator)
	else:
		facial.queue_free()


## Todas las piezas dibujables del pescador, rigidas o skinned.
func _body_meshes(model: Node3D) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		out.append(node as MeshInstance3D)
	return out


## Enciende o apaga el cuerpo entero. En partida SIEMPRE esta apagado; lo usan
## las capturas de tercera persona y, cuando entre la red, la copia de este
## jugador que veran los demas.
func set_body_visible(body_visible: bool) -> void:
	var model := get_node_or_null(^"Pescador") as Node3D
	if model == null:
		return
	var mode: int = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON if body_visible
		else GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	)
	for mesh: MeshInstance3D in _body_meshes(model):
		mesh.cast_shadow = mode
	if arm != null:
		arm.visible = not body_visible


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		rotate_y(-motion.relative.x * mouse_sensitivity)
		_pitch = clampf(_pitch - motion.relative.y * mouse_sensitivity, -1.4, 1.4)
		_camera.rotation.x = _pitch
	elif event.is_action_pressed(&"toggle_mouse"):
		Input.mouse_mode = (
			Input.MOUSE_MODE_VISIBLE
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED
		)


func _physics_process(delta: float) -> void:
	_update_water_state()

	match state:
		State.DECK:
			_process_deck(delta)
		State.SWIMMING, State.UNDERWATER:
			_process_swimming(delta)

	move_and_slide()
	_feed_animator(delta)


## La animacion se alimenta de `velocity` TAL CUAL, y esto es contraintuitivo:
## parece que sobre un barco en marcha habria que restarle la velocidad de la
## plataforma. NO. Medido en el toybox con el jugador quieto sobre la cubierta:
## `velocity` = (0,0,0) y `get_platform_velocity()` = el cabeceo del barco
## (hasta 0.5 m/s). Godot ya mueve al CharacterBody3D con la plataforma sin
## tocarle la velocidad, asi que restarla haria que el pescador "caminara" con
## cada ola y que la mezcla vibrara con el balanceo. Si alguien lo "arregla",
## esta es la razon por la que no.
func _feed_animator(delta: float) -> void:
	if animator == null:
		return
	var ratio: float = 0.0
	if not is_in_water():
		ratio = Vector2(velocity.x, velocity.z).length() / maxf(walk_speed, 0.001)
	# El agua no entra de golpe al cruzar el umbral de nadar: se va colando desde
	# que te llega al muslo. Vadear y nadar son el mismo gesto continuo, y un
	# corte seco justo en el umbral se lee como un bug de estado.
	var agua := smoothstep(swim_threshold - 0.2, swim_threshold, submerged_fraction)
	# La pose de caña la dispara LA LUCHA, no el recuento de manos: con un fletan
	# a dos manos caminas cargando, no pescando.
	animator.update(ratio, agua, input_captured, delta)


func _update_water_state() -> void:
	# `global_position` es el CENTRO de la capsula, no los pies. Medir desde
	# aqui y no desde los pies evita que el juego crea que estas nadando en
	# cuanto una ola te moja los tobillos.
	var water_y := Ocean.get_height(global_position)
	submersion = water_y - global_position.y

	# 0 = agua a la altura de los pies, 0.5 = a la cintura, 1 = cubierto.
	submerged_fraction = clampf((submersion + body_height * 0.5) / body_height, 0.0, 1.0)

	if submerged_fraction >= 0.99:
		state = State.UNDERWATER
	elif submerged_fraction >= swim_threshold:
		state = State.SWIMMING
	else:
		state = State.DECK


func _input_direction() -> Vector3:
	if input_captured:
		return Vector3.ZERO # A/D son ahora la contra de la caña, no andar
	var raw := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	return (transform.basis * Vector3(raw.x, 0.0, raw.y)).normalized()


func _process_deck(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta

	var dir := _input_direction()
	var accel: float = deck_acceleration if is_on_floor() else air_acceleration
	var target := dir * walk_speed * carry_slowdown

	velocity.x = move_toward(velocity.x, target.x, accel * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * delta)

	if Input.is_action_just_pressed(&"jump") and is_on_floor() and not hands_busy:
		velocity.y = jump_velocity


func _process_swimming(delta: float) -> void:
	# Empuje hacia la superficie, proporcional a lo hundido que estes. No es un
	# muelle rigido a proposito: rebotar como un corcho se ve mal y ademas marea.
	var buoyancy: float = submerged_fraction * _gravity * 1.55
	velocity.y += (buoyancy - _gravity) * delta
	velocity.y = clampf(velocity.y, -6.0, 4.0)

	# Nadas RELATIVO al agua, no relativo al mundo: la corriente te lleva, pero
	# tu input siempre produce el mismo efecto visible sobre ella. Si la
	# corriente pudiera anular el input, el juego se sentiria roto en vez de
	# dificil, que es la diferencia entre comedia y castigo.
	var current := Ocean.get_surface_velocity(global_position)
	var target := _input_direction() * swim_speed * carry_slowdown + Vector3(current.x, 0.0, current.z)
	velocity.x = move_toward(velocity.x, target.x, 4.0 * delta)
	velocity.z = move_toward(velocity.z, target.z, 4.0 * delta)


func is_in_water() -> bool:
	return state != State.DECK
