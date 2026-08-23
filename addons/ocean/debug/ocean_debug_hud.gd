class_name OceanDebugHUD
extends CanvasLayer

## HUD de debug del oceano. La perilla de furia en manos de alguien que hace de
## dios cabron es, literalmente, la mecanica que hay que validar en F1.
##
## Muestra el numero que mas importa del sistema: Hs OBJETIVO frente a Hs
## MEDIDO. Si divergen mucho es que las olas estan saturando en su limite de
## rotura, que es correcto y deseable, pero hay que verlo y no adivinarlo.

@export var parity_markers_path: NodePath
@export var boat_path: NodePath
@export var director_path: NodePath
@export var day_night_path: NodePath

@export_group("Lanzador de tsunamis")
## Los tiers que apareceran como botones, en orden. Las teclas 1..N los lanzan.
@export var tsunami_tiers: Array[TsunamiTier] = []
## Segundos hasta el impacto con los que se lanza. Ajustable con el deslizador.
@export var default_lead_seconds: float = 40.0
## De donde viene, en grados. 90 = desde +Z.
@export var tsunami_from_direction_deg: float = 90.0

@onready var _slider: HSlider = %FurySlider
@onready var _readout: RichTextLabel = %Readout
@onready var _presets: HBoxContainer = %Presets
@onready var _parity_toggle: CheckButton = %ParityToggle
@onready var _tsunami_buttons: HBoxContainer = %TsunamiButtons
@onready var _lead_slider: HSlider = %LeadSlider
@onready var _lead_label: Label = %LeadLabel

var _parity_markers: Node3D
var _boat: FloatingBody3D
var _director: TsunamiDirector
var _day_night: DayNightCycle
var _slam_flash: float = 0.0
var _peak_wave: float = 0.0


func _ready() -> void:
	_parity_markers = get_node_or_null(parity_markers_path) as Node3D
	_boat = get_node_or_null(boat_path) as FloatingBody3D
	_director = get_node_or_null(director_path) as TsunamiDirector
	_day_night = get_node_or_null(day_night_path) as DayNightCycle

	_slider.min_value = 0.0
	_slider.max_value = 10.0
	_slider.step = 0.1
	_slider.value = Ocean.fury
	_slider.value_changed.connect(_on_fury_changed)

	for preset in [0, 3, 5, 8, 10]:
		var btn := Button.new()
		btn.text = str(preset)
		btn.custom_minimum_size = Vector2(36, 0)
		btn.pressed.connect(_on_preset.bind(float(preset)))
		_presets.add_child(btn)

	_parity_toggle.toggled.connect(_on_parity_toggled)
	if _parity_markers != null:
		_parity_toggle.button_pressed = _parity_markers.visible

	if _boat != null:
		_boat.slammed.connect(_on_slam)

	_build_tsunami_launcher()


# =============================================================================
#  Lanzador de tsunamis
# =============================================================================

func _build_tsunami_launcher() -> void:
	_lead_slider.min_value = 8.0
	_lead_slider.max_value = 120.0
	_lead_slider.step = 1.0
	_lead_slider.value = default_lead_seconds
	_lead_slider.value_changed.connect(func(_v: float) -> void: _update_lead_label())
	_update_lead_label()

	for i in tsunami_tiers.size():
		var tier: TsunamiTier = tsunami_tiers[i]
		if tier == null:
			continue
		var btn := Button.new()
		btn.text = "%d · %s" % [i + 1, tier.tier_name]
		btn.tooltip_text = tier.summary()
		btn.pressed.connect(_launch_tier.bind(tier))
		_tsunami_buttons.add_child(btn)

	var clear_btn := Button.new()
	clear_btn.text = "0 · limpiar"
	clear_btn.tooltip_text = "Cancela el tsunami en curso."
	clear_btn.pressed.connect(_clear_tsunami)
	_tsunami_buttons.add_child(clear_btn)


func _update_lead_label() -> void:
	_lead_label.text = "AVISO: %.0f s hasta el impacto" % _lead_slider.value


## Teclas 1..N para los tiers y 0 para limpiar.
##
## Los botones no bastan: durante el playtest el raton esta CAPTURADO porque
## estas de pie en la cubierta, asi que no puedes hacer clic sin soltarlo antes
## y perder justo el momento que querias provocar.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	var key := (event as InputEventKey).keycode
	if key == KEY_0:
		_clear_tsunami()
		get_viewport().set_input_as_handled()
		return
	if key == KEY_N and _day_night != null:
		_day_night.advance_hours(3.0)
		get_viewport().set_input_as_handled()
		return
	var index := key - KEY_1
	if index >= 0 and index < tsunami_tiers.size() and tsunami_tiers[index] != null:
		_launch_tier(tsunami_tiers[index])
		get_viewport().set_input_as_handled()


func _launch_tier(tier: TsunamiTier) -> void:
	# El director tiene su propio ciclo y volveria a llamar a `clear_events()`,
	# asi que se detiene: a partir de aqui manda el lanzador.
	if _director != null:
		_director.stop()
	Ocean.spawn_tsunami_tier(_target_position(), tsunami_from_direction_deg,
		_lead_slider.value, tier)


func _clear_tsunami() -> void:
	Ocean.clear_events()


## Hacia donde apunta el tsunami: el barco si lo hay, si no la camara.
func _target_position() -> Vector3:
	if _boat != null:
		return _boat.global_position
	var cam := get_viewport().get_camera_3d()
	return cam.global_position if cam != null else Vector3.ZERO


func _on_fury_changed(value: float) -> void:
	# Por el slider se usa la rampa: mover el dial de golpe es justo lo que el
	# rate limit esta para evitar.
	Ocean.fury = value


func _on_preset(value: float) -> void:
	Ocean.set_fury_immediate(value)
	_slider.set_value_no_signal(value)


func _on_parity_toggled(pressed: bool) -> void:
	if _parity_markers != null:
		_parity_markers.visible = pressed


func _on_slam(strength: float, _pos: Vector3) -> void:
	_slam_flash = maxf(_slam_flash, minf(strength, 3.0))


func _process(delta: float) -> void:
	_slam_flash = maxf(_slam_flash - delta * 2.0, 0.0)

	var cam := get_viewport().get_camera_3d()
	var here := cam.global_position if cam != null else Vector3.ZERO
	var wave_here := Ocean.get_height(here)
	_peak_wave = maxf(_peak_wave * 0.995, absf(wave_here))

	var breaking := Ocean.get_breaking(here)
	var steep := Ocean.steepness_sum()

	var lines := PackedStringArray()

	if Ocean.has_tsunami():
		var eta := Ocean.time_until_tsunami(here)
		var act_label := _director.act_name() if _director != null else "TSUNAMI"
		if Ocean.current_tier != null:
			act_label = "%s  ·  %s" % [Ocean.current_tier.tier_name, act_label]
		if _director != null and not _director.is_running():
			act_label += "  (manual)"
		# El color del contador es la telegrafia: pasa a rojo cuando ya no da
		# tiempo a hacer nada.
		var col := "#8fe388"
		if eta < 10.0:
			col = "#ff6b6b"
		elif eta < 55.0:
			col = "#ffd166"
		lines.append("[color=%s][b]%s[/b][/color]" % [col, act_label])
		if eta > -30.0 and eta < 900.0:
			lines.append("[color=%s][b]impacto en %+.1f s[/b][/color]" % [col, eta])
		# Altura que el tsunami aporta AQUI: negativa mientras el mar se retira.
		var ev_h := Ocean.get_events().height_at(Vector2(here.x, here.z), Ocean.sim_time)
		lines.append("aporte del evento %+.2f m" % ev_h)
		lines.append("")

	lines.append("[b]MAR[/b]")
	lines.append("furia            [b]%.2f[/b] / 10" % Ocean.fury)
	lines.append("Hs objetivo      %.2f m" % Ocean.target_hs())
	lines.append("Hs medido        [color=%s]%.2f m[/color]" % [
		"#8fe388" if absf(Ocean.measured_hs() - Ocean.target_hs()) < 0.5 else "#e3c988",
		Ocean.measured_hs()
	])
	lines.append("steepness        [color=%s]%.3f[/color] / %.2f" % [
		"#8fe388" if steep <= OceanWaveProxy.STEEPNESS_LIMIT else "#e38888",
		steep, OceanWaveProxy.STEEPNESS_LIMIT
	])
	lines.append("altura aqui      %.2f m  (pico %.1f)" % [wave_here, _peak_wave])
	lines.append("jacobiano        [color=%s]%.3f[/color]  %s" % [
		"#e38888" if breaking < 0.0 else "#8fe388",
		breaking,
		"ROMPIENDO" if breaking < 0.0 else ""
	])
	lines.append("t simulacion     %.1f s" % Ocean.sim_time)
	if _day_night != null:
		lines.append("hora             [b]%s[/b]  %s" % [
			_day_night.clock_text(),
			"[color=#9db4e8]NOCHE[/color]" if _day_night.is_night() else "[color=#e8d99d]DIA[/color]"])

	if _boat != null:
		lines.append("")
		lines.append("[b]BARCO[/b]")
		lines.append("sumergido        %.0f%%" % (_boat.submerged_fraction * 100.0))
		lines.append("inundacion       %.0f%%" % (_boat.flooding_level() * 100.0))
		lines.append("velocidad        %.1f m/s" % _boat.linear_velocity.length())
		if _slam_flash > 0.0:
			lines.append("[color=#ffd166][b]IMPACTO %.1f[/b][/color]" % _slam_flash)

	lines.append("")
	lines.append("[b]RENDIMIENTO[/b]")
	lines.append("fps              %d" % Engine.get_frames_per_second())
	lines.append("fisica           %.2f ms" % (
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0))
	lines.append("proceso          %.2f ms" % (
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0))

	_readout.text = "\n".join(lines)
