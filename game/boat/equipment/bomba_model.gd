class_name BombaModel
extends RefCounted

## Las decisiones de la bomba de achique: quien puede usarla y cuanta agua saca.
## PURO: cero nodos, cero red, cero Ocean — el mismo contrato que `NetPorteo` y
## `AguaEmbarcadaModel`, y por el mismo motivo: `Net` es un autoload singleton,
## asi que un RPC no se puede testear y lo que decida algo tiene que vivir fuera.
##
## [b]La regla que da forma a todo esto[/b] (docs/DISENO.md): una persona sola
## achica al 50 %, dos coordinadas al 100 %, y JAMAS por un candado de rol. Aqui
## eso no es un `if numero_de_jugadores == 2`: sale de donde este el cabezal de
## la manguera. Si alguien lo sostiene y lo dirige a la celda anegada, la bomba
## aspira agua de verdad; si esta tirado en cubierta, el colador se tumba con el
## cabeceo y media embolada chupa aire. El solitario puede hacerlo todo —soltar
## el cabezal dentro de la celda inundada, volver a la palanca y bombear al
## 50 %—, solo que lento y feo, que es exactamente lo que el diseño pide.

## Que se le pide a la bomba. APPEND-ONLY: viaja por el cable.
enum Verbo { OCUPAR = 0, LIBERAR = 1, ACCION_ON = 2, ACCION_OFF = 3,
	TOMAR_MANGUERA = 4, SOLTAR_MANGUERA = 5,
	## El selector de modo, que vive EN LA BOMBA: lo mueve quien esta en la
	## palanca, no quien lleva la manguera.
	MODO_SUCCION = 6, MODO_EXTRACCION = 7 }

## Por que se deniega. El motivo se le dice al jugador: la regla 8 pide
## telegrafiar el fallo, no solo no mentir.
## ⚠️ APPEND-ONLY: el motivo viaja por el cable en `_bomba_denegada`, asi que
## insertar en medio le cambia el numero a todo lo que venga detras.
enum Motivo { OK, OCUPADA, MANOS_LLENAS, NO_ES_TUYO, MANGUERA_TOMADA,
	VERBO_IMPOSIBLE, TARDIO }

## `ocupante` cuando no la usa nadie. Los peers de Godot empiezan en 1, asi que
## el 0 esta libre para "de nadie" (misma convencion que `NetPorteo.NADIE`).
const NADIE := 0

## Las estaciones de bombeo del barco, colgando del casco.
##
## ⚠️ El indice en ESTE array ES el id que viaja por el cable, asi que la lista
## es APPEND-ONLY: insertar en medio le cambia el id a todo lo que venga detras y
## dos versiones del juego dejarian de entenderse EN SILENCIO — el que pidiera
## ocupar la de babor ocuparia la de estribor. Es la misma regla, y por el mismo
## motivo, que `NetPorteo.CUERPOS_ESCENA`.
##
## La de estribor (`PumpStarboard`) entra AL FINAL el dia que se compre la
## mejora de la segunda bomba.
const BOMBAS: Array[NodePath] = [
	^"UpgradeSockets/PumpPort/BombaManual",
]

const BOMBA_NINGUNA := -1

## Manos que ocupa cada cosa. Bombear son las dos —es una palanca de barco, no un
## boton—; llevar el cabezal es UNA, para que quien dirige la manguera conserve
## el movimiento y pueda seguir hablando con las manos, digamos.
const MANOS_BOMBEAR := 2
const MANOS_MANGUERA := 1
const MANOS_TOTALES := 2


# =============================================================================
#  El arbitro
# =============================================================================

## ¿Puede `quien` hacer `verbo`? Devuelve un `Motivo`; OK es el unico que
## autoriza. Lo llama el HOST y difunde el resultado.
##
## La carrera de dos jugadores pulsando E a la vez se resuelve por ORDEN TOTAL,
## igual que el porteo: el host ve las peticiones en un orden y gana la primera.
static func arbitrar(verbo: int, ocupante: int, portador_manguera: int,
		quien: int, manos_usadas: int) -> int:
	match verbo:
		Verbo.OCUPAR:
			if ocupante != NADIE:
				return Motivo.OK if ocupante == quien else Motivo.OCUPADA
			if manos_usadas + MANOS_BOMBEAR > MANOS_TOTALES:
				return Motivo.MANOS_LLENAS
			return Motivo.OK
		Verbo.LIBERAR:
			if ocupante == NADIE:
				return Motivo.OK # idempotente: soltar lo que ya esta suelto no es un error
			return Motivo.OK if ocupante == quien else Motivo.NO_ES_TUYO
		Verbo.ACCION_ON, Verbo.ACCION_OFF:
			# Accionar es del que la ocupa. Sin esta guarda, un cliente podria
			# bombear la bomba de otro por la via del RPC directo.
			if ocupante == quien:
				return Motivo.OK
			# Pero si la estacion esta LIBRE no hay nadie a quien usurpar: es un
			# flanco de palanca que salio antes de que llegara tu propio LIBERAR
			# y cruzo con el por el camino. Decirle "no es tuyo" a alguien que
			# acaba de soltarla es feedback que miente (regla 8), asi que se
			# distingue y se calla.
			return Motivo.TARDIO if ocupante == NADIE else Motivo.NO_ES_TUYO
		Verbo.TOMAR_MANGUERA:
			if portador_manguera != NADIE:
				return Motivo.OK if portador_manguera == quien else Motivo.MANGUERA_TOMADA
			if manos_usadas + MANOS_MANGUERA > MANOS_TOTALES:
				return Motivo.MANOS_LLENAS
			return Motivo.OK
		Verbo.SOLTAR_MANGUERA:
			if portador_manguera == NADIE:
				return Motivo.OK
			return Motivo.OK if portador_manguera == quien else Motivo.NO_ES_TUYO
		Verbo.MODO_SUCCION, Verbo.MODO_EXTRACCION:
			# El selector es de quien esta en la palanca. Si la estacion quedo
			# libre es un mensaje que llego tarde, no un robo.
			if ocupante == quien:
				return Motivo.OK
			return Motivo.TARDIO if ocupante == NADIE else Motivo.NO_ES_TUYO
	return Motivo.VERBO_IMPOSIBLE


## Lo que se le dice al jugador cuando se le niega. En segunda persona y sin
## jerga: el HUD lo pinta tal cual.
static func texto_motivo(motivo: int) -> String:
	match motivo:
		Motivo.OCUPADA:
			return "ya está bombeando otro"
		Motivo.MANOS_LLENAS:
			return "necesitas las manos libres"
		Motivo.NO_ES_TUYO:
			return "no es tuyo"
		Motivo.MANGUERA_TOMADA:
			return "otro lleva el colador"
	return ""


# =============================================================================
#  El ciclo de dos tiempos: chupar y escupir
# =============================================================================
#
# Una bomba no es un grifo. Tiene una CAMARA: mantener el clic la llena desde la
# celda donde este el cabezal, y soltarlo la vacia por la manguera de descarga,
# fuera del barco. Son dos gestos, no uno sostenido, y de ahi salen tres cosas
# que el caudal continuo no daba:
#
#  1. Mantener el clic para siempre deja de ser lo optimo: con la camara llena ya
#     no entra nada mas. El ritmo no hay que imponerlo con una regla, ES la forma
#     de la mecanica.
#  2. El agua de la camara SIGUE contando como agua a bordo hasta que se escupe
#     (lo suma `AguaEmbarcada.nivel`). Sin eso, chupar y no escupir nunca seria
#     una forma gratis de bajar el nivel y burlar el umbral de naufragio.
#  3. Como el agua sale de la celda al chupar pero del barco al escupir, cada
#     tiempo tiene su propio feedback: CHUPAR CORRIGE LA ESCORA, ESCUPIR BAJA EL
#     NIVEL. Elegir que celda achicar importa por dos motivos, no por uno.
#
# Todo se mide en unidades de nivel MEDIO del barco, igual que el balance del
# agua; `caudal_por_celda` y `agua_de_celda` son los dos conversores a la celda.

## Cuanto mueve cada tiempo respecto al caudal medio del balance. Dos, porque en
## un ciclo bien hecho la mitad del tiempo se chupa y la otra mitad se escupe:
## para que la MEDIA sea la del balance, cada tiempo tiene que ir al doble.
const FACTOR_TIEMPO := 2.0


## Lo que un ciclo perfecto mueve por segundo: la media armonica de los dos
## tiempos (el ciclo tarda `C/succion + C/descarga` y mueve `C`).
##
## [b]La capacidad se cancela[/b], y eso es lo que separa los ejes de mejora:
## una camara mas grande NO achica mas, achica con menos emboladas — comodidad.
## Quien sube el caudal es la succion y la descarga. Vale para los tiers.
static func caudal_sostenido(succion: float, descarga: float) -> float:
	if succion <= 0.0 or descarga <= 0.0:
		return 0.0
	return 1.0 / (1.0 / succion + 1.0 / descarga)


## El factor que hay que aplicarle a la ASPIRACION para que el ciclo ENTERO rinda
## `fraccion` del caudal pleno. Es lo que convierte el 50 % de DISENO.md en un
## numero que se pueda aplicar.
##
## No es `fraccion` a secas, y ese es exactamente el error que el ciclo de dos
## tiempos invita a cometer: el cabezal suelto solo estropea el tiempo de CHUPAR
## —escupir dura lo mismo lo sostenga alguien o no—, asi que meter 0,5 en la
## aspiracion dejaba el ciclo al 67 %, no al 50 %. Medio ciclo no se enteraba del
## castigo. Aqui se despeja al reves: se parte del rendimiento que el diseño
## pide y sale el factor del unico tiempo al que se le puede cobrar.
static func factor_aspiracion_solo(fraccion: float, succion: float,
		descarga: float) -> float:
	var f: float = clampf(fraccion, 0.001, 1.0)
	if succion <= 0.0 or descarga <= 0.0:
		return f
	var r: float = succion / descarga
	var divisor: float = (1.0 + r) / f - r
	if divisor <= 0.0:
		return 1.0
	return clampf(1.0 / divisor, 0.0, 1.0)


## Cuanta agua entra en la camara este tick. Devuelve lo REALMENTE aspirado, que
## es lo que hay que restarle a la celda: nunca mas de lo que cabe ni de lo que
## hay.
##
## `factor_solo` es el factor YA despejado por [method factor_aspiracion_solo],
## no el 50 % de diseño: aqui se aplica tal cual.
static func paso_aspiracion(carga: float, capacidad: float, succion: float,
		agua_disponible: float, cabezal_dirigido: bool, factor_solo: float,
		dt: float) -> float:
	var hueco: float = maxf(capacidad - carga, 0.0)
	# Camara llena: seguir apretando ya no mete nada. Es el tope contra el que la
	# pesa traqueteara cuando entre el feel, y hoy ya es el limite real.
	if hueco <= 0.0 or dt <= 0.0:
		return 0.0
	# Celda seca: la bomba chupa aire. No es un caso raro, es LA forma de fallar
	# de esta mecanica — pusiste el cabezal donde no habia agua.
	if agua_disponible <= 0.0:
		return 0.0
	var factor: float = 1.0 if cabezal_dirigido else clampf(factor_solo, 0.0, 1.0)
	return minf(succion * factor * dt, minf(hueco, agua_disponible))


## Cuanta agua sale de la camara al mar este tick. Esta es la unica puerta por la
## que el agua abandona el barco.
##
## Escupir NO exige estar en la estacion: la camara se vacia sola en cuanto
## sueltas la palanca, aunque te hayas ido corriendo. Una camara que se quedara
## llena para siempre seria un castigo silencioso por soltar en mal momento.
static func paso_descarga(carga: float, descarga: float, dt: float) -> float:
	if carga <= 0.0 or descarga <= 0.0 or dt <= 0.0:
		return 0.0
	return minf(descarga * dt, carga)


## El caudal expresado sobre UNA celda. `flooding_level()` es la media de las n
## celdas, asi que para bajar la media en `c` hay que sacarle `c * n` a la celda
## que se esta achicando. Sin esta conversion la bomba achicaria ocho veces mas
## despacio de lo que dice el balance.
static func caudal_por_celda(caudal_medio: float, n_celdas: int) -> float:
	if n_celdas <= 0:
		return 0.0
	return caudal_medio * float(n_celdas)


## La inversa: lo que una celda tiene dentro, expresado sobre la media del barco.
## Es lo que la aspiracion puede sacarle antes de quedarse chupando aire.
static func agua_de_celda(flooding_celda: float, n_celdas: int) -> float:
	if n_celdas <= 0:
		return 0.0
	return maxf(flooding_celda, 0.0) / float(n_celdas)
