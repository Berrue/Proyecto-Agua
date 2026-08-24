extends Node

## Autoload `Partida`: el caparazón de una partida en curso. Dos pantallas que
## no son del mundo sino de la sesión — el menú de `Esc` y la lista de
## tripulación de `TAB`.
##
## Es autoload y no un nodo suelto en cada escena a propósito: así lo tienen
## TODAS las escenas jugables (el juguete, el modo tsunami y las que vengan) sin
## que nadie tenga que acordarse de instanciarlo. Un HUD que se olvida en una
## escena nueva es el fallo silencioso clásico del repo.
##
## [b]`Esc` NO pausa nada.[/b] En cooperativo no se puede —el mar de los demás
## sigue— y en solitario tampoco se hace, por dos motivos: que el juego se
## comporte igual jugando solo que acompañado, y que la perilla de furia del HUD
## de debug siga siendo usable con el ratón suelto, que es como se valida el
## juego (CLAUDE.md: el HUD de debug es sagrado en F1). Por eso la tarjeta es
## pequeña y centrada: deja libre la columna izquierda, que es donde vive ese
## HUD, y no tapa el mar.
##
## [b]`Esc` sigue soltando el ratón[/b], igual que antes de que esto existiera:
## la tarjeta se suma al gesto que ya había en `player.gd`, no lo sustituye.

## A dónde se vuelve. La otra mitad del viaje (`MenuPrincipal.RUTA_PARTIDA`)
## vive en el menú: cada pantalla sabe adónde va, y solo eso.
const RUTA_MENU := "res://game/ui/menu/menu_principal.tscn"

## Por encima del HUD de pesca (8) y del overlay de red (9): esto es la sesión,
## y cuando está abierto manda sobre lo que pasa en el barco.
const CAPA := 11

## Cada cuánto se repinta la lista mientras se tiene TAB apretado. Los pings
## llegan a 1 Hz; refrescar más rápido solo repinta lo mismo.
const REFRESCO_LISTA := 0.5

var _capa: CanvasLayer
var _tarjeta: PanelContainer
var _lista: PanelContainer
var _filas: VBoxContainer
var _botones: Array[Button] = []
var _acum: float = 0.0

## La escena que se miró la última vez y si era una partida. Se cachea porque
## `_input` corre por cada tecla y buscar el jugador en cada pulsación es
## trabajo tirado.
var _escena_id: int = 0
var _es_partida: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_construir()
	set_process(false)


# =============================================================================
#  Las dos teclas
# =============================================================================

func _input(event: InputEvent) -> void:
	if not en_partida():
		return
	# `toggle_mouse` (Esc) es la MISMA acción de siempre, no una nueva: aquí se
	# le añade la tarjeta y se consume el evento, así que `player.gd` ya no lo
	# ve y el ratón lo maneja este archivo entero.
	if event.is_action_pressed(&"toggle_mouse"):
		get_viewport().set_input_as_handled()
		mostrar_menu(not menu_visible())
		return
	if event.is_action_pressed(&"crew") and not menu_visible():
		get_viewport().set_input_as_handled()
		_mostrar_lista(true)
	elif event.is_action_released(&"crew"):
		_mostrar_lista(false)


func _process(delta: float) -> void:
	_acum += delta
	if _acum < REFRESCO_LISTA:
		return
	_acum = 0.0
	_pintar_lista(Net.tripulacion())


## ¿Hay una partida delante? La portada y los arneses no llevan jugador, y ahí
## ni `Esc` ni `TAB` significan nada. Se resuelve como lo hace `Net`: el jugador
## local es el nodo `Player` de la escena.
func en_partida() -> bool:
	var escena := get_tree().current_scene
	if escena == null:
		return false
	var id := escena.get_instance_id()
	if id != _escena_id:
		_escena_id = id
		_es_partida = escena.get_node_or_null(^"Player") != null
	return _es_partida


# =============================================================================
#  El menú de Esc
# =============================================================================

func menu_visible() -> bool:
	return _tarjeta.visible


func mostrar_menu(visible: bool) -> void:
	_tarjeta.visible = visible
	if visible:
		_mostrar_lista(false)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if not _botones.is_empty():
			_botones[0].grab_focus()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Cerrar la partida y volver a la portada. Lo primero es soltar la red: sin
## esto el peer se quedaría abierto detrás del menú y el host seguiría contando
## con un tripulante que ya no está en ninguna escena.
func volver_al_menu() -> void:
	mostrar_menu(false)
	_mostrar_lista(false)
	# El menú es una pantalla de ratón: se suelta aquí y no al llegar, para que
	# no haya un fotograma con el puntero atrapado sobre la portada.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Net.desconectar()
	Ocean.clear_events()
	get_tree().change_scene_to_file(RUTA_MENU)


func _salir_del_juego() -> void:
	get_tree().quit()


# =============================================================================
#  La lista de TAB
# =============================================================================

func _mostrar_lista(visible: bool) -> void:
	_lista.visible = visible
	set_process(visible)
	if visible:
		_acum = 0.0
		_pintar_lista(Net.tripulacion())


## Pinta las filas que le den. Recibe la lista por parámetro —y no la pide él
## mismo— para que el arnés pueda darle una tripulación de mentira sin levantar
## una red de verdad: `Net` es un autoload singleton y no se puede tener host y
## cliente en un proceso (docs/RED.md).
func _pintar_lista(tripulacion: Array) -> void:
	for hijo in _filas.get_children():
		# `remove_child` ANTES de liberar: `queue_free` a secas deja el nodo
		# viejo colgando hasta el final del frame y la lista se pinta doble.
		_filas.remove_child(hijo)
		hijo.queue_free()
	for f: Dictionary in tripulacion:
		_filas.add_child(_fila(f))


func _fila(datos: Dictionary) -> HBoxContainer:
	var caja := HBoxContainer.new()
	caja.add_theme_constant_override(&"separation", 16)

	var nombre := String(datos["nombre"])
	if bool(datos["soy_yo"]):
		# Encontrarse a uno mismo en la lista tiene que ser instantáneo.
		nombre += "  (tú)"
	var color: Color = EstiloMenu.LATON if bool(datos["soy_yo"]) else EstiloMenu.CREMA
	var quien := EstiloMenu.etiqueta(nombre, GameTypography.ui_regular(), 18, color)
	quien.custom_minimum_size = Vector2(240.0, 0.0)
	caja.add_child(quien)

	# «Patrón» y no «host»: es quien manda el mar y quien arbitra el porteo, y
	# en un pesquero eso tiene nombre.
	var papel := EstiloMenu.etiqueta(
		"patrón" if bool(datos["es_host"]) else "", GameTypography.ui_regular(),
		15, EstiloMenu.APAGADO)
	papel.custom_minimum_size = Vector2(72.0, 0.0)
	caja.add_child(papel)

	var ms := int(datos["ms"])
	var retardo := EstiloMenu.etiqueta(NetTripulacion.texto_ms(ms),
		GameTypography.ui_bold(), 17, _color_de_ping(ms))
	retardo.custom_minimum_size = Vector2(84.0, 0.0)
	retardo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	caja.add_child(retardo)
	return caja


## El color dice el estado y el número dice el dato: ninguno de los dos solo
## (docs/TIPOGRAFIA.md — el color nunca es la instrucción entera).
func _color_de_ping(ms: int) -> Color:
	match NetTripulacion.calidad(ms):
		NetTripulacion.Calidad.BUENA:
			return EstiloMenu.VERDE
		NetTripulacion.Calidad.REGULAR:
			return EstiloMenu.LATON
		NetTripulacion.Calidad.MALA:
			return EstiloMenu.CORAL
		_:
			return EstiloMenu.APAGADO


# =============================================================================
#  Construcción
# =============================================================================

func _construir() -> void:
	_capa = CanvasLayer.new()
	_capa.name = "PartidaHUD"
	_capa.layer = CAPA
	add_child(_capa)
	_construir_tarjeta()
	_construir_lista()


func _construir_tarjeta() -> void:
	_tarjeta = PanelContainer.new()
	_tarjeta.add_theme_stylebox_override(&"panel", EstiloMenu.caja_panel())
	_tarjeta.set_anchors_preset(Control.PRESET_CENTER)
	_tarjeta.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_tarjeta.grow_vertical = Control.GROW_DIRECTION_BOTH
	_tarjeta.visible = false
	_capa.add_child(_tarjeta)

	var caja := VBoxContainer.new()
	caja.add_theme_constant_override(&"separation", 8)
	_tarjeta.add_child(caja)

	caja.add_child(EstiloMenu.etiqueta("Pausa", GameTypography.display_hud(),
		34, EstiloMenu.CREMA))
	caja.add_child(EstiloMenu.ayuda(
		"El mar no se detiene: la partida sigue corriendo mientras miras esto.",
		EstiloMenu.ANCHO_BOTON))
	caja.add_child(_boton("Continuar", mostrar_menu.bind(false)))
	caja.add_child(_boton("Volver al menú", volver_al_menu))
	caja.add_child(_boton("Salir del juego", _salir_del_juego))


func _construir_lista() -> void:
	_lista = PanelContainer.new()
	_lista.add_theme_stylebox_override(&"panel", EstiloMenu.caja_panel())
	_lista.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_lista.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_lista.position += Vector2(0.0, 48.0)
	_lista.visible = false
	_lista.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_capa.add_child(_lista)

	var caja := VBoxContainer.new()
	caja.add_theme_constant_override(&"separation", 6)
	_lista.add_child(caja)
	caja.add_child(EstiloMenu.etiqueta("Tripulación", GameTypography.ui_bold(),
		15, EstiloMenu.LATON))
	_filas = VBoxContainer.new()
	_filas.add_theme_constant_override(&"separation", 2)
	caja.add_child(_filas)


func _boton(texto: String, accion: Callable) -> Button:
	var boton := EstiloMenu.boton(texto)
	boton.pressed.connect(accion)
	_botones.append(boton)
	return boton
