class_name RuedaTimon
extends Node3D

## EL PUESTO DE TIMÓN: la rueda que se agarra, el telégrafo, la llave y el cabo
## de trinca. Cuelga del socket `UpgradeSockets/Helm` del pesquero.
##
## Es la capa de MANDO. Debajo, [Gobierno] convierte lo que sale de aqui en
## fuerzas y [TimonModel] hace las cuentas; quien decide quien puede agarrar es
## [PuestoTimonModel], puro y testeable. Aqui solo queda el cableado: leer el
## input del que esta en la rueda, mover el telegrafo, animar el aro y llevar la
## cuenta del cabo.
##
## [b]Que hace cada tecla en el puesto[/b], y por que ninguna es nueva:
##
##   A / D  la rueda. Son las MISMAS teclas de andar, y funcionan porque agarrar
##          la rueda pone `input_captured` en el jugador —el mecanismo que ya usa
##          la caña para quedarse con A/D—. La rueda ES el agarre del timonel
##          (`DISENO.md` §2), asi que mientras esta ahi no anda: no hay conflicto
##          que resolver, hay un rol.
##   W / S  el telegrafo, una muesca por pulsacion. Por lo mismo: con las manos
##          en la rueda, adelante y atras ya no son pasos, son maquina.
##   Q      el contacto.
##   clic   la llave: meter la que llevas encima, o sacar la que hay puesta.
##   E      soltar la rueda, y el cabo de trinca empieza a contar.
##
## [b]La segunda etapa se ve.[/b] El aro da tres vueltas de tope a tope, no 35
## grados como un volante: es lo que hace CONTABLE el angulo de pala. Con la
## marca de rey —la cabilla distinta que queda arriba con el timon a la via— el
## timonel lee de un vistazo cuanto lleva metido, sin HUD y sin mentiras. Es la
## respuesta al problema que Sailwind tiene abierto.
##
## Ver `docs/TIMON.md` §4.

signal ocupacion_cambiada(ocupante: int)
signal contacto_dado(arrancado: bool)
## El cabo de trinca se corrio y la rueda vuelve sola a la via. Para el sonido y
## para que alguien pueda gritarlo.
signal trinca_vencida()

@export_group("Cableado")

## El nodo del aro dentro del GLB del barco (`HelmWheel`). Se busca por nombre
## porque el visual y la fisica son escenas distintas a proposito: reexportar el
## arte no puede mover un socket (`docs/BARCO_MODULAR.md`).
@export var nombre_aro: StringName = &"HelmWheel"

@export_group("Puesto")

## Medio arco de mirada al agarrar, en grados. 0 lo desactiva.
##
## Es el patron del Cyclops de Subnautica, y NO es una restriccion molesta: es lo
## que garantiza que el timonel nunca llegue a un encuadre donde no vea ni el
## horizonte ni la cabina. Eso —el marco de reposo— es la mitad del anti-mareo
## (docs/TIMON.md §11 de la investigacion), y el mareo es lo que decide si
## alguien juega dos horas o veinte minutos.
@export var arco_mirada_deg: float = 100.0

## Vueltas completas del aro de tope a tope.
@export var vueltas_aro: float = PuestoTimonModel.VUELTAS_TOPE_A_TOPE

var ocupante: int = PuestoTimonModel.NADIE

## Si el ultimo contacto se dio con llave. Solo para el HUD y el audio: quien
## decide es quien llama a [method dar_al_contacto], porque la llave la lleva el
## timonel encima y el puesto no tiene forma de saberlo.
var llave_puesta: bool = true

## Segundos que le quedan al cabo de trinca. Cero = la rueda vuelve a la via.
var trinca_restante: float = 0.0

var _barco: FloatingBody3D
var _gobierno: Gobierno
var _aro: Node3D
var _jugador: Node = null
var _mando_trincado: float = 0.0


func _ready() -> void:
	_barco = _buscar_barco()
	if _barco == null:
		push_error("RuedaTimon tiene que colgar del barco.")
		set_physics_process(false)
		return
	_gobierno = _barco.get_node_or_null(^"Gobierno") as Gobierno
	if _gobierno == null:
		push_error("RuedaTimon sin Gobierno: no hay nada que gobernar.")
		set_physics_process(false)
		return
	_gobierno.llave_puesta = llave_puesta
	var n := _barco.find_child(String(nombre_aro), true, false)
	_aro = n as Node3D


## El puesto cuelga de un socket, asi que el barco esta varios padres arriba.
func _buscar_barco() -> FloatingBody3D:
	var n := get_parent()
	while n != null:
		var b := n as FloatingBody3D
		if b != null:
			return b
		n = n.get_parent()
	return null


# =============================================================================
#  Ocupar y soltar
# =============================================================================

func estacion_libre() -> bool:
	return ocupante == PuestoTimonModel.NADIE


## El gobierno al que manda esta rueda, para que el HUD pueda leer el estado del
## motor sin buscarlo por el arbol.
func gobierno() -> Gobierno:
	return _gobierno


## Lo llama quien ya haya arbitrado con [method PuestoTimonModel.arbitrar].
##
## `jugador` es el nodo del que agarra, y solo lo pasa el que agarra EN ESTA
## maquina: es lo que distingue "yo llevo el timon" (leo el teclado) de "lo lleva
## un compañero" (solo veo girar el aro).
func ocupar_estacion(peer: int, jugador: Node = null) -> void:
	ocupante = peer
	_jugador = jugador
	trinca_restante = 0.0
	if jugador != null and &"input_captured" in jugador:
		# El mismo mecanismo con el que la caña se queda A/D. La rueda ES el
		# agarre: mientras esta aqui, el timonel no anda.
		jugador.set(&"input_captured", true)
	ocupacion_cambiada.emit(ocupante)


func liberar_estacion() -> void:
	if _jugador != null and &"input_captured" in _jugador:
		_jugador.set(&"input_captured", false)
	# Al soltar se AMARRA: el rumbo aguanta lo que aguante el cabo. Es lo que
	# permite ir a ayudar, y el reloj que convierte "voy un momento" en apuesta.
	if _gobierno != null:
		_mando_trincado = _gobierno.mando
		trinca_restante = _segundos_de_trinca()
	ocupante = PuestoTimonModel.NADIE
	_jugador = null
	ocupacion_cambiada.emit(ocupante)


func _segundos_de_trinca() -> float:
	if _gobierno == null or _gobierno.balance == null:
		return 0.0
	var hs: float = Ocean.target_hs() if Ocean != null else 0.0
	return PuestoTimonModel.segundos_trinca(hs, _gobierno.balance.trinca_s,
			_gobierno.balance.trinca_s_temporal,
			_gobierno.balance.trinca_hs_temporal)


# =============================================================================
#  El contacto y la llave
# =============================================================================

## Da al contacto. `lleva_llave` lo sabe el porteo, no el puesto: la llave no se
## mete en ningun sitio, se LLEVA (ver [PuestoTimonModel]).
##
## Devuelve el motivo de [MotorModel] para poder decirselo al jugador.
func dar_al_contacto(lleva_llave: bool) -> int:
	if _gobierno == null:
		return MotorModel.MotivoArranque.SIN_LLAVE
	if _gobierno.arrancado:
		_gobierno.parar("lo pararon")
		contacto_dado.emit(false)
		return MotorModel.MotivoArranque.OK
	llave_puesta = lleva_llave
	_gobierno.llave_puesta = lleva_llave
	var motivo := _gobierno.arrancar()
	if motivo == MotorModel.MotivoArranque.OK:
		contacto_dado.emit(true)
	return motivo


## Mueve el telegrafo `direccion` muescas (+1 avante, -1 atras).
func mover_telegrafo(direccion: int) -> void:
	if _gobierno == null:
		return
	_gobierno.muesca = MotorModel.mover_muesca(_gobierno.muesca, direccion)


# =============================================================================
#  El bucle
# =============================================================================

## Los gestos discretos van por evento y NO por `is_action_just_pressed` en el
## tick de fisica: la fisica corre a 120 y los frames a menos, asi que un
## `just_pressed` leido ahi puede verse DOS veces y el telegrafo saltaria dos
## muescas de una pulsacion.
func _unhandled_input(event: InputEvent) -> void:
	if _jugador == null:
		return
	if event.is_action_pressed(&"telegrafo_avante"):
		mover_telegrafo(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"telegrafo_atras"):
		mover_telegrafo(-1)
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if _gobierno == null:
		return
	if _jugador != null:
		# El eje crudo con su zona muerta. Esto —y no el angulo resultante— es lo
		# que viajara por el cable en F8: si se replicara el angulo, host y
		# cliente divergirian en cuanto un evento de input cayera entre ticks.
		var eje := Input.get_axis(&"timon_babor", &"timon_estribor")
		_gobierno.mando = TimonModel.aplicar_zona_muerta(eje,
				_gobierno.balance.zona_muerta)
		_limitar_mirada()
		return
	if ocupante != PuestoTimonModel.NADIE:
		# La lleva OTRO. Aqui no se toca el mando: llega con lo que mande su
		# maquina (F8). Sin esta guarda —y con el guard puesto solo en `_jugador`,
		# que fue el primer intento— cada copia del barco le centraria la rueda al
		# compañero que la esta llevando, y el timon dejaria de responder sin un
		# solo error: exactamente el fallo silencioso que el repo convierte en test.
		return
	# Sin nadie: manda el cabo hasta que se corre.
	if trinca_restante > 0.0:
		trinca_restante = maxf(trinca_restante - delta, 0.0)
		_gobierno.mando = _mando_trincado
		if trinca_restante <= 0.0:
			trinca_vencida.emit()
	else:
		_gobierno.mando = 0.0


## Presentacion: el aro gira en `_process`, no en el tick de fisica. Dibujar es
## presentacion (la leccion que costo una caida a 7 fps con la manguera).
func _process(_delta: float) -> void:
	if _aro == null or _gobierno == null:
		return
	# La rueda VISIBLE gira con la rueda, no con la pala: la pala va por detras
	# (el servo) y el timonel tiene que ver su propia mano, no el resultado.
	_aro.rotation.z = PuestoTimonModel.angulo_rueda(_gobierno.rueda, vueltas_aro)


## Le pone tope al arco de mirada mientras se lleva la rueda. Ver
## [member arco_mirada_deg].
func _limitar_mirada() -> void:
	if arco_mirada_deg <= 0.0 or _barco == null:
		return
	var jugador := _jugador as Node3D
	if jugador == null:
		return
	var popa := _barco.global_basis.z
	var mirada := jugador.global_basis.z
	var d := wrapf(atan2(mirada.x, mirada.z) - atan2(popa.x, popa.z), -PI, PI)
	var tope := deg_to_rad(arco_mirada_deg)
	if absf(d) > tope:
		jugador.rotate_y(-(d - signf(d) * tope))
