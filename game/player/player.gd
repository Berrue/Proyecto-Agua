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

var state: State = State.DECK
var submersion: float = 0.0
var submerged_fraction: float = 0.0

## Las dos manos estan ocupadas (luchando con un pez, bombeando...): A/D dejan
## de mover al jugador — los consume la herramienta — y no se puede saltar.
## Es LA apuesta fisica del diseño: pescar te quita el agarre.
var hands_busy: bool = false

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


## En primera persona se oculta SOLO la cabeza (y el sombrero): al mirar abajo
## ves tu chubasquero y tus botas — la encarnacion estilo PEAK — sin que el
## craneo recorte la camara. El resto del cuerpo queda visible para sombras y,
## en el futuro, para los demas jugadores.
func _setup_first_person_body() -> void:
	var model := get_node_or_null(^"Pescador")
	if model == null:
		return
	for part_name in ["cabeza", "sombrero"]:
		var part := model.find_child(part_name, true, false) as Node3D
		if part != null:
			part.visible = false


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
	if hands_busy:
		return Vector3.ZERO # A/D son ahora la contra de la caña, no andar
	var raw := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	return (transform.basis * Vector3(raw.x, 0.0, raw.y)).normalized()


func _process_deck(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta

	var dir := _input_direction()
	var accel: float = deck_acceleration if is_on_floor() else air_acceleration
	var target := dir * walk_speed

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
	var target := _input_direction() * swim_speed + Vector3(current.x, 0.0, current.z)
	velocity.x = move_toward(velocity.x, target.x, 4.0 * delta)
	velocity.z = move_toward(velocity.z, target.z, 4.0 * delta)


func is_in_water() -> bool:
	return state != State.DECK
