class_name PorteoHud
extends CanvasLayer

## El HUD del porteo: UN prompt contextual y una barra de carga de lanzamiento.
## Deliberadamente minimo (DISENO.md: "el barco es el HUD") — no hay rejilla ni
## iconos: lo que llevas se VE en tus manos y en las de los demas. La pantalla
## solo enseña el boton, igual que la UI de pesca: primero se aprende, luego se
## presume, y cuando el juego este enseñado esto pasa a ayuda desactivable.
##
## Tipografia por contrato (docs/TIPOGRAFIA.md): tecla + ayuda en Atkinson
## (ui_bold), en frase normal — es instruccion sostenida, no un imperativo.

var _prompt: Label
var _carga_bg: ColorRect
var _carga_fill: ColorRect
## La tira del cinturon: hasta dos fichas abajo a la derecha. La ultima lleva
## la "Q" porque es la que sale (LIFO). Vacio = ni un pixel en pantalla.
var _cinturon_box: HBoxContainer
var _fichas: Array[Label] = []
## Aviso temporal que PISA al prompt (un rechazo del host, en red).
var _aviso: String = ""
var _aviso_seg: float = 0.0


func _ready() -> void:
	# Bajo la capa de pesca (8): si un dia coinciden, el "¡RECOGE!" manda.
	layer = 7

	_prompt = Label.new()
	var ls := LabelSettings.new()
	ls.font = GameTypography.ui_bold()
	ls.font_size = 21
	ls.font_color = Color(0.92, 0.95, 0.97)
	ls.outline_size = 7
	ls.outline_color = Color(0.05, 0.07, 0.1)
	ls.shadow_size = 5
	ls.shadow_color = Color(0, 0, 0, 0.4)
	_prompt.label_settings = ls
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.position += Vector2(0, -130)
	_prompt.visible = false
	add_child(_prompt)

	# La barra de carga: fina y muda, como la de sedal. Crece hacia los lados
	# desde el centro; el color pasa de hueso a ambar al llenarse.
	_carga_bg = ColorRect.new()
	_carga_bg.custom_minimum_size = Vector2(180, 6)
	_carga_bg.color = Color(0.05, 0.08, 0.12, 0.75)
	_carga_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_carga_bg.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_carga_bg.position += Vector2(-90, -104)
	_carga_bg.visible = false
	add_child(_carga_bg)

	_carga_fill = ColorRect.new()
	_carga_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_carga_fill.position = Vector2(2, 2)
	_carga_fill.size = Vector2(0, 2)
	_carga_bg.add_child(_carga_fill)

	_cinturon_box = HBoxContainer.new()
	_cinturon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cinturon_box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_cinturon_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_cinturon_box.position += Vector2(-24, -28)
	_cinturon_box.add_theme_constant_override("separation", 8)
	_cinturon_box.visible = false
	add_child(_cinturon_box)
	for i in 2:
		var ficha := Label.new()
		var fls := LabelSettings.new()
		fls.font = GameTypography.ui_regular()
		fls.font_size = 16
		fls.font_color = Color(0.85, 0.89, 0.92)
		fls.outline_size = 6
		fls.outline_color = Color(0.05, 0.07, 0.1)
		fls.shadow_size = 4
		fls.shadow_color = Color(0, 0, 0, 0.4)
		ficha.label_settings = fls
		ficha.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ficha.visible = false
		_cinturon_box.add_child(ficha)
		_fichas.append(ficha)


func set_prompt(texto: String) -> void:
	# El aviso manda mientras dura: enterarte de POR QUE no pudiste importa mas
	# que ver otra vez el mismo "E agarrar".
	var final := _aviso if _aviso_seg > 0.0 else texto
	if _prompt.text != final:
		_prompt.text = final
	_prompt.visible = not final.is_empty()


## Un aviso corto en el sitio del prompt: "se te adelantó Ana", "el cinturón
## está lleno". Existe porque en red un gesto puede fallar por culpa de otro, y
## la regla 8 pide que el fallo se DIGA — un botón que no hace nada es
## exactamente el "me robó" que el juego promete no hacer.
func set_aviso(texto: String, segundos: float) -> void:
	if texto.is_empty():
		return
	_aviso = texto
	_aviso_seg = segundos


func _process(delta: float) -> void:
	if _aviso_seg > 0.0:
		_aviso_seg -= delta
		if _aviso_seg <= 0.0:
			_aviso = ""


## La tira del cinturon: una ficha por objeto guardado, la ultima con su "Q"
## (es la que Q devuelve a la mano). Sin objetos, la tira desaparece entera.
func set_cinturon(nombres: PackedStringArray) -> void:
	_cinturon_box.visible = not nombres.is_empty()
	for i in _fichas.size():
		var ficha := _fichas[i]
		if i < nombres.size():
			var ultima := i == nombres.size() - 1
			ficha.text = ("Q  %s" % nombres[i]) if ultima else nombres[i]
			ficha.visible = true
		else:
			ficha.visible = false


## carga < 0 esconde la barra; 0..1 la pinta.
func set_carga(carga: float) -> void:
	var activa := carga >= 0.0
	_carga_bg.visible = activa
	if not activa:
		return
	var c := clampf(carga, 0.0, 1.0)
	_carga_fill.size = Vector2((_carga_bg.custom_minimum_size.x - 4.0) * c, 2)
	_carga_fill.color = Color(0.92, 0.86, 0.70).lerp(Color(1.0, 0.72, 0.25), c)
