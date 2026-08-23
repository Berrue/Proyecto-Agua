class_name FishingRod
extends Node3D

## La caña — el verbo del dia 1, ahora con el plan de game feel aplicado.
##
## PRINCIPIOS (de la investigacion, ya podados por el critico adversarial):
## - La tension se OYE: el click del freno del carrete acelera con la tension
##   real (el indicador universal de la pesca). Silencio = vas bien.
## - Los eventos criticos son picos MULTIMODALES en el mismo frame (Stardew):
##   escalonar tres señales debiles no suma un suceso fisico.
## - La picada es un juego de nervios (Animal Crossing): 1-4 toques FALSOS antes
##   del mordisco real, con polaridad sonora opuesta (plip agudo ascendente vs
##   chomp grave descendente). Tras el ultimo falso, el mordisco es GARANTIZADO.
## - La rotura SIEMPRE se telegrafia (crujido + sedal ambar->rojo 1-2 s antes):
##   "me aviso" en vez de "me robo".
## - El feedback jamas miente: todos los canales leen la MISMA tension real
##   (tiron del pez + aceleracion de la borda). Si el chirrido miente una vez,
##   el jugador deja de usarlo y el sistema muere.
## - Legible por la TRIPULACION: chomp y splashes son audio 3D EN la boya, el
##   "!" flota sobre ella, y la amplitud del cabeceo escala con el peso del pez.

signal fish_landed(fish: Fish)
signal line_snapped()

enum State { IDLE, CASTING, WAITING, NIBBLING, BITE, FIGHT }

const CAST_MIN_DIST := 5.0
const CAST_MAX_DIST := 18.0
const CAST_CHARGE_SECONDS := 1.2
const BITE_WINDOW := 1.8
## Cruce del tren de clicks al loop de buzz (correccion del critico: por encima
## de esto el scheduler de frames no llega; la fusion se hornea en el loop).
const BUZZ_CROSSOVER_HZ := 25.0

@export var player_path: NodePath
@export var fish_scene: PackedScene
@export var view_offset := Vector3(0.3, -0.34, -0.62)
@export var view_angles_deg := Vector3(-55.0, -10.0, -8.0)

var state: State = State.IDLE
var fight := FightModel.new()
var hooked_species: Dictionary = {}
var deck_accel_y: float = 0.0

var _player: Player
var _camfx: CameraFeedback
var _rng := RandomNumberGenerator.new()
var _charge: float = 0.0
var _wait_left: float = 0.0
var _bite_left: float = 0.0
var _cast_point := Vector2.ZERO
var _prev_platform_vy: float = 0.0
var _snap_flash: float = 0.0

# --- picada por capas --------------------------------------------------------
var _nibble_delays: PackedFloat32Array = PackedFloat32Array()
var _nibble_index: int = 0
var _nibble_timer: float = 0.0
var _nibble_dip: float = 0.0 ## 0..1, cuanto se hunde la boya en el toque falso

# --- feel: muelle de la caña -------------------------------------------------
var _bend: float = 0.0
var _bend_vel: float = 0.0
var _lateral: float = 0.0
var _lateral_vel: float = 0.0

# --- feel: audio -------------------------------------------------------------
var _click_cooldown: float = 0.0
var _creak_cooldown: float = 0.0
var _lap_cooldown: float = 0.0
var _prev_bobber_y: float = 0.0
var _prev_pull: FightModel.Pull = FightModel.Pull.NONE

# --- feel: eventos -----------------------------------------------------------
var _freeze_left: float = 0.0 ## hitstop LOCAL de presentacion (max 0.1 s)
var _silence_left: float = 0.0 ## hueco de casi-silencio tras la rotura
var _remnant_left: float = 0.0 ## trozo de sedal colgando tras el snap
var _adrift_left: float = 0.0 ## la boya perdida, a la deriva
var _rumble_refresh: float = 0.0
var _reel_rearm: bool = false ## tras clavar, recoger exige un clic NUEVO

var _reel_p: AudioStreamPlayer3D
var _reel_pb: AudioStreamPlaybackPolyphonic
var _buzz_p: AudioStreamPlayer3D
var _world_p: AudioStreamPlayer3D
var _world_pb: AudioStreamPlaybackPolyphonic
var _ui_p: AudioStreamPlayer
var _ui_pb: AudioStreamPlaybackPolyphonic
var _mark: Label3D

@onready var _tip: Node3D = $RodPivot/Tip
@onready var _rod_pivot: Node3D = $RodPivot
@onready var _bobber: MeshInstance3D = $Bobber
@onready var _line: MeshInstance3D = $Line
@onready var _line_mat := StandardMaterial3D.new()


## El plan de toques falsos: 1-4, separados 0.5-1.5 s. Estatica para el test.
static func plan_nibbles(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for _i in rng.randi_range(1, 4):
		out.append(rng.randf_range(0.5, 1.5))
	return out


func _ready() -> void:
	position = view_offset
	rotation_degrees = view_angles_deg
	_player = get_node_or_null(player_path) as Player
	_camfx = get_parent() as CameraFeedback
	_rng.randomize()
	_bobber.visible = false
	_bobber.top_level = true
	_line.top_level = true
	_line.mesh = ImmediateMesh.new()
	_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_mat.albedo_color = Color(0.9, 0.9, 0.85)
	_line.material_override = _line_mat
	_setup_audio()
	_setup_mark()


func _setup_audio() -> void:
	_reel_p = AudioStreamPlayer3D.new()
	_reel_p.bus = &"Reel"
	_reel_p.stream = AudioStreamPolyphonic.new()
	_rod_pivot.add_child(_reel_p)
	_reel_p.play()
	_reel_pb = _reel_p.get_stream_playback() as AudioStreamPlaybackPolyphonic

	_buzz_p = AudioStreamPlayer3D.new()
	_buzz_p.bus = &"Reel"
	_buzz_p.stream = SfxLibrary.reel_buzz
	_buzz_p.volume_db = -60.0
	_rod_pivot.add_child(_buzz_p)

	# Sonidos del MUNDO (boya, splashes): posicional y top_level, para que los
	# compañeros oigan DONDE pica y donde lucha el pez.
	_world_p = AudioStreamPlayer3D.new()
	_world_p.bus = &"SFX"
	_world_p.stream = AudioStreamPolyphonic.new()
	_world_p.top_level = true
	add_child(_world_p)
	_world_p.play()
	_world_pb = _world_p.get_stream_playback() as AudioStreamPlaybackPolyphonic

	_ui_p = AudioStreamPlayer.new()
	_ui_p.bus = &"SFX"
	_ui_p.stream = AudioStreamPolyphonic.new()
	add_child(_ui_p)
	_ui_p.play()
	_ui_pb = _ui_p.get_stream_playback() as AudioStreamPlaybackPolyphonic


## El "!" sobre la boya: la señal coop mas barata del dossier (Stardew) — el
## compañero a 20 m que no oye tu audio posicional VE que te ha picado.
func _setup_mark() -> void:
	_mark = Label3D.new()
	_mark.text = "!"
	# Tamaño de cartel: tiene que leerse a 20 m por un compañero distraido.
	_mark.font_size = 280
	_mark.pixel_size = 0.012
	_mark.modulate = Color(1.0, 0.9, 0.4)
	_mark.outline_size = 36
	_mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_mark.top_level = true
	_mark.visible = false
	add_child(_mark)


func _physics_process(delta: float) -> void:
	_update_deck_accel(delta)
	_freeze_left = maxf(_freeze_left - delta, 0.0)
	_silence_left = maxf(_silence_left - delta, 0.0)
	_snap_flash = maxf(_snap_flash - delta * 2.0, 0.0)

	match state:
		State.IDLE:
			if Input.is_action_just_pressed(&"grab"):
				state = State.CASTING
				_charge = 0.0
		State.CASTING:
			_charge = minf(_charge + delta / CAST_CHARGE_SECONDS, 1.0)
			# Anticipacion controlada por el jugador: rumble debil creciente.
			_refresh_rumble(delta, 0.1 + _charge * 0.2, 0.0)
			if Input.is_action_just_released(&"grab"):
				_cast()
		State.WAITING:
			_wait_left -= delta
			_lap_sounds(delta)
			if Input.is_action_just_pressed(&"grab"):
				_recall()
			elif _wait_left <= 0.0:
				_begin_nibbling()
		State.NIBBLING:
			_step_nibbling(delta)
		State.BITE:
			_bite_left -= delta
			if Input.is_action_just_pressed(&"grab"):
				_hook()
			elif _bite_left <= 0.0:
				_flee(false) # se escapo sin castigo: la ventana es generosa
		State.FIGHT:
			_step_fight(delta)

	if _camfx != null:
		_camfx.set_tension(_tension_norm() if state == State.FIGHT else 0.0)

	_update_visuals(delta)


func _tension_norm() -> float:
	return clampf(fight.tension / FightModel.SNAP_TENSION, 0.0, 1.0)


func _update_deck_accel(delta: float) -> void:
	var vy: float = 0.0
	if _player != null and _player.is_on_floor():
		vy = _player.get_platform_velocity().y
	var raw: float = (vy - _prev_platform_vy) / maxf(delta, 1e-5)
	_prev_platform_vy = vy
	deck_accel_y = lerpf(deck_accel_y, raw, clampf(8.0 * delta, 0.0, 1.0))


# =============================================================================
#  Lanzar y esperar
# =============================================================================

func _cast() -> void:
	var cam := get_viewport().get_camera_3d()
	var dist: float = lerpf(CAST_MIN_DIST, CAST_MAX_DIST, _charge)
	var fwd: Vector3 = -cam.global_transform.basis.z
	var flat := Vector2(fwd.x, fwd.z).normalized() * dist
	var origin := cam.global_position
	_cast_point = Vector2(origin.x, origin.z) + flat

	state = State.WAITING
	_wait_left = _rng.randf_range(8.0, 25.0) * clampf(1.0 - Ocean.fury * 0.06, 0.4, 1.0)
	_bobber.visible = true
	_bobber.global_position = _tip.global_position
	_stop_rumble()

	# El latigazo del lanzamiento: FOV kick sutil (+4 grados) y el muelle de la
	# caña suelta la carga — el follow-through sale gratis del muelle.
	if _camfx != null:
		_camfx.kick_fov(4.0, 0.12, 0.0, 0.5)
	_bend_vel += 6.0

	# Plop de caida donde aterriza la boya, con un vuelo corto visible.
	get_tree().create_timer(0.45).timeout.connect(func() -> void:
		if state == State.WAITING and _silence_left <= 0.0:
			_world_p.global_position = _bobber_rest_pos()
			SfxLibrary.play_one(_world_pb, SfxLibrary.plip, -2.0, 0.6))


func _bobber_rest_pos() -> Vector3:
	var pos := Vector3(_cast_point.x, 0.0, _cast_point.y)
	pos.y = Ocean.get_height(pos) + 0.05
	return pos


## El lap-lap de la boya en reposo: el fondo contra el que la picada sorprende.
func _lap_sounds(delta: float) -> void:
	_lap_cooldown -= delta
	if not _bobber.visible or _lap_cooldown > 0.0:
		return
	var vy: float = absf(_bobber.global_position.y - _prev_bobber_y) / maxf(delta, 1e-5)
	if vy > 0.35:
		_world_p.global_position = _bobber.global_position
		SfxLibrary.play_one(_world_pb, SfxLibrary.lap, -14.0)
		_lap_cooldown = _rng.randf_range(0.5, 1.1)


# =============================================================================
#  La picada por capas: nibbles falsos -> mordisco garantizado
# =============================================================================

func _begin_nibbling() -> void:
	state = State.NIBBLING
	hooked_species = FishSpecies.choose(Ocean.fury, _rng)
	_nibble_delays = plan_nibbles(_rng)
	_nibble_index = 0
	_nibble_timer = _nibble_delays[0]


func _step_nibbling(delta: float) -> void:
	_nibble_dip = maxf(_nibble_dip - delta * 3.0, 0.0)
	_nibble_timer -= delta
	_lap_sounds(delta)

	# Clavar durante un toque FALSO = el pez huye. Nace el juego de nervios.
	if Input.is_action_just_pressed(&"grab"):
		_flee(true)
		return

	if _nibble_timer <= 0.0:
		if _nibble_index < _nibble_delays.size():
			_do_nibble()
			_nibble_index += 1
			_nibble_timer = _nibble_delays[_nibble_index - 1] * 0.7 + 0.4 \
				if _nibble_index < _nibble_delays.size() else _rng.randf_range(0.4, 0.9)
		else:
			_start_bite() # tras el ultimo falso, el mordisco es GARANTIZADO


## Un toque falso: plip agudo, boya hundida solo 15-25%, micro-cabeceo, rumble
## debil. Todo lo CONTRARIO del mordisco, en todos los canales.
func _do_nibble() -> void:
	_nibble_dip = 1.0
	_world_p.global_position = _bobber.global_position
	SfxLibrary.play_one(_world_pb, SfxLibrary.plip, -4.0)
	_bend_vel += 2.5
	Input.start_joy_vibration(0, 0.25, 0.0, 0.1)


func _flee(punished: bool) -> void:
	# El pez se va: splash apagado y la sombra desaparece. Sin mas castigo que
	# la propia huida (y la verguenza, que en coop es el castigo real).
	_world_p.global_position = _bobber.global_position
	SfxLibrary.play_varied(_world_pb, SfxLibrary.splashes, "splash", -12.0 if punished else -16.0, 1.2)
	_recall()


func _start_bite() -> void:
	state = State.BITE
	_bite_left = BITE_WINDOW
	if hooked_species.is_empty():
		hooked_species = FishSpecies.choose(Ocean.fury, _rng)

	# EL PICO MULTIMODAL, todo el mismo frame (Stardew): chomp posicional EN la
	# boya, hundimiento total, tiron de la caña, doble pulso fuerte de rumble,
	# "!" sobre la boya, y punch-in de FOV como UNICO efecto de camara.
	_world_p.global_position = _bobber.global_position
	SfxLibrary.play_one(_world_pb, SfxLibrary.chomp, 0.0,
		clampf(1.3 - float(hooked_species[&"weight"]) * 0.012, 0.55, 1.3))
	_bend_vel += 5.0
	Input.start_joy_vibration(0, 0.0, 0.9, 0.12)
	get_tree().create_timer(0.2).timeout.connect(func() -> void:
		if state == State.BITE:
			Input.start_joy_vibration(0, 0.0, 0.9, 0.12))
	_mark.visible = true
	_mark.scale = Vector3.ONE * 0.2
	var tw := create_tween()
	tw.tween_property(_mark, "scale", Vector3.ONE * 1.25, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_mark, "scale", Vector3.ONE, 0.1)
	if _camfx != null:
		_camfx.kick_fov(-3.0, 0.08, BITE_WINDOW, 0.3)


func _hook() -> void:
	state = State.FIGHT
	fight.start(hooked_species, _rng)
	_reel_rearm = true # recoger exige un clic NUEVO: clavar no es recoger
	_prev_pull = fight.pull_dir
	_mark.visible = false
	_set_player_lock(true)


# =============================================================================
#  La lucha
# =============================================================================

func _step_fight(delta: float) -> void:
	var counter := FightModel.Pull.NONE
	if Input.is_action_pressed(&"move_left"):
		counter = FightModel.Pull.LEFT
	elif Input.is_action_pressed(&"move_right"):
		counter = FightModel.Pull.RIGHT

	# Acuse en el MISMO frame del input de contra: sacudida lateral + un click.
	if Input.is_action_just_pressed(&"move_left"):
		_ack_counter(-1.0)
	elif Input.is_action_just_pressed(&"move_right"):
		_ack_counter(1.0)

	if _reel_rearm and not Input.is_action_pressed(&"grab"):
		_reel_rearm = false
	var reeling := Input.is_action_pressed(&"grab") and not _reel_rearm

	fight.step(delta, reeling, counter, deck_accel_y)
	var norm := _tension_norm()

	# Cambios de fase del pez: el tiron arranca con splash 3D EN la boya (la
	# tripulacion oye donde y cuanto lucha); la pausa es SILENCIO — la señal.
	if fight.pull_dir != _prev_pull:
		if fight.pull_dir != FightModel.Pull.NONE and _rng.randf() < 0.6:
			_world_p.global_position = _bobber.global_position
			SfxLibrary.play_varied(_world_pb, SfxLibrary.splashes, "splash",
				-8.0 + float(hooked_species[&"pull"]) * 6.0, 1.15)
		_prev_pull = fight.pull_dir

	_click_train(delta, norm)
	_creak(delta, norm, counter)
	_fight_rumble(delta, norm)

	var cam := get_viewport().get_camera_3d()
	var origin := Vector2(cam.global_position.x, cam.global_position.z)
	_cast_point = origin + (_cast_point - origin) * (1.0 - fight.progress * 0.25 * delta * 10.0)

	if fight.snapped:
		_on_snap()
	elif fight.landed:
		_land()


func _ack_counter(side: float) -> void:
	_lateral_vel += side * 5.0
	SfxLibrary.play_varied(_reel_pb, SfxLibrary.reel_clicks, "click", -6.0)
	Input.start_joy_vibration(0, 0.2, 0.0, 0.05)


## El click del freno: la tension exacta, decodificable como un contador Geiger.
## Bajo el cruce, pulsos por acumulador; por encima, el loop de buzz pitcheado.
func _click_train(delta: float, norm: float) -> void:
	var rate := SfxLibrary.click_rate_for(norm)
	if norm > 0.85: # el zing: la linea saliendo a toda velocidad
		rate = lerpf(30.0, 60.0, (norm - 0.85) / 0.15)

	if rate >= BUZZ_CROSSOVER_HZ:
		if not _buzz_p.playing:
			_buzz_p.play()
		_buzz_p.pitch_scale = rate / 40.0
		_buzz_p.volume_db = lerpf(_buzz_p.volume_db, -6.0, clampf(10.0 * delta, 0.0, 1.0))
	else:
		_buzz_p.volume_db = lerpf(_buzz_p.volume_db, -60.0, clampf(10.0 * delta, 0.0, 1.0))
		if _buzz_p.playing and _buzz_p.volume_db < -50.0:
			_buzz_p.stop()
		if rate > 0.0:
			_click_cooldown -= delta
			if _click_cooldown <= 0.0:
				SfxLibrary.play_varied(_reel_pb, SfxLibrary.reel_clicks, "click",
					-4.0, 1.0 + 0.2 * norm)
				_click_cooldown = (1.0 / rate) * _rng.randf_range(0.85, 1.15)


## El crujido pre-rotura (stick-slip): la rampa que convierte la rotura en
## culpa propia. Tambien cruje al contrar en direccion equivocada.
func _creak(delta: float, norm: float, counter: FightModel.Pull) -> void:
	var wrong := fight.pull_dir != FightModel.Pull.NONE and counter == fight.pull_dir
	if norm < 0.7 and not wrong:
		return
	_creak_cooldown -= delta
	if _creak_cooldown > 0.0:
		return
	var t: float = clampf((norm - 0.7) / 0.3, 0.0, 1.0)
	var creak_rate: float = lerpf(4.0, 28.0, t) if norm >= 0.7 else 8.0
	# Ganancia minima garantizada por encima del 80%: es el aviso que sustituye
	# al rumble para quien juega sin mando.
	var gain: float = -10.0 + t * 6.0
	SfxLibrary.play_varied(_reel_pb, SfxLibrary.creak_pulses, "creak", gain, 1.0 + 0.3 * norm)
	_creak_cooldown = (1.0 / creak_rate) * _rng.randf_range(0.6, 1.4)


## Regla Sea of Thieves: vibra solo cuando algo va mal. Pausas = silencio total.
func _fight_rumble(delta: float, norm: float) -> void:
	if fight.pull_dir == FightModel.Pull.NONE and norm < 0.5:
		_stop_rumble()
		return
	_refresh_rumble(delta, norm * 0.5, clampf((norm - 0.7) / 0.3, 0.0, 1.0) * 0.8)


func _refresh_rumble(delta: float, weak: float, strong: float) -> void:
	_rumble_refresh -= delta
	if _rumble_refresh <= 0.0:
		Input.start_joy_vibration(0, weak, strong, 0.15)
		_rumble_refresh = 0.1


func _stop_rumble() -> void:
	Input.stop_joy_vibration(0)
	_rumble_refresh = 0.0


# =============================================================================
#  Rotura y captura: los dos eventos maximos
# =============================================================================

func _on_snap() -> void:
	# Mismo frame: snap + CORTE en seco de clicks/creak/rumble + hitstop local
	# de 100 ms + trauma. Despues, 300 ms de casi-silencio: el hueco ES el golpe.
	SfxLibrary.play_one(_reel_pb, SfxLibrary.snap, 2.0)
	_buzz_p.stop()
	_buzz_p.volume_db = -60.0
	Input.start_joy_vibration(0, 0.0, 1.0, 0.2)
	get_tree().create_timer(0.25).timeout.connect(_stop_rumble)
	_freeze_left = 0.1
	_silence_left = 0.3
	if _camfx != null:
		_camfx.add_trauma(0.6)
	# PERMANENCIA (Nijman): el compañero ve QUE paso sin haberlo mirado — un
	# trozo de sedal colgando de la caña y la boya perdida, a la deriva.
	_remnant_left = 6.0
	_adrift_left = 8.0
	_snap_flash = 1.0
	line_snapped.emit()
	_recall(true)


func _land() -> void:
	var fish: Fish = fish_scene.instantiate()
	get_tree().current_scene.add_child(fish)
	fish.setup(hooked_species)

	var water := _bobber_rest_pos()
	fish.global_position = water
	var to_player := _player.global_position - water
	var flat := Vector3(to_player.x, 0, to_player.z)
	fish.linear_velocity = flat * 1.1 + Vector3.UP * (4.5 + flat.length() * 0.45)
	fish.angular_velocity = Vector3(_rng.randf_range(-6, 6), _rng.randf_range(-6, 6), _rng.randf_range(-6, 6))

	# El climax encadenado: freeze de 70 ms al romper el agua -> splash 3D ->
	# jingle a +250 ms (nunca solapado) -> el thud lo pone el pez al aterrizar.
	_freeze_left = 0.07
	_world_p.global_position = water
	SfxLibrary.play_varied(_world_pb, SfxLibrary.splashes, "splash", 0.0)
	var rarity: int = 2 if fish.value >= 400 else (1 if fish.value >= 90 else 0)
	get_tree().create_timer(0.25).timeout.connect(func() -> void:
		SfxLibrary.play_one(_ui_pb, SfxLibrary.jingles[rarity], -4.0))
	# Rumble alegre: doble pulso debil (canal haptico del climax, del critico).
	Input.start_joy_vibration(0, 0.4, 0.0, 0.1)
	get_tree().create_timer(0.15).timeout.connect(func() -> void:
		Input.start_joy_vibration(0, 0.4, 0.0, 0.1))
	if _camfx != null:
		_camfx.add_trauma(0.35)

	fish_landed.emit(fish)
	_recall()


func _recall(keep_adrift: bool = false) -> void:
	state = State.IDLE
	hooked_species = {}
	if not keep_adrift:
		_bobber.visible = false
	(_line.mesh as ImmediateMesh).clear_surfaces()
	_mark.visible = false
	_nibble_dip = 0.0
	_stop_rumble()
	_buzz_p.stop()
	_buzz_p.volume_db = -60.0
	_set_player_lock(false)


func _set_player_lock(locked: bool) -> void:
	if _player != null:
		_player.hands_busy = locked


func _exit_tree() -> void:
	_stop_rumble()


# =============================================================================
#  Visual: la caña ES la interfaz
# =============================================================================

func _update_visuals(delta: float) -> void:
	_prev_bobber_y = _bobber.global_position.y

	# Hitstop LOCAL: la presentacion se congela (la camara y el raton JAMAS).
	if _freeze_left > 0.0:
		_rod_pivot.rotation.x = -_bend + sin(Time.get_ticks_msec() * 0.08) * 0.01
		_draw_line()
		return

	# Muelle sub-amortiguado (K=120, D=12): la caña tiene masa, no un lerp.
	# El follow-through al soltar tension sale gratis: 1-2 oscilaciones.
	var target: float = 0.0
	match state:
		State.CASTING:
			target = -_charge * 0.5
		State.NIBBLING:
			target = _nibble_dip * 0.12
		State.BITE:
			target = 0.45 + sin(Time.get_ticks_msec() * 0.03) * 0.15
		State.FIGHT:
			# Exagerar mas de lo fisicamente creible (low-poly lo tolera) y
			# escalar con el peso: el compañero lee "es gordo" a 20 m.
			var weight_scale: float = 1.0 + float(hooked_species.get(&"weight", 2.0)) * 0.004
			target = clampf(fight.tension, 0.0, 1.3) * 0.75 * weight_scale
			if fight.is_warning():
				target += sin(Time.get_ticks_msec() * 0.09) * 0.08
	_bend_vel += ((target - _bend) * 120.0 - _bend_vel * 12.0) * delta
	_bend += _bend_vel * delta
	_lateral_vel += ((0.0 - _lateral) * 140.0 - _lateral_vel * 10.0) * delta
	_lateral += _lateral_vel * delta

	_rod_pivot.rotation.x = -_bend
	_rod_pivot.rotation.z = _lateral * 0.03
	if _snap_flash > 0.0:
		_rod_pivot.rotation.x += _snap_flash * sin(_snap_flash * 40.0) * 0.3

	# El sedal cambia de color con la tension real: neutro -> ambar (70%) ->
	# rojo (90%). Siempre en el centro de la mirada, y visible para el de al lado.
	var norm := _tension_norm() if state == State.FIGHT else 0.0
	var line_col := Color(0.9, 0.9, 0.85)
	if norm > 0.7:
		line_col = Color(0.95, 0.75, 0.25).lerp(Color(0.95, 0.2, 0.15),
			clampf((norm - 0.9) / 0.1, 0.0, 1.0)) if norm > 0.9 \
			else Color(0.9, 0.9, 0.85).lerp(Color(0.95, 0.75, 0.25),
			clampf((norm - 0.7) / 0.2, 0.0, 1.0))
	_line_mat.albedo_color = line_col

	# La boya.
	if _bobber.visible:
		if _adrift_left > 0.0:
			# Perdida: se queda cabalgando la ola donde rompio el sedal.
			_adrift_left -= delta
			var drift := _bobber_rest_pos()
			_bobber.global_position = _bobber.global_position.lerp(drift, clampf(3.0 * delta, 0, 1))
			if _adrift_left <= 0.0:
				_bobber.visible = false
		else:
			var pos := _bobber_rest_pos()
			match state:
				State.NIBBLING:
					pos.y -= _nibble_dip * 0.12 # 15-25% hundida: toque falso
				State.BITE:
					pos.y -= 0.3 + sin(Time.get_ticks_msec() * 0.02) * 0.1 # TODA
				State.FIGHT:
					if fight.is_pulling():
						var side := 1.0 if fight.pull_dir == FightModel.Pull.RIGHT else -1.0
						pos.x += side * sin(Time.get_ticks_msec() * 0.008) * 0.6
				State.WAITING, State.CASTING, State.IDLE:
					pass
			# La picada tira ACELERANDO (algo vivo), la espera flota suave.
			var speed: float = 14.0 if state == State.BITE else 8.0
			_bobber.global_position = _bobber.global_position.lerp(pos, clampf(speed * delta, 0, 1))

	if _mark.visible:
		_mark.global_position = _bobber.global_position + Vector3.UP * 1.1

	_draw_line()


func _draw_line() -> void:
	var im := _line.mesh as ImmediateMesh
	im.clear_surfaces()

	# Trozo de sedal colgando tras la rotura: la permanencia del fallo.
	if _remnant_left > 0.0:
		_remnant_left -= get_physics_process_delta_time()
		var a := _tip.global_position
		var sway := sin(Time.get_ticks_msec() * 0.004) * 0.06
		im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for i in 5:
			var t := float(i) / 4.0
			im.surface_add_vertex(_line.to_local(a + Vector3(sway * t, -0.5 * t, 0.05 * t)))
		im.surface_end()
		return

	if not _bobber.visible or _adrift_left > 0.0 or state == State.IDLE or state == State.CASTING:
		return
	var a := _tip.global_position
	var b := _bobber.global_position
	var slack: float = 1.2
	if state == State.FIGHT:
		slack = lerpf(0.9, 0.05, clampf(fight.tension, 0.0, 1.0))
	var mid := (a + b) * 0.5 + Vector3.DOWN * slack
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in 9:
		var t := float(i) / 8.0
		var p := a.lerp(mid, t).lerp(mid.lerp(b, t), t)
		im.surface_add_vertex(_line.to_local(p))
	im.surface_end()


## Linea de estado para el HUD de debug (el juego real no la enseña).
func debug_line() -> String:
	match state:
		State.IDLE:
			return "caña lista  ·  clic: lanzar"
		State.CASTING:
			return "cargando  %d%%" % int(_charge * 100)
		State.WAITING:
			return "esperando  (%.0f s)  ·  mar %.2f m/s2" % [_wait_left, absf(deck_accel_y)]
		State.NIBBLING:
			return "algo ronda la boya..."
		State.BITE:
			return "[b]¡PICA![/b]  clic para clavar  (%.1f s)" % _bite_left
		State.FIGHT:
			var dir := "<- tira IZQ" if fight.pull_dir == FightModel.Pull.LEFT else \
				("tira DER ->" if fight.pull_dir == FightModel.Pull.RIGHT else "descansa: ¡RECOGE!")
			var warn := "  [color=#ff6b6b]¡¡CHIRRIA!![/color]" if fight.is_warning() else ""
			return "%s %.0f kg  ·  %s  ·  T=%.2f  ·  %d%%%s" % [
				hooked_species[&"name"], hooked_species[&"weight"], dir,
				fight.tension, int(fight.progress * 100), warn]
	return ""
