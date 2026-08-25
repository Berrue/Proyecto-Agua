class_name PuestoTimonModel
extends RefCounted

## Las decisiones del PUESTO DE TIMON: quien puede agarrar la rueda, que hacen el
## contacto y la llave, y cuanto aguanta el cabo de trinca.
##
## PURO —cero nodos, cero red— por el mismo motivo que [BombaModel]: lo que
## decide algo tiene que poder correrse en headless, y `Net` es un autoload
## singleton donde un RPC no se puede testear. La matematica del gobierno (la
## rueda de dos etapas, la pala) vive en [TimonModel]; aqui solo esta el PUESTO.
##
## [b]La regla que le da forma[/b] (docs/DISENO.md §2): la rueda ES el agarre del
## timonel. No puede pescar ni achicar mientras esta ahi, y por eso ocupa las dos
## manos. Lo que hace que el puesto no sea una carcel es el CABO DE TRINCA: se
## amarra la rueda y el rumbo aguanta unos segundos, los justos para cruzar la
## cubierta y volver. Ese reloj es lo que convierte "voy un momento" en una
## apuesta.

## Que se le pide al puesto.
## ⚠️ APPEND-ONLY: el verbo viaja por el cable (F8).
enum Verbo { OCUPAR = 0, LIBERAR = 1 }

## Por que se deniega. Se le dice al jugador por su nombre: la regla 8 pide
## telegrafiar el fallo, no solo no mentir.
## ⚠️ APPEND-ONLY: el motivo viaja por el cable.
enum Motivo { OK, OCUPADO, MANOS_LLENAS, NO_ES_TUYO, TARDIO }

## `ocupante` cuando no hay nadie. Los peers de Godot empiezan en 1, asi que el 0
## queda libre para "de nadie" (misma convencion que `BombaModel.NADIE`).
const NADIE := 0

## La rueda son las DOS manos: es una rueda de barco, no un boton. De aqui sale
## que el timonel no pueda pescar ni llevar el colador, sin un solo candado de
## rol.
const MANOS_TIMON := 2
const MANOS_TOTALES := 2

## Como se llama el nodo de la llave del motor.
##
## Vive aqui y no como texto suelto en `portador.gd` porque de este nombre
## depende que el barco se pueda arrancar: si alguien renombra el nodo, dar al
## contacto deja de encontrar la llave y el motor no prende NUNCA, sin un solo
## error. Es el mismo nombre que `NetPorteo.CUERPOS_ESCENA` usa para
## identificarla por el cable, y `gobierno_tests` comprueba que los tres —escena,
## tabla de red y esta constante— siguen diciendo lo mismo.
const NOMBRE_LLAVE := &"LlaveMotor"

## Vueltas completas de la rueda de tope a tope.
##
## Tres (o sea vuelta y media a cada banda) no es decoracion: es lo que hace
## CONTABLE el angulo de pala. Con la marca de rey —la cabilla distinta que queda
## arriba con el timon a la via— el timonel lee cuanto lleva metido de un vistazo
## y cuenta vueltas viendo pasar las cabillas, sin HUD. Es la respuesta al
## problema que Sailwind tiene abierto: en un simulador no se siente por las
## manos cuando el timon se centra, asi que hay que poder VERLO.
const VUELTAS_TOPE_A_TOPE := 3.0


# =============================================================================
#  El arbitro del puesto
# =============================================================================

## ¿Puede `quien` hacer `verbo`? Devuelve un [enum Motivo]; OK es el unico que
## autoriza. Lo llama el HOST y difunde el resultado, igual que la bomba.
static func arbitrar(verbo: int, ocupante: int, quien: int,
		manos_usadas: int) -> int:
	match verbo:
		Verbo.OCUPAR:
			if ocupante != NADIE:
				return Motivo.OK if ocupante == quien else Motivo.OCUPADO
			if manos_usadas + MANOS_TIMON > MANOS_TOTALES:
				return Motivo.MANOS_LLENAS
			return Motivo.OK
		Verbo.LIBERAR:
			# Idempotente: soltar lo que ya esta suelto no es un error.
			if ocupante == NADIE:
				return Motivo.OK
			return Motivo.OK if ocupante == quien else Motivo.NO_ES_TUYO
	return Motivo.NO_ES_TUYO


## Lo que se le dice al jugador cuando se le niega. En segunda persona y sin
## jerga: el HUD lo pinta tal cual.
static func texto_motivo(motivo: int) -> String:
	match motivo:
		Motivo.OCUPADO:
			return "ya lleva el timón otro"
		Motivo.MANOS_LLENAS:
			return "necesitas las dos manos"
		Motivo.NO_ES_TUYO:
			return "no es tuyo"
	return ""


# =============================================================================
#  El contacto
# =============================================================================
#
# [b]La llave no se mete ni se saca: se LLEVA.[/b] Dar al contacto es girar la
# llave, asi que arrancar exige que quien esta en la rueda la lleve encima —en el
# cinturon, que es donde vive (`docs/PORTEO.md`)—. Una vez en marcha el motor
# sigue solo, porque si hiciera falta la llave para SEGUIR andando el timonel no
# podria soltar la rueda nunca, y el puesto se volveria una carcel.
#
# Lo que esto conserva entero es lo que le importa al diseño: la llave SE HUNDE
# (`DISENO.md` §2), asi que perderla al agua deja al barco sin poder arrancar y
# convierte el rescate en una mision — que es justo el patron que se buscaba. Y
# ahorra una ceremonia de meter y sacar que habria que replicar en F8 sin darle
# nada al jugador a cambio.

## El texto del puesto: lo que se puede hacer AHORA, no una lista de teclas.
##
## Dice el estado ademas de la tecla porque el timonel tiene que poder DECIDIR:
## "falta la llave" manda a alguien a buscarla y "el tanque está seco" manda a por
## el bidon. Son dos problemas distintos con dos soluciones distintas, y decirlos
## por su nombre es lo que pide la regla 8.
static func texto_puesto(arrancado: bool, lleva_llave: bool, muesca: int,
		sin_nafta: bool) -> String:
	var linea := ""
	if arrancado:
		linea = "%s  ·  Q  parar" % MotorModel.nombre_muesca(muesca).to_upper()
	elif sin_nafta:
		linea = "el tanque está seco"
	elif lleva_llave:
		linea = "Q  dar al contacto"
	else:
		# No basta con decir que falta: hay que decir DONDE va. Con las dos manos
		# en la rueda la llave solo puede estar en el cinturon, y ese paso —coger
		# la llave, guardarla con Q y despues agarrar el timon— no lo adivina
		# nadie. Un prompt que nombra el problema y esconde la solucion es la
		# mitad de la regla 8.
		linea = "falta la llave: llévala en el cinturón"
	return linea + "  ·  A/D  timón  ·  W/S  máquina  ·  E  soltar"


# =============================================================================
#  El cabo de trinca
# =============================================================================

## Segundos que el cabo aguanta el rumbo con la rueda sin nadie.
##
## Con mar hecha aguanta la mitad (`DISENO.md` §2: 12 s, y 6 s con Hs > 6 m). No
## es una penalizacion arbitraria: cuanto peor esta el mar, mas empuja la ola
## sobre la pala y antes se corre el cabo — o sea que la ventana para ir a ayudar
## se cierra justo cuando mas falta hace ayudar. Ahi esta la tension.
static func segundos_trinca(hs: float, trinca_s: float, trinca_temporal_s: float,
		hs_temporal: float) -> float:
	if hs >= hs_temporal:
		return maxf(trinca_temporal_s, 0.0)
	return maxf(trinca_s, 0.0)


# =============================================================================
#  La rueda que se ve
# =============================================================================

## El angulo del aro, en radianes, para la posicion de rueda -1..1.
##
## Da varias vueltas (ver [constant VUELTAS_TOPE_A_TOPE]) porque una rueda que
## girara 35 grados como el volante de un coche no dejaria contar nada, y contar
## es como el timonel sabe donde esta la via.
static func angulo_rueda(rueda: float, vueltas: float = VUELTAS_TOPE_A_TOPE) -> float:
	return clampf(rueda, -1.0, 1.0) * vueltas * PI


## ¿Esta la marca de rey arriba? O sea: ¿esta el timon a la via?
##
## Con la rueda dando vueltas completas, la cabilla marcada vuelve arriba en cada
## vuelta entera, asi que "arriba" NO basta para decir "a la via" y por eso esto
## mira la posicion de la rueda y no el angulo. La marca sirve para leer el
## angulo de un vistazo; el centro exacto lo dice esta funcion, que es la que
## alimenta el feedback.
static func a_la_via(rueda: float, tolerancia: float = 0.02) -> bool:
	return absf(rueda) <= tolerancia
