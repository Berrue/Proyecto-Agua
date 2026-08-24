class_name ManualBilgePump
extends Node3D

## Estacion modular de achique manual, independiente del barco y del Player.
##
## Conserva el contrato de montaje y expone el cabezal de aspiracion agarrable;
## la palanca y el testigo de cadencia siguen siendo piezas separadas para poder
## sumarles el ritmo de bombeo sin rehacer el arte.
##
## [b]Ya achica, y en dos tiempos.[/b] Mantener la palanca CHUPA agua de LA CELDA
## donde este el cabezal de la manguera —no del barco en abstracto— hacia la
## camara; soltarla la ESCUPE al mar por la manguera de descarga. Elegir que
## compartimento vaciar primero es la decision del achicador (docs/DISENO.md), y
## por eso el modulo pregunta por indice de celda y no sabe ni como se llaman.
##
## Mientras el agua esta en la camara sigue contando como agua a bordo: el barco
## no se alivia por chupar, se alivia por escupir. Lo que si cambia al chupar es
## el REPARTO — la celda anegada se vacia y el barco se endereza —, asi que cada
## tiempo tiene su propio feedback. El porque completo, en [BombaModel].
##
## Quien decide (arbitraje y caudal) es [BombaModel], puro y testeable; quien
## manda en red es siempre el HOST.

signal hose_taken(grip: Node3D)
signal hose_released
signal manguera_tomada_por(portador: Node3D)
signal manguera_soltada
signal tension_manguera_cambiada(valor01: float)
signal longitud_maxima_alcanzada
signal estacion_cambiada(ocupante: int)
signal bombeo_cambiado(activo: bool)
## Una embolada que movio agua (o que chupo aire, con `con_agua` en false). Para
## el audio, el chorro y el traqueteo.
signal embolada(con_agua: bool)
## La bomba cambio de modo. Para el arte del selector, el sonido, y —cuando
## exista el ragdoll— el empujon del chorro a quien se ponga delante.
signal modo_cambiado(modo: int)

const FOOTPRINT_METERS := Vector2(0.70, 1.00)
const MOUNT_PLANE_Y := -0.25

## Los dos modos del selector. SUCCION traga, EXTRACCION suelta.
enum Modo { SUCCION = 0, EXTRACCION = 1 }

## Cadencia de la palanca, en segundos por embolada. 0,75 s es el vaiven comodo
## de una bomba de sentina de brazo largo: bastante lento para que se oiga cada
## golpe y para que se vea el esfuerzo. Ya no es solo el pulso de presentacion:
## es lo que TARDA la camara en llenarse, asi que el ritmo que el arte pedia y el
## ritmo que la mecanica premia son el mismo numero.
const SEGUNDOS_POR_EMBOLADA := 0.75

@export_group("Cableado")
@export var hose_path: NodePath = ^"HoseAssembly"
@export var stored_coil_path: NodePath = ^"StoredCoil"

@export_group("Achique")
## Que fraccion del caudal saca una persona sola, sin nadie que dirija el
## cabezal. El 50 % de DISENO.md, y no es un candado: el colador suelto se tumba
## con el cabeceo y media embolada aspira aire.
##
## Es la fraccion del CICLO COMPLETO, no un multiplicador de la aspiracion:
## `BombaModel.factor_aspiracion_solo` hace la conversion, porque el tiempo de
## escupir no se entera de quien sostiene el cabezal.
@export_range(0.0, 1.0) var factor_solo: float = 0.5

## Los dos tiempos, como multiplos del caudal medio del balance del agua. El
## caudal NO se escribe aqui: vive en `agua_embarcada.tres` y solo ahi, porque
## entrada y salida son los dos lados de la misma balanza y el punto de
## equilibrio ES el dial de dificultad. Estos factores dicen como se reparte ese
## caudal entre chupar y escupir; los tiers de bomba los multiplicaran.
@export var factor_succion: float = BombaModel.FACTOR_TIEMPO
@export var factor_descarga: float = BombaModel.FACTOR_TIEMPO

## Cuanto rato se bombea antes de llenar el deposito. Es EL numero del ritmo: no
## decide cuanta agua sacas por minuto —eso lo marca la palanca—, decide cada
## cuanto hay que parar, cambiar el selector y llevarse la manguera a la borda.
## Y mientras uno vacia esta expuesto, que es de donde sale la tension.
@export var segundos_de_deposito: float = 8.0

var _hose: Node
var _stored_coil: Node3D

## Peer que ocupa la estacion, 0 si nadie (convencion `BombaModel.NADIE`).
var ocupante: int = BombaModel.NADIE
## Peer que lleva el cabezal, 0 si nadie.
var portador_manguera: int = BombaModel.NADIE
## La palanca: mientras esta accionada, el deposito se LLENA.
var bombeando: bool = false
## En que esta puesto el selector. En SUCCION la palanca llena el deposito; en
## EXTRACCION el agua sale sola por la manguera, sin tocar la palanca — por eso
## vaciar lo puede hacer una persona sola y llenar va mejor de a dos.
var modo: int = Modo.SUCCION

## Agua que la bomba tiene chupada y todavia no ha escupido, en unidades de nivel
## MEDIO del barco. Publica porque es lo que la pesa del testigo va a mostrar
## cuando entre el feel, y lo que `AguaEmbarcada` suma al nivel a bordo.
##
## ⚠️ HOST-ONLY: no viaja por el cable y en un cliente se mantiene en cero a
## proposito. Lo unico que hay replicado del agua son los ocho niveles de celda.
var carga_deposito: float = 0.0

var _barco: FloatingBody3D
var _agua: AguaEmbarcada
var _balance: AguaEmbarcadaBalance
var _celda_actual: int = -1
var _acum_embolada: float = 0.0
var _movio_agua: bool = false
var _deposito_lleno_remoto: bool = false
var _media_manga: float = 0.0
var _media_eslora: float = 0.0


func _ready() -> void:
	_hose = get_node_or_null(hose_path)
	_stored_coil = get_node_or_null(stored_coil_path) as Node3D
	if _hose == null:
		push_error("ManualBilgePump necesita HoseAssembly para exponer el agarre.")
		return
	if _hose.has_signal("tomada"):
		_hose.connect("tomada", _on_hose_taken)
	if _hose.has_signal("soltada"):
		_hose.connect("soltada", _on_hose_released)
	if _hose.has_signal("tension_changed"):
		_hose.connect("tension_changed", _on_hose_tension_changed)
	if _hose.has_signal("max_length_reached"):
		_hose.connect("max_length_reached", _on_hose_max_length_reached)


func _process(_delta: float) -> void:
	_update_stored_coil()


# =============================================================================
#  La estacion: quien la ocupa y quien la acciona
# =============================================================================

func estacion_libre() -> bool:
	return ocupante == BombaModel.NADIE


## Los verbos NO comprueban permisos: eso lo hace `BombaModel.arbitrar` en el
## host, que es el unico que ve todas las peticiones en un orden. Aqui solo se
## aplica el resultado, igual en las seis maquinas.
func ocupar_estacion(peer: int) -> void:
	if ocupante == peer:
		return
	ocupante = peer
	estacion_cambiada.emit(ocupante)


func liberar_estacion() -> void:
	if ocupante == BombaModel.NADIE:
		return
	ocupante = BombaModel.NADIE
	set_bombeando(false)
	estacion_cambiada.emit(ocupante)


## Aplica un verbo ya ARBITRADO. Es el punto por el que pasan los dos caminos —
## el host difundiendo por la red y el jugador solitario resolviendolo en su
## maquina— para que no existan dos versiones de "que significa OCUPAR" que
## puedan separarse. Aqui no se comprueba nada: quien decide es
## `BombaModel.arbitrar`.
##
## `grip` es el socket de mano del que toma el cabezal; se ignora en los demas
## verbos.
func aplicar_verbo(peer: int, verbo: int, grip: Node3D) -> void:
	match verbo:
		BombaModel.Verbo.OCUPAR:
			ocupar_estacion(peer)
		BombaModel.Verbo.LIBERAR:
			liberar_estacion()
		BombaModel.Verbo.ACCION_ON:
			set_bombeando(true)
		BombaModel.Verbo.ACCION_OFF:
			set_bombeando(false)
		BombaModel.Verbo.TOMAR_MANGUERA:
			if grip == null or not tomar_manguera(grip):
				return
			portador_manguera = peer
		BombaModel.Verbo.SOLTAR_MANGUERA:
			soltar_manguera()
			portador_manguera = BombaModel.NADIE
		BombaModel.Verbo.MODO_SUCCION:
			_fijar_modo(Modo.SUCCION)
		BombaModel.Verbo.MODO_EXTRACCION:
			_fijar_modo(Modo.EXTRACCION)


func set_bombeando(activo: bool) -> void:
	if bombeando == activo:
		return
	bombeando = activo and ocupante != BombaModel.NADIE
	_acum_embolada = 0.0
	bombeo_cambiado.emit(bombeando)


## La celda que esta achicando ahora mismo, o -1. Para el HUD de debug y los
## tests: es lo que hace visible que la manguera decide DONDE se saca el agua.
func celda_en_uso() -> int:
	return _celda_actual


## El ciclo. Corre SIEMPRE, no solo mientras alguien acciona: la camara tiene que
## poder vaciarse aunque el que bombeaba haya salido corriendo.
func _physics_process(delta: float) -> void:
	_celda_actual = -1
	# El agua es del HOST. En solitario `Net.rol` es OFFLINE y esto tambien
	# corre; en un cliente, no: alli el agua es un dato que llega por el cable.
	if Net != null and Net.rol == Net.Rol.CLIENTE:
		# Y la camara se tira, no se congela: si esta partida empezo en solitario
		# con agua chupada dentro, quedarse el numero significaria que al volver a
		# ser host (o al caerse el host) reapareceria agua de una vida anterior.
		# En un cliente la carga no es estado simulable — es un dato que hoy nadie
		# manda —, asi que el unico valor honesto es cero.
		carga_deposito = 0.0
		return
	_asegurar_barco()
	if _barco == null or _balance == null:
		return

	# El selector manda. En EXTRACCION el agua sale sola, sin palanca: por eso
	# vaciar es cosa de uno. En SUCCION solo entra agua mientras alguien bombea.
	if modo == Modo.EXTRACCION:
		_vaciar(delta)
	elif bombeando:
		_llenar(delta)
	_pulso_embolada(delta)


## MODO SUCCION: de la celda al deposito, mientras alguien da a la palanca.
##
## El agua sigue a bordo — lo que cambia es DONDE esta, y por eso el barco se
## endereza al llenar aunque el nivel no baje todavia.
func _llenar(delta: float) -> void:
	var celda := _barco.probe_index_at(posicion_toma_global())
	if celda < 0:
		return
	_celda_actual = celda
	var n := _barco.probe_count()
	# Sin nadie sujetando el colador, el castigo va DIRECTO al llenado: vaciar ya
	# es un modo aparte que hace una sola persona, asi que no hay que repartir la
	# penalizacion entre dos tiempos. El 50 % de DISENO es el 50 % del ritmo al
	# que se llena, y ya esta.
	var aspirado := BombaModel.paso_aspiracion(carga_deposito, capacidad_deposito(),
		_succion(), BombaModel.agua_de_celda(_barco.probe_flooding(celda), n),
		esta_manguera_tomada(), factor_solo, delta)
	if aspirado <= 0.0:
		return
	# Lo que la celda entrega de verdad manda sobre lo que se pidio: si la sonda
	# da menos, la camara se queda solo con eso. Apuntar lo pedido en vez de lo
	# entregado haria aparecer agua de la nada en el momento de escupirla.
	var sacado := _barco.drain_probe(celda, BombaModel.caudal_por_celda(aspirado, n))
	carga_deposito += BombaModel.agua_de_celda(sacado, n)
	_movio_agua = true


## MODO EXTRACCION: el deposito sale por la manguera como una manga de bombero.
## No hace falta bombear —se vacia solo—, asi que esto lo hace UNA persona: la
## que lleva el colador y lo saca por la borda.
##
## [b]Y adonde va el agua lo decide DONDE APUNTAS.[/b] Punta fuera del casco: al
## mar, y esa es la unica puerta por la que el agua abandona el barco. Punta
## dentro: cae en la celda que tenga debajo y no has arreglado nada — solo has
## movido el problema de sitio y mojado a quien pasara. Dejarse el selector en
## EXTRACCION con la manguera recogida vacia el deposito de vuelta en la
## cubierta, y eso no hay que prohibirlo: hay que dejar que se vea.
func _vaciar(delta: float) -> void:
	var soltado := BombaModel.paso_descarga(carga_deposito, _descarga(), delta)
	if soltado <= 0.0:
		return
	carga_deposito = maxf(carga_deposito - soltado, 0.0)
	_movio_agua = true
	if punta_fuera_del_casco():
		return
	var celda := _barco.probe_index_at(posicion_toma_global())
	if celda >= 0:
		_barco.flood_probe(celda,
			BombaModel.caudal_por_celda(soltado, _barco.probe_count()))


func _fijar_modo(nuevo: int) -> void:
	if modo == nuevo:
		return
	modo = nuevo
	modo_cambiado.emit(modo)


## ¿La punta de la manguera esta por fuera del casco? Se mide en planta contra el
## `HullShape` real y no contra un numero copiado: si el barco cambia de eslora,
## esto cambia con el.
func punta_fuera_del_casco() -> bool:
	if _barco == null:
		return false
	_asegurar_huella()
	var local := _barco.to_local(posicion_toma_global())
	return absf(local.x) > _media_manga or absf(local.z) > _media_eslora


func _asegurar_huella() -> void:
	if _media_manga > 0.0:
		return
	var casco := _barco.get_node_or_null(^"HullShape") as CollisionShape3D
	var caja := casco.shape as BoxShape3D if casco != null else null
	if caja == null:
		_media_manga = 2.7
		_media_eslora = 6.5
		return
	_media_manga = caja.size.x * 0.5
	_media_eslora = caja.size.z * 0.5


## Ritmo de cada tiempo. Se DERIVA del caudal del balance en vez de escribirse:
## el dial de dificultad tiene que vivir en un solo sitio.
func _succion() -> float:
	return _balance.caudal_bomba * factor_succion


func _descarga() -> float:
	return _balance.caudal_bomba * factor_descarga


## Lo que le cabe a la camara: una embolada de aspiracion.
## Lo que le cabe al deposito.
##
## Se mide en SEGUNDOS DE BOMBEO y no en litros, y no es por pereza: para que
## esta bomba aguante una tormenta tendria que mover unos 480 litros por segundo
## —un camion de bomberos, no una bomba de palanca—, asi que un numero de litros
## realista seria mentira. Lo que si es real, y es lo que se juega, es cuanto
## rato bombeas antes de tener que ir a vaciar.
func capacidad_deposito() -> float:
	if _balance == null:
		return 0.0
	return _succion() * segundos_de_deposito


## ¿Esta llena? Es la UNICA forma de fallar de esta mecanica que no se ve sola:
## chupar sobre una celda seca al menos deja el colador a la vista fuera del
## agua, pero con la camara llena la bomba deja de mover agua sin que cambie
## nada en pantalla. Alguien tiene que decirlo antes de que el jugador concluya
## que la bomba esta rota (regla 8).
func deposito_lleno() -> bool:
	# En un cliente NO se simula, asi que `carga_deposito` es cero y la cuenta
	# diria que no siempre: alli manda la bandera que llega por el cable.
	if Net != null and Net.rol == Net.Rol.CLIENTE:
		return _deposito_lleno_remoto
	var cabe := capacidad_deposito()
	return cabe > 0.0 and carga_deposito >= cabe - 1e-6


## Lo que dice el host. Solo la escribe la replica.
func fijar_deposito_lleno_remoto(llena: bool) -> void:
	_deposito_lleno_remoto = llena


## La embolada es el pulso de presentacion: sin ella el achique seria un chorro
## mudo y continuo, y lo que se quiere oir es el vaiven de la palanca. Lleva si
## el tramo movio agua, para poder distinguir el chof del sorbo en seco.
func _pulso_embolada(delta: float) -> void:
	# Nada moviendose: ni se acciona la palanca ni queda agua saliendo. La guarda
	# mira `bombeando` y NO `ocupante`, porque el caso corriente es justo el que
	# se colaba: alguien de pie en la bomba sin apretar, esperando a que llegue el
	# del colador, oyendo un traqueteo cada 0,75 s con la palanca quieta.
	if not bombeando and (modo != Modo.EXTRACCION or carga_deposito <= 0.0):
		_acum_embolada = 0.0
		_movio_agua = false
		return
	_acum_embolada += delta
	# El periodo es el de la CARRERA de esta bomba, no la constante: un tier con
	# la camara mas grande tiene emboladas mas largas, y el pulso tiene que ir con
	# el brazo o sonara a destiempo en cuanto haya audio.
	var periodo: float = maxf(SEGUNDOS_POR_EMBOLADA, 0.05)
	if _acum_embolada < periodo:
		return
	_acum_embolada -= periodo
	embolada.emit(_movio_agua)
	_movio_agua = false


## Tira el agua de la camara sin escupirla. SOLO para el reflote: al barco se le
## acaba de sacar toda el agua y devolverlo con la camara llena seria dejarle una
## gota de la vida anterior.
func vaciar_camara() -> void:
	carga_deposito = 0.0
	_acum_embolada = 0.0
	_movio_agua = false


## De donde saca el barco y su balance. Perezoso y no en `_ready` porque la bomba
## es un modulo: se instancia en su propia escena de test sin barco ninguno, y
## ademas Godot corre el `_ready` de los hijos ANTES que el del padre, asi que en
## ese momento el `FloatingBody3D` todavia no ha recogido sus sondas.
func _asegurar_barco() -> void:
	if _barco != null and is_instance_valid(_barco):
		return
	var n: Node = get_parent()
	while n != null:
		if n is FloatingBody3D:
			_barco = n as FloatingBody3D
			break
		n = n.get_parent()
	if _barco == null:
		return
	var agua := _barco.get_node_or_null(^"AguaEmbarcada") as AguaEmbarcada
	if agua != null:
		_agua = agua
		_balance = agua.balance
		# Para que el agua de la camara cuente como agua a bordo. Sin esto,
		# chupar y no escupir nunca bajaria el nivel gratis.
		agua.registrar_bomba(self)


## La API recibe un socket de mano, no un Player. Asi el interactor futuro puede
## arbitrar farol, cana y manguera sin que tres objetos consuman la tecla E.
func tomar_manguera(grip: Node3D) -> bool:
	if _hose == null or not _hose.has_method("tomar"):
		return false
	return bool(_hose.call("tomar", grip))


func soltar_manguera(_velocidad: Vector3 = Vector3.ZERO) -> void:
	if _hose != null and _hose.has_method("soltar"):
		_hose.call("soltar")


func esta_manguera_tomada() -> bool:
	if _hose == null or not _hose.has_method("esta_tomada"):
		return false
	return bool(_hose.call("esta_tomada"))


func posicion_toma_global() -> Vector3:
	if _hose == null or not _hose.has_method("get_tip_global_position"):
		return global_position
	return _hose.call("get_tip_global_position") as Vector3


func get_hose() -> Node:
	return _hose


func puede_tomar_manguera() -> bool:
	return _hose != null and not esta_manguera_tomada()


func manguera_tomada() -> bool:
	return esta_manguera_tomada()


func longitud_manguera() -> float:
	if _hose == null:
		return 0.0
	if _hose.has_method("get_deployed_length"):
		return float(_hose.call("get_deployed_length"))
	if _hose.has_method("debug_get_deployed_length"):
		return float(_hose.call("debug_get_deployed_length"))
	return 0.0


func longitud_maxima_manguera() -> float:
	if _hose == null:
		return 0.0
	if _hose.has_method("get_max_length"):
		return float(_hose.call("get_max_length"))
	return float(_hose.get("longitud_maxima"))


func posicion_aspiracion_global() -> Vector3:
	return posicion_toma_global()


func huella_montaje() -> Vector2:
	return FOOTPRINT_METERS


func get_mount_footprint() -> Vector2:
	return FOOTPRINT_METERS


func get_mount_plane_y() -> float:
	return MOUNT_PLANE_Y


func _on_hose_taken(grip: Node3D) -> void:
	hose_taken.emit(grip)
	manguera_tomada_por.emit(grip)


func _on_hose_released() -> void:
	hose_released.emit()
	manguera_soltada.emit()


func _on_hose_tension_changed(value: float) -> void:
	tension_manguera_cambiada.emit(value)


func _on_hose_max_length_reached() -> void:
	longitud_maxima_alcanzada.emit()


func _update_stored_coil() -> void:
	if _stored_coil == null or _hose == null:
		return
	if not _hose.has_method("get_deployed_length") or not _hose.has_method("get_max_length"):
		return
	var deployed := float(_hose.call("get_deployed_length"))
	var maximum := maxf(float(_hose.call("get_max_length")), 0.001)
	var reserve_ratio := clampf(1.0 - deployed / maximum, 0.0, 1.0)
	# El rollo no representa metros exactos: encogerlo suavemente evita mostrar
	# simultaneamente una reserva llena y seis metros ya extendidos.
	_stored_coil.scale = Vector3.ONE * lerpf(0.55, 1.0, reserve_ratio)
	_stored_coil.visible = reserve_ratio > 0.04
