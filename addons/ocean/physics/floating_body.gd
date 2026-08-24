class_name FloatingBody3D
extends RigidBody3D

## Cuerpo que flota sobre el oceano. Convierte la altura del agua en humor
## fisico creible, sin jitter y sin depender del tick rate.
##
## [b]Las cinco reglas que aqui NO se rompen.[/b] Son la causa raiz de los bugs
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
## 5. Los BRAZOS se miden desde el centro de masas, no desde el origen del nodo.
##    Medirlos desde el origen es aplicar cada empuje desplazado, y con lastre
##    (centro de masas por debajo) el error TUMBA en vez de adrizar. Estuvo asi
##    desde F1 y era mudo: el lastre del pesquero no hacia absolutamente nada.
##    Ver [method _centro_de_masas].
##
## Jolt tiene `ApplyBuoyancyImpulse` en su API de C++, pero Godot NO la expone
## (no hay ficheros de buoyancy en `modules/jolt_physics/objects`, la doc no la
## menciona y no hay ni una propuesta abierta). Y aunque la expusiera, asume un
## PLANO infinito, no un campo de olas. Asi que se escribe a mano.

signal slammed(strength: float, world_position: Vector3)
signal entered_water()
signal exited_water()

## El cuerpo paso de escorar a estar DEL REVES, y al reves. Hoy no lo escucha
## nadie: es el enganche para el estado REVOLCADO del jugador (F4 del plan), el
## aviso y el audio. Solo lo emiten los cuerpos con `brazo_adrizante > 0`.
##
## ⚠️ En un cliente NO se emite: `Net` le apaga el `_physics_process` al barco
## replicado, asi que `inclinacion` y `esta_volcado` se quedan congelados. Lo
## que cuelgue de esta señal y tenga que verse en las seis pantallas necesita
## viajar por el cable, como ya hacen la alarma y el naufragio del agua.
signal volcado()
signal adrizado()

const WATER_DENSITY := 1000.0

## Banda de histeresis del estado VOLCADO, en grados. Es un invariante del
## FEEDBACK, no un knob: ver `AdrizamientoModel.volcado` para el porque.
const BANDA_VOLCADO_DEG := 25.0

## Cada cuantos ticks simulados se le vuelve a preguntar al servidor donde tiene
## el cuerpo su centro de masas. Ver [method _centro_de_masas].
const REFRESCO_COM_TICKS := 240

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

@export_group("Adrizamiento")

## Brazo adrizante de la superestructura estanca, en METROS: el GZ que usaria un
## arquitecto naval. El par sale de peso x brazo, asi que no hay que reafinarlo
## si cambia la masa.
##
## 0 = el cuerpo no se adriza solo, y es lo correcto por defecto: un bidon, un
## farol o una caja no tienen un "arriba" que recuperar, y obligarles a uno se
## veria como magia. Lo enciende solo lo que tiene cubierta.
##
## El porque de que este par exista aparte de las sondas esta en
## `AdrizamientoModel`, y se resume en que las ocho celdas del pesquero estan en
## un plano y el casco flota igual de bien del derecho que del reves.
@export var brazo_adrizante: float = 0.0

## Escora (grados) a la que la superestructura empieza a morder el agua. Por
## debajo de esto el par vale CERO exactamente: navegar, cabecear y escorar con
## el oleaje se comportan igual que si este sistema no existiera.
@export var adrizamiento_inicio_deg: float = 45.0

## Escora (grados) a partir de la cual el brazo ya es pleno: la superestructura
## esta sumergida entera y hundirla mas no empuja mas.
@export var adrizamiento_pleno_deg: float = 100.0

## A que velocidad devuelve el mar, en grados por segundo. Es un objetivo, no un
## tope duro: el par empuja mientras se gire mas despacio y frena si se pasa.
@export var adrizamiento_deg_s: float = 35.0

## Escora (grados) a partir de la cual el cuerpo se declara VOLCADO y emite
## [signal volcado]. Solo tiene sentido con `brazo_adrizante > 0`.
@export var angulo_volcado_deg: float = 100.0

@export_group("")

var probes: Array[BuoyancyProbe3D] = []
var submerged_fraction: float = 0.0 ## 0..1 del cuerpo entero.
var is_in_water: bool = false

## Inclinacion actual en radianes: angulo entre el "arriba" del cuerpo y el del
## mundo. 0 = en pie, PI = del reves. Se actualiza en cada tick simulado.
var inclinacion: float = 0.0

## true desde [signal volcado] hasta [signal adrizado]. Ver `angulo_volcado_deg`.
var esta_volcado: bool = false

var _prev_submersion: PackedFloat32Array = PackedFloat32Array()
var _tick: int = 0
var _gravity: float = 9.81

## En el primer tick no hay profundidad anterior con la que comparar. Sin esto,
## un cuerpo que aparece bajo el agua registra una "entrada" a cientos de m/s y
## el impulso de impacto lo manda a la estratosfera nada mas nacer.
var _has_previous: bool = false

## Centro de masas en ejes LOCALES, cacheado. Ver [method _centro_de_masas].
var _com_local := Vector3.ZERO
var _com_cuenta: int = 0


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
	# REGLA 5: los brazos se miden desde el CENTRO DE MASAS. Ver `_centro_de_masas`.
	var com := _centro_de_masas()

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

		var offset := probe_pos - com

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

	submerged_fraction = total_submerged / float(probes.size())
	is_in_water = submerged_fraction > 0.0

	# Va DESPUES de `submerged_fraction` a proposito: el adrizamiento necesita
	# saber cuanto cuerpo hay dentro del agua en ESTE tick, porque el mar no
	# puede adrizar lo que no esta tocando.
	total_torque += _par_adrizante()

	constant_force = total_force
	constant_torque = total_torque
	_has_previous = true

	if is_in_water and not was_in_water:
		entered_water.emit()
	elif was_in_water and not is_in_water:
		exited_water.emit()


## El par que devuelve el cuerpo a su vertical, y de paso el estado VOLCADO.
##
## Es un par PURO: no suma ni un newton de fuerza, asi que no puede mover la
## linea de flotacion, el francobordo ni el pico de velocidad con que el barco
## sale del muro. Lo unico que cambia es la ACTITUD.
##
## Esa es tambien la razon de aplicarlo asi en vez de colgar sondas nuevas por
## encima de la cubierta, que seria lo "emergente": una celda estanca sobre la
## cubierta es empuje que la bodega no puede inundar, y un barco anegado hasta
## arriba dejaria de hundirse nunca. El agua tiene que seguir siendo lo que mata.
func _par_adrizante() -> Vector3:
	inclinacion = AdrizamientoModel.inclinacion(global_basis.y)
	if brazo_adrizante <= 0.0:
		return Vector3.ZERO

	var ahora := AdrizamientoModel.volcado(inclinacion, deg_to_rad(angulo_volcado_deg),
		deg_to_rad(BANDA_VOLCADO_DEG), esta_volcado)
	if ahora != esta_volcado:
		esta_volcado = ahora
		if esta_volcado:
			volcado.emit()
		else:
			adrizado.emit()

	# La reserva intacta manda: una bodega llena se lleva por delante el
	# adrizamiento igual que se lleva la flotacion. Volcar no es un estado sin
	# salida —el mar te devuelve—; lo que se paga es el agua que entro mientras
	# estabas del reves.
	var ganancia: float = AdrizamientoModel.ganancia(
		AdrizamientoModel.curva(inclinacion, deg_to_rad(adrizamiento_inicio_deg),
			deg_to_rad(adrizamiento_pleno_deg)),
		1.0 - flooding_level(),
		submerged_fraction)
	if ganancia <= 0.0:
		return Vector3.ZERO

	# El desempate es la proa: con el barco EXACTAMENTE del reves lo hace rodar
	# sobre el costado, que es como vuelve un barco de verdad, en vez de dar la
	# voltereta sobre la roda.
	var eje := AdrizamientoModel.eje(global_basis.y, -global_basis.z)
	return AdrizamientoModel.par(eje, mass * _gravity * brazo_adrizante, ganancia,
		angular_velocity.dot(eje), deg_to_rad(adrizamiento_deg_s))


## Centro de masas del cuerpo, en coordenadas del mundo.
##
## [b]REGLA 5 de la flotabilidad: los brazos se miden desde aqui, no desde el
## origen del nodo.[/b] Godot aplica `constant_force` EN el centro de masas y
## `constant_torque` RESPECTO a el, asi que un par acumulado con brazos medidos
## desde el origen equivale a aplicar cada empuje desplazado `centro - origen`.
## Con el centro de masas por debajo del origen —que es como se pone lastre— eso
## deja el empuje por DEBAJO de donde esta, y el termino que sobra,
## `(centro - origen) x F`, tumba en vez de adrizar: 0,45 x peso x sin(escora),
## unos 6 kN*m a 20 grados en el pesquero.
##
## Medido antes de arreglarlo: el par salia IDENTICO (+33.097 N*m a 20 grados de
## escora) con el centro de masas en -0,45, en 0 y en +0,45. O sea que el lastre
## del barco no entraba en la cuenta, y bajarlo restaba estabilidad en lugar de
## darla — justo al reves de lo que espera quien lo baja.
##
## Se lee del estado del servidor y no de la propiedad `center_of_mass` porque
## esa solo vale en modo CUSTOM: en AUTO el centro sale de las colisiones y hay
## cuerpos del juego (props, farol) cuya forma no esta centrada en su origen.
## El mismo offset sirve para el arrastre, que necesita la velocidad del PUNTO y
## esa se compone alrededor del centro de masas, no del origen.
##
## El offset LOCAL se cachea y se rota aqui. Preguntarselo al servidor en cada
## tick costaba un 9 % del presupuesto de flotabilidad del criterio de F2 con
## 200 sondas (medido con `perf_tests`: p50 3337 us contra 3074), y el dato no
## cambia salvo que alguien reescriba `center_of_mass` o las colisiones del
## cuerpo — cosa que hoy no hace nadie en el juego. Se refresca cada
## [constant REFRESCO_COM_TICKS] para que ese caso raro se cure solo en un par
## de segundos en vez de quedarse en un valor viejo para siempre, que es
## justamente la clase de fallo mudo que este repo convierte en test.
func _centro_de_masas() -> Vector3:
	_com_cuenta -= 1
	if _com_cuenta <= 0:
		_com_cuenta = REFRESCO_COM_TICKS
		var estado := PhysicsServer3D.body_get_direct_state(get_rid())
		if estado != null:
			_com_local = estado.center_of_mass_local
	return global_position + global_basis * _com_local


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
	# Aqui el brazo SI va desde el origen, y no contradice la regla 5:
	# `apply_impulse()` recibe la posicion respecto al origen y le resta el centro
	# de masas por dentro. Pasarle `probe_pos - com` seria descontarlo dos veces.
	apply_impulse(Vector3.UP * strength * slam_impulse_scale * mass, probe_pos - global_position)
	slammed.emit(strength, probe_pos)


func _update_flooding(probe: BuoyancyProbe3D, step: float) -> void:
	if not probe.floodable or probe.flood_rate <= 0.0:
		return
	# Inundacion progresiva: un solo float por celda y el barco se escora solo
	# hacia donde entra el agua.
	probe.flooding = clampf(probe.flooding + probe.flood_rate * step * 0.001 / probe.volume, 0.0, 1.0)


## Olvida la historia de agua del cuerpo y su empuje acumulado. Hay que
## llamarlo SIEMPRE despues de mover un cuerpo escribiendole el transform.
##
## Una escritura de transform ES un teleport, y un teleport fabrica un slam:
## `_check_slam()` calcula la velocidad de entrada como
## `(profundidad - profundidad_anterior) / step`, y ni `_prev_submersion` ni
## `_has_previous` se resetean en ningun sitio. El primer tick despues de un
## teleport ve decenas de m/s de entrada y dispara el impulso, el `slammed` y
## con el su SFX y su espuma: un chapuzon que no ocurrio (regla 8), ademas
## calculado distinto en cada maquina.
##
## No es un problema futuro de la red: soltar un farol bajo el agua ya lo
## produce hoy. La red solo lo multiplica por cada cuerpo replicado y cada
## devolucion de autoridad.
##
## De paso borra `constant_force`/`constant_torque`, que se escriben de forma
## PERSISTENTE (a proposito, para sobrevivir al `tick_divisor`) y no se borran
## en ningun otro sitio del repo: sin esto, un cuerpo congelado guarda dentro
## el empuje de antes y se lo come entero en el instante del descongelado.
func olvidar_historial_agua() -> void:
	_prev_submersion.fill(0.0)
	_has_previous = false
	constant_force = Vector3.ZERO
	constant_torque = Vector3.ZERO


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


## Achica UNA celda y devuelve cuanta agua salio de verdad. Es la operacion de la
## BOMBA, frente a `bail_out()`, que reparte entre todas.
##
## La diferencia es la mecanica entera: si la bomba vaciara todas las celdas por
## igual, daria lo mismo donde pusieras el cabezal de la manguera y se perderia
## la unica decision que tiene el achicador (docs/DISENO.md: "elegir QUE celda
## achicar primero es la decision").
##
## Devolver lo drenado —y no void— es lo que deja distinguir "estoy sacando
## agua" de "estoy chupando aire" sin que el llamador tenga que leer el estado
## antes y despues: con la celda seca sale 0 y la bomba puede escupir y sonar a
## vacio.
func drain_probe(index: int, amount: float) -> float:
	if index < 0 or index >= probes.size() or amount <= 0.0:
		return 0.0
	var antes: float = probes[index].flooding
	probes[index].flooding = clampf(antes - amount, 0.0, 1.0)
	return antes - probes[index].flooding


## Anegamiento de UNA celda, 0..1.
func probe_flooding(index: int) -> float:
	if index < 0 or index >= probes.size():
		return 0.0
	return probes[index].flooding


func probe_count() -> int:
	return probes.size()


## La celda mas cercana a un punto del mundo, o -1 si el cuerpo no tiene sondas.
##
## Compara solo en el plano de cubierta (XZ local) a proposito: el cabezal de la
## manguera cuelga y se balancea, y lo que decide de que compartimento aspira es
## DONDE esta sobre la cubierta, no a que altura quedo colgando ese tick.
func probe_index_at(global_pos: Vector3) -> int:
	if probes.is_empty():
		return -1
	var local := to_local(global_pos)
	var mejor: int = 0
	var mejor_dist: float = INF
	for i in probes.size():
		var p := probes[i].position
		var d: float = Vector2(p.x - local.x, p.z - local.z).length_squared()
		if d < mejor_dist:
			mejor_dist = d
			mejor = i
	return mejor


## Escribe los niveles de las celdas de golpe. SOLO para la replica de red: el
## agua la simula el host y el cliente la copia.
##
## En el host no lo llama NADIE. La regla es que cada `flooding` tenga un solo
## escritor: en el host, quien simula el agua; en el cliente, este metodo. Dos
## escritores sobre el mismo float es como se desincroniza una partida sin que
## salte ningun error.
func fijar_inundacion(niveles: PackedFloat32Array) -> void:
	for i in mini(niveles.size(), probes.size()):
		probes[i].flooding = clampf(niveles[i], 0.0, 1.0)
