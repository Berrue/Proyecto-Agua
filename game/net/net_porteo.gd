class_name NetPorteo
extends RefCounted

## El arbitro del porteo en red y las tablas que le dan identidad a las cosas
## (docs/RED.md, fase R1). PURO: cero nodos, cero ENet, cero Ocean — el mismo
## contrato que declara `NetMath` en su cabecera.
##
## Y esa pureza no es elegancia, es la UNICA forma de probar esto: `Net` es un
## autoload SINGLETON, asi que `/root/Net` existe una sola vez por proceso y no
## hay manera de que dos instancias se manden RPCs entre si en un test headless
## (por eso `_test_loopback_enet` usa `ENetMultiplayerPeer` crudo con
## `put_packet`, no RPCs). Conclusion que ordena todo este archivo: TODO lo que
## haya que decidir vive aca como funcion estatica, y el cuerpo del RPC en
## `network_manager.gd` es un envoltorio de dos lineas. Si alguna regla de
## arbitraje se cuela dentro del RPC, deja de existir forma de testearla.
##
## La carrera de dos jugadores agarrando lo mismo se resuelve por ORDEN TOTAL:
## el host es el unico que ve todas las peticiones en un orden, y gana la
## primera que entra. Sin marcas de tiempo, sin rollback (decision cerrada del
## plan) y sin optimismo: el que pierde recibe un `_porteo_denegado` y su HUD
## lo dice, porque la regla 8 pide telegrafiar el fallo, no solo no mentir.


## Los cuerpos AUTORADOS en escena, por ruta desde la raiz. Son identicos en
## `toybox.tscn` y `tsunami.tscn`, asi que su identidad de red sale gratis: no
## hace falta negociar nada al conectar, las dos maquinas leen la misma lista.
##
## El indice en ESTE array ES el id de red del cuerpo, asi que la lista es
## APPEND-ONLY: insertar en medio le cambia el id a todo lo que venga detras y
## dos versiones del juego dejarian de entenderse en silencio.
##
## Es NodePath y no StringName a proposito: hoy los cinco son hijos directos
## de la raiz, pero el dia que un prop cuelgue de un contenedor (los barriles
## vivian bajo `Cargo` hasta que se quitaron de las dos escenas), la lista lo
## admite sin cambiar de tipo ni de mecanismo.
##
## `tests/net_tests` comprueba que las rutas resuelven EN LAS DOS ESCENAS: es
## el unico seguro contra que alguien renombre un prop y este deje de
## replicarse el solo, en silencio, mientras todo lo demas sigue funcionando.
const CUERPOS_ESCENA: Array[NodePath] = [
	^"Farol",              # 0
	^"Radio",              # 1
	^"LlaveMotor",         # 2
	^"CajaHerramientas",   # 3
	^"Bichero",            # 4
]

## Los cuerpos que NACEN en partida (los peces) empiezan a numerar aca. El
## hueco entre medias deja sitio a props autorados futuros sin recolocar ni un
## id de los que ya se emitieron.
const ID_DINAMICO_BASE := 256

## Los sockets donde un portable puede quedar enganchado, POR INDICE y nunca
## por nombre: los DOS `SoporteCania` del barco se llaman IGUAL (uno bajo
## `GearPort` y otro bajo `GearStarboard`), asi que un id basado en el nombre
## los confundiria en silencio y la caña clavada en babor apareceria en
## estribor en las otras cinco pantallas.
##
## Los indices < SOCKET_DEL_BARCO cuelgan del Player de su dueño; los >= ,
## del FishingBoat. Esa frontera es lo que hace que `_aplicar_porteo` sepa
## contra QUE nodo resolver la ruta sin mandar un flag aparte.
const SOCKETS: Array[NodePath] = [
	^"Camera3D/Portador/Agarre",                  # 0 — una mano
	^"Camera3D/Portador/AgarreDosManos",          # 1 — dos manos
	^"Cinto1",                                    # 2
	^"Cinto2",                                    # 3
	^"Ganchos/GanchoCabinaBabor",                 # 4
	^"Ganchos/GanchoCabinaEstribor",              # 5
	^"UpgradeSockets/GearPort/SoporteCania",      # 6
	^"UpgradeSockets/GearStarboard/SoporteCania", # 7
]
const SOCKET_DEL_BARCO := 4
const SOCKET_NINGUNO := -1

## El verbo que viaja por el cable ES `Portable3D.Estado`: los mismos valores,
## a proposito, para que el receptor no tenga que traducir (traducir dos enums
## paralelos es como se desincronizan las cosas seis meses despues).
enum Verbo { SUELTO = 0, EN_MANO = 1, COLGADO = 2, EN_CINTURON = 3 }

enum Motivo { OK, YA_ES_DE_OTRO, SOCKET_OCUPADO, CINTURON_LLENO, NO_ES_TUYO,
	VERBO_IMPOSIBLE, YA_LO_LLEVAS, MANOS_LLENAS }

## Cuantas manos tiene un jugador. Vive aca y no en `Portador` porque el
## arbitro corre en el HOST, que no tiene el Portador del que pide.
const MANOS := 2

## `dueno_actual` cuando no lo lleva nadie. Los peers de Godot empiezan en 1
## (el host), asi que el 0 esta libre para significar "de nadie".
const NADIE := 0


# =============================================================================
#  El arbitro
# =============================================================================

## ¿Puede `quien` hacer `verbo` sobre este cuerpo? Devuelve un `Motivo`; OK es
## el unico que autoriza. El host llama a esto y difunde el resultado.
##
## Las reglas que implementa NO existen hoy en ningun sitio: `Portable3D`
## solo rechaza tomar lo que ya esta EN_MANO, y `soltar()` no tiene NINGUNA
## guarda — o sea que por el camino de un RPC directo cualquiera podria soltar
## el objeto de cualquiera.
static func arbitrar(estado_actual: int, dueno_actual: int, quien: int,
		verbo: int, id_socket: int, socket_ocupado: bool,
		huecos_cinturon_libres: int, colgable: bool, cabe_en_cinturon: bool,
		manos_usadas: int = 0, manos_del_cuerpo: int = 1) -> int:
	match verbo:
		Verbo.EN_MANO:
			# Descolgar de un gancho, sacar del cinturon y recoger del suelo son
			# el MISMO gesto: lo unico que lo impide es que ya este en una mano.
			if estado_actual == Verbo.EN_MANO:
				# Que YA LO LLEVES no es lo mismo que perder una carrera. Con
				# el agarre pesimista, pulsar E dos veces sobre lo mismo es
				# normalisimo —el objeto tarda un viaje en aparecer— y decirte
				# "se te adelanto otro" cuando el que gano fuiste vos es
				# feedback que miente (regla 8).
				return Motivo.YA_LO_LLEVAS if dueno_actual == quien else Motivo.YA_ES_DE_OTRO
			if not _socket_valido(id_socket) or not socket_es_del_jugador(id_socket):
				return Motivo.VERBO_IMPOSIBLE
			# Y las manos son DOS. Sin esta cuenta, dos toques de E dentro de la
			# misma ventana de ida y vuelta sueldan dos objetos al mismo marker:
			# el segundo tapa al primero, y el primero queda inalcanzable —
			# imposible de soltar, de colgar y de apuntar— para el resto de la
			# sesion, en las seis pantallas a la vez.
			if manos_usadas + manos_del_cuerpo > MANOS:
				return Motivo.MANOS_LLENAS
			return Motivo.OK

		Verbo.SUELTO:
			# Soltar y lanzar. Solo lo suelta quien lo lleva.
			if dueno_actual != quien:
				return Motivo.NO_ES_TUYO
			return Motivo.OK

		Verbo.COLGADO:
			if not colgable:
				return Motivo.VERBO_IMPOSIBLE
			if dueno_actual != quien:
				return Motivo.NO_ES_TUYO
			if not _socket_valido(id_socket) or socket_es_del_jugador(id_socket):
				return Motivo.VERBO_IMPOSIBLE
			if socket_ocupado:
				return Motivo.SOCKET_OCUPADO
			return Motivo.OK

		Verbo.EN_CINTURON:
			if not cabe_en_cinturon:
				return Motivo.VERBO_IMPOSIBLE
			if dueno_actual != quien:
				return Motivo.NO_ES_TUYO
			if not _socket_valido(id_socket) or not socket_es_del_jugador(id_socket):
				return Motivo.VERBO_IMPOSIBLE
			if huecos_cinturon_libres <= 0:
				return Motivo.CINTURON_LLENO
			return Motivo.OK

	return Motivo.VERBO_IMPOSIBLE


static func _socket_valido(id_socket: int) -> bool:
	return id_socket >= 0 and id_socket < SOCKETS.size()


## ¿Ese socket cuelga del Player (true) o del FishingBoat (false)?
static func socket_es_del_jugador(id_socket: int) -> bool:
	return id_socket >= 0 and id_socket < SOCKET_DEL_BARCO


## El socket de mano que le toca a un cuerpo segun cuantas manos ocupe. Es la
## misma decision que toma `Portador._intentar_coger` al elegir marker, pero
## expresada como dato para que viaje por el cable.
static func socket_de_mano(manos: int) -> int:
	return 0 if manos <= 1 else 1


## El hueco de cinturon como indice de socket, y su inverso.
static func socket_de_cinturon(hueco: int) -> int:
	return 2 + clampi(hueco, 0, 1)


static func cinturon_de_socket(id_socket: int) -> int:
	return id_socket - 2


## Texto honesto para el PorteoHud. La regla 8 pide que el fallo se DIGA: un
## boton que no hizo nada es exactamente el "me robo" que el juego promete no
## hacer, aunque tecnicamente no haya mentido nadie.
static func texto_motivo(motivo: int, nombre_de_quien_gano: String) -> String:
	match motivo:
		Motivo.YA_ES_DE_OTRO:
			if nombre_de_quien_gano.is_empty():
				return "se te adelantaron"
			return "se te adelantó %s" % nombre_de_quien_gano
		Motivo.YA_LO_LLEVAS:
			return "" # ya lo tenés: no hay nada que avisar
		Motivo.MANOS_LLENAS:
			return "no te quedan manos"
		Motivo.SOCKET_OCUPADO:
			return "ese sitio ya está ocupado"
		Motivo.CINTURON_LLENO:
			return "el cinturón está lleno"
		Motivo.NO_ES_TUYO:
			return "eso no lo llevás vos"
		Motivo.VERBO_IMPOSIBLE:
			return "ahí no va"
	return ""
