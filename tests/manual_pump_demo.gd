extends Node3D

## Banco interactivo del modulo de achique. No suplanta al futuro interactor del
## Player: permite validar por separado agarre, recorrido y estabilidad antes de
## instalar la estacion en un RigidBody3D que cabecea.
##
## Controles: E toma/suelta; flechas desplazan en horizontal; RePag/AvPag en
## vertical; R recoge la manguera; F activa un recorrido automatico.

@export var hand_speed: float = 1.8

@onready var pump: ManualBilgePump = $ManualBilgePump
@onready var grip: Marker3D = $GripTarget
@onready var grip_visual: MeshInstance3D = $GripTarget/DebugHand
@onready var camera: Camera3D = $Camera3D

var _automatic: bool = false
var _automatic_time: float = 0.0


func _ready() -> void:
	camera.look_at(Vector3(0.0, 0.65, 0.0), Vector3.UP)
	grip.global_position = pump.posicion_toma_global()
	grip_visual.visible = true


func _physics_process(delta: float) -> void:
	if _automatic:
		_automatic_time += delta
		if not pump.esta_manguera_tomada():
			grip.global_position = pump.posicion_toma_global()
			pump.tomar_manguera(grip)
		var local_target := Vector3(
			2.1 + sin(_automatic_time * 0.65) * 1.2,
			0.40 + sin(_automatic_time * 1.1) * 0.25,
			-1.2 + cos(_automatic_time * 0.55) * 1.8
		)
		grip.global_position = pump.to_global(local_target)
		grip_visual.visible = false
		return

	var direction := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_LEFT):
		direction.x -= 1.0
	if Input.is_physical_key_pressed(KEY_RIGHT):
		direction.x += 1.0
	if Input.is_physical_key_pressed(KEY_UP):
		direction.z -= 1.0
	if Input.is_physical_key_pressed(KEY_DOWN):
		direction.z += 1.0
	if Input.is_physical_key_pressed(KEY_PAGEUP):
		direction.y += 1.0
	if Input.is_physical_key_pressed(KEY_PAGEDOWN):
		direction.y -= 1.0
	if direction.length_squared() > 0.0:
		var speed_scale := 2.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0
		grip.global_position += direction.normalized() * hand_speed * speed_scale * delta


func _unhandled_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	match key_event.physical_keycode:
		KEY_E:
			_automatic = false
			if pump.esta_manguera_tomada():
				pump.soltar_manguera()
				grip.global_position = pump.posicion_toma_global()
				grip_visual.visible = true
			else:
				grip.global_position = pump.posicion_toma_global()
				if pump.tomar_manguera(grip):
					grip_visual.visible = false
		KEY_R:
			_automatic = false
			pump.soltar_manguera()
			var hose := pump.get_hose()
			if hose != null and hose.has_method("reset_hose"):
				hose.call("reset_hose")
			grip.global_position = pump.posicion_toma_global()
			grip_visual.visible = true
		KEY_F:
			_automatic = not _automatic
			_automatic_time = 0.0
		_:
			pass
