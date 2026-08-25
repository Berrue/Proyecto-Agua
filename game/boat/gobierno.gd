class_name Gobierno
extends Node

## El GOBIERNO del pesquero: lo que lo hace navegable. Cuelga del
## [FloatingBody3D] del barco y aplica TRES fuerzas cada tick — el plano de
## deriva del casco, la helice y la pala del timon.
##
## Toda la matematica vive en [TimonModel] y [MotorModel] (puros y testeables) y
## todos los numeros en los dos `.tres` de balance. Aca solo queda el cableado:
## muestrear `Ocean`, evaluar el modelo tres veces y aplicar.
##
## Es un [Node] y no un [Node3D] a proposito: no tiene transform propio: los
## puntos donde empuja salen del balance, en ejes del casco. Un transform aqui
## seria un segundo sitio donde vive la misma posicion.
##
## [b]LA TRAMPA QUE DA FORMA A ESTE ARCHIVO.[/b] [FloatingBody3D] publica sus
## fuerzas ASIGNANDO `constant_force`/`constant_torque` en cada tick simulado —
## lo necesita para sobrevivir a su `tick_divisor`, que le hace saltar ticks—.
## Si el gobierno escribiera en esas mismas propiedades, o usara
## `add_constant_force()`, la flotabilidad se borraria o el empuje se perderia
## SEGUN EL ORDEN DE LOS NODOS EN EL ARBOL. Y el orden del arbol no es un
## contrato: alguien reordena la escena y el barco se hunde sin un solo error en
## consola. Por eso aqui SOLO se usa `apply_force()`: en Jolt esas llamadas se
## acumulan en un sumador aparte que el motor vacia tras cada Update, asi que
## conviven con `constant_force` sin pisarla y sin depender del orden.
## `gobierno_tests` lo custodia.
##
## [b]Solo corre en el host[/b], igual que `AguaEmbarcada`, y el guard tiene que
## estar en ESTE nodo y no solo en `Net`: cuando el cliente congela el barco le
## apaga el `_physics_process` al cuerpo, pero los hijos siguen procesando tan
## campantes.
##
## Ver `docs/TIMON.md`.

## El motor arranco. Para el audio del arranque y el ralenti (ElevenLabs).
signal motor_arrancado()

## El motor se paro, y por que. "sin nafta" es el unico motivo automatico; el
## resto llegan de que alguien lo pare o saque la llave.
signal motor_parado(causa: String)

@export var balance: GobiernoBalance
@export var motor: MotorNaftaBalance


# =============================================================================
#  Lo que el puesto escribe (F3) y hoy escriben el arnes y el HUD de debug
# =============================================================================

## Lo que pide la mano del timonel: -1 babor, +1 estribor. NO es el angulo de
## pala: entre esto y la pala hay dos etapas de rate-limit (ver [TimonModel]).
var mando: float = 0.0

## La muesca del telegrafo. Ver [enum MotorModel.Muesca].
var muesca: int = MotorModel.Muesca.STOP

## ¿Esta la llave del motor en el contacto? Hoy nace puesta para que el barco se
## pueda probar; en F3 la pone y la saca el jugador con la llave de verdad
## (`game/props/llave_motor.tscn`), que se hunde si cae al agua.
var llave_puesta: bool = true


# =============================================================================
#  El estado que se lee (HUD, audio, y lo que replicara F8)
# =============================================================================

## Donde llego la rueda persiguiendo a la mano, -1..1. Es lo que hay que animar
## en el aro del timon, y lo que viaja por el cable.
var rueda: float = 0.0

## Donde llego la pala persiguiendo a la rueda, -1..1.
var pala: float = 0.0

## Empuje real de la maquina tras la rampa, -1..1.
var empuje: float = 0.0

var arrancado: bool = false

## Nafta en el tanque, en litros.
var litros: float = 0.0

var _barco: FloatingBody3D


func _ready() -> void:
	_barco = get_parent() as FloatingBody3D
	if _barco == null:
		push_error("Gobierno tiene que colgar del FloatingBody3D del barco.")
		set_physics_process(false)
		return
	if balance == null or motor == null:
		push_error("Gobierno sin balance: no hay con que gobernar.")
		set_physics_process(false)
		return
	# Interim de docs/TIMON.md §0: se zarpa con el tanque lleno hasta que exista
	# la lonja donde comprarla.
	litros = motor.tanque_l


func _es_cliente() -> bool:
	return Net != null and Net.rol == Net.Rol.CLIENTE


func _physics_process(delta: float) -> void:
	if _barco == null or _es_cliente():
		return
	_avanzar_mando(delta)
	_avanzar_motor(delta)
	_aplicar_fuerzas()


# =============================================================================
#  El mando y la maquina
# =============================================================================

func _avanzar_mando(delta: float) -> void:
	rueda = TimonModel.avanzar_rueda(rueda, mando, delta, balance.vuelta_completa_s)
	pala = TimonModel.avanzar_pala(pala, rueda, delta, balance.pala_rate_deg,
			balance.pala_max_deg)


func _avanzar_motor(delta: float) -> void:
	# La rampa corre SIEMPRE, tambien al parar: la helice no se frena de golpe.
	empuje = MotorModel.avanzar_empuje(empuje,
			MotorModel.empuje_objetivo(muesca, arrancado), delta, motor.rampa_s)
	if not arrancado:
		return
	var consumo := MotorModel.consumo_l_s(muesca, true, motor.consumos_l_min)
	litros = maxf(litros - MotorModel.paso_nafta(litros, consumo, delta), 0.0)
	if litros <= 0.0:
		arrancado = false
		motor_parado.emit("sin nafta")


## El empuje que de verdad llega a la helice: el de la rampa, menos los cortes de
## la tos cuando el tanque agoniza. Con el tanque en seco es cero.
func _empuje_util() -> float:
	var t: float = Ocean.sim_time if Ocean != null else 0.0
	return empuje * MotorModel.factor_tos(litros, motor.umbral_tos_l, t)


# =============================================================================
#  Las tres superficies
# =============================================================================

## Aplica una superficie sustentadora en `pos_local`. `delta_rad` es el angulo de
## la pala (0 para el plano de deriva) y `estela` el flujo que le inyecta la
## helice (0 para todo lo que no sea la pala).
##
## Fuera del agua no hace nada: un apendice al aire no sustenta. En la helice eso
## es la ventilacion —en mar gruesa la popa sale y el motor se embala en vacio— y
## aqui es lo mismo para la pala, que es cuando el timon deja de responder.
func _aplicar_superficie(pos_local: Vector3, area: float, delta_rad: float,
		estela: float) -> void:
	var punto := _barco.to_global(pos_local)
	var orbital := Vector3.ZERO
	if Ocean != null:
		# Altura y velocidad del agua en UNA sola resolucion del punto fijo.
		# `Ocean.sample()` existe exactamente para esto: pedirlas por separado
		# duplica el coste de lo mas caro del sistema, y aqui hacen falta las dos
		# (la altura para saber si el apendice esta sumergido, la velocidad para
		# la resta que ES el broaching).
		var agua: Dictionary = Ocean.sample(punto)
		if float(agua[&"height"]) - punto.y <= 0.0:
			return
		orbital = agua[&"velocity"] as Vector3
	var base := _barco.global_basis
	# Ortonormal en un cuerpo rigido, asi que la transpuesta ES la inversa (y es
	# mas barata y mas estable que invertir).
	var flujo_local := base.transposed() * TimonModel.velocidad_relativa(
			_barco.linear_velocity, _barco.angular_velocity, punto,
			_barco.global_position, orbital, balance.factor_orbital)
	# Avante es -Z, asi que mas empuje es flujo local mas negativo en z. Se suma
	# al flujo sobre la pala SIN sumarse a la velocidad del barco: eso es lo que
	# permite girar casi parado de un golpe de maquina.
	flujo_local.z -= estela
	var alfa := TimonModel.angulo_ataque(delta_rad, flujo_local)
	var f := TimonModel.fuerza_superficie(base * flujo_local, alfa, area, base.y)
	_barco.apply_force(f, punto - _barco.global_position)


## ⚠️ El ORDEN de estas tres llamadas es fijo a proposito. Jolt es determinista
## en el mismo binario solo si las llamadas que modifican la simulacion ocurren
## en el mismo orden; si algun dia esto se vuelve un bucle, que sea sobre un
## array fijo y nunca sobre algo cuyo orden pueda cambiar.
func _aplicar_fuerzas() -> void:
	var util := _empuje_util()

	# 1. El plano de deriva: la MISMA matematica de la pala con el angulo a cero,
	#    area grande y a popa del centro de masas. Da de una vez la resistencia
	#    lateral (se acabo patinar), el par que alinea el casco con el flujo (la
	#    estabilidad direccional) y el auto-limite de la virada.
	_aplicar_superficie(balance.pos_plano_deriva, balance.area_plano_deriva, 0.0, 0.0)

	# 2. La helice: empuje axial puro, solo si esta sumergida.
	var p_helice := _barco.to_global(motor.pos_helice)
	if Ocean == null or Ocean.get_submersion(p_helice) > 0.0:
		_barco.apply_force(-_barco.global_basis.z * (util * motor.empuje_max),
				p_helice - _barco.global_position)

	# 3. La pala: el mismo modelo, orientable y con la estela encima.
	_aplicar_superficie(balance.pos_pala, balance.area_pala,
			TimonModel.pala_rad_desde_mando(pala, balance.pala_max_deg),
			MotorModel.estela(motor.estela_ms, util))


# =============================================================================
#  Lo que el puesto llamara (F3)
# =============================================================================

## Da al contacto. Devuelve un [enum MotorModel.MotivoArranque]; OK es el unico
## que arranca, y los demas se le dicen al jugador por su nombre (regla 8).
func arrancar() -> int:
	var motivo := MotorModel.arbitrar_arranque(llave_puesta, litros, arrancado)
	if motivo == MotorModel.MotivoArranque.OK:
		arrancado = true
		motor_arrancado.emit()
	return motivo


func parar(causa: String = "lo pararon") -> void:
	if not arrancado:
		return
	arrancado = false
	motor_parado.emit(causa)


## Vuelca un bidon en la boca de llenado durante `delta`. Devuelve los litros que
## han pasado de verdad, que es lo que hay que restarle al bidon: asi la nafta
## total a bordo se conserva por construccion y no se puede fabricar.
func repostar(litros_bidon: float, delta: float) -> float:
	var pasa := MotorModel.paso_repostaje(litros, motor.tanque_l, litros_bidon,
			motor.ritmo_repostaje_l_s, delta)
	litros += pasa
	return pasa


## La aguja del puesto, 0..1.
func fraccion_tanque() -> float:
	return MotorModel.fraccion_tanque(litros, motor.tanque_l)
