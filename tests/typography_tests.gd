extends Node

## Contrato headless del sistema tipografico: las fuentes correctas cargan,
## conservan los ejes variables y cubren todo el vocabulario que ya usa la UI.
## Evita el fallo silencioso de publicar glifos de reemplazo o volver sin querer
## a la fuente por defecto de Godot.

const REQUIRED_TEXT_GLYPHS := "ÁÉÍÓÚÜÑáéíóúüñ¡!¿?·—0123456789[]%+/,."
const REQUIRED_SYMBOL_GLYPHS := "←→"
const LICENSE_PATHS := [
	"res://assets/fonts/anybody/OFL.txt",
	"res://assets/fonts/atkinson-hyperlegible/OFL.txt",
	"res://assets/fonts/noto-symbols/OFL.txt",
]

var _failures: Array[String] = []


func _ready() -> void:
	print("\n=== TYPOGRAPHY TESTS ===")
	_test_sources_and_axes()
	_test_glyph_coverage()
	_test_license_files()
	_test_hud_wiring()
	if _failures.is_empty():
		print("=== TYPOGRAPHY TESTS: TODO OK ===\n")
		get_tree().quit(0)
	else:
		print("=== TYPOGRAPHY TESTS: %d FALLOS ===" % _failures.size())
		for failure in _failures:
			print("  - ", failure)
		get_tree().quit(1)


func _test_sources_and_axes() -> void:
	var display := GameTypography.display_hud()
	var brand := GameTypography.display_brand()
	var ui := GameTypography.ui_regular()
	_check(display.get_font_name().contains("Anybody"),
		"la voz de impacto carga Anybody", display.get_font_name())
	_check(ui.get_font_name().contains("Atkinson"),
		"la voz informativa carga Atkinson", ui.get_font_name())
	var text_server := TextServerManager.get_primary_interface()
	var axes := display.get_supported_variation_list()
	_check(axes.has(text_server.name_to_tag("wdth")), "Anybody conserva el eje wdth")
	_check(axes.has(text_server.name_to_tag("wght")), "Anybody conserva el eje wght")
	var hud_width := display.get_string_size(
		"¡¡RECOGE YA — SE SUELTA!!", HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	_check(hud_width < 600.0, "el aviso mas largo cabe en el ancho seguro",
		"%.1f px" % hud_width)
	_check(brand.get_string_size("PROYECTO AGUA", HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x
		> display.get_string_size("PROYECTO AGUA", HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x,
		"la voz de marca es mas ancha que la voz urgente")


func _test_glyph_coverage() -> void:
	var display := GameTypography.display_hud()
	var missing := ""
	for character in REQUIRED_TEXT_GLYPHS:
		if not display.has_char(character.unicode_at(0)):
			missing += character
	_check(missing.is_empty(), "la cadena española y numerica tiene cobertura",
		"faltan: %s" % missing)
	var symbols := GameTypography.symbols()
	missing = ""
	for character in REQUIRED_SYMBOL_GLYPHS:
		if not symbols.has_char(character.unicode_at(0)):
			missing += character
	_check(missing.is_empty(), "la reserva vendorizada cubre las flechas",
		"faltan: %s" % missing)
	_check(GameTypography.ui_bold().fallbacks.has(symbols),
		"la voz informativa encadena la reserva de simbolos")


func _test_license_files() -> void:
	var missing := ""
	for path in LICENSE_PATHS:
		if not FileAccess.file_exists(path):
			missing += (", " if missing != "" else "") + path
	_check(missing.is_empty(), "las tres licencias OFL estan vendorizadas",
		"faltan: %s" % missing)


func _test_hud_wiring() -> void:
	var hud := FishingHud.new()
	add_child(hud)
	_check(hud._action.label_settings.font == GameTypography.display_hud(),
		"los imperativos usan Faena costera")
	_check(hud._arrow.label_settings.font == GameTypography.ui_bold(),
		"las teclas y flechas usan la voz hiperlegible")
	hud.queue_free()


func _check(condition: bool, label: String, detail: String = "") -> void:
	if condition:
		print("  ok    ", label)
	else:
		var line := label + (("  ->  " + detail) if detail != "" else "")
		_failures.append(line)
		print("  FALLO ", line)
