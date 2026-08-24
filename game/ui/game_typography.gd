class_name GameTypography
extends RefCounted

## Sistema tipografico compartido del juego.
##
## "Faena costera" combina una voz de rotulacion de pesquero para impacto con
## una voz hiperlegible para informacion. Las variantes se crean aca para que
## el HUD, el titulo futuro y la UI diegetica no inventen pesos o anchos por su
## cuenta. El nombre del juego sigue abierto: esto define el idioma visual, no
## un wordmark definitivo.

const DISPLAY_SOURCE: FontFile = preload(
	"res://assets/fonts/anybody/Anybody[wdth,wght].ttf")
const UI_REGULAR_SOURCE: FontFile = preload(
	"res://assets/fonts/atkinson-hyperlegible/AtkinsonHyperlegible-Regular.ttf")
const UI_BOLD_SOURCE: FontFile = preload(
	"res://assets/fonts/atkinson-hyperlegible/AtkinsonHyperlegible-Bold.ttf")
const SYMBOLS_SOURCE: FontFile = preload(
	"res://assets/fonts/noto-symbols/NotoSansSymbols[wght].ttf")

static var _display_hud: FontVariation
static var _display_brand: FontVariation
static var _ui_regular: FontVariation
static var _ui_bold: FontVariation
static var _symbols: FontVariation


## Imperativos, resultados y señales: condensada para soportar frases urgentes
## sin comerse la pantalla. El ancho es fijo; la furia cambia color/escala, no
## las metricas del texto que el jugador esta intentando leer.
static func display_hud() -> FontVariation:
	if _display_hud == null:
		_display_hud = _make_display(92.0, 700.0)
	return _display_hud


## Titulos, actos y marketing: mas ancha y humana que el HUD, como rotulo
## pintado sobre un casco. No se usa aun para cerrar un logo provisional.
static func display_brand() -> FontVariation:
	if _display_brand == null:
		_display_brand = _make_display(118.0, 700.0)
	return _display_brand


## Informacion sostenida, ayuda, unidades y cuerpo de texto.
static func ui_regular() -> FontVariation:
	if _ui_regular == null:
		_ui_regular = _make_ui(UI_REGULAR_SOURCE)
	return _ui_regular


## Teclas, numeros importantes y señal cooperativa a distancia.
static func ui_bold() -> FontVariation:
	if _ui_bold == null:
		_ui_bold = _make_ui(UI_BOLD_SOURCE)
	return _ui_bold


## Flechas y simbolos quedan vendorizados: una instruccion no puede cambiar de
## forma segun la fuente instalada en cada sistema operativo.
static func symbols() -> FontVariation:
	if _symbols == null:
		_symbols = FontVariation.new()
		_symbols.base_font = SYMBOLS_SOURCE
		var text_server := TextServerManager.get_primary_interface()
		_symbols.variation_opentype = {text_server.name_to_tag("wght"): 700.0}
		var fallbacks: Array[Font] = []
		if ThemeDB.fallback_font != null:
			fallbacks.append(ThemeDB.fallback_font)
		_symbols.fallbacks = fallbacks
	return _symbols


static func _make_display(width: float, weight: float) -> FontVariation:
	var font := FontVariation.new()
	font.base_font = DISPLAY_SOURCE
	var text_server := TextServerManager.get_primary_interface()
	font.variation_opentype = {
		text_server.name_to_tag("wdth"): width,
		text_server.name_to_tag("wght"): weight,
	}
	var fallbacks: Array[Font] = [ui_bold(), symbols()]
	if ThemeDB.fallback_font != null:
		fallbacks.append(ThemeDB.fallback_font)
	font.fallbacks = fallbacks
	return font


static func _make_ui(source: FontFile) -> FontVariation:
	var font := FontVariation.new()
	font.base_font = source
	var fallbacks: Array[Font] = [symbols()]
	if ThemeDB.fallback_font != null:
		fallbacks.append(ThemeDB.fallback_font)
	font.fallbacks = fallbacks
	return font
