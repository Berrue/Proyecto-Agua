class_name MenuPrincipal
extends CanvasLayer

## El menú principal: la primera pantalla del juego y la puerta a los tres modos
## (solo, hostear, conectarse) y a los ajustes.
##
## [b]El fondo es el mar de verdad.[/b] No hay vídeo ni imagen: la escena monta
## el mismo `OceanSurface3D`, el mismo cielo y el mismo ciclo día/noche que la
## partida, con la hora congelada en media mañana. Sale casi gratis —ya estaba
## todo escrito— y tiene una consecuencia buena: si alguien rompe el agua, el
## menú se rompe con ella y se ve al arrancar, no diez minutos después.
##
## [b]El menú deja el mar EXACTAMENTE como lo encontró.[/b] Le pone una
## marejadilla suave para la portada —con marejada la nubosidad se come el
## cielo y la pantalla se vuelve gris—, pero se guarda la furia que había y la
## devuelve al abrir la partida: mirar la portada no puede cambiar el mar que
## viene después. Lo otro que toca al empezar es el reloj, que se pone a cero
## (ver [method _lanzar_mundo]).
##
## Toda la interfaz se construye por código, sin una sola fuente ni tamaño
## escritos en el `.tscn`: la regla 11 del repo dice que las fuentes salen de
## `GameTypography` y solo de ahí.

## Lo que se carga al darle a jugar. Hoy es el juguete de F1, que es el mundo
## jugable que existe; el día que haya campaña se cambia aquí, en un solo sitio.
const RUTA_PARTIDA := "res://game/world/toybox.tscn"

## La furia del mar de la portada: Douglas ~1,6, marejadilla. No es una decisión
## de balance sino de FOTO — medido con capturas: a la furia de arranque (3) el
## cielo se encapota y la pantalla entera se va al gris; a 1,6 el horizonte se
## abre, el agua rompe en rizos y sigue siendo el mismo mar. Se devuelve intacta
## al empezar a jugar ([method _devolver_el_mar]).
const FURIA_PORTADA := 1.6

## Paleta tipográfica de `docs/TIPOGRAFIA.md`: el color expresa estado, la forma
## de las letras expresa identidad.
const CREMA := Color(0.914, 0.933, 0.937)
const APAGADO := Color(0.62, 0.68, 0.70)
const LATON := Color(1.0, 0.72, 0.25)
const CORAL := Color(0.90, 0.36, 0.30)
const VERDE := Color(0.55, 0.80, 0.62)
const PETROLEO := Color(0.051, 0.071, 0.098)

const MARGEN_X := 76.0
const ANCHO_COLUMNA := 780.0
const Y_COLUMNA := 272.0

## Ancho de los párrafos de ayuda. Fijo y más estrecho que la columna: una línea
## de texto que cruza media pantalla se lee peor, por muy bien que quepa.
const ANCHO_AYUDA := 560.0

## Ancho de los botones. El más largo («Conectarse a una partida») cabe justo, y
## que todos midan lo mismo es lo que hace que la banda del foco sea una lista y
## no una escalera.
const ANCHO_BOTON := 430.0

## Cada cuánto se relee la lista de micrófonos, en segundos. El mismo intervalo
## que usa el autoload `Microfono` para vigilar desconexiones: enumerar aparatos
## de audio toca el sistema operativo y no es gratis.
const SONDEO_MICROS := 2.0

var _nav := MenuNavegacion.new()
## Pantalla -> su contenedor, y Pantalla -> el control que recibe el foco al abrirlo.
var _paneles: Dictionary = {}
var _foco_inicial: Dictionary = {}
var _botones: Array[Button] = []

var _columna: VBoxContainer
var _ruta: Label
var _estado: Label
var _pista: Label
var _ip: LineEdit

var _mic_lista: OptionButton
var _mic_nivel: ProgressBar
var _mic_volumen: HSlider
var _mic_pct: Label
var _mic_aparatos := PackedStringArray()
var _acum_sondeo: float = 0.0

## Preferencia guardada, que NO es lo mismo que el aparato abierto: si los cascos
## no están enchufados se abre el del sistema, pero la preferencia se respeta en
## cuanto vuelvan (`MicrofonoModel.elegir_dispositivo`).
var _mic_preferido: String = MicrofonoModel.POR_DEFECTO

## Hay un intento de conexión en marcha. Mientras dura, los botones se apagan:
## irse a «un jugador» con un peer a medio abrir es la receta de una partida que
## no sabe si está en red.
var _conectando: bool = false

## La furia que había antes de que el menú pusiera la suya. Negativa = todavía
## no se ha mirado.
var _furia_previa: float = -1.0


func _ready() -> void:
	layer = 0
	_furia_previa = Ocean.fury
	Ocean.set_fury_immediate(FURIA_PORTADA)
	# `player.gd` captura el puntero en cuanto nace, y de ahí no vuelve solo. El
	# menú es la pantalla que lo devuelve.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_construir()
	_aplicar_ajustes_guardados()
	multiplayer.connected_to_server.connect(_al_conectar)
	multiplayer.connection_failed.connect(_al_fallar_conexion)
	Microfono.dispositivo_perdido.connect(_al_perder_microfono)
	_refrescar_paneles()


func _input(event: InputEvent) -> void:
	# F9/F10 son los atajos de desarrollo de `Net` y esperan que YA estés en el
	# mundo (hostear censa la escena actual). En el menú se atienden aquí y se
	# marcan consumidos, para que abran la partida por el camino bueno en vez de
	# censar una pantalla de botones.
	var tecla := event as InputEventKey
	if tecla == null or not tecla.is_pressed() or tecla.is_echo():
		return
	match tecla.keycode:
		KEY_F9:
			get_viewport().set_input_as_handled()
			_hostear()
		KEY_F10:
			get_viewport().set_input_as_handled()
			_conectar("127.0.0.1")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_atras()


func _process(delta: float) -> void:
	if _nav.actual() != MenuNavegacion.Pantalla.OPCIONES:
		return
	# El medidor solo corre mientras se mira: es lo único que convierte una
	# lista de aparatos en un detector («¿me coge este?»).
	_mic_nivel.value = Microfono.nivel01()
	_acum_sondeo += delta
	if _acum_sondeo < SONDEO_MICROS:
		return
	_acum_sondeo = 0.0
	if Microfono.dispositivos() != _mic_aparatos:
		_poblar_microfonos()


# =============================================================================
#  Navegación
# =============================================================================

func _abrir(panel: int) -> void:
	_nav.abrir(panel)
	_refrescar_paneles()


func _atras() -> void:
	if _conectando:
		return
	if _nav.actual() == MenuNavegacion.Pantalla.OPCIONES:
		_guardar_ajustes()
	if _nav.atras():
		_decir("", CREMA)
		_refrescar_paneles()


func _refrescar_paneles() -> void:
	var actual := _nav.actual()
	for panel: int in _paneles:
		(_paneles[panel] as Control).visible = panel == actual
	_ruta.text = _nav.ruta()
	_ruta.visible = not _nav.en_raiz()
	_pista.visible = not _nav.en_raiz()
	var foco := _foco_inicial.get(actual) as Control
	if foco != null:
		foco.grab_focus()


# =============================================================================
#  Los tres modos
# =============================================================================

## Solo. El mar es el mismo; lo que falta es alguien que achique.
func _un_jugador() -> void:
	_lanzar_mundo()


## Hostear. El puerto se comprueba ANTES de cambiar de escena: si ya hay otra
## instancia hosteando, `Net.hostear()` avisaría por consola y dejaría al
## jugador dentro de un mundo en solitario creyendo que espera tripulación
## (regla 8: el fallo se telegrafía antes de castigar).
func _hostear() -> void:
	if _conectando:
		return
	if not _puerto_libre():
		_decir("Ya hay una partida abierta en este equipo (puerto %d ocupado)."
			% Net.PUERTO, CORAL)
		return
	_lanzar_mundo()
	Net.hostear()


## ¿Se puede abrir el puerto? Se prueba abriéndolo de verdad y cerrándolo: no
## hay forma de preguntarlo sin intentarlo, y es exactamente lo que hará `Net`
## un instante después.
func _puerto_libre() -> bool:
	var sonda := ENetMultiplayerPeer.new()
	if sonda.create_server(Net.PUERTO, 1) != OK:
		return false
	sonda.close()
	return true


## Conectarse. Aquí NO se cambia de escena todavía: se espera a saber si hay
## alguien al otro lado. Cargar el mundo antes dejaría al jugador dentro de un
## mar vacío mientras la conexión falla en segundo plano, sin nada que decirle.
func _conectar(destino: String) -> void:
	if _conectando:
		return
	var limpio := destino.strip_edges()
	if limpio.is_empty():
		_decir("Escribe la dirección de quien hostea.", CORAL)
		return
	_conectando = true
	_bloquear(true)
	_decir("Conectando con %s…" % limpio, LATON)
	Net.unirse(limpio)
	if Net.rol != Net.Rol.CLIENTE:
		# `unirse` ya avisó por consola: la dirección no vale ni para intentarlo.
		_conectando = false
		_bloquear(false)
		_decir("No pude usar esa dirección.", CORAL)


func _al_conectar() -> void:
	# Hay host. El mundo se carga AQUÍ y de forma síncrona: el `_hola` del host
	# —que censa la escena y coloca a todo el mundo— llega en un paquete
	# posterior, así que para cuando se procese, el barco ya existe.
	_conectando = false
	_lanzar_mundo()


func _al_fallar_conexion() -> void:
	_conectando = false
	_bloquear(false)
	_decir("No hay nadie escuchando ahí. ¿Ya abrió la partida quien hostea?", CORAL)


## Deja el mundo en marcha y se lleva el menú por delante.
##
## Lo único que le escribe al océano es el reloj: la partida empieza en t=0. Sin
## esto, quien deje el menú abierto diez minutos empezaría a jugar de noche —la
## hora del día es una función pura de `Ocean.sim_time`, y ese reloj corre
## también mientras se mira el mar del fondo.
func _lanzar_mundo() -> void:
	_devolver_el_mar()
	Ocean.sim_time = 0.0
	Ocean.clear_events()
	var pack := load(RUTA_PARTIDA) as PackedScene
	if pack == null:
		_decir("No encuentro el mundo (%s)." % RUTA_PARTIDA, CORAL)
		return
	var mundo := pack.instantiate()
	var arbol := get_tree()
	var vieja := arbol.current_scene
	if vieja != null:
		vieja.queue_free()
	# El mismo orden que `change_scene_to_packed`: `current_scene` primero, para
	# que lo que despierte en `_ready` ya vea la escena buena. `Net.hostear()`
	# censa por ahí (`get_tree().current_scene`).
	arbol.current_scene = mundo
	arbol.root.add_child(mundo)


## Devuelve la furia que había antes de la portada. La partida tiene que empezar
## con el mar que le toque —hoy el de arranque de `Ocean`, mañana el que ponga
## el caladero elegido—, no con el que hacía bonito detrás de los botones.
func _devolver_el_mar() -> void:
	if _furia_previa >= 0.0:
		Ocean.set_fury_immediate(_furia_previa)


func _salir() -> void:
	get_tree().quit()


# =============================================================================
#  Ajustes
# =============================================================================

func _aplicar_ajustes_guardados() -> void:
	var ajustes := MenuAjustes.cargar()
	_mic_preferido = String(ajustes[MenuAjustes.CLAVE_DISPOSITIVO])
	Microfono.volumen_pct = float(ajustes[MenuAjustes.CLAVE_VOLUMEN])
	Microfono.usar_dispositivo(_mic_preferido)
	_poblar_microfonos()
	_mic_volumen.value = Microfono.volumen_pct
	_pintar_pct()


func _guardar_ajustes() -> void:
	MenuAjustes.guardar(_mic_preferido, Microfono.volumen_pct)


func _al_elegir_microfono(indice: int) -> void:
	var pedido := String(_mic_lista.get_item_metadata(indice))
	_mic_preferido = pedido
	var abierto := Microfono.usar_dispositivo(pedido)
	_guardar_ajustes()
	if abierto != pedido:
		# Regla 8: el aparato elegido ya no está y el juego NO se queda mudo en
		# silencio. Se dice, y la preferencia se guarda igual por si vuelve.
		_decir("Ese micrófono ya no está conectado; escucho por el del sistema.",
			LATON)
	else:
		_decir("", CREMA)


func _al_perder_microfono(anterior: String) -> void:
	_poblar_microfonos()
	_decir("Se desconectó «%s»; escucho por el del sistema." % anterior, LATON)


func _al_mover_volumen(valor: float) -> void:
	Microfono.volumen_pct = valor
	_pintar_pct()


func _al_soltar_volumen(cambio: bool) -> void:
	if cambio:
		_guardar_ajustes()


func _pintar_pct() -> void:
	_mic_pct.text = "%d %%" % roundi(Microfono.volumen_pct)


## Rellena la lista de aparatos. La primera entrada es SIEMPRE el del sistema:
## es la única que se puede prometer que existe, y la respuesta correcta para
## quien no sabe cuál de los cuatro «Micrófono (Realtek)» es el suyo.
func _poblar_microfonos() -> void:
	_mic_aparatos = Microfono.dispositivos()
	_mic_lista.clear()
	_mic_lista.add_item("Predeterminado del sistema")
	_mic_lista.set_item_metadata(0, MicrofonoModel.POR_DEFECTO)
	var elegido := 0
	for nombre in _mic_aparatos:
		if nombre == MicrofonoModel.POR_DEFECTO:
			continue
		_mic_lista.add_item(nombre)
		var i := _mic_lista.item_count - 1
		_mic_lista.set_item_metadata(i, nombre)
		if nombre == _mic_preferido:
			elegido = i
	_mic_lista.select(elegido)


# =============================================================================
#  Mensajes
# =============================================================================

## Una línea de estado bajo los botones. Es el único sitio donde el menú cuenta
## lo que pasó: un botón que no hace nada es exactamente el «me robó» que el
## juego promete no hacer (regla 8).
func _decir(texto: String, color: Color) -> void:
	_estado.text = texto
	_estado.visible = not texto.is_empty()
	_estado.label_settings.font_color = color


func _bloquear(apagados: bool) -> void:
	for boton in _botones:
		boton.disabled = apagados


# =============================================================================
#  Construcción de la interfaz
# =============================================================================

func _construir() -> void:
	_construir_velo()
	_construir_cabecera()
	_columna = VBoxContainer.new()
	_columna.position = Vector2(MARGEN_X, Y_COLUMNA)
	_columna.size = Vector2(ANCHO_COLUMNA, 0.0)
	_columna.custom_minimum_size = Vector2(ANCHO_COLUMNA, 0.0)
	_columna.add_theme_constant_override(&"separation", 10)
	add_child(_columna)

	_panel_raiz()
	_panel_jugar()
	_panel_multijugador()
	_panel_unirse()
	_panel_opciones()

	_estado = _etiqueta("", GameTypography.ui_regular(), 17, CREMA)
	_estado.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_estado.custom_minimum_size = Vector2(ANCHO_COLUMNA, 0.0)
	_estado.visible = false
	_columna.add_child(_estado)

	_pista = _etiqueta("Esc · volver", GameTypography.ui_bold(), 15, APAGADO)
	_pista.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_pista.position += Vector2(MARGEN_X, -58.0)
	_pista.visible = false
	add_child(_pista)


## Un velo oscuro por la izquierda. El mar pasa de espuma blanca a azul de
## sombra dentro de la misma ola, así que el texto necesita un fondo propio: es
## la misma solución que el contorno del HUD (docs/TIPOGRAFIA.md), a escala de
## pantalla. Va en degradado para que no se vea el borde del panel.
func _construir_velo() -> void:
	var grad := Gradient.new()
	grad.set_color(0, Color(PETROLEO.r, PETROLEO.g, PETROLEO.b, 0.90))
	grad.set_color(1, Color(PETROLEO.r, PETROLEO.g, PETROLEO.b, 0.0))
	grad.add_point(0.45, Color(PETROLEO.r, PETROLEO.g, PETROLEO.b, 0.72))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 512
	tex.height = 8
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(1.0, 0.0)
	var velo := TextureRect.new()
	velo.texture = tex
	velo.stretch_mode = TextureRect.STRETCH_SCALE
	velo.set_anchors_preset(Control.PRESET_FULL_RECT)
	velo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(velo)


## Título y lema salen de `project.godot` y no de una cadena escrita aquí: el
## nombre del juego sigue abierto (docs/TIPOGRAFIA.md), y cuando se cierre no
## puede quedarse el viejo colgado en la portada.
func _construir_cabecera() -> void:
	var nombre := String(ProjectSettings.get_setting(
		"application/config/name", "Proyecto Agua"))
	# Mayúsculas y la variante ANCHA: es el único sitio del juego donde manda la
	# voz de marca (regla 11); el resto de la pantalla es información.
	var titulo := _etiqueta(nombre.to_upper(), GameTypography.display_brand(), 72, CREMA)
	titulo.position = Vector2(MARGEN_X, 92.0)
	add_child(titulo)

	var lema := _etiqueta(String(ProjectSettings.get_setting(
		"application/config/description", "")), GameTypography.ui_regular(), 19, APAGADO)
	lema.position = Vector2(MARGEN_X + 4.0, 198.0)
	lema.custom_minimum_size = Vector2(720.0, 0.0)
	lema.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(lema)

	_ruta = _etiqueta("", GameTypography.ui_bold(), 15, LATON)
	_ruta.position = Vector2(MARGEN_X + 4.0, 240.0)
	_ruta.visible = false
	add_child(_ruta)


func _panel_raiz() -> void:
	var caja := _caja_panel()
	var jugar := _boton("Jugar", _abrir.bind(MenuNavegacion.Pantalla.JUGAR))
	caja.add_child(jugar)
	caja.add_child(_boton("Opciones", _abrir.bind(MenuNavegacion.Pantalla.OPCIONES)))
	caja.add_child(_boton("Salir", _salir))
	_registrar(MenuNavegacion.Pantalla.RAIZ, caja, jugar)


func _panel_jugar() -> void:
	var caja := _caja_panel()
	caja.add_child(_ayuda(
		"El mar es el mismo en los dos modos. Lo que cambia es si hay alguien más para achicar."))
	var solo := _boton("Un jugador", _un_jugador)
	caja.add_child(solo)
	caja.add_child(_boton("Multijugador",
		_abrir.bind(MenuNavegacion.Pantalla.MULTIJUGADOR)))
	caja.add_child(_boton("Atrás", _atras))
	_registrar(MenuNavegacion.Pantalla.JUGAR, caja, solo)


func _panel_multijugador() -> void:
	var caja := _caja_panel()
	# Los números salen de `Net` y no de un texto a mano: si mañana caben ocho,
	# esta pantalla no puede seguir prometiendo seis.
	caja.add_child(_ayuda(
		"Hasta %d a bordo, por red local (ENet, puerto %d). Quien hostea manda el mar."
		% [Net.MAX_JUGADORES + 1, Net.PUERTO]))
	var hostear := _boton("Hostear una partida", _hostear)
	caja.add_child(hostear)
	caja.add_child(_boton("Conectarse a una partida",
		_abrir.bind(MenuNavegacion.Pantalla.UNIRSE)))
	caja.add_child(_boton("Atrás", _atras))
	_registrar(MenuNavegacion.Pantalla.MULTIJUGADOR, caja, hostear)


func _panel_unirse() -> void:
	var caja := _caja_panel()
	caja.add_child(_ayuda(
		"La dirección de quien hostea. 127.0.0.1 es este mismo equipo, para probar con dos ventanas."))
	_ip = LineEdit.new()
	_ip.text = "127.0.0.1"
	_ip.placeholder_text = "127.0.0.1"
	_ip.custom_minimum_size = Vector2(340.0, 0.0)
	_ip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_ip.add_theme_font_override(&"font", GameTypography.ui_regular())
	_ip.add_theme_font_size_override(&"font_size", 19)
	_ip.add_theme_color_override(&"font_color", CREMA)
	_ip.add_theme_color_override(&"font_placeholder_color", APAGADO)
	_ip.add_theme_color_override(&"caret_color", LATON)
	_ip.add_theme_stylebox_override(&"normal", _estilo_campo(false))
	_ip.add_theme_stylebox_override(&"focus", _estilo_campo(true))
	_ip.text_submitted.connect(_al_enviar_ip)
	caja.add_child(_ip)
	caja.add_child(_boton("Conectar", _conectar_desde_campo))
	caja.add_child(_boton("Atrás", _atras))
	_registrar(MenuNavegacion.Pantalla.UNIRSE, caja, _ip)


func _panel_opciones() -> void:
	var caja := _caja_panel()
	# Dos columnas, controles y micrófono. En una sola, la tabla de teclas empuja
	# el botón de «Atrás» fuera de la pantalla — medido con `capture_menu`.
	var columnas := HBoxContainer.new()
	columnas.add_theme_constant_override(&"separation", 56)
	caja.add_child(columnas)

	var izquierda := VBoxContainer.new()
	izquierda.add_theme_constant_override(&"separation", 2)
	izquierda.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	izquierda.add_child(_seccion("Controles"))
	var rejilla := GridContainer.new()
	rejilla.columns = 2
	rejilla.add_theme_constant_override(&"h_separation", 28)
	rejilla.add_theme_constant_override(&"v_separation", 0)
	for fila in ControlesBasicos.filas():
		# La acción en Atkinson normal y las TECLAS en negrita: las teclas son
		# lo que se busca con la vista (docs/TIPOGRAFIA.md).
		rejilla.add_child(_etiqueta(String(fila["etiqueta"]),
			GameTypography.ui_regular(), 16, APAGADO))
		rejilla.add_child(_etiqueta(String(fila["teclas"]),
			GameTypography.ui_bold(), 16, CREMA))
	izquierda.add_child(rejilla)
	columnas.add_child(izquierda)

	var derecha := VBoxContainer.new()
	derecha.add_theme_constant_override(&"separation", 6)
	derecha.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	columnas.add_child(derecha)

	derecha.add_child(_seccion("Micrófono"))
	_mic_lista = OptionButton.new()
	_mic_lista.custom_minimum_size = Vector2(380.0, 0.0)
	_mic_lista.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_mic_lista.add_theme_font_override(&"font", GameTypography.ui_regular())
	_mic_lista.add_theme_font_size_override(&"font_size", 18)
	_mic_lista.add_theme_color_override(&"font_color", CREMA)
	_mic_lista.add_theme_color_override(&"font_hover_color", LATON)
	_mic_lista.add_theme_color_override(&"font_focus_color", LATON)
	_mic_lista.add_theme_stylebox_override(&"normal", _estilo_campo(false))
	_mic_lista.add_theme_stylebox_override(&"hover", _estilo_campo(true))
	_mic_lista.add_theme_stylebox_override(&"focus", _estilo_campo(true))
	_mic_lista.add_theme_stylebox_override(&"pressed", _estilo_campo(true))
	var lista := _mic_lista.get_popup()
	lista.add_theme_font_override(&"font", GameTypography.ui_regular())
	lista.add_theme_font_size_override(&"font_size", 18)
	_mic_lista.item_selected.connect(_al_elegir_microfono)
	derecha.add_child(_mic_lista)

	var fila_vol := HBoxContainer.new()
	fila_vol.add_theme_constant_override(&"separation", 14)
	fila_vol.add_child(_etiqueta("Volumen de entrada",
		GameTypography.ui_regular(), 17, APAGADO))
	_mic_volumen = HSlider.new()
	_mic_volumen.min_value = 0.0
	_mic_volumen.max_value = MicrofonoModel.PCT_MAX
	_mic_volumen.step = 5.0
	_mic_volumen.custom_minimum_size = Vector2(200.0, 0.0)
	_mic_volumen.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_mic_volumen.value_changed.connect(_al_mover_volumen)
	_mic_volumen.drag_ended.connect(_al_soltar_volumen)
	fila_vol.add_child(_mic_volumen)
	_mic_pct = _etiqueta("100 %", GameTypography.ui_bold(), 17, CREMA)
	_mic_pct.custom_minimum_size = Vector2(64.0, 0.0)
	fila_vol.add_child(_mic_pct)
	derecha.add_child(fila_vol)

	# El medidor: verde claro, que en la paleta del juego es «esto está bien»
	# (docs/TIPOGRAFIA.md). Sin él, elegir micrófono es adivinar.
	_mic_nivel = ProgressBar.new()
	_mic_nivel.min_value = 0.0
	_mic_nivel.max_value = 1.0
	_mic_nivel.step = 0.01
	_mic_nivel.show_percentage = false
	_mic_nivel.custom_minimum_size = Vector2(340.0, 8.0)
	_mic_nivel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var fondo := StyleBoxFlat.new()
	fondo.bg_color = Color(0.05, 0.08, 0.12, 0.8)
	var relleno := StyleBoxFlat.new()
	relleno.bg_color = VERDE
	_mic_nivel.add_theme_stylebox_override(&"background", fondo)
	_mic_nivel.add_theme_stylebox_override(&"fill", relleno)
	derecha.add_child(_mic_nivel)

	derecha.add_child(_ayuda(
		"No te oyes a ti mismo a propósito (acoplaría). La barra sube al hablar: con eso ya sabes que el juego te coge."))
	caja.add_child(_boton("Atrás", _atras))
	_registrar(MenuNavegacion.Pantalla.OPCIONES, caja, _mic_lista)


func _registrar(panel: int, caja: Control, foco: Control) -> void:
	_paneles[panel] = caja
	if foco != null:
		_foco_inicial[panel] = foco
	_columna.add_child(caja)


func _caja_panel() -> VBoxContainer:
	var caja := VBoxContainer.new()
	caja.add_theme_constant_override(&"separation", 6)
	caja.visible = false
	return caja


func _al_enviar_ip(texto: String) -> void:
	_conectar(texto)


func _conectar_desde_campo() -> void:
	_conectar(_ip.text)


# =============================================================================
#  Piezas de la interfaz — todas las fuentes salen de GameTypography (regla 11)
# =============================================================================

func _etiqueta(texto: String, fuente: Font, tamano: int, color: Color) -> Label:
	var etiqueta := Label.new()
	etiqueta.text = texto
	var ls := LabelSettings.new()
	ls.font = fuente
	ls.font_size = tamano
	ls.font_color = color
	# Contorno oscuro y sombra corta: el texto va sobre el mar, y el mar cambia
	# de blanco a azul dentro de la misma ola (docs/TIPOGRAFIA.md).
	ls.outline_size = maxi(4, tamano / 5)
	ls.outline_color = Color(PETROLEO.r, PETROLEO.g, PETROLEO.b, 0.95)
	ls.shadow_size = 4
	ls.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	etiqueta.label_settings = ls
	etiqueta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return etiqueta


## Texto de ayuda de un panel: en frase normal y en la voz de información, nunca
## en la de impacto. Explicar no es un imperativo.
func _ayuda(texto: String, ancho: float = ANCHO_AYUDA) -> Label:
	var etiqueta := _etiqueta(texto, GameTypography.ui_regular(), 16, APAGADO)
	etiqueta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	etiqueta.custom_minimum_size = Vector2(ancho, 0.0)
	etiqueta.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return etiqueta


func _seccion(texto: String) -> Label:
	var etiqueta := _etiqueta(texto, GameTypography.ui_bold(), 16, LATON)
	etiqueta.custom_minimum_size = Vector2(0.0, 42.0)
	etiqueta.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	return etiqueta


func _boton(texto: String, accion: Callable) -> Button:
	var boton := Button.new()
	boton.text = texto
	boton.alignment = HORIZONTAL_ALIGNMENT_LEFT
	boton.focus_mode = Control.FOCUS_ALL
	# Ancho fijo y no el de la columna: el resalte del foco es una BANDA, y una
	# banda que llega a media pantalla deja de leerse como un botón.
	boton.custom_minimum_size = Vector2(ANCHO_BOTON, 0.0)
	boton.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	boton.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	boton.add_theme_font_override(&"font", GameTypography.display_hud())
	boton.add_theme_font_size_override(&"font_size", 30)
	boton.add_theme_color_override(&"font_color", CREMA)
	boton.add_theme_color_override(&"font_hover_color", LATON)
	boton.add_theme_color_override(&"font_focus_color", LATON)
	boton.add_theme_color_override(&"font_pressed_color", LATON)
	boton.add_theme_color_override(&"font_hover_pressed_color", LATON)
	boton.add_theme_color_override(&"font_disabled_color", APAGADO)
	boton.add_theme_color_override(&"font_outline_color",
		Color(PETROLEO.r, PETROLEO.g, PETROLEO.b, 0.95))
	boton.add_theme_constant_override(&"outline_size", 6)
	# El resalte lo pinta SIEMPRE el estilo de foco, y el ratón mueve el foco al
	# pasar por encima: así teclado y ratón nunca señalan botones distintos, que
	# es como se acaba pulsando Intro sobre el que no estabas mirando.
	boton.add_theme_stylebox_override(&"normal", _estilo_boton(0.0, false))
	boton.add_theme_stylebox_override(&"hover", _estilo_boton(0.0, false))
	boton.add_theme_stylebox_override(&"disabled", _estilo_boton(0.0, false))
	boton.add_theme_stylebox_override(&"focus", _estilo_boton(0.20, true))
	boton.add_theme_stylebox_override(&"pressed", _estilo_boton(0.30, true))
	boton.pressed.connect(accion)
	boton.mouse_entered.connect(boton.grab_focus)
	_botones.append(boton)
	return boton


## La caja de un botón. Los márgenes son los MISMOS en todos los estados: si la
## barra del foco moviera el texto, la lista entera bailaría al pasar el ratón.
func _estilo_boton(alfa: float, barra: bool) -> StyleBoxFlat:
	var caja := StyleBoxFlat.new()
	caja.bg_color = Color(0.09, 0.13, 0.17, alfa)
	caja.content_margin_left = 20.0
	caja.content_margin_right = 20.0
	caja.content_margin_top = 9.0
	caja.content_margin_bottom = 9.0
	if barra:
		caja.border_width_left = 4
		caja.border_color = LATON
	return caja


func _estilo_campo(activo: bool) -> StyleBoxFlat:
	var caja := StyleBoxFlat.new()
	caja.bg_color = Color(0.05, 0.08, 0.12, 0.85)
	caja.content_margin_left = 12.0
	caja.content_margin_right = 12.0
	caja.content_margin_top = 8.0
	caja.content_margin_bottom = 8.0
	caja.border_width_bottom = 2
	caja.border_color = LATON if activo else Color(0.35, 0.41, 0.45)
	return caja
