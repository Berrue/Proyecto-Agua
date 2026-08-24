class_name EstiloMenu
extends RefCounted

## La misma voz para TODAS las pantallas de menú: la portada, el menú de Esc y
## lo que venga.
##
## Existe por el mismo motivo que `GameTypography` (regla 11): si el botón de
## «Volver al menú» se dibuja con su propio azul y su propio margen, deja de ser
## el mismo juego que la portada aunque use la misma fuente. Aquí viven la
## paleta, los márgenes y las cajas; las fuentes se siguen pidiendo a
## `GameTypography`, que es la única fábrica que las hace.
##
## Todo estático y sin nodos: cada pantalla monta su árbol, esto solo lo viste.

## Paleta tipográfica de `docs/TIPOGRAFIA.md`. El color expresa estado; la forma
## de las letras expresa identidad.
const CREMA := Color(0.914, 0.933, 0.937)
const APAGADO := Color(0.62, 0.68, 0.70)
const LATON := Color(1.0, 0.72, 0.25)
const CORAL := Color(0.90, 0.36, 0.30)
const VERDE := Color(0.55, 0.80, 0.62)
const PETROLEO := Color(0.051, 0.071, 0.098)

## Ancho de los botones. El más largo («Conectarse a una partida») cabe justo, y
## que todos midan lo mismo es lo que hace que la banda del foco sea una lista y
## no una escalera.
const ANCHO_BOTON := 430.0


static func etiqueta(texto: String, fuente: Font, tamano: int, color: Color) -> Label:
	var control := Label.new()
	control.text = texto
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
	control.label_settings = ls
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return control


## Texto de ayuda: en frase normal y en la voz de información, nunca en la de
## impacto. Explicar no es un imperativo.
static func ayuda(texto: String, ancho: float) -> Label:
	var control := etiqueta(texto, GameTypography.ui_regular(), 16, APAGADO)
	control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	control.custom_minimum_size = Vector2(ancho, 0.0)
	control.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return control


static func seccion(texto: String) -> Label:
	var control := etiqueta(texto, GameTypography.ui_bold(), 16, LATON)
	control.custom_minimum_size = Vector2(0.0, 42.0)
	control.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	return control


## Un botón de menú. Quien lo pide conecta la acción y se lo apunta: aquí solo
## se decide cómo se ve y cómo responde al foco.
static func boton(texto: String) -> Button:
	var control := Button.new()
	control.text = texto
	control.alignment = HORIZONTAL_ALIGNMENT_LEFT
	control.focus_mode = Control.FOCUS_ALL
	control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	control.custom_minimum_size = Vector2(ANCHO_BOTON, 0.0)
	control.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	control.add_theme_font_override(&"font", GameTypography.display_hud())
	control.add_theme_font_size_override(&"font_size", 30)
	control.add_theme_color_override(&"font_color", CREMA)
	control.add_theme_color_override(&"font_hover_color", LATON)
	control.add_theme_color_override(&"font_focus_color", LATON)
	control.add_theme_color_override(&"font_pressed_color", LATON)
	control.add_theme_color_override(&"font_hover_pressed_color", LATON)
	control.add_theme_color_override(&"font_disabled_color", APAGADO)
	control.add_theme_color_override(&"font_outline_color",
		Color(PETROLEO.r, PETROLEO.g, PETROLEO.b, 0.95))
	control.add_theme_constant_override(&"outline_size", 6)
	# El resalte lo pinta SIEMPRE el estilo de foco, y el ratón mueve el foco al
	# pasar por encima: así teclado y ratón nunca señalan botones distintos, que
	# es como se acaba pulsando Intro sobre el que no estabas mirando.
	control.add_theme_stylebox_override(&"normal", caja_boton(0.0, false))
	control.add_theme_stylebox_override(&"hover", caja_boton(0.0, false))
	control.add_theme_stylebox_override(&"disabled", caja_boton(0.0, false))
	control.add_theme_stylebox_override(&"focus", caja_boton(0.20, true))
	control.add_theme_stylebox_override(&"pressed", caja_boton(0.30, true))
	control.mouse_entered.connect(control.grab_focus)
	return control


## Un campo de texto (la dirección del host, el nombre a bordo). Subrayado y no
## recuadrado: el foco se lee en la línea de abajo, que es donde está el cursor.
static func campo(ancho: float) -> LineEdit:
	var control := LineEdit.new()
	control.custom_minimum_size = Vector2(ancho, 0.0)
	control.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	control.add_theme_font_override(&"font", GameTypography.ui_regular())
	control.add_theme_font_size_override(&"font_size", 19)
	control.add_theme_color_override(&"font_color", CREMA)
	control.add_theme_color_override(&"font_placeholder_color", APAGADO)
	control.add_theme_color_override(&"caret_color", LATON)
	control.add_theme_stylebox_override(&"normal", caja_campo(false))
	control.add_theme_stylebox_override(&"focus", caja_campo(true))
	return control


## La caja de un botón. Los márgenes son los MISMOS en todos los estados: si la
## barra del foco moviera el texto, la lista entera bailaría al pasar el ratón.
static func caja_boton(alfa: float, barra: bool) -> StyleBoxFlat:
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


static func caja_campo(activo: bool) -> StyleBoxFlat:
	var caja := StyleBoxFlat.new()
	caja.bg_color = Color(0.05, 0.08, 0.12, 0.85)
	caja.content_margin_left = 12.0
	caja.content_margin_right = 12.0
	caja.content_margin_top = 8.0
	caja.content_margin_bottom = 8.0
	caja.border_width_bottom = 2
	caja.border_color = LATON if activo else Color(0.35, 0.41, 0.45)
	return caja


## El fondo de una tarjeta que se pinta ENCIMA del mundo (el menú de Esc, la
## lista de tripulación). Opaca de verdad: sobre espuma blanca, un panel
## translúcido deja el texto ilegible justo cuando más prisa hay.
static func caja_panel() -> StyleBoxFlat:
	var caja := StyleBoxFlat.new()
	caja.bg_color = Color(PETROLEO.r, PETROLEO.g, PETROLEO.b, 0.92)
	caja.border_width_left = 3
	caja.border_color = LATON
	caja.content_margin_left = 26.0
	caja.content_margin_right = 26.0
	caja.content_margin_top = 22.0
	caja.content_margin_bottom = 22.0
	return caja
