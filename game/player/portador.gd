class_name Portador
extends Node3D

## Las manos del jugador para el porteo: mirar, coger, colgar, soltar y LANZAR
## cualquier Portable3D (docs/PORTEO.md). Generaliza al portador del farol, que
## fue el prototipo del sistema.
##
## Vive colgado de la Camera3D del Player para que el agarre sea RIGIDO con la
## vista. El objeto se pega a su marker y acompaña cada cabeceo sin un frame de
## retraso; con un seguimiento por codigo, a 120 Hz de fisica y 60 de render,
## el objeto "persigue" a la camara y se nota enseguida.
##
## Toda la logica de coger vive AQUI y no en player.gd a proposito: el jugador
## no tiene que saber que existe un farol o un pez, igual que no sabe que
## existe una caña. El contrato con player.gd son tres numeros: `hands_used`,
## `carry_slowdown` y (de la caña) `input_captured`.
##
## Controles — un solo boton contextual, el click que la caña deja libre, y Q:
##   E     agarrar / colgar en gancho / clavar o retomar la caña / soltar
##   click  (manteniendo) cargar y lanzar — la caña no puede lanzarse con las
##          manos ocupadas, asi que el click es del porteo mientras llevas algo.
##   Q     al cinturon / sacar del cinturon (solo objetos chicos declarados)

## Alcance del agarre. Corto y honesto: si hay que estirarse, es que no lo
## alcanzas de verdad.
const ALCANCE := 2.2

## La lentitud por peso, pura y testeable: 1.0 hasta PESO_GRATIS_KG, despues
## cae linea abajo hasta el suelo. El fletan (20 kg) baja a ~0.85; el atun
## (60 kg) te deja al 0.4 — cruzar la cubierta con el ES la escena.
const PESO_GRATIS_KG := 6.0
const LENTITUD_POR_KG := 0.011
const LENTITUD_MINIMA := 0.3

## Cuanto tarda la carga del lanzamiento en llenarse, y cuanto empuja: de un
## empujoncito (tap) a pasarle la sardina al de la borda (carga llena). El
## empuje util cae con el peso alrededor de LANZAR_REFERENCIA_KG — un atun no
## se lanza, se deja caer con intencion.
const LANZAR_CARGA_S := 0.85
const LANZAR_FUERZA_MIN := 2.0
const LANZAR_FUERZA_MAX := 8.5
const LANZAR_ARCO := 1.6
const LANZAR_REFERENCIA_KG := 12.0

## Huecos del cinturon: DOS, y solo para objetos chicos declarados
## (`en_cinturon`). Decision del usuario (DECISIONES 2026-08-23): calidad de
## vida para la radio y la llave, jamas un escape del deficit de manos.
const CINTURON_HUECOS := 2

@export var player_path: NodePath = ^"../.."

## La caña, para clavarla y retomarla en los soportes de borda.
@export var rod_path: NodePath = ^"../FishingRod"

## Donde queda el objeto de UNA mano. Bajo y a la derecha (numeros del farol):
## ilumina/asoma sin comerse el centro de la pantalla.
@export var agarre_offset := Vector3(0.30, -0.32, -0.42)
@export var agarre_angulos_deg := Vector3(-8.0, 6.0, -5.0)

## Donde queda el porteo a DOS manos: centrado y abajo, un abrazo. Mas cerca
## del pecho que el agarre fino — el objeto grande TAPA parte de la vista, y
## eso es informacion honesta, no un bug.
@export var agarre2_offset := Vector3(0.0, -0.40, -0.62)
@export var agarre2_angulos_deg := Vector3(-14.0, 0.0, 0.0)

## Cuanto se espera una respuesta del host antes de dar la peticion por
## perdida y devolverle el boton al jugador. Generoso: con 150 ms de ida y
## vuelta sobra, y quedarse mudo es peor que reintentar.
const ESPERA_MAX := 1.5
const AVISO_SEG := 1.8

## A que velocidad se considera que te fuiste de la bomba, en m/s. Bajo, pero no
## cero: la cubierta se mueve bajo los pies y el jugador quieto sobre un barco
## que cabecea nunca esta del todo a cero.
const SALIR_BOMBA_MS := 0.8

## Las copias de los demas jugadores: markers vivos y VISIBLES (el principio 1
## de PORTEO dice que lo que llevas se VE, y de esos markers cuelgan los
## objetos replicados), pero sin leer input ni tocar contabilidad.
var modo_presentacion: bool = false

var objeto: Portable3D = null

## La bomba que estoy accionando, o null. Ocuparla son las dos manos.
var bomba: ManualBilgePump = null
## La bomba cuyo cabezal de aspiracion llevo en la mano, o null. Una sola mano:
## quien dirige la manguera conserva el movimiento.
var manguera: ManualBilgePump = null

## Lo ultimo que se le PIDIO a la bomba sobre la palanca. No es "esta bombeando"
## —eso lo dice la bomba, y en red lo decide el host—: es lo que este jugador
## mando, para no repetir el evento sesenta veces por segundo.
var _bombeando_pedido: bool = false

## Verbo de AGARRE de bomba en vuelo, o -1. Mismo candado que `_pidiendo` del
## porteo y por el mismo motivo: con el agarre pesimista nada cambia en local
## hasta que el host contesta, asi que dos E dentro de la misma ventana de ida y
## vuelta mandan DOS verbos distintos y el host acepta los dos — se acababa
## ocupando la estacion Y llevando el cabezal a la vez, con tres manos.
##
## ⚠️ Cubre solo OCUPAR/LIBERAR/TOMAR/SOLTAR. La PALANCA no: sus flancos no se
## reintentan nunca, asi que descartar un ACCION_OFF dejaria la bomba accionada
## en el host hasta el siguiente flanco — chupando sola.
var _pidiendo_bomba: int = -1
var _pidiendo_bomba_seg: float = 0.0

## id_red del cuerpo que le pedimos al host, o -1. Mientras esta pedido el
## prompt dice "pidiendo...", que es honesto: dice que pediste, no que tenes.
var _pidiendo: int = -1
var _pidiendo_seg: float = 0.0

## Lo guardado en el cinturon, en orden de entrada. Q saca el ULTIMO (LIFO):
## lo que acabas de guardar es lo que mas probablemente necesites de vuelta.
var cinturon: Array[Portable3D] = []

var _player: Player
var _rod: FishingRod = null
var _agarre1: Marker3D
var _agarre2: Marker3D
var _cintos: Array[Marker3D] = []
var _rayo: RayCast3D
var _hud: PorteoHud
## <0 = sin carga en curso; 0..1 = cargando el lanzamiento.
var _carga: float = -1.0


func _ready() -> void:
	_player = get_node_or_null(player_path) as Player
	_rod = get_node_or_null(rod_path) as FishingRod

	_agarre1 = _crear_agarre("Agarre", agarre_offset, agarre_angulos_deg)
	_agarre2 = _crear_agarre("AgarreDosManos", agarre2_offset, agarre2_angulos_deg)

	# El cinturon cuelga del CUERPO, no de la camara: la radio a la cadera se
	# ve al mirar abajo, en tu sombra, y en tu copia de red. Los markers son
	# AUTORADOS en `player.tscn` (y los indexa `NetPorteo.SOCKETS`, que es
	# quien los nombra en el cable).
	#
	# Crearlos aca fallaba EN SILENCIO: Godot rechaza `add_child` sobre un
	# padre que todavia esta montando sus hijos, y el `_ready` de un nieto cae
	# justo dentro de esa ventana. El cinturon se quedaba con dos markers
	# huerfanos FUERA del arbol — invisible en los tests aislados (donde el
	# padre es este mismo nodo y no esta ocupado) y roto en el juego real.
	var cuerpo: Node3D = _player if _player != null else self
	for i in CINTURON_HUECOS:
		var nombre_cinto := "Cinto%d" % (i + 1)
		var cinto := cuerpo.get_node_or_null(NodePath(nombre_cinto)) as Marker3D
		if cinto == null:
			# Solo pasa fuera de la escena de jugador (tests, capturas): ahi el
			# padre somos nosotros mismos y el add_child si entra.
			cinto = Marker3D.new()
			cinto.name = nombre_cinto
			cinto.position = Vector3(-0.24 if i == 0 else 0.24, 0.0, 0.14)
			cuerpo.add_child(cinto)
		_cintos.append(cinto)

	_rayo = RayCast3D.new()
	_rayo.name = "Mira"
	_rayo.target_position = Vector3(0.0, 0.0, -ALCANCE)
	_rayo.collide_with_areas = true
	add_child(_rayo)

	_hud = PorteoHud.new()
	_hud.name = "PorteoHud"
	add_child(_hud)


func _crear_agarre(nombre_nodo: String, offset: Vector3, angulos_deg: Vector3) -> Marker3D:
	var m := Marker3D.new()
	m.name = nombre_nodo
	m.position = offset
	m.rotation = Vector3(
		deg_to_rad(angulos_deg.x),
		deg_to_rad(angulos_deg.y),
		deg_to_rad(angulos_deg.z)
	)
	add_child(m)
	return m


## La lentitud que impone un peso, expuesta pura para el test y para que el
## HUD futuro pueda contarla sin cargar la escena.
static func factor_lentitud(kg: float) -> float:
	return clampf(
		1.0 - maxf(kg - PESO_GRATIS_KG, 0.0) * LENTITUD_POR_KG,
		LENTITUD_MINIMA, 1.0
	)


func _unhandled_input(event: InputEvent) -> void:
	# Las copias de los demas tienen markers vivos y visibles, pero NO leen
	# input: sin esta guarda, los cinco Portadores ajenos agarrarian cosas con
	# TU raton (ver `modo_presentacion`).
	if modo_presentacion:
		return
	if event.is_action_pressed(&"belt"):
		# En la palanca, Q es el SELECTOR de la bomba y no el cinturon: con las
		# dos manos puestas el cinturon no se puede usar de todas formas, asi que
		# la tecla estaba libre y no hace falta inventar una nueva.
		if bomba != null:
			_pedir_bomba(bomba, BombaModel.Verbo.MODO_SUCCION \
				if bomba.modo == ManualBilgePump.Modo.EXTRACCION \
				else BombaModel.Verbo.MODO_EXTRACCION)
			return
		_cinturon_accion()
		return
	if not event.is_action_pressed(&"interact"):
		return
	if objeto == null:
		if _interactuar_bomba():
			return
		if _interactuar_soporte():
			return
		if _interactuar_cubo():
			return
		_intentar_coger()
	else:
		var g := _gancho_a_la_vista()
		if g != null and g.libre() and objeto.colgable:
			_colgar(g)
		else:
			_soltar()


func _physics_process(delta: float) -> void:
	if modo_presentacion:
		return
	# El objeto puede desaparecer bajo nuestros pies (un despawn futuro, una
	# escena que se descarga): ni las manos ni el cinturon pueden quedarse
	# ocupados por un fantasma.
	if objeto != null and not is_instance_valid(objeto):
		objeto = null
		_liberar_manos()
	# RECONCILIACION: "sigue vivo" no basta. El host puede haber decidido que
	# ese objeto ya no es tuyo —te lo quito una ola, se lo llevo un compañero,
	# lo solto el vaciado de manos— y sin comprobarlo las manos se quedan
	# ocupadas por un fantasma PARA SIEMPRE, que es justo el fallo que la
	# cabecera de porteo_tests dice proteger.
	elif objeto != null and (objeto.portador != _player
			or objeto.estado != Portable3D.Estado.EN_MANO):
		objeto = null
		_liberar_manos()
	for i in range(cinturon.size() - 1, -1, -1):
		if not is_instance_valid(cinturon[i]) \
				or cinturon[i].estado != Portable3D.Estado.EN_CINTURON:
			cinturon.remove_at(i)
	# La manguera tambien se reconcilia, y no dentro de `_paso_bomba`: esa sale
	# en la primera linea cuando no ocupas la estacion, y llevar el cabezal y
	# estar en la palanca son mutuamente excluyentes por la cuenta de manos, asi
	# que ahi no correria nunca. Sin esto, un cabezal que se suelta por otra via
	# deja las manos ocupadas por un fantasma para siempre.
	if manguera != null and (not is_instance_valid(manguera)
			or manguera.portador_manguera != _peer()):
		manguera = null
		_liberar_manos()

	_pidiendo_seg = maxf(_pidiendo_seg - delta, 0.0)
	if _pidiendo_seg <= 0.0:
		_pidiendo = -1
	_pidiendo_bomba_seg = maxf(_pidiendo_bomba_seg - delta, 0.0)
	if _pidiendo_bomba_seg <= 0.0:
		_pidiendo_bomba = -1

	_paso_bomba()
	_paso_lanzamiento(delta)
	_refrescar_hud()


# =============================================================================
#  La red (docs/RED.md R1 · docs/PORTEO.md fase C)
# =============================================================================

## Pide un verbo. En solitario lo hace y devuelve true; en red lo MANDA y
## devuelve false — con agarre PESIMISTA, o sea que hasta que el host conteste
## no se toca nada. La regla 8 no deja otra: un agarre optimista revocado 120
## ms despues ES "me robo".
func _pedir(cuerpo: Portable3D, verbo: int, id_socket: int,
		extra := Vector3.ZERO) -> bool:
	if cuerpo == null:
		return false
	# UNA peticion en vuelo, y solo una. Sin este candado, dos toques de E
	# dentro de la misma ventana de ida y vuelta mandan dos peticiones que el
	# host acepta las dos: los objetos se sueldan al mismo marker y el primero
	# queda inalcanzable para el resto de la sesion.
	if _pidiendo >= 0:
		return false
	if not Net.pedir_porteo(cuerpo, verbo, id_socket, extra):
		return true # en solitario: lo ejecuta el llamador, como siempre
	# El HOST resuelve SINCRONO: para cuando `pedir_porteo` vuelve, el verbo ya
	# se ejecuto y `aplicar_porteo` ya limpio el estado. Marcar "pidiendo" aqui
	# lo dejaria mintiendo 1,5 s con el objeto ya en la mano, y taparia la
	# linea que enseña el sistema a quien lo esta aprendiendo.
	if Net.rol == Net.Rol.CLIENTE:
		_pidiendo = cuerpo.id_red
		_pidiendo_seg = ESPERA_MAX
	return false


## El host dijo que si (o el mundo cambio y hay que enterarse). El verbo YA se
## ejecuto sobre el cuerpo: aca solo se pone al dia la contabilidad local.
func aplicar_porteo(cuerpo: Portable3D, peer: int, verbo: int, _id_socket: int) -> void:
	if modo_presentacion or _player == null:
		return
	if peer != multiplayer.get_unique_id():
		# Es de otro: si era mio, ya no.
		if objeto == cuerpo:
			objeto = null
			_liberar_manos()
		cinturon.erase(cuerpo)
		return
	_pidiendo = -1
	match verbo:
		NetPorteo.Verbo.EN_MANO:
			objeto = cuerpo
			cinturon.erase(cuerpo)
			_player.hands_used = cuerpo.manos
			_player.carry_slowdown = factor_lentitud(cuerpo.peso_kg())
		NetPorteo.Verbo.EN_CINTURON:
			if objeto == cuerpo:
				objeto = null
			if not cinturon.has(cuerpo):
				cinturon.append(cuerpo)
			_liberar_manos()
		NetPorteo.Verbo.COLGADO, NetPorteo.Verbo.SUELTO:
			if objeto == cuerpo:
				objeto = null
				_liberar_manos()
			cinturon.erase(cuerpo)


## El host dijo que no. Se DICE: un boton que no hizo nada es el "me robo" que
## el juego promete no hacer, aunque tecnicamente no haya mentido nadie.
func denegado(id_cuerpo: int, motivo: int, gano: int) -> void:
	if _pidiendo == id_cuerpo:
		_pidiendo = -1
		_pidiendo_seg = 0.0
	if _hud != null:
		_hud.set_aviso(NetPorteo.texto_motivo(motivo,
			"" if gano <= 0 else "otro"), AVISO_SEG)


# =============================================================================
#  Coger / colgar / soltar
# =============================================================================

func _intentar_coger() -> void:
	# En plena lucha las manos son de la caña: no se recoge nada hasta que el
	# pez este dentro (o se haya ido). El espejo de este candado vive en la
	# caña: con carga en brazos no se lanza el sedal.
	if _player != null and _player.input_captured:
		return
	var objetivo := _portable_a_la_vista()
	if objetivo == null:
		return
	var socket := NetPorteo.socket_de_mano(objetivo.manos)
	if not _pedir(objetivo, NetPorteo.Verbo.EN_MANO, socket):
		return # va por red: manda el host, y `aplicar_porteo` pondra al dia
	var agarre := _agarre1 if objetivo.manos == 1 else _agarre2
	if not objetivo.tomar(_player, agarre):
		return
	objeto = objetivo
	if _player != null:
		_player.hands_used = objetivo.manos
		_player.carry_slowdown = factor_lentitud(objetivo.peso_kg())


func _colgar(g: GanchoFarol) -> void:
	if objeto == null:
		return
	if not _pedir(objeto, NetPorteo.Verbo.COLGADO, _socket_de_gancho(g)):
		return
	# `ocupar()` lo hace ahora el verbo, que ademas consulta `libre()` por
	# dentro: el gancho y el objeto se enganchan en una sola operacion y no
	# hay forma de dejar uno de los dos a medias.
	if objeto.colgar_en(g):
		objeto = null
		_liberar_manos()


func _soltar() -> void:
	if objeto == null:
		return
	# Se suelta con la velocidad del jugador: en cubierta el gesto es dejarlo,
	# pero si te lo arranca una ola mientras corres, el objeto sale despedido
	# con la inercia que ya tenia. Sin esto se queda flotando en el sitio y
	# parece que el mundo hace trampas.
	var v := _player.velocity if _player != null else Vector3.ZERO
	if not _pedir(objeto, NetPorteo.Verbo.SUELTO, NetPorteo.SOCKET_NINGUNO, v):
		return
	objeto.soltar(get_tree().current_scene, v, _player)
	objeto = null
	_liberar_manos()


## El indice de socket de un gancho concreto. Va por INDICE en la tabla y no
## por nombre porque los dos soportes de caña del barco se llaman IGUAL.
func _socket_de_gancho(g: Node3D) -> int:
	var barco := _barco_de_escena()
	if barco == null or g == null:
		return NetPorteo.SOCKET_NINGUNO
	for i in range(NetPorteo.SOCKET_DEL_BARCO, NetPorteo.SOCKETS.size()):
		if barco.get_node_or_null(NetPorteo.SOCKETS[i]) == g:
			return i
	return NetPorteo.SOCKET_NINGUNO


func _barco_de_escena() -> Node3D:
	var escena := get_tree().current_scene
	if escena == null:
		return null
	return escena.get_node_or_null(^"FishingBoat") as Node3D


## Recuenta las manos a partir de lo que este Portador lleva DE VERDAD.
##
## Antes ponia `hands_used = 0` a ciegas, y eso abria un agujero real: soltar la
## palanca (o que el host te sacara de ella) con el colador todavia en la mano
## dejaba las manos a cero, y con ellas el salto y la caña desbloqueados mientras
## seguias llevando el cabezal. Poner a cero solo es correcto cuando no queda
## nada, asi que se calcula en vez de asumirse.
func _liberar_manos() -> void:
	_carga = -1.0
	if _player == null:
		return
	var usadas: int = 0
	if objeto != null:
		usadas += objeto.manos
	if bomba != null:
		usadas += BombaModel.MANOS_BOMBEAR
	if manguera != null:
		usadas += BombaModel.MANOS_MANGUERA
	_player.hands_used = usadas
	if usadas == 0:
		_player.carry_slowdown = 1.0


# =============================================================================
#  El cinturon: dos huecos, solo objetos chicos, Q para todo
# =============================================================================

func _cinturon_accion() -> void:
	if objeto != null:
		_al_cinturon()
	else:
		_del_cinturon()


func _al_cinturon() -> void:
	if not objeto.en_cinturon or cinturon.size() >= CINTURON_HUECOS:
		return
	# El hueco se busca LIBRE, no se deduce del tamaño de la lista: la poda de
	# `_physics_process` borra desde el medio, asi que con dos guardados y el
	# primero invalidado, `cinturon.size()` volveria a apuntar al marker que ya
	# esta ocupado y los dos objetos compartirian sitio.
	var hueco := _hueco_libre()
	if hueco < 0:
		return
	if not _pedir(objeto, NetPorteo.Verbo.EN_CINTURON,
			NetPorteo.socket_de_cinturon(hueco)):
		return
	if objeto.guardar_en(_cintos[hueco], hueco):
		cinturon.append(objeto)
		objeto = null
		_liberar_manos()


## El primer hueco de cinturon que nadie esta usando, o -1.
func _hueco_libre() -> int:
	for i in _cintos.size():
		var libre := true
		for p in cinturon:
			if is_instance_valid(p) and p.hueco_cinturon == i:
				libre = false
				break
		if libre:
			return i
	return -1


func _del_cinturon() -> void:
	if cinturon.is_empty():
		return
	# En plena lucha las manos son de la caña: la radio espera.
	if _player != null and _player.input_captured:
		return
	var p: Portable3D = cinturon.pop_back()
	if p == null or not is_instance_valid(p):
		return
	if not _pedir(p, NetPorteo.Verbo.EN_MANO, NetPorteo.socket_de_mano(p.manos)):
		cinturon.append(p) # sigue en el cinturon hasta que el host conteste
		return
	if p.tomar(_player, _agarre1):
		objeto = p
		if _player != null:
			_player.hands_used = p.manos
			_player.carry_slowdown = factor_lentitud(p.peso_kg())
	else:
		cinturon.append(p)


# =============================================================================
#  El soporte de borda: clavar y retomar la caña
# =============================================================================

## E sobre un soporte: clavar la caña (si esta libre y la caña en un estado
## clavable) o retomarla (si es NUESTRA caña la que cuelga ahi). Devuelve true
## solo si el gesto se hizo, para que un E fallido caiga al porteo normal.
func _interactuar_soporte() -> bool:
	if _rod == null:
		return false
	var s := _soporte_a_la_vista()
	if s == null:
		return false
	if s.ocupado:
		if _rod.soporte == s:
			_rod.retomar()
			return true
		return false
	return _rod.clavar_en(s)


func _soporte_a_la_vista() -> SoporteCania:
	if not _rayo.is_colliding():
		return null
	var n := _rayo.get_collider() as Node
	while n != null:
		if n is SoporteCania:
			return n as SoporteCania
		n = n.get_parent()
	return null


# =============================================================================
#  La bomba de achique: E para ponerse, clic para bombear (docs/BOMBA_MANUAL.md)
# =============================================================================

## E sobre la bomba. El orden ES el arbitraje: el cabezal de la manguera manda
## sobre la estacion porque es el volumen chico y especifico, y estar ya
## ocupando la bomba manda sobre todo, para que salir sea siempre la misma tecla.
##
## Devuelve true solo si el gesto se hizo, para que una E fallida caiga al
## siguiente candidato de la cadena.
func _interactuar_bomba() -> bool:
	if bomba != null:
		return _pedir_bomba(bomba, BombaModel.Verbo.LIBERAR)
	if manguera != null:
		return _pedir_bomba(manguera, BombaModel.Verbo.SOLTAR_MANGUERA)

	var b := _bomba_a_la_vista()
	if b == null:
		return false
	if _mirando_el_cabezal(b):
		return _pedir_bomba(b, BombaModel.Verbo.TOMAR_MANGUERA)
	return _pedir_bomba(b, BombaModel.Verbo.OCUPAR)


## Pide un verbo sobre una bomba.
##
## En red lo MANDA y no toca nada hasta que el host conteste — agarre pesimista,
## igual que el porteo: un "ya estas bombeando" que se revoca 120 ms despues es
## el "me robo" que prohibe la regla 8. En solitario no hay host, asi que este
## Portador hace de arbitro con la MISMA funcion pura que usaria el.
##
## Devuelve true si el gesto se dio por hecho (o viajo), para que una E fallida
## caiga al siguiente candidato de la cadena de interaccion.
func _pedir_bomba(b: ManualBilgePump, verbo: int) -> bool:
	if b == null:
		return false
	var de_agarre := verbo != BombaModel.Verbo.ACCION_ON 		and verbo != BombaModel.Verbo.ACCION_OFF
	if de_agarre and _pidiendo_bomba >= 0:
		return false
	if Net != null and Net.pedir_bomba(b, verbo):
		# El HOST resuelve SINCRONO: para cuando `pedir_bomba` vuelve, el verbo ya
		# se aplico. Marcar "pidiendo" ahi lo dejaria mintiendo un segundo y medio
		# con la palanca ya en la mano.
		if de_agarre and Net.rol == Net.Rol.CLIENTE:
			_pidiendo_bomba = verbo
			_pidiendo_bomba_seg = ESPERA_MAX
		return true
	var motivo := BombaModel.arbitrar(verbo, b.ocupante, b.portador_manguera,
		_peer(), _manos_usadas())
	if motivo != BombaModel.Motivo.OK:
		bomba_denegada(b, motivo)
		return false
	b.aplicar_verbo(_peer(), verbo, _agarre1)
	aplicar_bomba(b, _peer(), verbo)
	return true


## El verbo ya aplicado en TODAS las maquinas: aqui solo se pone al dia lo que es
## de este jugador y de nadie mas — sus manos y a que estacion esta atado.
##
## De los demas no hay nada que apuntar: `ocupante` y `portador_manguera` viven
## en la propia bomba y ya viajaron, asi que sus copias no necesitan contabilidad
## paralela que pueda desincronizarse.
func aplicar_bomba(b: ManualBilgePump, peer: int, verbo: int) -> void:
	if b == null or peer != _peer() or modo_presentacion:
		return
	if verbo != BombaModel.Verbo.ACCION_ON and verbo != BombaModel.Verbo.ACCION_OFF:
		_pidiendo_bomba = -1
		_pidiendo_bomba_seg = 0.0
	match verbo:
		BombaModel.Verbo.OCUPAR:
			bomba = b
			_bombeando_pedido = false
			# Las dos manos: es una palanca de barco. De ahi salen solas la caña
			# vedada, el salto vedado y que no puedas ademas dirigir el cabezal —
			# la interdependencia sale de la cuenta de manos, no de un candado.
			_liberar_manos()
		BombaModel.Verbo.LIBERAR:
			if bomba == b:
				bomba = null
				_bombeando_pedido = false
				_liberar_manos()
		BombaModel.Verbo.TOMAR_MANGUERA:
			manguera = b
			# UNA mano, y sin penalizacion de peso: quien dirige la manguera
			# conserva el movimiento (docs/BOMBA_MANUAL.md). El `hands_busy` de
			# dos manos NO vale aqui.
			_liberar_manos()
		BombaModel.Verbo.SOLTAR_MANGUERA:
			if manguera == b:
				manguera = null
				_liberar_manos()


## El host dijo que no. Se dice por su nombre: un boton que no hace nada es el
## "me robo" que el juego promete no hacer, aunque nadie haya mentido.
func bomba_denegada(_b: ManualBilgePump, motivo: int) -> void:
	# El candado se suelta SIEMPRE, tambien cuando la respuesta es que no: si no,
	# un rechazo te dejaria mudo hasta que venciera la espera.
	_pidiendo_bomba = -1
	_pidiendo_bomba_seg = 0.0
	if _hud == null:
		return
	var texto := BombaModel.texto_motivo(motivo)
	if texto != "":
		_hud.set_aviso(texto, AVISO_SEG)


## Manos ocupadas AHORA, contando lo que este Portador ya tiene entre manos.
func _manos_usadas() -> int:
	if _player == null:
		return 0
	return int(_player.hands_used)


func _peer() -> int:
	if Net != null and Net.en_red():
		return multiplayer.get_unique_id()
	# En solitario no hay peers: se usa el 1 (el host) para que el estado de la
	# bomba se lea igual en los dos modos.
	return 1


func _bomba_a_la_vista() -> ManualBilgePump:
	if not _rayo.is_colliding():
		return null
	var n := _rayo.get_collider() as Node
	while n != null:
		if n is ManualBilgePump:
			return n as ManualBilgePump
		n = n.get_parent()
	return null


## ¿Lo que tengo delante es el cabezal de aspiracion y no el cuerpo de la bomba?
## Se decide por DISTANCIA al cabezal, no por el nombre del collider: el cabezal
## se mueve en runtime con la manguera y puede acabar a seis metros de la bomba.
func _mirando_el_cabezal(b: ManualBilgePump) -> bool:
	if not _rayo.is_colliding():
		return false
	return _rayo.get_collision_point().distance_to(b.posicion_toma_global()) < 0.45


## Mientras ocupas la estacion, mantener el clic bombea. El boton esta libre: a
## la bomba se llega con las manos vacias, asi que ni la caña (vedada por
## `hands_used`) ni el lanzamiento (que pide `objeto`) lo estan usando.
func _paso_bomba() -> void:
	if bomba == null:
		return
	if not is_instance_valid(bomba):
		bomba = null
		_bombeando_pedido = false
		_liberar_manos()
		return
	# RECONCILIACION: el host puede haberte sacado de la estacion (te fuiste, se
	# cayo la conexion, otro la reclamo). Sin esto las manos se quedan ocupadas
	# por una bomba que ya no es tuya, para siempre.
	if bomba.ocupante != _peer():
		bomba = null
		_bombeando_pedido = false
		_liberar_manos()
		return

	# FLANCOS, no muestreo: el estado de la palanca es un evento fiable de dos
	# por segundo como mucho, no un dato periodico. Mandarlo cada frame serian
	# sesenta RPC fiables por segundo por cada persona bombeando.
	var quiere := Input.is_action_pressed(&"grab")
	if quiere != _bombeando_pedido:
		_bombeando_pedido = quiere
		_pedir_bomba(bomba, BombaModel.Verbo.ACCION_ON if quiere 			else BombaModel.Verbo.ACCION_OFF)

	# Moverse ES salir. Nadie deberia tener que buscar una tecla para dejar de
	# bombear cuando el barco se esta hundiendo y hay que correr a otro sitio.
	if _player != null and _player.velocity.length() > SALIR_BOMBA_MS:
		_pedir_bomba(bomba, BombaModel.Verbo.LIBERAR)


# =============================================================================
#  El cubo de cebo: E para cebar la caña
# =============================================================================

## E sobre el cubo: llenar el anzuelo. Solo cuenta si se movio cebo de verdad
## (cubo vacio o caña ya cebada al tope caen al porteo normal). La caña puede
## estar en la mano o clavada en la borda: cebar es trabajo de cubierta.
func _interactuar_cubo() -> bool:
	if _rod == null:
		return false
	var cubo := _cubo_a_la_vista()
	return cubo != null and cubo.cebar(_rod)


func _cubo_a_la_vista() -> CuboCebo:
	if not _rayo.is_colliding():
		return null
	var n := _rayo.get_collider() as Node
	while n != null:
		if n is CuboCebo:
			return n as CuboCebo
		n = n.get_parent()
	return null


# =============================================================================
#  Lanzar: mantener el click carga, soltarlo lanza
# =============================================================================

## El click es de la caña... hasta que llevas algo: con las manos ocupadas la
## caña esta vedada (su gate lee hands_used), asi que el boton queda libre para
## el gesto que el genero pide a gritos — pasarle el pez al companero, tirar la
## carga que te esta hundiendo, o el farol al agua sin querer.
func _paso_lanzamiento(delta: float) -> void:
	if objeto == null:
		return
	if Input.is_action_just_pressed(&"grab"):
		_carga = 0.0
	if _carga >= 0.0:
		_carga = minf(_carga + delta / LANZAR_CARGA_S, 1.0)
		if Input.is_action_just_released(&"grab"):
			_lanzar(_carga)


func _lanzar(carga: float) -> void:
	if objeto == null:
		return
	var fuerza: float = lerpf(LANZAR_FUERZA_MIN, LANZAR_FUERZA_MAX, carga)
	# El empuje util cae con el peso: la misma carga que cruza una sardina de
	# borda a borda apenas despega un atun del pecho.
	fuerza *= clampf(LANZAR_REFERENCIA_KG / maxf(objeto.peso_kg(), 1.0), 0.25, 1.0)
	var dir := -global_transform.basis.z
	var v_base := _player.velocity if _player != null else Vector3.ZERO
	var v := v_base + dir * fuerza + Vector3.UP * (LANZAR_ARCO * carga)
	# Lanzar ES soltar con mas velocidad, asi que va por el mismo verbo: la
	# velocidad viaja en `extra` y el host la aplica igual en las seis
	# maquinas. Si cada una la calculara por su cuenta, el mismo lanzamiento
	# aterrizaria en seis sitios distintos.
	if not _pedir(objeto, NetPorteo.Verbo.SUELTO, NetPorteo.SOCKET_NINGUNO, v):
		_carga = -1.0
		return
	objeto.soltar(get_tree().current_scene, v, _player)
	objeto = null
	_liberar_manos()


# =============================================================================
#  Que hay delante
# =============================================================================

func _portable_a_la_vista() -> Portable3D:
	if not _rayo.is_colliding():
		return null
	var golpe := _rayo.get_collider()
	if golpe is Portable3D:
		return golpe as Portable3D
	# Un objeto colgado esta congelado y sin capa de colision (no queremos que
	# empuje al jugador), asi que se busca a traves de su gancho.
	var n := golpe as Node
	while n != null:
		if n is GanchoFarol:
			for hijo: Node in n.get_children():
				if hijo is Portable3D:
					return hijo as Portable3D
			return null
		n = n.get_parent()
	return null


func _gancho_a_la_vista() -> GanchoFarol:
	if not _rayo.is_colliding():
		return null
	var n := _rayo.get_collider() as Node
	while n != null:
		if n is GanchoFarol:
			return n as GanchoFarol
		n = n.get_parent()
	return null


# =============================================================================
#  El HUD minimo: un prompt que enseña y una barra de carga
# =============================================================================

func _refrescar_hud() -> void:
	if _hud == null:
		return
	_hud.set_carga(_carga if objeto != null else -1.0)
	_hud.set_prompt(_texto_prompt())
	var nombres := PackedStringArray()
	for p in cinturon:
		nombres.append(p.nombre)
	_hud.set_cinturon(nombres)


func _texto_prompt() -> String:
	# Honesto: dice que PEDISTE, no que tenes. Con 80-150 ms se lee como
	# estirar el brazo; lo que no puede pasar es que el boton parezca no haber
	# hecho nada (regla 8).
	if _pidiendo >= 0:
		return "pidiendo…"
	# La bomba manda sobre todo lo demas: mientras la ocupas, lo unico que hay
	# que saber es como bombear y como salir.
	if bomba != null:
		# El prompt ENSEÑA el ciclo: son dos tiempos, y sin decirlo el jugador
		# mantiene el clic para siempre y se pregunta por que no sale agua.
		# Y AVISA cuando la camara se llena, que es la unica forma de fallar de
		# esta mecanica que no se ve sola: la bomba deja de mover agua sin que
		# cambie nada en pantalla, y sin decirlo se lee como averia (regla 8).
		if bomba.modo == ManualBilgePump.Modo.EXTRACCION:
			return "EXTRAYENDO  ·  saca la manguera por la borda  ·  Q  succión  ·  E  salir"
		if bomba.deposito_lleno():
			return "lleno  ·  Q  pasar a extraer  ·  E  salir"
		return "clic  bombear  ·  Q  extraer  ·  E  salir"
	if manguera != null:
		var linea := "E  soltar el colador"
		if manguera.modo == ManualBilgePump.Modo.EXTRACCION:
			linea = "sácala por la borda  ·  E  soltar el colador"
		if manguera.longitud_maxima_manguera() > 0.0 \
				and manguera.longitud_manguera() / manguera.longitud_maxima_manguera() > 0.85:
			# Avisar ANTES de que se te escape, no despues (regla 8).
			linea += "  ·  no da más cuerda"
		return linea
	if objeto != null:
		if _carga >= 0.0:
			return "" # cargando: la barra ya lo cuenta, el texto solo taparia
		var linea := "E  soltar  ·  clic  lanzar"
		var g := _gancho_a_la_vista()
		if g != null and g.libre() and objeto.colgable:
			linea = "E  colgar  ·  clic  lanzar"
		if objeto.en_cinturon and cinturon.size() < CINTURON_HUECOS:
			linea += "  ·  Q  al cinturón"
		return linea
	var b := _bomba_a_la_vista()
	if b != null:
		if _mirando_el_cabezal(b):
			return "" if not b.puede_tomar_manguera() else "E  llevar el colador"
		if not b.estacion_libre():
			return "la bomba está ocupada"
		return "E  bombear"
	var s := _soporte_a_la_vista()
	if s != null and _rod != null:
		if s.ocupado and _rod.soporte == s:
			return "E  retomar la caña"
		if s.libre() and _rod.soporte == null:
			return "E  clavar la caña"
	var cubo := _cubo_a_la_vista()
	if cubo != null:
		# El prompt dice lo que hay y lo que hace, no solo la tecla: el cebo es
		# una DECISION (gastarlo ahora o guardarlo) y decidir pide el dato.
		if cubo.vacio():
			return "cubo de cebo vacío"
		if _rod != null and _rod.cebo == cubo.tipo \
				and _rod.cebo_cargas >= FishingRod.CEBO_CARGAS_MAX:
			return "%s  ·  la caña ya va cebada" % cubo.resumen()
		return "E  cebar  ·  %s  ·  %s" % [cubo.resumen(), cubo.tipo.resumen()]
	var objetivo := _portable_a_la_vista()
	if objetivo == null:
		return ""
	var texto := "E  agarrar %s" % objetivo.nombre
	if objetivo.peso_kg() >= 5.0:
		texto += "  ·  %.0f kg" % objetivo.peso_kg()
	if objetivo.manos == 2:
		texto += "  ·  dos manos"
	return texto
