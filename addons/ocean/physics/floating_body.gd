class_name FloatingBody3D
extends RigidBody3D

## Cuerpo que flota sobre el oceano. Convierte la altura del agua en humor
## fisico creible, sin jitter y sin depender del tick rate.
##
## [b]Las cuatro reglas que aqui NO se rompen.[/b] Son la causa raiz de los bugs
## de flotabilidad que arrastra medio ecosistema de Godot (el issue "Heavy
## buoyancy jitter" de godot4-oceanfft lleva abierto desde 2024 y empeora justo
## al subir el viento, o sea que falla en tormenta, que es cuando mas importa):
##
## 1. NUNCA multiplicar la fuerza por delta antes de `apply_force()`: ya integra
##    sobre el tick. Hacerlo es integrar dos veces.
## 2. NUNCA `linear_velocity *= (1 - drag)`: eso depende del tick rate, asi que
##    el cuerpo se comporta distinto a 60 y a 120 Hz. Se usa `linear_damp` con
##    `DAMP_MODE_REPLACE`, que Jolt integra bien.
## 3. CLAMPAR la profundidad antes de convertirla en fuerza. Sin esto, un cuerpo
##    que aparece 20 m bajo el agua (o que cae desde la cresta de una ola de
##    15 m) sale disparado a la estratosfera. Es el "bug del barril cohete".
## 4. AMORTIGUAR contra la superficie MOVIL, no contra el mundo. Contra el mundo
##    el cuerpo se resiste a subir con la ola y parece pegado; contra la
##    superficie, cabalga la ola. Y de paso salen las corrientes gratis.
##
## Jolt tiene `ApplyBuoyancyImpulse` en su API de C++, pero Godot NO la expone
## (no hay ficheros de buoyancy en `modules/jolt_physics/objects`, la doc no la
## menciona y no hay ni una propuesta abierta). Y aunque la expusiera, asume un
## PLANO infinito, no un campo de olas. Asi que se escribe a mano.

signal slammed(strength: float, world_position: Vector3)
signal entered_water()
signal exited_water()

const WATER_DENSITY := 1000.0

## Coeficiente de arrastre. 0.5 es una caja; ~0.05 un casco hidrodinamico.
@export var drag_coefficient: float = 0.5

## Arrastre angular sumergido. Sube esto antes que inventar "added mass": el
## equipo de Avalanche intento implementarla y la dejo fuera por complejidad.
@export var angular_drag: float = 0.6

## Tope de profundidad efectiva, en metros. REGLA 3: es el clamp que impide que
## un cuerpo muy hundido salga disparado.
@export var max_submersion_depth: float = 3.0

## Velocidad de entrada (m/s) a partir de la cual se considera un impacto.
## Es lo que convierte "el barco sube y baja" en "el barco SE ESTRELLA contra el
## agua": diez lineas de codigo para el mejor feedback fisico del juego.
@export var slam_threshold: float = 6.0

@export var slam_impulse_scale: float = 0.35

## Cada cuantos ticks se recalcula. 1 para el barco y los jugadores; 2 o 3 para
## bidones y restos, que nadie mira de cerca.
@export_range(1, 8) var tick_divisor: int = 1

var probes: Array[BuoyancyProbe3D] = []
var submerged_fraction: float = 0.0 ## 0..1 del cuerpo entero.
var is_in_water: bool = false

var _prev_submersion: PackedFloat32Array = PackedFloat32Array()
var _tick: int = 0
var _gravity: float = 9.81

## En el primer tick no hay profundidad anterior con la que comparar. Sin esto,
## un cuerpo que aparece bajo el agua registra una "entrada" a cientos de m/s y
## el impulso de impacto lo manda a la estratosfera nada mas nacer.
var _has_previous: bool = false


func _ready() -> void:
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.81))
	_collect_probes()

	# REGLA 2: el amortiguado lo lleva el motor, no una multiplicacion de la
	# velocidad. Se deja bajo y constante porque el arrastre de verdad lo aplica
	# `_apply_drag()` contra la superficie movil.
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.05
	angular_damp = 0.1

	can_sleep = false


func _collect_probes() -> void:
	probes.clear()
	for child in get_children():
		if child is BuoyancyProbe3D:
			probes.append(child)
	_prev_submersion.resize(probes.size())
	_prev_submersion.fill(0.0)

	if probes.is_empty():
		push_warning("FloatingBody3D '%s' no tiene ninguna BuoyancyProbe3D: no va a flotar." % name)


func _physics_process(delta: float) -> void:
	_tick += 1
	if _tick % tick_divisor != 0:
		return
	# El divisor salta ticks, asi que el delta efectivo es mayor. Solo importa
	# para tasas (inundacion, deteccion de impacto), nunca para las fuerzas.
	var step: float = delta * float(tick_divisor)

	if probes.is_empty():
		return

	var total_submerged: float = 0.0
	var was_in_water := is_in_water

	# Las fuerzas se acumulan y se publican como `constant_force`/`constant_torque`
	# en vez de `apply_force`. Motivo: `apply_force` solo dura UN step de fisica,
	# asi que con `tick_divisor > 1` el cuerpo pasaria los ticks saltados sin
	# empuje y sin arrastre, cayendo a plomo. `constant_*` persiste hasta que se
	# reescribe, que es exactamente el comportamiento que queremos.
	var total_force := Vector3.ZERO
	var total_torque := Vector3.ZERO

	for i in probes.size():
		var probe: BuoyancyProbe3D = probes[i]
		var probe_pos := probe.global_position

		# Una sola resolucion del punto fijo para altura Y velocidad.
		var sample: Dictionary = Ocean.sample(probe_pos)
		var depth: float = float(sample[&"height"]) - probe_pos.y
		probe.submersion = depth

		if depth <= 0.0:
			probe.submerged_fraction = 0.0
			_prev_submersion[i] = depth
			continue

		var offset := probe_pos - global_position

		var frac: float = probe.compute_submerged_fraction(depth)
		probe.submerged_fraction = frac
		total_submerged += frac

		# REGLA 3: la profundidad que entra en la fuerza va clampada.
		var effective_depth: float = minf(depth, max_submersion_depth)
		var depth_ratio: float = effective_depth / maxf(probe.height, 0.01)
		var submerged_volume: float = probe.volume * clampf(depth_ratio, 0.0, 1.0)

		# Empuje de Arquimedes. REGLA 1: sin multiplicar por delta.
		var buoyant := Vector3.UP * (
			WATER_DENSITY * _gravity * submerged_volume * probe.effective_buoyancy())
		total_force += buoyant
		total_torque += offset.cross(buoyant)

		var drag := _compute_drag(probe, sample[&"velocity"], offset, frac)
		total_force += drag
		total_torque += offset.cross(drag)

		# Amortiguado angular proporcional a lo sumergido que este el cuerpo.
		# Sube esto antes que inventar "added mass": el equipo de Avalanche la
		# intento implementar y la dejo fuera por complejidad.
		total_torque -= angular_velocity * angular_drag * frac * mass / float(probes.size())

		_check_slam(i, probe, depth, probe_pos, step)
		_update_flooding(probe, step)

		_prev_submersion[i] = depth

	constant_force = total_force
	constant_torque = total_torque
	_has_previous = true

	submerged_fraction = total_submerged / float(probes.size())
	is_in_water = submerged_fraction > 0.0

	if is_in_water and not was_in_water:
		entered_water.emit()
	elif was_in_water and not is_in_water:
		exited_water.emit()


func _compute_drag(probe: BuoyancyProbe3D, water_vel: Vector3, offset: Vector3, frac: float) -> Vector3:
	# REGLA 4: la velocidad que cuenta es la RELATIVA a la superficie, no al
	# mundo. Contra el mundo el cuerpo se resiste a subir con la ola y parece
	# pegado; contra la superficie, la cabalga. Y de paso salen las corrientes.
	var point_vel := linear_velocity + angular_velocity.cross(offset)
	var rel_vel := point_vel - water_vel

	var speed := rel_vel.length()
	if speed < 0.001:
		return Vector3.ZERO

	# Arrastre cuadratico: F = -0.5 * rho * Cd * A * |v| * v
	var drag_mag: float = 0.5 * WATER_DENSITY * drag_coefficient * probe.drag_area * frac * speed * speed

	# TOPE DE ESTABILIDAD. El arrastre puede, como mucho, llevar el cuerpo a la
	# velocidad del agua: nunca pasarse de largo. Si se pasa, al tick siguiente
	# la velocidad relativa se ha invertido y es mayor, el termino cuadratico
	# devuelve un golpe aun mas fuerte, y el cuerpo explota en unos pocos ticks.
	#
	# El reparto entre sondas es imprescindible: el tope acota la fuerza TOTAL
	# sobre el cuerpo, asi que a cada sonda le toca su parte. Sin dividir entre
	# `probes.size()`, un barco de 8 sondas recibe 8 veces el tope y explota
	# igualmente. Se descubrio con el tsunami de tier 3, donde el agua viaja a
	# ~31 m/s, pero habria pasado con cualquier corriente fuerte.
	var dt: float = float(tick_divisor) / float(maxi(Engine.physics_ticks_per_second, 1))
	var max_mag: float = 0.5 * speed * mass / maxf(dt * float(probes.size()), 1e-6)
	drag_mag = minf(drag_mag, max_mag)

	return -rel_vel.normalized() * drag_mag


func _check_slam(index: int, probe: BuoyancyProbe3D, depth: float, probe_pos: Vector3, step: float) -> void:
	if slam_threshold <= 0.0 or step <= 0.0 or not _has_previous:
		return
	if _prev_submersion[index] > 0.0:
		return # ya estaba sumergida: no es una entrada
	var entry_speed: float = (depth - _prev_submersion[index]) / step
	if entry_speed <= slam_threshold:
		return
	# Tope duro: por muy violento que sea el golpe, el impulso no puede exceder
	# unas pocas veces el peso del cuerpo. Un impacto es un golpe seco, no un
	# lanzamiento.
	var strength: float = minf((entry_speed - slam_threshold) / slam_threshold, 3.0)
	apply_impulse(Vector3.UP * strength * slam_impulse_scale * mass, probe_pos - global_position)
	slammed.emit(strength, probe_pos)


func _update_flooding(probe: BuoyancyProbe3D, step: float) -> void:
	if not probe.floodable or probe.flood_rate <= 0.0:
		return
	# Inundacion progresiva: un solo float por celda y el barco se escora solo
	# hacia donde entra el agua.
	probe.flooding = clampf(probe.flooding + probe.flood_rate * step * 0.001 / probe.volume, 0.0, 1.0)


## Anota una sonda como anegada. La escora sale sola de la fisica.
func flood_probe(index: int, amount: float) -> void:
	if index < 0 or index >= probes.size():
		return
	probes[index].flooding = clampf(probes[index].flooding + amount, 0.0, 1.0)


## Achicar: es lo que hace el jugador con el cubo.
func bail_out(amount: float) -> void:
	for probe in probes:
		probe.flooding = clampf(probe.flooding - amount, 0.0, 1.0)


## Media de anegamiento, 0..1. Para el HUD y para decidir cuando el barco se pierde.
func flooding_level() -> float:
	if probes.is_empty():
		return 0.0
	var total: float = 0.0
	for probe in probes:
		total += probe.flooding
	return total / float(probes.size())
