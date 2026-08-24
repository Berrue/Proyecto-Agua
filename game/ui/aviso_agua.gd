class_name AvisoAgua
extends CanvasLayer

## Los dos unicos avisos del agua embarcada: ALARMA y NAUFRAGIO.
##
## Deliberadamente minimo (DISENO.md: "el barco es el HUD"). No hay barra de
## nivel a proposito: el nivel se lee en el barco —la escora hacia el costado
## anegado, el calado, lo pastoso que responde— y el dia que exista el audio, el
## chapoteo avisara mucho antes que esto. Lo que la pantalla aporta es lo que el
## barco no puede decir a tiempo: que esto ya no es normal.
##
## Tipografia por contrato (docs/TIPOGRAFIA.md, regla 11): Anybody condensada en
## MAYUSCULAS, que es la voz de los imperativos y los actos. El color expresa el
## estado y NUNCA la instruccion por si solo: el texto ya lo dice.

## Cuanto tarda en aparecer y desaparecer, en segundos. Un aviso que hace "pop"
## se lee como un bug del HUD; entrando en dos tercios de segundo se lee como que
## algo esta pasando en el barco.
const FUNDIDO := 0.65

## Parpadeo de la alarma, en Hz. Lento: es una campana de sentina, no una alerta
## de videojuego.
const PARPADEO_HZ := 0.8

@export var boat_path: NodePath = ^"FishingBoat"

var _label: Label
var _ajustes: LabelSettings
var _agua: AguaEmbarcada
var _estado: int = 0 ## 0 nada, 1 alarma, 2 naufragio
var _visible01: float = 0.0
var _fase: float = 0.0


func _ready() -> void:
	# Por encima del porteo (7) y de la pesca (8): si el barco se esta hundiendo,
	# eso manda sobre cualquier otro texto en pantalla.
	layer = 9

	_ajustes = LabelSettings.new()
	_ajustes.font = GameTypography.display_hud()
	_ajustes.font_size = 34
	_ajustes.outline_size = 9
	_ajustes.outline_color = Color(0.05, 0.05, 0.06)
	_ajustes.shadow_size = 6
	_ajustes.shadow_color = Color(0, 0, 0, 0.45)

	_label = Label.new()
	_label.label_settings = _ajustes
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_label.position += Vector2(0, 96)
	_label.visible = false
	add_child(_label)

	_enganchar()


## El barco puede no existir todavia (o no existir nunca, en un test de solo
## mar), asi que esto no es un error: el aviso simplemente se queda callado.
func _enganchar() -> void:
	var escena := get_tree().current_scene
	if escena == null:
		return
	var barco := escena.get_node_or_null(boat_path)
	if barco == null:
		return
	_agua = barco.get_node_or_null(^"AguaEmbarcada") as AguaEmbarcada
	if _agua == null:
		return
	_agua.alarma_cambiada.connect(_al_cambiar_alarma)
	_agua.naufragio.connect(_al_naufragar)
	_agua.reflotado.connect(_al_reflotar)


func _al_cambiar_alarma(encendida: bool) -> void:
	if _estado == 2:
		return # el naufragio ya esta dicho: no se degrada a alarma
	_estado = 1 if encendida else 0


func _al_naufragar(_causa: String) -> void:
	_estado = 2


func _al_reflotar() -> void:
	_estado = 0


func _process(delta: float) -> void:
	var objetivo: float = 0.0 if _estado == 0 else 1.0
	_visible01 = move_toward(_visible01, objetivo, delta / FUNDIDO)
	_label.visible = _visible01 > 0.001
	if not _label.visible:
		return

	_fase += delta
	match _estado:
		2:
			_label.text = "NAUFRAGIO"
			_ajustes.font_color = Color(0.94, 0.35, 0.30)
		_:
			_label.text = "ENTRA AGUA"
			# El parpadeo es del COLOR, no de la visibilidad: un texto que
			# desaparece y vuelve obliga a esperarlo para leerlo.
			var pulso: float = 0.5 + 0.5 * sin(_fase * TAU * PARPADEO_HZ)
			_ajustes.font_color = Color(0.98, 0.78, 0.35).lerp(
				Color(0.96, 0.55, 0.22), pulso)
	_label.modulate.a = _visible01
