extends Node

## La red minima de F1 (docs/RED.md): ENet en localhost detras de UNA puerta.
## Autoload `Net`. F9 = hostear, F10 = unirse a 127.0.0.1 (o por linea de
## comandos: `--net-host` / `--net-join=IP`, para abrir dos instancias).
##
## R0 replica exactamente lo que el plan promete que basta: la SEMILLA al
## unirse, el reloj y la furia en goteo (~50 bytes), el barco del host, y los
## jugadores en espacio LOCAL del barco con sus tres numeros de animacion.
## Los props, los peces, el porteo en red y los eventos del oceano son R1.
##
## Los tres contratos de la costura (RED.md) viven aca y en NetMath:
##  1. jugadores en espacio local del barco (NetMath.a_local / a_mundo);
##  2. el reloj del cliente persigue `t_host - RETARDO_INTERP` con slew
##     acotado — el oceano del cliente se evalua EN EL PASADO exacto en el
##     que vive su barco interpolado;
##  3. el barco del cliente se congela KINEMATICO (reporta velocidad real a
##     los contactos: la cubierta sigue llevando a los personajes).

const PUERTO := 4247
const MAX_JUGADORES := 5

## Por donde viajan los paquetes.
##
## Los DOS se mantienen a proposito, y no es indecision: Steam es una sesion por
## PC —el peer identifica por Steam ID, no por IP—, asi que con el transporte de
## Steam se acaba el ciclo de dos ventanas en la misma maquina. Y ese es
## justamente el ciclo con el que se depura TODO lo demas: las estaciones, el
## porteo, el agua. Ademas `net_tests` levanta un loopback ENet de verdad dentro
## de un proceso; sin ENet ese test no tiene sustituto, porque `Net` es un
## autoload singleton y los RPC no se pueden testear en headless.
##
## O sea: ENET es el transporte de desarrollo y de pruebas, STEAM el de la
## version publicada. Cambiarlo no es una decision de codigo, es un arranque:
## `--net-transporte=steam`.
enum Transporte { ENET, STEAM }

var transporte: Transporte = Transporte.ENET

## Cuanto vive el cliente en el pasado. Dos snapshots de barco (20 Hz) y aire
## para un paquete perdido. Subirlo suaviza; bajarlo acerca el "ahora".
const RETARDO_INTERP := 0.12

## Dilatacion maxima del reloj al corregir (25%). Contrato 2: jamas saltar.
const MAX_SLEW := 0.25

const HZ_MAR := 10.0
const HZ_MUNDO := 20.0

## El agua embarcada cambia a centesimas por segundo, asi que 4 Hz la sigue de
## sobra y el cliente interpola lo que quiera para el HUD. Va en su propio RPC y
## no dentro del lote del mundo para no ensanchar el paquete de 20 Hz por un dato
## que no lo necesita.
const HZ_AGUA := 4.0

## Cuantos snapshots de barco guardamos (a 20 Hz, ~1 s de historia).
const BUFFER_BARCO_MAX := 24

## Y cuantos por CUERPO replicado: a 20 Hz son ~0,4 s, tres veces el retardo
## de interpolacion, que aguanta una racha de perdidas sin quedarse seco. Con
## los 24 del barco por cada uno de N cuerpos serian miles de diccionarios
## rotando para nada.
const BUFFER_CUERPO_MAX := 8

## Tope RUIDOSO de cuerpos replicados. Pasado esto se avisa y no se replican:
## mejor un warning en la consola que un presupuesto de red que se dispara en
## silencio justo en tier 3.
const MAX_CUERPOS := 64

## Radio alrededor del barco dentro del cual un cuerpo viaja en marco LOCAL
## (contrato 1). Fuera —un farol que se fue a la deriva— viaja en mundo: no
## tiene sentido componerlo contra un casco del que ya no depende.
const RADIO_LOCAL := 12.0

## Cuando se considera que un cuerpo se durmio y deja de gastar ancho de banda.
## Ningun cuerpo duerme solo: `FloatingBody3D` fuerza `can_sleep = false`, asi
## que no hay señal gratis del motor y hay que medirlo a mano con histeresis.
const DORMIDO_VEL := 0.05
const DORMIDO_TICKS := 3
## Cuantas veces se repite el anuncio de DORMIDO. Va por canal no fiable, y
## perder el unico paquete que lo lleva deja al cuerpo colgado.
const DORMIDO_REPETIR := 3

## Un pez SIN dueño, EN EL AGUA y a mas de esto del barco se despawnea. Sin
## una cota, el censo crece toda la sesion (verificado: hoy no se libera ni un
## pez en todo el juego) y el presupuesto de ancho de banda es ficcion.
## OJO: este numero es DISEÑO DE PESCA, no de red — el pez que se aleja ya
## esta perdido para el jugador; esto solo decide cuando deja de costar bytes.
const DESPAWN_PEZ_M := 60.0

enum Rol { OFFLINE, HOST, CLIENTE }

var rol: Rol = Rol.OFFLINE

var _acum_mar: float = 0.0
var _acum_mundo: float = 0.0
var _acum_agua: float = 0.0

## CLIENTE: estimacion del reloj del host (ultimo recibido + delta local).
var _host_time: float = 0.0
var _tiene_hola: bool = false

## CLIENTE: snapshots del barco del host, ordenados por t.
var _buffer_barco: Array[Dictionary] = []

## peer -> Player (la copia visible del otro).
var _remotos: Dictionary = {}
## peer -> [pos_local: Vector3, yaw: float, ratio: float, agua: float, lucha: bool, manos: int]
var _estados: Dictionary = {}
## peer -> sim_time del ultimo estado recibido, para poder podar por ANTIGUEDAD
## y no solo por desconexion: `_chau` viaja por canal fiable y `_estado_jugador`
## por el no fiable, asi que un estado en vuelo puede llegar DESPUES del adios,
## resucitar al fantasma y dejar un jugador de piedra en cubierta para siempre.
var _visto_jugador: Dictionary = {}

# --- el censo de cuerpos replicados (R1) -------------------------------------
## id -> Node3D
var _cuerpos: Dictionary = {}
## get_instance_id() -> id. La clave es un int y NUNCA el Object: un Dictionary
## con clave Object deja claves colgando cuando el nodo se libera.
var _ids: Dictionary = {}
## id -> peer que lo lleva (NetPorteo.NADIE si no lo lleva nadie)
var _dueno: Dictionary = {}
## CLIENTE: id -> Array[Dictionary] de snapshots
var _buffers: Dictionary = {}
## CLIENTE: id -> Transform3D de reposo (local al barco) mientras esta DORMIDO
var _reposo: Dictionary = {}
## HOST: id -> ticks consecutivos quieto
var _quietos: Dictionary = {}
## id -> sim_time del ultimo snapshot, para podar cuerpos rancios
var _visto: Dictionary = {}
## id -> indice en FishSpecies.SPECIES (solo peces; -1 el resto)
var _especies: Dictionary = {}
## Los cuerpos que NACEN en partida numeran desde aca (los peces).
var _proximo_id_dinamico: int = NetPorteo.ID_DINAMICO_BASE
## HOST: por donde va la rotacion del sobrante cuando no caben todos en un lote
var _cursor_lote: int = 0

var _lag: NetLag = null

var _overlay: CanvasLayer = null
var _overlay_label: Label = null
var _barco_cache: RigidBody3D = null


func _ready() -> void:
	multiplayer.peer_connected.connect(_al_conectarse_peer)
	multiplayer.peer_disconnected.connect(_al_irse_peer)
	multiplayer.connected_to_server.connect(_al_conectar_como_cliente)
	multiplayer.connection_failed.connect(_al_fallar_conexion)
	multiplayer.server_disconnected.connect(_al_caerse_el_host)
	# El guion del clima: si este par se sale de el (alguien le escribio la furia
	# a mano, y el TsunamiDirector lo hace cada tick), hay que contarselo a la
	# tripulacion o los mares divergen en silencio.
	Ocean.parte_cambiado.connect(_on_parte_cambiado)
	# Dos instancias a mano sin tocar teclas: util para probar y para CI.
	var args := OS.get_cmdline_args()
	for arg in args:
		if arg == "--net-host":
			hostear.call_deferred()
		elif arg.begins_with("--net-join"):
			var ip := "127.0.0.1"
			if "=" in arg:
				ip = arg.get_slice("=", 1)
			unirse.call_deferred(ip)
		elif arg.begins_with("--net-lag"):
			_configurar_lag(arg.get_slice("=", 1) if "=" in arg else "")
		elif arg.begins_with("--net-transporte"):
			# Va ANTES que `hostear`/`unirse` porque los dos se llaman diferidos:
			# el orden de los argumentos en la linea de comandos no importa.
			var quiere := arg.get_slice("=", 1) if "=" in arg else ""
			transporte = Transporte.STEAM if quiere == "steam" else Transporte.ENET


## `--net-lag=120,30,2` = 120 ms de base, 30 de jitter, 2% de perdida. Vive
## SOLO en la linea de comandos y no en project.godot a proposito: un ajuste
## de este calibre guardado en el proyecto se escaparia activado en un build.
func _configurar_lag(spec: String) -> void:
	var partes := spec.split(",", false)
	_lag = NetLag.new()
	_lag.sembrar(hash(spec) if not spec.is_empty() else 4247)
	_lag.configurar(
		float(partes[0]) if partes.size() > 0 else 120.0,
		float(partes[1]) if partes.size() > 1 else 30.0,
		(float(partes[2]) if partes.size() > 2 else 0.0) * 0.01)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	match (event as InputEventKey).keycode:
		KEY_F9:
			hostear()
		KEY_F10:
			unirse("127.0.0.1")


# =============================================================================
#  Entrar y salir
# =============================================================================

func hostear() -> void:
	if rol != Rol.OFFLINE:
		return
	var peer := _crear_peer_host()
	if peer == null:
		return
	multiplayer.multiplayer_peer = peer
	rol = Rol.HOST
	# El host censa su mundo pero NO congela nada: el es quien lo simula.
	_censar_escena()
	_marcar_autoridad_local()
	_refrescar_overlay()


## `destino` es una IP con el transporte ENET y sera un Steam ID con STEAM: por
## eso ya no se llama `ip`. Es el unico sitio del juego donde esa diferencia se
## nota — nadie fuera de este archivo llama a `hostear()` ni a `unirse()`.
func unirse(destino: String) -> void:
	if rol != Rol.OFFLINE:
		return
	var peer := _crear_peer_cliente(destino)
	if peer == null:
		return
	multiplayer.multiplayer_peer = peer
	rol = Rol.CLIENTE
	_refrescar_overlay()


## El peer del host, o null si no se pudo abrir (y ya avisa el mismo).
func _crear_peer_host() -> MultiplayerPeer:
	if transporte == Transporte.STEAM:
		return _crear_peer_steam(true, "")
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(PUERTO, MAX_JUGADORES) != OK:
		push_warning("Net: no pude abrir el puerto %d (¿otra instancia ya es host?)." % PUERTO)
		return null
	return peer


func _crear_peer_cliente(destino: String) -> MultiplayerPeer:
	if transporte == Transporte.STEAM:
		return _crear_peer_steam(false, destino)
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(destino, PUERTO) != OK:
		push_warning("Net: no pude crear el cliente hacia %s." % destino)
		return null
	return peer


## El transporte de Steam, TODAVIA NO IMPLEMENTADO (fase R2 de docs/RED.md).
##
## La comprobacion es en RUNTIME y no una referencia directa a la clase a
## proposito: GodotSteam no esta vendorizado, y nombrar `SteamMultiplayerPeer` en
## el codigo dejaria el proyecto entero sin compilar hasta que lo este. Asi la
## puerta existe, las estaciones se escriben contra ella, y el dia que entre el
## addon lo unico que falta aqui es el lobby.
##
## Falla en voz alta en vez de caer en silencio a ENet: un juego publicado que
## creyera estar en Steam y estuviera abriendo un puerto en el router seria una
## sorpresa muy fea.
func _crear_peer_steam(_es_host: bool, _destino: String) -> MultiplayerPeer:
	if not ClassDB.class_exists(&"SteamMultiplayerPeer"):
		push_error("Net: se pidio el transporte STEAM pero GodotSteam no esta instalado. Ver docs/RED.md, fase R2.")
		return null
	push_error("Net: el transporte STEAM aun no tiene lobby. Ver docs/RED.md, fase R2.")
	return null


func _al_conectarse_peer(id: int) -> void:
	if rol != Rol.HOST:
		return
	# El paquete de bienvenida: la semilla UNA vez, el estado del mar, los
	# eventos en vuelo y el censo entero del mundo. Con esto el cliente
	# reconstruye el oceano — es toda la magia del plan — y ademas ve el
	# tsunami que ya venia de camino y quien lleva que en la mano.
	# El parte va DENTRO de la bienvenida y no en un mensaje aparte: quien se
	# une sin guion caeria al carril manual, y ahi los rayos se deciden con la
	# furia cuantizada en vez de con el spline — o sea que veria una tormenta
	# electrica DISTINTA de la de sus compañeros, sin un solo error en consola.
	_hola.rpc_id(id, Ocean.ocean_seed, Ocean.sim_time, Ocean.fury_objetivo(),
		Ocean.fury, Ocean.rain_level, Ocean.rain_scale,
		Ocean.events_pack(), _foto_del_mundo(),
		Ocean.parte().empaquetar() if Ocean.tiene_parte() else {},
		_foto_de_estaciones())
	_refrescar_overlay()


## El censo entero como Array de Arrays planos: [id, estado, dueño, socket,
## hueco, pos, rot]. Se manda una sola vez, al entrar.
## Quien esta en cada estacion, por INDICE de `BombaModel.BOMBAS`.
##
## Va en la bienvenida porque si no, el que se une tarde ve TODAS las bombas
## libres: su prompt le ofrece "E bombear" sobre una palanca que otro esta
## accionando y, al pulsarla, el host le contesta OCUPADA — el HUD
## contradiciendose consigo mismo, que es feedback que miente (regla 8). Y el
## colador le aparece enrollado en el carrete aunque un compañero lo lleve en la
## mano y este achicando la celda de proa con el.
func _foto_de_estaciones() -> Array:
	var foto: Array = []
	for i in BombaModel.BOMBAS.size():
		var b := _bomba_de(i)
		if b == null:
			continue
		foto.append([i, b.ocupante, b.portador_manguera, b.bombeando])
	return foto


## Y su reconstruccion, con los MISMOS verbos que usa el juego en marcha: asi no
## existe una segunda version de "que significa estar ocupando la bomba" que
## pueda separarse de la primera.
func _aplicar_foto_de_estaciones(foto: Array) -> void:
	for fila: Array in foto:
		if fila.size() < 4:
			continue
		var i: int = int(fila[0])
		var quien: int = int(fila[1])
		var lleva: int = int(fila[2])
		if quien != BombaModel.NADIE:
			_ejecutar_bomba(i, quien, BombaModel.Verbo.OCUPAR)
			if bool(fila[3]):
				_ejecutar_bomba(i, quien, BombaModel.Verbo.ACCION_ON)
		if lleva != BombaModel.NADIE:
			_ejecutar_bomba(i, lleva, BombaModel.Verbo.TOMAR_MANGUERA)


func _foto_del_mundo() -> Array:
	var foto: Array = []
	for id: int in _cuerpos:
		var cuerpo: Node3D = _cuerpos[id]
		if not is_instance_valid(cuerpo):
			continue
		var p := cuerpo as Portable3D
		foto.append([
			id,
			int(p.estado) if p != null else NetPorteo.Verbo.SUELTO,
			int(_dueno.get(id, NetPorteo.NADIE)),
			_socket_actual(p),
			p.hueco_cinturon if p != null else -1,
			cuerpo.global_position,
			cuerpo.global_basis.get_rotation_quaternion(),
			_indice_especie(cuerpo),
		])
	return foto


func _al_irse_peer(id: int) -> void:
	# ANTES del adios: el host vacia las manos del que se fue y lo difunde con
	# UN transform decidido por el. Si cada maquina lo hiciera por su cuenta el
	# objeto acabaria en seis sitios distintos; y `_despedir` hace `queue_free`
	# del subarbol entero, asi que un portable reparentado bajo su camara o su
	# cinturon se iria con la copia y dejaria de existir para TODOS.
	if rol == Rol.HOST:
		_vaciar_manos_de(id)
		# Y lo saca de las estaciones: una bomba que se queda ocupada por alguien
		# que ya no esta es un barco que nadie puede achicar.
		_liberar_bombas_de(id)
		_chau.rpc(id)
	_despedir(id)
	_refrescar_overlay()


## Suelta todo lo que llevaba un peer, en el sitio donde estaba, y lo difunde.
func _vaciar_manos_de(peer: int) -> void:
	for id: int in _dueno.keys():
		if int(_dueno[id]) != peer:
			continue
		var cuerpo: Node3D = _cuerpos.get(id)
		if not is_instance_valid(cuerpo):
			_dueno[id] = NetPorteo.NADIE
			continue
		var mundo := cuerpo.global_transform
		_ejecutar_porteo(id, NetPorteo.NADIE, NetPorteo.Verbo.SUELTO,
			NetPorteo.SOCKET_NINGUNO, Vector3.ZERO, mundo)
		_aplicar_porteo.rpc(id, NetPorteo.NADIE, NetPorteo.Verbo.SUELTO,
			NetPorteo.SOCKET_NINGUNO, Vector3.ZERO, mundo, false)


func _al_conectar_como_cliente() -> void:
	_refrescar_overlay()


func _al_fallar_conexion() -> void:
	push_warning("Net: no habia host escuchando.")
	multiplayer.multiplayer_peer = null
	rol = Rol.OFFLINE
	_refrescar_overlay()


func _al_caerse_el_host() -> void:
	# Sin migracion de host (el plan la descarta). Se avisa y el mundo local
	# SIGUE: lo que no puede pasar es quedarse con un mundo congelado para
	# siempre, que es lo que hacia R0 — el barco se quedaba en `freeze` con su
	# `_physics_process` apagado y no existia la operacion inversa en NINGUN
	# sitio del repo. R1 multiplicaria esa fuga por cada cuerpo replicado.
	push_warning("Net: el host se fue. Quedaste solo con tu copia del mar.")
	multiplayer.multiplayer_peer = null
	rol = Rol.OFFLINE
	for peer in _remotos.keys():
		_despedir(peer)
	_tiene_hola = false
	_buffer_barco.clear()
	_devolver_el_mundo()
	_refrescar_overlay()


## Le devuelve la fisica al barco y a todos los cuerpos replicados. Es la
## operacion inversa exacta del congelado de red, y tiene que existir: sin
## ella, perder al host deja un mundo de estatuas.
func _devolver_el_mundo() -> void:
	var barco := _barco()
	if barco != null:
		barco.freeze = false
		barco.set_physics_process(true)
		if barco.has_method(&"olvidar_historial_agua"):
			barco.call(&"olvidar_historial_agua")
	_liberar_estaciones_fantasma()
	for id: int in _cuerpos:
		var cuerpo: Node3D = _cuerpos[id]
		if not is_instance_valid(cuerpo):
			continue
		var p := cuerpo as Portable3D
		# Lo que alguien llevaba en la mano se queda como estaba: descongelar
		# un objeto que cuelga de un marker lo haria caer por dentro del brazo.
		if p != null and p.estado != Portable3D.Estado.SUELTO:
			continue
		_descongelar_replicado(cuerpo as RigidBody3D)
	_buffers.clear()
	_reposo.clear()


# =============================================================================
#  El goteo por tick
# =============================================================================

func _physics_process(delta: float) -> void:
	# El simulador de latencia se drena ANTES que nada: lo que vencio en este
	# tick tiene que estar aplicado antes de que el mundo lo lea.
	if _lag != null and _lag.activo():
		_lag.drenar(Time.get_ticks_msec() * 0.001)
	match rol:
		Rol.HOST:
			_tick_host(delta)
		Rol.CLIENTE:
			_tick_cliente(delta)
		Rol.OFFLINE:
			return
	_aplicar_remotos(delta)
	_podar_rancios()


func _tick_host(delta: float) -> void:
	_acum_mar += delta
	if _acum_mar >= 1.0 / HZ_MAR:
		# Se RESTA el periodo en vez de poner a cero: con la fisica a 120 Hz,
		# poner a cero tira el resto y la cadencia real cae a ~8,3 Hz en vez de
		# los 10 que promete la constante.
		_acum_mar -= 1.0 / HZ_MAR
		_estado_mar.rpc(Ocean.sim_time, Ocean.fury, Ocean.fury_objetivo(),
			Ocean.rain_level, Ocean.rain_scale)

	_acum_mundo += delta
	if _acum_mundo >= 1.0 / HZ_MUNDO:
		_acum_mundo -= 1.0 / HZ_MUNDO
		var barco := _barco()
		if barco != null:
			_estado_barco.rpc(Ocean.sim_time, barco.global_position,
				barco.global_basis.get_rotation_quaternion())
		var lote := _empaquetar_tick()
		if not lote.is_empty():
			_estado_cuerpos.rpc(lote)
		_emitir_mi_jugador()
		_vigilar_peces()

	_acum_agua += delta
	if _acum_agua >= 1.0 / HZ_AGUA:
		_acum_agua -= 1.0 / HZ_AGUA
		var agua := _agua_embarcada()
		if agua != null:
			_estado_agua.rpc(NetAgua.empaquetar(agua.niveles(), agua.alarma, agua.hundido,
				_mascara_de_depositos()))


func _tick_cliente(delta: float) -> void:
	if not _tiene_hola:
		return
	# Contrato 2: el reloj estima y PERSIGUE, jamas salta.
	_host_time += delta
	Ocean.sim_time = NetMath.corregir_reloj(
		Ocean.sim_time, _host_time - RETARDO_INTERP, delta, MAX_SLEW)

	# Contrato 3: el barco congelado se mueve por transform, en NUESTRO reloj.
	var barco := _barco()
	if barco != null and not _buffer_barco.is_empty():
		barco.global_transform = NetMath.muestrear_buffer(_buffer_barco, Ocean.sim_time)
	_aplicar_cuerpos()

	_acum_mundo += delta
	if _acum_mundo >= 1.0 / HZ_MUNDO:
		_acum_mundo -= 1.0 / HZ_MUNDO
		_emitir_mi_jugador()


## Mi jugador, en espacio local del barco (contrato 1), con los numeros que
## alimentan al animator ajeno — los mismos que mueven mi sombra.
func _emitir_mi_jugador() -> void:
	var barco := _barco()
	var yo := _jugador_local()
	if barco == null or yo == null:
		return
	var local := NetMath.a_local(barco.global_transform, yo.global_transform)
	var ratio: float = 0.0
	if not yo.is_in_water():
		ratio = Vector2(yo.velocity.x, yo.velocity.z).length() / maxf(yo.walk_speed, 0.001)
	var agua: float = smoothstep(yo.swim_threshold - 0.2, yo.swim_threshold,
		yo.submerged_fraction)
	# `manos` viaja porque la caña se esconde del viewmodel cuando porteas
	# (`FishingRod._guardada()` lo lee): sin ese int, la copia de un compañero
	# con un atun al pecho seguiria enseñando la caña en la mano.
	# `carry_slowdown` NO viaja: se deriva del peso del cuerpo ya replicado.
	if rol == Rol.HOST:
		_estado_jugador.rpc(1, local.origin, local.basis.get_euler().y,
			ratio, agua, yo.input_captured, yo.hands_used)
	else:
		_estado_jugador_al_host.rpc_id(1, local.origin, local.basis.get_euler().y,
			ratio, agua, yo.input_captured, yo.hands_used)


# =============================================================================
#  RPCs
# =============================================================================

@rpc("authority", "call_remote", "reliable")
func _hola(semilla: int, t: float, furia: float, furia_objetivo: float,
		lluvia: float, escala_lluvia: float, eventos: Array, foto: Array,
		parte: Dictionary = {}, estaciones: Array = []) -> void:
	if _demorar(NetLag.Canal.FIABLE, _hola, [semilla, t, furia, furia_objetivo,
			lluvia, escala_lluvia, eventos, foto, parte, estaciones]):
		return
	# Guarda de idempotencia: `_hola` es el UNICO salto de reloj permitido —al
	# unirse todavia no hay mundo que romper— pero si llegara dos veces (una
	# reconexion, un cambio de escena) el segundo seria un salto en caliente,
	# justo lo que el contrato 2 prohibe.
	if _tiene_hola:
		return
	if Ocean.ocean_seed != semilla:
		Ocean.regenerate(semilla)
	Ocean.sim_time = t - RETARDO_INTERP
	# El parte PRIMERO: con guion en vigor `set_fury_red` se ignora a proposito
	# (la furia sale del spline), asi que ponerlo despues dejaria la furia de
	# arranque escrita por el cable y luego pisada — el mismo resultado, pero
	# por accidente en vez de por diseño.
	Ocean.rain_scale = escala_lluvia
	if parte.is_empty():
		Ocean.limpiar_parte()
		Ocean.set_fury_red(furia, furia_objetivo)
		Ocean.rain_level = lluvia
	else:
		var guion := ParteMeteorologico.new()
		guion.desempaquetar(parte)
		Ocean.fijar_parte(guion)
	Ocean.events_unpack(eventos)
	_host_time = t
	_tiene_hola = true
	_congelar_barco_local()
	_ceder_directores()
	_censar_escena()
	_marcar_autoridad_local()
	_aplicar_foto(foto)
	# DESPUES de la foto de cuerpos: tomar el cabezal necesita el socket de mano
	# del compañero, y esa copia puede acabar de crearse ahi.
	_aplicar_foto_de_estaciones(estaciones)
	_refrescar_overlay()


@rpc("authority", "call_remote", "reliable")
func _chau(peer: int) -> void:
	if _demorar(NetLag.Canal.FIABLE, _chau, [peer]):
		return
	_despedir(peer)
	_refrescar_overlay()


@rpc("authority", "call_remote", "unreliable_ordered")
func _estado_mar(t: float, furia: float, furia_objetivo: float,
		lluvia: float, escala_lluvia: float) -> void:
	if _demorar(NetLag.Canal.ORDENADO, _estado_mar,
			[t, furia, furia_objetivo, lluvia, escala_lluvia]):
		return
	_host_time = t
	# Se fijan LAS DOS furias a la vez. Con solo el valor actual, el setter del
	# cliente volvia a pasar por el rate limit: mientras el dial se movia, el
	# cliente perseguia un blanco que huia a su misma velocidad y nunca lo
	# alcanzaba — el mar del cliente iba sistematicamente por detras.
	Ocean.set_fury_red(furia, furia_objetivo)
	Ocean.rain_level = lluvia
	# `rain_scale` es lo que CORTA la lluvia durante la retirada del tsunami.
	# Sin replicarlo, cinco pantallas de seis no ven el corte y esa telegrafia
	# —de las mas fuertes que tiene el juego— se pierde (regla 8).
	Ocean.rain_scale = escala_lluvia


@rpc("authority", "call_remote", "unreliable_ordered")
func _estado_barco(t: float, pos: Vector3, rot: Quaternion) -> void:
	if _demorar(NetLag.Canal.ORDENADO, _estado_barco, [t, pos, rot]):
		return
	_buffer_barco.append({&"t": t, &"pos": pos, &"rot": rot})
	while _buffer_barco.size() > BUFFER_BARCO_MAX:
		_buffer_barco.pop_front()


## Todos los cuerpos replicados del tick, en UN paquete (ver el codec en
## NetMath): un RPC por prop pagaria la cabecera de Variant por cada uno.
@rpc("authority", "call_remote", "unreliable_ordered")
func _estado_cuerpos(datos: PackedByteArray) -> void:
	if _demorar(NetLag.Canal.ORDENADO, _estado_cuerpos, [datos]):
		return
	var lote := NetMath.desempaquetar_lote(datos)
	var t := float(lote[&"t"])
	for c: Dictionary in lote[&"cuerpos"]:
		var id := int(c[&"id"])
		var cuerpo: Node3D = _cuerpos.get(id)
		if not is_instance_valid(cuerpo):
			continue
		# La otra mitad del candado: un snapshot viejo puede llegar DESPUES del
		# `_aplicar_porteo` que lo puso en una mano — lo fiable y lo no fiable
		# van por canales ENet distintos y se secuencian por separado, asi que
		# el segundo en salir puede ser el primero en llegar.
		var p := cuerpo as Portable3D
		if p != null and p.estado != Portable3D.Estado.SUELTO:
			continue
		_visto[id] = t
		var flags := int(c[&"flags"])
		var trans := Transform3D(Basis(c[&"rot"] as Quaternion), c[&"pos"] as Vector3)
		if flags & NetMath.FLAG_DORMIDO:
			# Ultimo snapshot: pasa a regimen de REPOSO. Si venia en marco
			# local se compone contra el barco cada tick (error CERO y cero
			# bytes); si venia en mundo, se clava donde esta.
			_reposo[id] = {&"local": bool(flags & NetMath.FLAG_LOCAL), &"t": trans}
			_buffers.erase(id)
		else:
			_reposo.erase(id)
			var buffer: Array[Dictionary] = _buffers.get(id, [] as Array[Dictionary])
			var local := bool(flags & NetMath.FLAG_LOCAL)
			# Al cruzar el radio, el cuerpo cambia de MARCO. Interpolar entre un
			# snapshot local y uno de mundo mezcla dos sistemas de coordenadas y
			# manda el objeto a cientos de metros durante medio segundo: cuando
			# cambia el marco, la historia anterior deja de ser comparable.
			if not buffer.is_empty() and bool(buffer[-1].get(&"local", false)) != local:
				buffer.clear()
			buffer.append({&"t": t, &"pos": trans.origin,
				&"rot": trans.basis.get_rotation_quaternion(),
				&"local": local})
			while buffer.size() > BUFFER_CUERPO_MAX:
				buffer.pop_front()
			_buffers[id] = buffer


## Cliente -> host. El host guarda y reparte (relay): con 2-6 amigos la
## topologia simple gana a cualquier optimizacion.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func _estado_jugador_al_host(pos: Vector3, yaw: float, ratio: float,
		agua: float, lucha: bool, manos: int) -> void:
	if rol != Rol.HOST:
		return
	var quien := multiplayer.get_remote_sender_id()
	_estados[quien] = [pos, yaw, ratio, agua, lucha, manos]
	_visto_jugador[quien] = Ocean.sim_time
	# Se reparte a todos MENOS al emisor: mandarselo tambien a el y descartar
	# el eco en el receptor funciona, pero regala un paquete por cliente y por
	# tick, y en R1 hay bastante mas goteo encima.
	for otro: int in multiplayer.get_peers():
		if otro != quien:
			_estado_jugador.rpc_id(otro, quien, pos, yaw, ratio, agua, lucha, manos)


@rpc("authority", "call_remote", "unreliable_ordered")
func _estado_jugador(peer: int, pos: Vector3, yaw: float, ratio: float,
		agua: float, lucha: bool, manos: int) -> void:
	if _demorar(NetLag.Canal.ORDENADO, _estado_jugador,
			[peer, pos, yaw, ratio, agua, lucha, manos]):
		return
	if peer == multiplayer.get_unique_id():
		return
	_estados[peer] = [pos, yaw, ratio, agua, lucha, manos]
	_visto_jugador[peer] = Ocean.sim_time


# =============================================================================
#  El censo: quien es quien entre maquinas
# =============================================================================

## Un identificador estable para cada cuerpo replicable. Los AUTORADOS lo
## sacan de su posicion en `NetPorteo.CUERPOS_ESCENA` (las dos maquinas leen
## la misma lista de disco: no hay nada que negociar); los que NACEN en
## partida los numera el host desde `ID_DINAMICO_BASE`.
func _censar_escena() -> void:
	_cuerpos.clear()
	_ids.clear()
	_dueno.clear()
	var escena := get_tree().current_scene
	if escena == null:
		return
	for id in NetPorteo.CUERPOS_ESCENA.size():
		var cuerpo := escena.get_node_or_null(NetPorteo.CUERPOS_ESCENA[id]) as Node3D
		if cuerpo == null:
			# Un prop renombrado dejaria de replicarse EL SOLO, en silencio,
			# mientras todo lo demas sigue funcionando. `net_tests` comprueba
			# las rutas en las dos escenas justamente por esto.
			push_warning("Net: no encuentro el cuerpo autorado '%s' para censar."
				% NetPorteo.CUERPOS_ESCENA[id])
			continue
		registrar_cuerpo(cuerpo, id)
		if rol == Rol.CLIENTE:
			_congelar_replicado(cuerpo as RigidBody3D)


func registrar_cuerpo(cuerpo: Node3D, id: int) -> void:
	if _cuerpos.size() >= MAX_CUERPOS and not _cuerpos.has(id):
		push_warning("Net: %d cuerpos censados, no replico mas (tope MAX_CUERPOS)."
			% _cuerpos.size())
		return
	_cuerpos[id] = cuerpo
	# La clave es el id de instancia (un int) y NUNCA el Object: un Dictionary
	# con clave Object se queda con claves colgando al liberarse el nodo.
	_ids[cuerpo.get_instance_id()] = id
	_dueno[id] = NetPorteo.NADIE
	var p := cuerpo as Portable3D
	if p != null:
		p.id_red = id


func olvidar_cuerpo(id: int) -> void:
	var cuerpo: Node3D = _cuerpos.get(id)
	if is_instance_valid(cuerpo):
		_ids.erase(cuerpo.get_instance_id())
	_cuerpos.erase(id)
	_dueno.erase(id)
	_buffers.erase(id)
	_reposo.erase(id)
	_quietos.erase(id)
	_visto.erase(id)
	_especies.erase(id)


func id_de(cuerpo: Node) -> int:
	if cuerpo == null:
		return -1
	return int(_ids.get(cuerpo.get_instance_id(), -1))


func cuerpo_de(id: int) -> Node3D:
	var c: Node3D = _cuerpos.get(id)
	return c if is_instance_valid(c) else null


func dueno_de(id: int) -> int:
	return int(_dueno.get(id, NetPorteo.NADIE))


func en_red() -> bool:
	return rol != Rol.OFFLINE


## Congela un cuerpo que es del HOST: aca solo se dibuja lo que el host dice.
## La capa de colision se CONSERVA (ver `Portable3D.congelar_por_red`), porque
## un cuerpo replicado sigue siendo un cuerpo del mundo — si no, la bodega del
## cliente marcaria cero mientras la del host marca sesenta kilos.
func _congelar_replicado(cuerpo: RigidBody3D) -> void:
	if cuerpo == null:
		return
	var p := cuerpo as Portable3D
	if p != null:
		p.congelar_por_red(true)
		return
	cuerpo.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	cuerpo.freeze = true
	cuerpo.set_physics_process(false)
	if cuerpo.has_method(&"olvidar_historial_agua"):
		cuerpo.call(&"olvidar_historial_agua")


func _descongelar_replicado(cuerpo: RigidBody3D) -> void:
	if cuerpo == null:
		return
	var p := cuerpo as Portable3D
	if p != null:
		p.congelar_por_red(false)
		return
	cuerpo.freeze = false
	cuerpo.set_physics_process(true)
	if cuerpo.has_method(&"olvidar_historial_agua"):
		cuerpo.call(&"olvidar_historial_agua")


## Poda por ANTIGUEDAD, no solo por desconexion. `_chau` viaja por el canal
## fiable y `_estado_jugador` por el no fiable: un estado en vuelo puede
## llegar DESPUES del adios, resucitar la copia y dejar un jugador de piedra
## en cubierta para siempre. Lo mismo con un cuerpo que dejo de existir.
func _podar_rancios() -> void:
	if rol != Rol.CLIENTE:
		return
	var ahora := Ocean.sim_time
	for peer: int in _estados.keys():
		if ahora - float(_visto_jugador.get(peer, ahora)) > 5.0:
			_despedir(peer)
	for id: int in _buffers.keys():
		if ahora - float(_visto.get(id, ahora)) > 10.0:
			_buffers.erase(id)


# =============================================================================
#  Los cuerpos en el cable
# =============================================================================

## HOST: arma el lote del tick. Deja fuera lo que alguien LLEVA (su sitio lo
## dice el socket, no un transform) y lo que ya se durmio.
func _empaquetar_tick() -> PackedByteArray:
	var barco := _barco()
	if barco == null:
		return PackedByteArray()
	var candidatos: Array[Dictionary] = []
	for id: int in _cuerpos:
		var cuerpo: Node3D = _cuerpos[id]
		if not is_instance_valid(cuerpo):
			continue
		var p := cuerpo as Portable3D
		if p != null and p.estado != Portable3D.Estado.SUELTO:
			_quietos[id] = 0 # al soltarlo habra que volver a contar
			continue
		var rb := cuerpo as RigidBody3D
		var quieto: bool = rb != null and rb.linear_velocity.length() < DORMIDO_VEL \
			and rb.angular_velocity.length() < DORMIDO_VEL
		var ticks := int(_quietos.get(id, 0))
		ticks = ticks + 1 if quieto else 0
		_quietos[id] = ticks

		# El anuncio de "me dormi" viaja por el canal NO FIABLE, asi que se
		# repite unas cuantas veces: si el unico paquete que lo llevaba se
		# pierde, el receptor se queda esperando snapshots que ya no van a
		# llegar y el cuerpo se congela en su ultima posicion interpolada.
		# Repetir es mucho mas barato que mandarlo por el canal fiable.
		if ticks > DORMIDO_TICKS + DORMIDO_REPETIR:
			continue

		var local := _marco_de(cuerpo, barco)
		var trans := NetMath.a_local(barco.global_transform, cuerpo.global_transform) \
			if local else cuerpo.global_transform
		var flags: int = (NetMath.FLAG_LOCAL if local else 0)
		if ticks >= DORMIDO_TICKS:
			flags |= NetMath.FLAG_DORMIDO
		candidatos.append({&"id": id, &"flags": flags, &"pos": trans.origin,
			&"rot": trans.basis.get_rotation_quaternion()})

	if candidatos.is_empty():
		return PackedByteArray()
	# Si no caben todos, el SOBRANTE ROTA entre ticks en vez de ensanchar el
	# paquete: cruzar el MTU fragmenta, y perder un fragmento pierde el tick
	# entero. Un cuerpo a 10 Hz efectivos lo absorbe el buffer del receptor.
	var tope := NetMath.cuerpos_por_paquete()
	if candidatos.size() > tope:
		var rotados: Array[Dictionary] = []
		for i in tope:
			rotados.append(candidatos[(_cursor_lote + i) % candidatos.size()])
		_cursor_lote = (_cursor_lote + tope) % candidatos.size()
		candidatos = rotados
	else:
		_cursor_lote = 0
	return NetMath.empaquetar_cuerpos(Ocean.sim_time, candidatos)


## Dentro del radio del barco, el cuerpo viaja en marco LOCAL (contrato 1);
## fuera —un farol a la deriva— en mundo, porque ya no depende del casco.
func _marco_de(cuerpo: Node3D, barco: RigidBody3D) -> bool:
	return cuerpo.global_position.distance_to(barco.global_position) < RADIO_LOCAL


## CLIENTE: mueve cada cuerpo replicado a donde toca EN NUESTRO RELOJ, que es
## el mismo en el que vive el barco interpolado. Por eso un prop en cubierta
## no "respira" contra el casco: los dos salen del mismo instante.
func _aplicar_cuerpos() -> void:
	var barco := _barco()
	if barco == null:
		return
	# Regimen de REPOSO: cero bytes por segundo y error CERO, porque se compone
	# contra el MISMO transform de barco que se acaba de muestrear.
	for id: int in _reposo:
		var cuerpo := cuerpo_de(id)
		if cuerpo == null:
			continue
		var r: Dictionary = _reposo[id]
		var t: Transform3D = r[&"t"]
		cuerpo.global_transform = NetMath.a_mundo(barco.global_transform, t) \
			if bool(r[&"local"]) else t

	for id: int in _buffers:
		var cuerpo := cuerpo_de(id)
		if cuerpo == null:
			continue
		var buffer: Array[Dictionary] = _buffers[id]
		if buffer.is_empty():
			continue
		var t := NetMath.muestrear_buffer(buffer, Ocean.sim_time)
		cuerpo.global_transform = NetMath.a_mundo(barco.global_transform, t) \
			if bool(buffer[-1].get(&"local", false)) else t


# =============================================================================
#  El porteo en red (fase C de docs/PORTEO.md)
# =============================================================================

## La puerta que usa el `Portador`. Devuelve true si la peticion se curso por
## red (y entonces el Portador NO debe tocar nada hasta que llegue la
## respuesta); false si estamos en solitario y tiene que hacerlo el mismo.
##
## AGARRE PESIMISTA, y es una DECISION. La regla 8 dice literal que todo fallo
## se telegrafia ANTES de castigar: "me aviso, nunca me robo". Un agarre
## optimista revocado por el host ES "me robo" — el objeto aparece en tu mano
## y desaparece 120 ms despues, sin forma de avisar antes. Con 80-150 ms de
## viaje, pedir se lee como estirar el brazo. Y de paso el camino pesimista
## tiene MENOS codigo, porque no existe el rollback.
##
## Asimetria deliberada: el HOST agarra al instante porque ES la autoridad.
## Los clientes pagan el viaje, igual que ya lo pagan por el barco y el mar.
func pedir_porteo(cuerpo: Portable3D, verbo: int, id_socket: int,
		extra := Vector3.ZERO) -> bool:
	if not en_red() or cuerpo == null:
		return false
	var id := id_de(cuerpo)
	if id < 0:
		# En red el porteo NUNCA se ejecuta en local, ni siquiera si todavia no
		# hay censo (la ventana entre `unirse()` y el `hola`) o si el cuerpo
		# rebotó contra MAX_CUERPOS. El `false` significa UNA sola cosa —
		# estamos en solitario—; devolverlo aqui haria que el jugador agarrara
		# la caja sin que el host se entere, y medio segundo despues el censo
		# se la arrancaria de la mano. Eso es exactamente el "me robo" que
		# prohibe la regla 8: mejor un gesto que no ocurre.
		return true
	if rol == Rol.HOST:
		_resolver_porteo(1, id, verbo, id_socket, extra)
	else:
		_pedir_porteo.rpc_id(1, id, verbo, id_socket, extra)
	return true


@rpc("any_peer", "call_remote", "reliable")
func _pedir_porteo(id_cuerpo: int, verbo: int, id_socket: int, extra: Vector3) -> void:
	# La guarda de rol no es decorativa: con `server_relay` activo por defecto,
	# es lo unico que impide que un cliente dirija este RPC a otro cliente.
	if rol != Rol.HOST:
		return
	_resolver_porteo(multiplayer.get_remote_sender_id(), id_cuerpo, verbo,
		id_socket, extra)


## El host arbitra y difunde. Su ORDEN TOTAL de las peticiones ES lo que
## resuelve la carrera de dos jugadores agarrando lo mismo: gana el primero
## que entra, sin marcas de tiempo y sin rollback.
func _resolver_porteo(quien: int, id_cuerpo: int, verbo: int, id_socket: int,
		extra: Vector3) -> void:
	var cuerpo := cuerpo_de(id_cuerpo) as Portable3D
	if cuerpo == null:
		return
	var socket := _nodo_de_socket(quien if NetPorteo.socket_es_del_jugador(id_socket)
		else 0, id_socket)
	var ocupado: bool = socket != null and socket.has_method(&"libre") \
		and not bool(socket.call(&"libre"))
	var motivo := NetPorteo.arbitrar(int(cuerpo.estado), dueno_de(id_cuerpo), quien,
		verbo, id_socket, ocupado, _huecos_libres_de(quien),
		cuerpo.colgable, cuerpo.en_cinturon,
		_manos_usadas_de(quien), cuerpo.manos)
	if motivo != NetPorteo.Motivo.OK:
		# El perdedor se entera POR SU NOMBRE. Un boton que no hace nada es el
		# "me robo" que el juego promete no hacer, aunque nadie haya mentido.
		if quien == 1:
			_porteo_denegado(id_cuerpo, motivo, dueno_de(id_cuerpo))
		else:
			_porteo_denegado.rpc_id(quien, id_cuerpo, motivo, dueno_de(id_cuerpo))
		return
	var destino := cuerpo.global_transform
	_ejecutar_porteo(id_cuerpo, quien, verbo, id_socket, extra, destino)
	_aplicar_porteo.rpc(id_cuerpo, quien, verbo, id_socket, extra, destino, false)


@rpc("authority", "call_remote", "reliable")
func _aplicar_porteo(id_cuerpo: int, peer: int, verbo: int, id_socket: int,
		extra: Vector3, destino: Transform3D, _reservado: bool) -> void:
	if _demorar(NetLag.Canal.FIABLE, _aplicar_porteo,
			[id_cuerpo, peer, verbo, id_socket, extra, destino, _reservado]):
		return
	_ejecutar_porteo(id_cuerpo, peer, verbo, id_socket, extra, destino)


@rpc("authority", "call_remote", "reliable")
func _porteo_denegado(id_cuerpo: int, motivo: int, gano: int) -> void:
	if _demorar(NetLag.Canal.FIABLE, _porteo_denegado, [id_cuerpo, motivo, gano]):
		return
	var portador := _portador_local()
	if portador != null:
		portador.denegado(id_cuerpo, motivo, gano)


## El verbo de verdad, identico en las seis maquinas.
func _ejecutar_porteo(id_cuerpo: int, peer: int, verbo: int, id_socket: int,
		extra: Vector3, destino: Transform3D) -> void:
	var cuerpo := cuerpo_de(id_cuerpo) as Portable3D
	if cuerpo == null:
		return
	match verbo:
		NetPorteo.Verbo.EN_MANO:
			var socket := _nodo_de_socket(peer, id_socket)
			if socket == null or not cuerpo.tomar(_jugador_de(peer), socket):
				return
			_dueno[id_cuerpo] = peer
			_soltar_replicacion(id_cuerpo)
		NetPorteo.Verbo.COLGADO:
			var g := _nodo_de_socket(0, id_socket)
			if g == null or not cuerpo.colgar_en(g):
				return
			_dueno[id_cuerpo] = NetPorteo.NADIE
			_soltar_replicacion(id_cuerpo)
		NetPorteo.Verbo.EN_CINTURON:
			var cinto := _nodo_de_socket(peer, id_socket)
			if cinto == null or not cuerpo.guardar_en(cinto,
					NetPorteo.cinturon_de_socket(id_socket)):
				return
			_dueno[id_cuerpo] = peer
			_soltar_replicacion(id_cuerpo)
		NetPorteo.Verbo.SUELTO:
			cuerpo.soltar(get_tree().current_scene, extra)
			cuerpo.global_transform = destino
			_dueno[id_cuerpo] = NetPorteo.NADIE
			# En el cliente vuelve a ser un cuerpo del host: se congela para
			# que siga los snapshots en vez de simular su propia realidad.
			if rol == Rol.CLIENTE:
				_congelar_replicado(cuerpo)
			_quietos[id_cuerpo] = 0
	var portador := _portador_local()
	if portador != null:
		portador.aplicar_porteo(cuerpo, peer, verbo, id_socket)


# =============================================================================
#  Las estaciones: la bomba de achique (docs/BOMBA_MANUAL.md)
# =============================================================================
#
# Mismo patron que el porteo, y a proposito: pedir -> el host arbitra -> difunde,
# con agarre PESIMISTA en los clientes. Lo que cambia es que aqui no se mueve un
# cuerpo, se ocupa un SITIO, asi que no hay transform que difundir ni
# replicacion que apagar — solo tres numeros (quien la ocupa, quien lleva el
# cabezal, si esta accionando) que acaban identicos en las seis maquinas.
#
# Quien decide sigue siendo `BombaModel.arbitrar`, puro y ya testeado. Aqui solo
# esta el cableado, que es lo que no se puede probar en headless.

## Pide un verbo sobre una bomba. Devuelve false SOLO en solitario, que es la
## señal de "hazlo tu mismo en local" (identico a `pedir_porteo`).
func pedir_bomba(bomba: Node, verbo: int) -> bool:
	if not en_red() or bomba == null:
		return false
	var id := id_de_bomba(bomba)
	if id == BombaModel.BOMBA_NINGUNA:
		# En red, una bomba que no esta en la tabla NO se acciona en local: seria
		# una palanca que solo mueve agua en tu pantalla.
		push_warning("Net: bomba fuera de BombaModel.BOMBAS; el verbo se descarta.")
		return true
	if rol == Rol.HOST:
		_resolver_bomba(1, id, verbo)
	else:
		_pedir_bomba.rpc_id(1, id, verbo)
	return true


@rpc("any_peer", "call_remote", "reliable")
func _pedir_bomba(id_bomba: int, verbo: int) -> void:
	# Igual que en el porteo: con `server_relay`, esta guarda es lo unico que
	# impide que un cliente le mande el RPC directamente a otro cliente.
	if rol != Rol.HOST:
		return
	_resolver_bomba(multiplayer.get_remote_sender_id(), id_bomba, verbo)


## El host arbitra y difunde. Su ORDEN TOTAL resuelve la carrera de dos
## jugadores pulsando E sobre la misma bomba: gana el primero que entra.
func _resolver_bomba(quien: int, id_bomba: int, verbo: int) -> void:
	var bomba := _bomba_de(id_bomba)
	if bomba == null:
		return
	var motivo := BombaModel.arbitrar(verbo, bomba.ocupante,
		bomba.portador_manguera, quien, _manos_usadas_de(quien))
	if motivo != BombaModel.Motivo.OK:
		# El perdedor se entera por su nombre, no con un boton que no hace nada.
		if quien == 1:
			_bomba_denegada(id_bomba, motivo)
		else:
			_bomba_denegada.rpc_id(quien, id_bomba, motivo)
		return
	_ejecutar_bomba(id_bomba, quien, verbo)
	_aplicar_bomba.rpc(id_bomba, quien, verbo)


@rpc("authority", "call_remote", "reliable")
func _aplicar_bomba(id_bomba: int, peer: int, verbo: int) -> void:
	if _demorar(NetLag.Canal.FIABLE, _aplicar_bomba, [id_bomba, peer, verbo]):
		return
	_ejecutar_bomba(id_bomba, peer, verbo)


@rpc("authority", "call_remote", "reliable")
func _bomba_denegada(id_bomba: int, motivo: int) -> void:
	if _demorar(NetLag.Canal.FIABLE, _bomba_denegada, [id_bomba, motivo]):
		return
	var portador := _portador_local()
	if portador != null:
		portador.bomba_denegada(_bomba_de(id_bomba), motivo)


## El verbo de verdad, identico en las seis maquinas.
func _ejecutar_bomba(id_bomba: int, peer: int, verbo: int) -> void:
	var bomba := _bomba_de(id_bomba)
	if bomba == null:
		return
	# El cabezal se sostiene con UNA mano, asi que va al agarre de una mano. En
	# las copias remotas ese marker tambien existe, y por eso la manguera de un
	# compañero sigue a su mano de verdad y no a un punto fijo del barco.
	bomba.aplicar_verbo(peer, verbo, _nodo_de_socket(peer, NetPorteo.socket_de_mano(1)))
	var portador := _portador_local()
	if portador != null:
		portador.aplicar_bomba(bomba, peer, verbo)


## Un bit por estacion con la camara llena, para el byte de banderas del agua.
##
## Va por ahi y no en un mensaje propio porque cabia: al byte de alarma y
## naufragio le sobraban seis bits, asi que el aviso viaja gratis a 4 Hz.
func _mascara_de_depositos() -> int:
	var mascara: int = 0
	for i in BombaModel.BOMBAS.size():
		var b := _bomba_de(i)
		if b != null and b.deposito_lleno():
			mascara |= 1 << i
	return mascara


## Y su aplicacion en el cliente. Sin esto, un invitado en la palanca no tiene
## forma de saber que la camara se lleno —alli no se simula, `carga_deposito` es
## siempre cero— y veria la bomba dejar de mover agua sin que nada cambie en
## pantalla: la unica forma de fallar de la mecanica que no se ve sola.
func _aplicar_camaras(mascara: int) -> void:
	for i in BombaModel.BOMBAS.size():
		var b := _bomba_de(i)
		if b != null:
			b.fijar_deposito_lleno_remoto((mascara & (1 << i)) != 0)


## La bomba con ese id, o null. Se resuelve por INDICE contra el casco y nunca
## por nombre: las dos bombas del barco se llaman igual dentro de su escena.
func _bomba_de(id: int) -> ManualBilgePump:
	if id < 0 or id >= BombaModel.BOMBAS.size():
		return null
	var barco := _barco()
	if barco == null:
		return null
	return barco.get_node_or_null(BombaModel.BOMBAS[id]) as ManualBilgePump


## El id de red de una bomba, o `BOMBA_NINGUNA`.
func id_de_bomba(bomba: Node) -> int:
	var barco := _barco()
	if barco == null or bomba == null:
		return BombaModel.BOMBA_NINGUNA
	for i in BombaModel.BOMBAS.size():
		if barco.get_node_or_null(BombaModel.BOMBAS[i]) == bomba:
			return i
	return BombaModel.BOMBA_NINGUNA


## Vacia las estaciones que quedaron a nombre de gente que ya no existe.
##
## Se llama al quedarse solo tras caerse el host, y arregla un encierro de
## partida entera: los `ocupante` y `portador_manguera` son ids de peers de la
## sesion muerta, asi que `arbitrar` contestaba OCUPADA para siempre y NADIE
## podia volver a achicar — con el barco hundiendose y sin un solo error. Y si
## alguien se quedo con `bombeando` puesto, la bomba seguia con la palanca
## apretada: no achica (la camara se llena y ahi se para) pero tampoco escupe, o
## sea que esa agua queda clavada contando para el umbral de naufragio.
##
## El unico peer que sobrevive al cambio a OFFLINE es el local, que pasa a ser 1.
func _liberar_estaciones_fantasma() -> void:
	for i in BombaModel.BOMBAS.size():
		var bomba := _bomba_de(i)
		if bomba == null:
			continue
		if bomba.ocupante != BombaModel.NADIE and bomba.ocupante != 1:
			bomba.aplicar_verbo(bomba.ocupante, BombaModel.Verbo.LIBERAR, null)
		if bomba.portador_manguera != BombaModel.NADIE and bomba.portador_manguera != 1:
			bomba.aplicar_verbo(bomba.portador_manguera,
				BombaModel.Verbo.SOLTAR_MANGUERA, null)


## Saca a un peer de todas las estaciones. Lo llama el host cuando alguien se va:
## sin esto, el que se desconecta deja la bomba ocupada PARA SIEMPRE y nadie mas
## puede achicar — con el barco hundiendose y sin un solo error en consola.
func _liberar_bombas_de(peer: int) -> void:
	for i in BombaModel.BOMBAS.size():
		var bomba := _bomba_de(i)
		if bomba == null:
			continue
		if bomba.portador_manguera == peer:
			_ejecutar_bomba(i, peer, BombaModel.Verbo.SOLTAR_MANGUERA)
			_aplicar_bomba.rpc(i, peer, BombaModel.Verbo.SOLTAR_MANGUERA)
		if bomba.ocupante == peer:
			_ejecutar_bomba(i, peer, BombaModel.Verbo.LIBERAR)
			_aplicar_bomba.rpc(i, peer, BombaModel.Verbo.LIBERAR)


## Un cuerpo que entra en una mano, un gancho o un cinturon DEJA de moverse
## por snapshots: su sitio lo dice el socket del que cuelga.
##
## Olvidarse de esto era el bug mas caro de R1, y no hacia falta ninguna
## carrera de paquetes para verlo: al agarrar, `_buffers[id]` YA tiene hasta
## ocho snapshots legitimos de cuando el cuerpo estaba suelto, el host deja de
## mandar mas (los no-SUELTO no entran en el lote) y `muestrear_buffer` CLAMPA
## al ultimo en vez de apagarse. Resultado: `_aplicar_cuerpos` devolvia el
## objeto a la cubierta cada tick, el compañero caminaba con la mano vacia y
## el farol se quedaba soldado al suelo. Con el cuerpo ya DORMIDO era peor:
## `_reposo` no se poda NUNCA, asi que se quedaba clavado para siempre.
func _soltar_replicacion(id: int) -> void:
	_buffers.erase(id)
	_reposo.erase(id)


## Resuelve un socket: los del jugador cuelgan del Player de `peer`, los del
## barco cuelgan del casco. Los DOS soportes de caña se llaman IGUAL, asi que
## esto va SIEMPRE por indice y nunca por nombre.
func _nodo_de_socket(peer: int, id_socket: int) -> Node3D:
	if id_socket < 0 or id_socket >= NetPorteo.SOCKETS.size():
		return null
	var base: Node3D = _jugador_de(peer) if NetPorteo.socket_es_del_jugador(id_socket) \
		else _barco()
	if base == null:
		return null
	return base.get_node_or_null(NetPorteo.SOCKETS[id_socket]) as Node3D


## En que socket esta un portable AHORA MISMO. Lo necesita la foto del mundo:
## sin el indice, quien se une no puede reconstruir de que gancho cuelga el
## farol — y con dos soportes de caña llamados igual, el nombre no basta.
func _socket_actual(p: Portable3D) -> int:
	if p == null:
		return NetPorteo.SOCKET_NINGUNO
	match p.estado:
		Portable3D.Estado.EN_MANO:
			return NetPorteo.socket_de_mano(p.manos)
		Portable3D.Estado.EN_CINTURON:
			return NetPorteo.socket_de_cinturon(maxi(p.hueco_cinturon, 0))
		Portable3D.Estado.COLGADO:
			var barco := _barco()
			if barco != null and p.gancho != null:
				for i in range(NetPorteo.SOCKET_DEL_BARCO, NetPorteo.SOCKETS.size()):
					if barco.get_node_or_null(NetPorteo.SOCKETS[i]) == p.gancho:
						return i
	return NetPorteo.SOCKET_NINGUNO


func _jugador_de(peer: int) -> Node3D:
	if peer == multiplayer.get_unique_id() or not en_red():
		return _jugador_local()
	var copia: Node3D = _remotos.get(peer)
	if is_instance_valid(copia):
		return copia
	# La copia se crea AQUI si hace falta, y no solo cuando llega el primer
	# `_estado_jugador`. Sin esto, el censo del `hola` no podia colocar nada
	# que estuviera en una mano: `_hola` llega ANTES que cualquier estado de
	# jugador, asi que `_remotos` estaba vacio y el farol del compañero se
	# quedaba en el suelo con `_dueno` a nadie — y como el host no vuelve a
	# mandar su transform (no esta SUELTO), ahi se quedaba.
	if peer <= 0 or not en_red():
		return null
	_spawn_remoto(peer)
	copia = _remotos.get(peer)
	return copia if is_instance_valid(copia) else null


## Cuantas manos tiene ocupadas ese peer AHORA MISMO, segun el censo del host
## (que es la unica verdad). El Portador del cliente no vale: con el agarre
## pesimista, en la ventana de ida y vuelta el cliente todavia no sabe que ya
## tiene algo.
## Manos que tiene ocupadas un peer, SEGUN EL HOST. Es la entrada del arbitraje,
## asi que tiene que contar lo mismo que `Player.hands_used` cuenta en la maquina
## de ese jugador: si no, el host autoriza lo que el solitario deniega y la
## "unica version de las reglas" se parte en dos sin que nada falle.
##
## Ese fue exactamente el bug: la cuenta solo miraba `_dueno` (los portables en
## la mano), asi que para el host alguien con las dos manos en la palanca tenia
## CERO manos ocupadas — y podia ademas llevar el colador, sacar del cinturon y
## lanzar la caña mientras bombeaba.
func _manos_usadas_de(peer: int) -> int:
	var usadas: int = 0
	for id: int in _dueno:
		if int(_dueno[id]) != peer:
			continue
		var p := cuerpo_de(id) as Portable3D
		if p != null and p.estado == Portable3D.Estado.EN_MANO:
			usadas += p.manos
	return usadas + _manos_en_estaciones_de(peer)


## Lo que le ocupan las estaciones: la palanca son dos manos, el cabezal una.
func _manos_en_estaciones_de(peer: int) -> int:
	var usadas: int = 0
	for i in BombaModel.BOMBAS.size():
		var bomba := _bomba_de(i)
		if bomba == null:
			continue
		if bomba.ocupante == peer:
			usadas += BombaModel.MANOS_BOMBEAR
		if bomba.portador_manguera == peer:
			usadas += BombaModel.MANOS_MANGUERA
	return usadas


func _huecos_libres_de(peer: int) -> int:
	var usados: int = 0
	for id: int in _dueno:
		if int(_dueno[id]) != peer:
			continue
		var p := cuerpo_de(id) as Portable3D
		if p != null and p.estado == Portable3D.Estado.EN_CINTURON:
			usados += 1
	return maxi(Portador.CINTURON_HUECOS - usados, 0)


func _portador_local() -> Portador:
	var yo := _jugador_local()
	if yo == null:
		return null
	return yo.get_node_or_null(^"Camera3D/Portador") as Portador


# =============================================================================
#  El pez: la especie la decide quien PESCA, el host ratifica
# =============================================================================

## El cliente que peleo el pez ya lleva treinta segundos viendo su nombre en
## el HUD: si el host re-sorteara la especie, el jugador habria peleado media
## pelea contra un Fletan para sacar una Sardina. Eso es feedback que MINTIO
## (regla 8). El host RATIFICA y le pone id; no re-decide. Es un coop de
## amigos: no hay nada que hacer trampa.
func pedir_pez(indice_especie: int, pos: Vector3, vel: Vector3, giro: Vector3) -> bool:
	if not en_red():
		return false
	if rol == Rol.HOST:
		_parir_pez(indice_especie, pos, vel, giro)
	else:
		_pedir_pez.rpc_id(1, indice_especie, pos, vel, giro)
	return true


@rpc("any_peer", "call_remote", "reliable")
func _pedir_pez(indice_especie: int, pos: Vector3, vel: Vector3, giro: Vector3) -> void:
	if rol != Rol.HOST:
		return
	_parir_pez(indice_especie, pos, vel, giro)


func _parir_pez(indice_especie: int, pos: Vector3, vel: Vector3, giro: Vector3) -> void:
	var id := _proximo_id_dinamico
	_proximo_id_dinamico += 1
	_nacer_pez(id, indice_especie, pos, vel, giro)
	_nacer_pez.rpc(id, indice_especie, pos, vel, giro)


@rpc("authority", "call_remote", "reliable")
func _nacer_pez(id: int, indice_especie: int, pos: Vector3, vel: Vector3,
		giro: Vector3) -> void:
	if _demorar(NetLag.Canal.FIABLE, _nacer_pez, [id, indice_especie, pos, vel, giro]):
		return
	if _cuerpos.has(id) or indice_especie < 0 \
			or indice_especie >= FishSpecies.SPECIES.size():
		return
	var escena := load("res://game/fishing/fish.tscn") as PackedScene
	if escena == null:
		return
	var pez := escena.instantiate() as Fish
	# El orden importa: `Fish.setup` recorre `get_children()` a mano en vez de
	# la cache de sondas, precisamente para ser correcto en instantiate ->
	# add_child -> setup. Se respeta el mismo orden que usa `_land`.
	get_tree().current_scene.add_child(pez)
	pez.setup(FishSpecies.SPECIES[indice_especie])
	pez.global_position = pos
	pez.linear_velocity = vel
	pez.angular_velocity = giro
	registrar_cuerpo(pez, id)
	_especies[id] = indice_especie
	if rol == Rol.CLIENTE:
		_congelar_replicado(pez)


@rpc("authority", "call_remote", "reliable")
func _muere_pez(id: int) -> void:
	if _demorar(NetLag.Canal.FIABLE, _muere_pez, [id]):
		return
	var cuerpo := cuerpo_de(id)
	olvidar_cuerpo(id)
	if cuerpo != null:
		cuerpo.queue_free()


## HOST: el pez que se fue a la deriva deja de costar bytes. Nunca uno en
## cubierta ni en la bodega — `Bodega` indexa por INSTANCIA, asi que liberar y
## recrear le descontaria y le volveria a contar en silencio.
func _vigilar_peces() -> void:
	var barco := _barco()
	if barco == null:
		return
	for id: int in _cuerpos.keys():
		if id < NetPorteo.ID_DINAMICO_BASE:
			continue
		var pez := cuerpo_de(id) as Fish
		if pez == null:
			continue
		if pez.estado != Portable3D.Estado.SUELTO or dueno_de(id) != NetPorteo.NADIE:
			continue
		if Ocean.get_submersion(pez.global_position) <= 0.0:
			continue # esta en cubierta: es botin, no basura
		if pez.global_position.distance_to(barco.global_position) < DESPAWN_PEZ_M:
			continue
		_muere_pez(id)
		_muere_pez.rpc(id)


func _indice_especie(cuerpo: Node3D) -> int:
	return int(_especies.get(id_de(cuerpo), -1))


# =============================================================================
#  El mar: los eventos y el HUD de debug
# =============================================================================

## Los mandos del HUD de debug que MUTAN estado global. Bloquearlos en el
## cliente rompe el juguete (CLAUDE.md: la perilla de furia en manos de
## alguien haciendo de dios ES la herramienta de validacion de F1); dejarlos
## divergir rompe el mar. Reenviarlos al host es lo unico honesto — y en un
## coop de amigos, que cualquiera pueda tirar un tsunami es una FEATURE.
## APPEND-ONLY: el valor viaja por el cable, asi que insertar en medio le cambia
## el numero a todo lo que venga detras y dos versiones dejarian de entenderse.
enum Debug { FURIA, FURIA_YA, LLUVIA, HORA, LIMPIAR, REFLOTE, PARTE, PARTE_OFF }


## Devuelve true si la peticion viajo (y el llamador no debe mutar nada).
func pedir_debug(que: int, valor: float) -> bool:
	if not en_red():
		return false
	if rol == Rol.HOST:
		_aplicar_debug(que, valor)
		return true
	_pedir_debug.rpc_id(1, que, valor)
	return true


@rpc("any_peer", "call_remote", "reliable")
func _pedir_debug(que: int, valor: float) -> void:
	if rol != Rol.HOST:
		return
	_aplicar_debug(que, valor)


func _aplicar_debug(que: int, valor: float) -> void:
	match que:
		Debug.FURIA:
			# El propio Ocean DESCARTA el guion al escribirle la furia (la mano
			# borra y lo suyo manda), y su señal `parte_cambiado` — ver
			# `_on_parte_cambiado` — difunde ese borrado a toda la tripulacion.
			# Aqui solo se escribe el valor.
			Ocean.fury = valor
		Debug.FURIA_YA:
			Ocean.set_fury_immediate(valor)
		Debug.LLUVIA:
			Ocean.rain_level = valor
		Debug.HORA:
			var ciclo := _dia_noche()
			if ciclo != null:
				ciclo.set_debug_hour(valor)
			_estado_dia.rpc(valor)
		Debug.LIMPIAR:
			Ocean.clear_events()
			_limpiar_eventos.rpc()
		Debug.REFLOTE:
			_reflotar_barco()
		Debug.PARTE:
			# El guion NO se puede regenerar en cada maquina a partir del techo:
			# `generar_parte` lo escribe desde la furia y el reloj DE QUIEN LO
			# PIDE, y esos dos numeros difieren entre maquinas. Se genera una
			# vez aqui y viaja la curva entera — medio kilobyte, una sola vez.
			var nuevo := Ocean.generar_parte(valor)
			_evento_parte.rpc(nuevo.empaquetar())
		Debug.PARTE_OFF:
			Ocean.limpiar_parte()
	# La furia y la lluvia viajan solas en el goteo de `_estado_mar` (10 Hz),
	# salvo con parte en vigor: ahi las dos salen del guion en cada maquina y
	# el goteo se ignora (ver `Ocean.set_fury_red`).


## El guion del clima, tal cual. Un diccionario vacio lo apaga.
##
## Viaja la CURVA y no la receta (semilla + techo) a proposito: un parte puede
## venir tambien de un director que lo escribio a mano, y entonces no hay receta
## que mandar. La curva es la verdad en los dos casos, y ademas hace imposible
## que dos maquinas generen partes que se parezcan pero no sean iguales.
@rpc("authority", "call_remote", "reliable")
func _evento_parte(datos: Dictionary) -> void:
	if _demorar(NetLag.Canal.FIABLE, _evento_parte, [datos]):
		return
	if datos.is_empty():
		Ocean.limpiar_parte()
		return
	var p := ParteMeteorologico.new()
	p.desempaquetar(datos)
	Ocean.fijar_parte(p)


## El guion murio en el host y hay que contarlo.
##
## `Ocean` DESCARTA el parte en cuanto alguien le escribe la furia a mano
## (decision de diseño 2026-08-24: la mano borra y lo suyo manda), y esa
## escritura puede venir de cualquiera — el otro escritor de `Ocean.fury` del
## repo es `TsunamiDirector._update_sea()`, que lo hace cada tick. Si el
## borrado no viajara, el host quedaria en carril manual goteando su furia
## mientras cada cliente la ignora por tener SU copia del parte en vigor:
## mares, lluvias y tormentas electricas distintas en cada pantalla, sin un
## solo error en consola.
##
## Se cierra por donde tenia que cerrarse: `Ocean` avisa con su señal y la
## capa de RED decide que eso se propaga. Difundir un borrado a clientes que
## ya no tienen parte es idempotente, asi que no hace falta saber el motivo.
func _on_parte_cambiado() -> void:
	if rol != Rol.HOST or not en_red():
		return
	if Ocean.parte() == null:
		_evento_parte.rpc({})


## Lanza un tsunami de forma que las seis maquinas vean LA MISMA ola: el host
## recalcula el objetivo con SU barco (el del cliente es la copia interpolada,
## otro origen) y clava el `t0` para que la onda no salga tarde en nadie.
func pedir_tsunami(target: Vector3, desde_deg: float, segundos: float,
		tier: TsunamiTier) -> bool:
	if not en_red() or rol != Rol.HOST or tier == null:
		return false
	var t0 := Ocean.sim_time
	var barco := _barco()
	var objetivo := barco.global_position if barco != null else target
	Ocean.spawn_tsunami_tier(objetivo, desde_deg, segundos, tier, t0)
	_evento_tsunami.rpc(objetivo, desde_deg, segundos, tier.resource_path, t0)
	return true


## Un CLIENTE haciendo de dios con el HUD de debug. El objetivo no viaja: lo
## pone el host con SU barco, porque el del cliente es la copia interpolada y
## esta en otro sitio. Menos bytes y ademas correcto.
func pedir_tsunami_cliente(desde_deg: float, segundos: float,
		tier: TsunamiTier) -> bool:
	if rol != Rol.CLIENTE or tier == null:
		return false
	_pedir_tsunami.rpc_id(1, desde_deg, segundos, tier.resource_path)
	return true


@rpc("any_peer", "call_remote", "reliable")
func _pedir_tsunami(desde_deg: float, segundos: float, ruta_tier: String) -> void:
	if rol != Rol.HOST:
		return
	var tier := load(ruta_tier) as TsunamiTier
	if tier == null:
		return
	pedir_tsunami(Vector3.ZERO, desde_deg, segundos, tier)


@rpc("authority", "call_remote", "reliable")
func _evento_tsunami(target: Vector3, desde_deg: float, segundos: float,
		ruta_tier: String, t0: float) -> void:
	if _demorar(NetLag.Canal.FIABLE, _evento_tsunami,
			[target, desde_deg, segundos, ruta_tier, t0]):
		return
	var tier := load(ruta_tier) as TsunamiTier
	if tier == null:
		push_warning("Net: no pude cargar el tier '%s'." % ruta_tier)
		return
	Ocean.spawn_tsunami_tier(target, desde_deg, segundos, tier, t0)


@rpc("authority", "call_remote", "reliable")
func _limpiar_eventos() -> void:
	if _demorar(NetLag.Canal.FIABLE, _limpiar_eventos, []):
		return
	Ocean.clear_events()


## Cuenta a los demas que una ola acaba de embarcar. En solitario no hace nada:
## la señal local ya la emitio `AguaEmbarcada`.
func avisar_ola_sobre_borda(intensidad: float, indice_punto: int) -> void:
	if not en_red() or rol != Rol.HOST:
		return
	_ola_sobre_borda.rpc(NetAgua.cuantizar_intensidad(intensidad), indice_punto)


## Los ocho niveles de inundacion del barco. Va sin fiabilidad y ORDENADO: es un
## estado que se reemplaza entero cuatro veces por segundo, asi que perder uno no
## importa, pero recibir uno viejo despues de uno nuevo haria retroceder el agua
## a ojos del cliente.
@rpc("authority", "call_remote", "unreliable_ordered")
func _estado_agua(datos: PackedByteArray) -> void:
	if _demorar(NetLag.Canal.ORDENADO, _estado_agua, [datos]):
		return
	var barco := _barco()
	if barco == null or not barco.has_method(&"fijar_inundacion"):
		return
	var estado := NetAgua.desempaquetar(datos)
	barco.fijar_inundacion(estado[&"niveles"])
	var agua := _agua_embarcada()
	if agua != null:
		agua.aplicar_estado_remoto(bool(estado[&"alarma"]), bool(estado[&"naufragio"]))
	_aplicar_camaras(int(estado[&"camaras"]))


## Una ola acaba de embarcar por un punto de la borda. Es COSMETICO (audio y
## spray), asi que va sin fiabilidad y sin orden: si se pierde, lo unico que pasa
## es que un chapoteo no suena. Lo que de verdad importa —cuanta agua entro— ya
## viaja en `_estado_agua`.
@rpc("authority", "call_remote", "unreliable")
func _ola_sobre_borda(intensidad_u8: int, indice_punto: int) -> void:
	if _demorar(NetLag.Canal.ORDENADO, _ola_sobre_borda, [intensidad_u8, indice_punto]):
		return
	var agua := _agua_embarcada()
	if agua != null:
		agua.ola_sobre_borda.emit(
			NetAgua.descuantizar_intensidad(intensidad_u8), indice_punto)


## Devuelve el barco a la superficie, seco y adrizado. Lo ejecuta el HOST y lo
## difunde: el agua es host-autoritativa, asi que un reflote solo local dejaria
## al cliente con su copia inundada hasta el siguiente estado.
func _reflotar_barco() -> void:
	var agua := _agua_embarcada()
	if agua == null:
		return
	agua.reflotar()
	# El teleport tiene que llegar tambien a los clientes, y ANTES que nada hay
	# que tirar su buffer de interpolacion: si no, siguen muestreando las
	# posiciones de hace 120 ms y arrastran el barco de vuelta al fondo durante
	# una decima, con su chapuzon y su slam de regalo.
	if rol == Rol.HOST:
		_reflote.rpc()


@rpc("authority", "call_remote", "reliable")
func _reflote() -> void:
	if _demorar(NetLag.Canal.FIABLE, _reflote, []):
		return
	_buffer_barco.clear()
	var agua := _agua_embarcada()
	if agua != null:
		agua.reflotar()


func _agua_embarcada() -> AguaEmbarcada:
	var barco := _barco()
	if barco == null:
		return null
	return barco.get_node_or_null(^"AguaEmbarcada") as AguaEmbarcada


@rpc("authority", "call_remote", "reliable")
func _estado_dia(offset_horas: float) -> void:
	if _demorar(NetLag.Canal.FIABLE, _estado_dia, [offset_horas]):
		return
	var ciclo := _dia_noche()
	if ciclo != null:
		ciclo.set_debug_hour(offset_horas)


func _dia_noche() -> DayNightCycle:
	var escena := get_tree().current_scene
	if escena == null:
		return null
	return escena.get_node_or_null(^"DayNightCycle") as DayNightCycle


## Los directores de tsunami del cliente se callan: los autoloads procesan
## ANTES que la escena, asi que `_update_sea()` seria la ULTIMA escritura de
## `Ocean.fury` y `rain_scale` de cada tick y ganaria siempre al goteo del
## host. Y con `loop`, su `start()` —que llama `clear_events()`— borraria el
## tsunami del host a mitad de vuelo, sin recuperacion posible.
func _ceder_directores() -> void:
	var escena := get_tree().current_scene
	if escena == null:
		return
	for nodo: Node in escena.find_children("*", "TsunamiDirector", true, false):
		(nodo as TsunamiDirector).ceder_al_host()


# =============================================================================
#  Estado inicial y utilidades
# =============================================================================

## El censo entero que manda el host al entrar: quien lleva que, y donde esta
## lo demas. Sin esto, quien se une a mitad de partida ve el mundo en su
## posicion de escena y los objetos en las manos de nadie.
func _aplicar_foto(foto: Array) -> void:
	for fila: Array in foto:
		if fila.size() < 8:
			continue
		var id := int(fila[0])
		var estado := int(fila[1])
		var peer := int(fila[2])
		var id_socket := int(fila[3])
		var indice := int(fila[7])
		if indice >= 0 and not _cuerpos.has(id):
			_nacer_pez(id, indice, fila[5] as Vector3, Vector3.ZERO, Vector3.ZERO)
		var destino := Transform3D(Basis(fila[6] as Quaternion), fila[5] as Vector3)
		_ejecutar_porteo(id, peer, estado, id_socket, Vector3.ZERO, destino)


## `farol.gd` es la UNICA lectura de autoridad del repo, y sin marcarla el
## default de Godot (peer 1) hace que el farol del cliente deje de proyectar
## sombras en silencio — y que en el host la copia remota SI salga autoridad,
## o sea que el host le regalaria su unica sombra al farol de otro.
func _marcar_autoridad_local() -> void:
	var yo := _jugador_local()
	if yo != null:
		yo.set_multiplayer_authority(multiplayer.get_unique_id())


## Una linea por cuerpo de RPC. Devuelve true si el mensaje quedo encolado en
## el simulador de latencia y el cuerpo NO debe ejecutarse todavia.
func _demorar(canal: int, metodo: Callable, args: Array) -> bool:
	if _lag == null:
		return false
	return _lag.encolar(canal, Time.get_ticks_msec() * 0.001, metodo, args)


# =============================================================================
#  Las copias de los demas
# =============================================================================

func _aplicar_remotos(delta: float) -> void:
	var barco := _barco()
	if barco == null:
		return
	for peer: int in _estados.keys():
		if not _remotos.has(peer):
			_spawn_remoto(peer)
		var copia: Player = _remotos.get(peer)
		if copia == null or not is_instance_valid(copia):
			continue
		var e: Array = _estados[peer]
		var objetivo := NetMath.a_mundo(barco.global_transform,
			Transform3D(Basis.from_euler(Vector3(0.0, float(e[1]), 0.0)), e[0]))
		# 20 Hz -> render: un perseguidor corto. Interpolar de verdad (buffer
		# por jugador) es R1; para F1 el suavizado basta y no acumula retardo.
		copia.global_transform = copia.global_transform.interpolate_with(
			objetivo, clampf(14.0 * delta, 0.0, 1.0))
		if copia.animator != null:
			copia.animator.update(float(e[2]), float(e[3]), bool(e[4]), delta)
		# Las manos del compañero: la caña se esconde de SU viewmodel cuando
		# portea, igual que en el tuyo.
		if e.size() > 5:
			copia.hands_used = int(e[5])


## La copia visible de otro jugador: el MISMO player.tscn con la simulacion
## apagada.
##
## Su PORTADOR se queda VIVO pero en `modo_presentacion`: los markers de
## agarre tienen que existir y ser visibles —el principio 1 de PORTEO dice que
## lo que llevas se VE, y ahi es donde cuelgan los objetos replicados—, pero
## no puede leer input. Es la pieza mas delicada de R1: `_paso_lanzamiento`
## consulta `Input.is_action_just_pressed` GLOBAL dentro de `_physics_process`,
## asi que un Portador remoto despierto agarraria cosas con TU raton, en las
## cinco copias a la vez.
##
## La caña, en cambio, sigue apagada del todo: replicar su maquina de pesca es
## trabajo de otra fase.
func _spawn_remoto(peer: int) -> void:
	var escena := load("res://game/player/player.tscn") as PackedScene
	if escena == null:
		return
	var copia := escena.instantiate() as Player
	copia.name = "JugadorRemoto%d" % peer
	# `Player._ready` recaptura el raton: sin guardar y restaurar el modo, cada
	# jugador que entra te lo secuestra a mitad de partida.
	var raton := Input.mouse_mode
	get_tree().current_scene.add_child(copia)
	Input.mouse_mode = raton
	copia.set_physics_process(false)
	copia.set_process_unhandled_input(false)
	copia.set_multiplayer_authority(peer)
	var cam := copia.get_node_or_null(^"Camera3D") as Camera3D
	if cam != null:
		cam.current = false
	var cana := copia.get_node_or_null(^"Camera3D/FishingRod")
	if cana != null:
		cana.process_mode = Node.PROCESS_MODE_DISABLED
		if cana is Node3D:
			(cana as Node3D).visible = false
		# Los HUD de las herramientas son CanvasLayer: esconderlos aparte,
		# porque la visibilidad 3D no los alcanza.
		for capa: Node in cana.find_children("*", "CanvasLayer", true, false):
			(capa as CanvasLayer).visible = false
	var portador := copia.get_node_or_null(^"Camera3D/Portador") as Portador
	if portador != null:
		portador.modo_presentacion = true
	copia.set_body_visible(true)
	# Y la camara local vuelve a mandar: instanciar `player.tscn` trae dentro
	# una Camera3D con `current = true` que se roba la vista al entrar.
	var mia := _jugador_local()
	if mia != null:
		var cam_local := mia.get_node_or_null(^"Camera3D") as Camera3D
		if cam_local != null:
			cam_local.current = true
	_remotos[peer] = copia


func _despedir(peer: int) -> void:
	var copia: Player = _remotos.get(peer)
	if copia != null and is_instance_valid(copia):
		# `queue_free` se lleva el SUBARBOL entero: un portable reparentado
		# bajo su marker de agarre o su cinturon se iria con la copia y
		# dejaria de existir para todos, sin un solo error. El host ya difundio
		# el vaciado de manos antes del adios; esto es el seguro de vida por si
		# ese mensaje se cruzo o el peer se fue de golpe.
		for hijo: Node in copia.find_children("*", "Portable3D", true, false):
			var p := hijo as Portable3D
			var mundo := p.global_transform
			p.soltar(get_tree().current_scene)
			p.global_transform = mundo
			if rol == Rol.CLIENTE:
				_congelar_replicado(p)
		copia.queue_free()
	_remotos.erase(peer)
	_estados.erase(peer)
	_visto_jugador.erase(peer)


# =============================================================================
#  El mundo local segun el rol
# =============================================================================

## Contrato 3: el barco del cliente es del host. Congelado KINEMATICO (la
## cubierta sigue reportando velocidad a los contactos) y con el
## _physics_process del FloatingBody3D apagado — la misma disciplina que un
## Portable3D en la mano: sin esto, el empuje del oceano se acumula en
## silencio sobre un cuerpo congelado.
func _congelar_barco_local() -> void:
	var barco := _barco()
	if barco == null:
		return
	barco.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	barco.freeze = true
	barco.set_physics_process(false)


func _barco() -> RigidBody3D:
	if _barco_cache != null and is_instance_valid(_barco_cache):
		return _barco_cache
	var escena := get_tree().current_scene
	if escena == null:
		return null
	_barco_cache = escena.get_node_or_null(^"FishingBoat") as RigidBody3D
	return _barco_cache


func _jugador_local() -> Player:
	var escena := get_tree().current_scene
	if escena == null:
		return null
	return escena.get_node_or_null(^"Player") as Player


# =============================================================================
#  El overlay: una linea que dice quien sos
# =============================================================================

func _refrescar_overlay() -> void:
	if _overlay == null:
		_overlay = CanvasLayer.new()
		_overlay.name = "NetOverlay"
		_overlay.layer = 9
		add_child(_overlay)
		_overlay_label = Label.new()
		var ls := LabelSettings.new()
		ls.font = GameTypography.ui_regular()
		ls.font_size = 15
		ls.font_color = Color(0.85, 0.9, 0.94)
		ls.outline_size = 6
		ls.outline_color = Color(0.05, 0.07, 0.1)
		_overlay_label.label_settings = ls
		_overlay_label.position = Vector2(12, 10)
		_overlay_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_overlay.add_child(_overlay_label)
	var texto := ""
	match rol:
		Rol.OFFLINE:
			texto = ""
		Rol.HOST:
			var abordo: int = 1 + multiplayer.get_peers().size()
			texto = "RED — host · %d a bordo   (F9 abrió el puerto %d)" % [abordo, PUERTO]
		Rol.CLIENTE:
			texto = "RED — cliente" + ("" if _tiene_hola else " · conectando...")
	# Un mundo con lag falso que no se anuncia miente igual que uno
	# desincronizado (regla 8).
	if _lag != null and _lag.activo() and not texto.is_empty():
		texto += "   ·   " + _lag.resumen()
	if not texto.is_empty() and _cuerpos.size() > 0:
		texto += "   ·   %d cuerpos" % _cuerpos.size()
	_overlay_label.text = texto
