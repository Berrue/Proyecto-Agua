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

@onready var _slider: HSlider = %FurySlider
@onready var _readout: RichTextLabel = %Readout
@onready var _presets: HBoxContainer = %Presets
@onready var _parity_toggle: CheckButton = %ParityToggle

var _parity_markers: Node3D
var _boat: FloatingBody3D
var _slam_flash: float = 0.0
var _peak_wave: float = 0.0


func _ready() -> void:
	_parity_markers = get_node_or_null(parity_markers_path) as Node3D
	_boat = get_node_or_null(boat_path) as FloatingBody3D

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
