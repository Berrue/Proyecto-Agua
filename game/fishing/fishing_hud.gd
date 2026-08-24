class_name FishingHud
extends CanvasLayer

## UI de pesca en pantalla — nacida del playtest: "el gameplay es confuso".
##
## La doctrina "todo diegetico" (la caña ES la interfaz) fallo el test de
## legibilidad con jugadores reales, asi que la pantalla ENSEÑA la jugada:
##
## - "!" gigante con punch al picar (el momento de reaccionar, inconfundible).
## - Durante la lucha, una FLECHA con la tecla a pulsar (el pez tira a un lado,
##   tu contras al otro) que da un punch en cada cambio de fase.
## - "¡RECOGE!" en la pausa (la ventana buena), "¡RECOGE YA!" si el anzuelo se
##   esta soltando, "¡SUELTA EL CLIC!" en rojo si vas a romper.
## - Barra fina de sedal recogido, teñida por la tension real.
## - Resultado con su color: captura dorada, rotura roja, escapada gris.
##
## Todo se construye en codigo (cero .tscn) y con tweens de punch: la
## legibilidad tambien puede ser juicy. Cuando el juego este enseñado, esta UI
## puede pasar a ser una "ayuda de pesca" desactivable — pero primero se
## aprende, luego se presume.

enum FontRole {
	DISPLAY,
	UI_BOLD,
}

var _bite_mark: Label
var _arrow: Label
var _action: Label
var _bar_bg: ColorRect
var _bar_fill: ColorRect
var _fight_box: VBoxContainer
var _result: Label
var _flash: ColorRect
var _result_tween: Tween


func _ready() -> void:
	layer = 8

	# Flash unico de picada: blanco-azulado, corto, de baja intensidad (WCAG:
	# un destello aislado ni siquiera cuenta como flash).
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(0.75, 0.85, 1.0, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)

	_bite_mark = _make_label("!", 150, Color(1.0, 0.85, 0.2), 16, FontRole.DISPLAY)
	_bite_mark.set_anchors_preset(Control.PRESET_CENTER)
	_bite_mark.position += Vector2(-30, -220)
	add_child(_bite_mark)

	_fight_box = VBoxContainer.new()
	_fight_box.set_anchors_preset(Control.PRESET_CENTER)
	_fight_box.position += Vector2(-160, 90)
	_fight_box.custom_minimum_size = Vector2(320, 0)
	_fight_box.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_fight_box)

	_arrow = _make_label("", 96, Color.WHITE, 12, FontRole.UI_BOLD)
	_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fight_box.add_child(_arrow)

	_action = _make_label("", 30, Color.WHITE, 8, FontRole.DISPLAY)
	_action.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fight_box.add_child(_action)

	# La barra de sedal: fina, sin numeros. El color ES la tension real.
	var bar_holder := CenterContainer.new()
	bar_holder.custom_minimum_size = Vector2(320, 18)
	_fight_box.add_child(bar_holder)
	_bar_bg = ColorRect.new()
	_bar_bg.custom_minimum_size = Vector2(260, 8)
	_bar_bg.color = Color(0.05, 0.08, 0.12, 0.75)
	bar_holder.add_child(_bar_bg)
	_bar_fill = ColorRect.new()
	_bar_fill.position = Vector2(2, 2)
	_bar_fill.size = Vector2(0, 4)
	_bar_bg.add_child(_bar_fill)

	_result = _make_label("", 44, Color.WHITE, 10, FontRole.DISPLAY)
	_result.set_anchors_preset(Control.PRESET_CENTER)
	_result.position += Vector2(-300, -80)
	_result.custom_minimum_size = Vector2(600, 0)
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_result)

	hide_all()


func _make_label(text: String, size: int, color: Color, outline: int, role: int) -> Label:
	var l := Label.new()
	l.text = text
	var ls := LabelSettings.new()
	ls.font = (GameTypography.display_hud() if role == FontRole.DISPLAY
		else GameTypography.ui_bold())
	ls.font_size = size
	ls.font_color = color
	ls.outline_size = outline
	ls.outline_color = Color(0.05, 0.07, 0.1)
	ls.shadow_size = 6
	ls.shadow_color = Color(0, 0, 0, 0.4)
	l.label_settings = ls
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func hide_all() -> void:
	_bite_mark.visible = false
	_fight_box.visible = false


## ¡PICA! — el "!" en pantalla con punch, mas un unico destello suave.
func show_bite() -> void:
	_bite_mark.visible = true
	_bite_mark.pivot_offset = _bite_mark.size * 0.5
	_bite_mark.scale = Vector2.ONE * 0.3
	_bite_mark.rotation = randf_range(-0.15, 0.15)
	var tw := create_tween()
	tw.tween_property(_bite_mark, "scale", Vector2.ONE * 1.3, 0.1) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_bite_mark, "scale", Vector2.ONE, 0.12)

	_flash.color.a = 0.16
	var ftw := create_tween()
	ftw.tween_property(_flash, "color:a", 0.0, 0.18)


func on_hooked() -> void:
	_bite_mark.visible = false
	_fight_box.visible = true


## Actualiza la lucha cada frame: flecha de la tecla correcta, accion de la
## fase, y barra de sedal teñida por la tension.
func update_fight(pull_dir: int, resting: bool, tension_norm: float,
		progress: float, spit_warning: bool, reeling: bool) -> void:
	if not _fight_box.visible:
		return

	# La flecha apunta la tecla que hay que PULSAR (la contra del tiron):
	# el pez tira a la izquierda -> pulsa D (->).
	if not resting:
		_arrow.visible = true
		_arrow.text = "→  [D]" if pull_dir == FightModel.Pull.LEFT else "[A]  ←"
		if tension_norm >= 0.8 and reeling:
			_action.text = "¡SUELTA EL CLIC!"
			_action.label_settings.font_color = Color(1.0, 0.3, 0.25)
		else:
			_action.text = "aguanta la contra"
			_action.label_settings.font_color = Color(0.85, 0.9, 0.95)
	else:
		_arrow.visible = false
		if spit_warning:
			_action.text = "¡¡RECOGE YA — SE SUELTA!!"
			_action.label_settings.font_color = Color(1.0, 0.75, 0.2)
		else:
			_action.text = "¡RECOGE!  (mantén clic)"
			_action.label_settings.font_color = Color(0.5, 0.95, 0.55)

	var tint := Color(0.85, 0.92, 1.0)
	if tension_norm > 0.7:
		tint = Color(0.95, 0.75, 0.25).lerp(Color(1.0, 0.25, 0.2),
			clampf((tension_norm - 0.9) / 0.1, 0.0, 1.0))
	_arrow.label_settings.font_color = tint
	_bar_fill.color = tint
	_bar_fill.size = Vector2(maxf((_bar_bg.size.x - 4.0) * progress, 0.0), 4)


## Punch de la flecha en cada cambio de fase: el ojo va solo a la instruccion.
func punch_arrow() -> void:
	if not _fight_box.visible:
		return
	_arrow.pivot_offset = _arrow.size * 0.5
	_arrow.scale = Vector2.ONE * 1.45
	var tw := create_tween()
	tw.tween_property(_arrow, "scale", Vector2.ONE, 0.15) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Resultado con su color: se planta con punch y se desvanece solo.
func show_result(text: String, color: Color) -> void:
	hide_all()
	if _result_tween != null and _result_tween.is_valid():
		_result_tween.kill()
	_result.text = text
	_result.label_settings.font_color = color
	_result.visible = true
	_result.modulate.a = 1.0
	_result.pivot_offset = _result.size * 0.5
	_result.scale = Vector2.ONE * 0.6
	_result_tween = create_tween()
	_result_tween.tween_property(_result, "scale", Vector2.ONE, 0.15) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_result_tween.tween_interval(1.4)
	_result_tween.tween_property(_result, "modulate:a", 0.0, 0.5)
	_result_tween.tween_callback(func() -> void: _result.visible = false)
