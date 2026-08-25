class_name MotorModel
extends RefCounted

## El MOTOR y la NAFTA: el telegrafo, la rampa, el consumo y las dos formas de
## quedarse sin gobierno.
##
## PURO —cero nodos, cero `Ocean`, cero `Time`— por lo mismo que `BombaModel`:
## lo que decide algo tiene que poder correrse en headless. El tiempo entra
## siempre como parametro (`dt`, `t`), y en el host ese `t` sera `Ocean.sim_time`
## para que las seis maquinas oigan toser al motor en el mismo instante.
##
## [b]La decision de diseño que lo ordena todo[/b] (docs/TIMON.md §0): la nafta
## se gasta de verdad, pero el tanque es HOLGADO. `DISENO.md` §3 habia cerrado
## "nunca medidores dentro de la run" citando que DREDGE corto el combustible
## por tedioso — y el tedio que DREDGE corto era la vigilancia CONSTANTE. Con un
## tanque que sobra para una salida normal, la nafta deja de ser una tarea y
## pasa a ser una decision por salida: cuanto corres, por donde vuelves y si te
## fias de la reserva. La factura de disel por distancia de DISENO §3 no se
## pierde: se convierte en factura por LITROS repostados, el mismo sink.
##
## Y quedarse seco PUEDE pasar, telegrafiado dos veces antes de castigar (regla
## 8): primero la aguja bajando, despues el motor tosiendo. Sin helice no hay
## estela, asi que se pierde el golpe de maquina y el broaching se queda sin
## respuesta — que es exactamente el peligro que parece.


# =============================================================================
#  El telegrafo
# =============================================================================
#
# Seis muescas, como la palanca de un pesquero. Es una palanca VISIBLE del
# puesto: la posicion se lee desde la otra punta de la cubierta, asi que el
# telegrafo informa a la tripulacion entera y no solo al timonel.
#
# ⚠️ El indice de la muesca viaja por el cable (F8), pero a diferencia de
# `BombaModel.BOMBAS` esto NO es una tabla de identidad append-only: el ORDEN es
# el significado —la palanca sube y baja de a una muesca—, asi que meter una
# muesca nueva en medio no es ampliar una lista, es rediseñar la palanca. Se
# hace, si se hace, en las dos puntas a la vez.

enum Muesca { ATRAS_TODA = 0, ATRAS = 1, STOP = 2, POCA = 3, MEDIA = 4,
	AVANTE_TODA = 5 }

## Empuje normalizado que pide cada muesca, de -1 (atras) a +1 (avante).
## Avante toda y atras toda no son simetricas en la vida real (una helice rinde
## menos ciando), pero eso se cobra en el EMPUJE MAXIMO del balance, no aqui:
## esta tabla es la palanca, no el motor.
##
## ⚠️ `Array[float]` y no `PackedFloat32Array`: un `const` inicializado con el
## constructor de un empaquetado NO se puede resolver desde otra clase (el
## parser lo da por nulo y el arnés se cuelga sin llegar a correr). Mismo patron
## que `BombaModel.BOMBAS`.
const EMPUJE_MUESCA: Array[float] = [-1.0, -0.5, 0.0, 1.0 / 3.0, 2.0 / 3.0, 1.0]

## Como se llama cada muesca cuando hay que decirla (HUD del puesto, voz, audio).
const NOMBRE_MUESCA: Array[String] = ["atrás toda", "atrás", "stop", "poca",
	"media", "avante toda"]

## Periodo del ciclo de la tos, en segundos. Un motor que se queda sin
## alimentacion no se apaga: pierde tiempos, arranca, vuelve a perderlos.
const PERIODO_TOS := 1.7

## Fraccion maxima del ciclo que el motor pasa cortado con el tanque en las
## ultimas gotas. No llega a 1 a proposito: mientras quede nafta, el motor
## SIEMPRE devuelve algo de empuje entre corte y corte — un motor que se queda
## mudo del todo antes de morir seria un lockout, y un lockout es el "me robo"
## que la regla 8 prohibe.
const DUTY_TOS_MAX := 0.55


## Sube o baja la palanca `direccion` muescas. Topa en los extremos en vez de
## dar la vuelta: una palanca que saltara de "avante toda" a "atras toda" por
## pasarse un clic seria una forma de romper la transmision sin querer.
static func mover_muesca(muesca: int, direccion: int) -> int:
	return clampi(muesca + direccion, 0, EMPUJE_MUESCA.size() - 1)


## Lo que pide la palanca, o cero si el motor no esta en marcha.
##
## La palanca se puede mover con el motor parado —y hace su ruido, y se ve desde
## cubierta—, simplemente no pasa nada. Que el gesto exista aunque no funcione es
## lo que hace legible que falte la llave o la nafta.
static func empuje_objetivo(muesca: int, arrancado: bool) -> float:
	if not arrancado:
		return 0.0
	if muesca < 0 or muesca >= EMPUJE_MUESCA.size():
		return 0.0
	return EMPUJE_MUESCA[muesca]


## El nombre de la muesca, para decirlo sin jerga.
static func nombre_muesca(muesca: int) -> String:
	if muesca < 0 or muesca >= NOMBRE_MUESCA.size():
		return ""
	return NOMBRE_MUESCA[muesca]


## El empuje real persiguiendo al que pide la palanca.
##
## `rampa_s` son los segundos de STOP a AVANTE TODA. Es lo que impide que el
## barco arranque como un coche y lo que convierte "avante toda" en una decision
## con antelacion en vez de un boton. Es tambien la via correcta de vender masa
## longitudinal sin implementar masa añadida traslacional — que se investigo y
## se dejo fuera a proposito (docs/TIMON.md §10).
##
## `move_toward` y no `lerp`, por lo mismo que el mando del timon: lerp depende
## del tick rate y dos maquinas dejarian de coincidir.
static func avanzar_empuje(empuje: float, objetivo: float, dt: float,
		rampa_s: float) -> float:
	var destino := clampf(objetivo, -1.0, 1.0)
	if rampa_s <= 0.0:
		return destino
	return move_toward(empuje, destino, (1.0 / rampa_s) * maxf(dt, 0.0))


## La velocidad que la helice INYECTA sobre la pala.
##
## El detalle que vale mas que el empuje: la helice mete flujo en el timon
## aunque el barco este parado. Sumarlo al flujo local SIN sumarlo a la
## velocidad del barco es lo que da el GOLPE DE MAQUINA —timon a la banda mas
## una rafaga de motor y el pesquero gira casi sin arrancada—, que ademas es la
## respuesta correcta al broaching y la razon de que el motor exista.
##
## Avante es -Z, asi que mas empuje es flujo local mas negativo en z: el que lo
## aplique hace `flujo_local.z -= estela(...)`.
static func estela(estela_ms: float, empuje: float) -> float:
	return estela_ms * empuje


# =============================================================================
#  El arranque: la llave
# =============================================================================
#
# La LLAVE DEL MOTOR ya existia como objeto porteable que SE HUNDE
# (`game/props/llave_motor.tscn`, y `DISENO.md` §2: si cae al agua, mision de
# rescate emergente). Aqui se le da el trabajo que le faltaba: sin llave puesta
# no hay motor. Sacarla y llevarsela es apagar el barco.

## Por que no arranca. Se le dice al jugador por su nombre: la regla 8 pide
## telegrafiar el fallo, no solo no mentir.
## ⚠️ APPEND-ONLY: el motivo viaja por el cable, asi que insertar en medio le
## cambia el numero a todo lo que venga detras.
enum MotivoArranque { OK, SIN_LLAVE, SIN_NAFTA, YA_ARRANCADO }


## ¿Se puede dar al contacto? Devuelve un `MotivoArranque`; OK es el unico que
## autoriza. Lo llama el HOST y difunde el resultado, igual que la bomba.
static func arbitrar_arranque(llave_puesta: bool, litros: float,
		arrancado: bool) -> int:
	if arrancado:
		return MotivoArranque.YA_ARRANCADO
	if not llave_puesta:
		return MotivoArranque.SIN_LLAVE
	# Con el tanque en seco el motor gira y no prende. Distinguirlo de la llave
	# importa: son dos problemas con dos soluciones distintas, y el jugador tiene
	# que saber a por cual correr.
	if litros <= 0.0:
		return MotivoArranque.SIN_NAFTA
	return MotivoArranque.OK


## Lo que se le dice al jugador. En segunda persona y sin jerga: el HUD lo pinta
## tal cual.
static func texto_motivo(motivo: int) -> String:
	match motivo:
		MotivoArranque.SIN_LLAVE:
			return "falta la llave"
		MotivoArranque.SIN_NAFTA:
			return "el tanque está seco"
	return ""


# =============================================================================
#  La nafta
# =============================================================================

## Litros por segundo que bebe la muesca. Cero con el motor parado: apagar el
## motor mientras se cala o se pesca es una decision que AHORRA algo.
##
## `consumos_l_min` viene del balance y va indexado por muesca, para que "avante
## toda bebe el doble que media" se pueda editar sin tocar codigo. Si la tabla no
## cuadra con las muescas se devuelve 0 en vez de reventar — y `gobierno_tests`
## comprueba el tamaño, porque una tabla corta seria un motor que deja de beber
## en las muescas altas SIN UN SOLO ERROR.
static func consumo_l_s(muesca: int, arrancado: bool,
		consumos_l_min: PackedFloat32Array) -> float:
	if not arrancado:
		return 0.0
	if muesca < 0 or muesca >= consumos_l_min.size():
		return 0.0
	return maxf(consumos_l_min[muesca], 0.0) / 60.0


## Lo que se bebe este tick: nunca mas de lo que queda en el tanque. Devuelve los
## litros REALMENTE gastados, que es lo que hay que restar — asi el tanque no
## puede cruzar el cero y quedarse en negativo.
static func paso_nafta(litros: float, consumo: float, dt: float) -> float:
	if litros <= 0.0 or consumo <= 0.0 or dt <= 0.0:
		return 0.0
	return minf(consumo * dt, litros)


## El factor que multiplica al empuje cuando el tanque agoniza: 1 normal, 0
## durante los cortes.
##
## Es la SEGUNDA telegrafia (la primera es la aguja). El corte se alarga segun se
## acaba —de un carraspeo a un motor que casi no vuelve—, asi que el jugador
## tiene minutos, no segundos, para decidir si vira a puerto o manda a alguien a
## por el bidon.
##
## Funcion PURA de `t` (nada de `Time`, nada de RNG): las seis maquinas tienen
## que oir el mismo corte en el mismo instante o el motor sonaria roto en una y
## sano en otra.
static func factor_tos(litros: float, umbral_l: float, t: float) -> float:
	if litros <= 0.0:
		return 0.0
	if umbral_l <= 0.0 or litros >= umbral_l:
		return 1.0
	# 0 justo en el umbral, 1 en la ultima gota.
	var fondo := 1.0 - clampf(litros / umbral_l, 0.0, 1.0)
	var fase := wrapf(t, 0.0, PERIODO_TOS) / PERIODO_TOS
	return 0.0 if fase < fondo * DUTY_TOS_MAX else 1.0


## Cuanta nafta pasa del bidon al tanque este tick. Devuelve los litros
## TRANSFERIDOS: el que llame se los suma al tanque y se los resta al bidon, y
## asi el total a bordo se conserva por construccion.
##
## A ritmo visible y no de golpe, porque volcar un bidon en la boca de llenado
## con el barco escorando en temporal es porteo, y el porteo ya es contenido.
static func paso_repostaje(tanque_l: float, capacidad_l: float, bidon_l: float,
		ritmo_l_s: float, dt: float) -> float:
	var hueco := maxf(capacidad_l - tanque_l, 0.0)
	if hueco <= 0.0 or bidon_l <= 0.0 or ritmo_l_s <= 0.0 or dt <= 0.0:
		return 0.0
	return minf(ritmo_l_s * dt, minf(hueco, bidon_l))


## La aguja, de 0 a 1. Existe aqui —y no en el nodo del indicador— para que la
## aguja y la tos lean el MISMO numero: un indicador que se calcule su propia
## fraccion es un indicador que un dia mentira (regla 8).
static func fraccion_tanque(litros: float, capacidad_l: float) -> float:
	if capacidad_l <= 0.0:
		return 0.0
	return clampf(litros / capacidad_l, 0.0, 1.0)
