class_name FishingRod
extends Node3D

## La caña — el verbo del dia 1 y el gate anti-mareo del proyecto.
##
## SIN UNA SOLA BARRA DE UI: la caña, el sedal y el carrete son la interfaz.
## La caña se dobla con la tension, el sedal cuelga hacia la boya, y el estado
## se lee mirando — tambien lo leen los COMPAÑEROS, que pueden gritarte
## "¡suelta!" al ver la caña doblada (Sea of Thieves: la pesca diegetica es
## legible por terceros).
##
## Estados: IDLE -> CASTING (cargar) -> WAITING (boya en el agua) -> BITE
## (ventana generosa) -> FIGHT (FightModel) -> pez a cubierta o latigazo.
##
## Durante FIGHT las dos manos estan ocupadas: A/D dejan de mover al jugador y
## pasan a ser la CONTRA contra el tiron del pez. No puedes agarrarte — esa es
## la apuesta fisica de pescar con mar bravo.

signal fish_landed(fish: Fish)
signal line_snapped()

enum State { IDLE, CASTING, WAITING, BITE, FIGHT }

const CAST_MIN_DIST := 5.0
const CAST_MAX_DIST := 18.0
const CAST_CHARGE_SECONDS := 1.2
## Ventana de enganche generosa (diseño: 1.5-2 s). Fallarla = el pez se va,
## cero castigo extra.
const BITE_WINDOW := 1.8

@export var player_path: NodePath
@export var fish_scene: PackedScene

## Colocacion view-model respecto a la camara: abajo-derecha, cruzando el
## cuadro hacia arriba-centro. Se fija por codigo (no en la escena) porque
## depende del FOV y es lo que mas se va a retocar en el playtest de mareo.
@export var view_offset := Vector3(0.3, -0.34, -0.62)
@export var view_angles_deg := Vector3(-55.0, -10.0, -8.0)

var state: State = State.IDLE
var fight := FightModel.new()
var hooked_species: Dictionary = {}
## Aceleracion vertical de la cubierta bajo los pies, suavizada. ES el termino
## del mar en la formula de tension.
var deck_accel_y: float = 0.0

var _player: Player
var _rng := RandomNumberGenerator.new()
var _charge: float = 0.0
var _wait_left: float = 0.0
var _bite_left: float = 0.0
var _cast_point := Vector2.ZERO
var _prev_platform_vy: float = 0.0
var _snap_flash: float = 0.0

@onready var _tip: Node3D = $RodPivot/Tip
@onready var _rod_pivot: Node3D = $RodPivot
@onready var _bobber: MeshInstance3D = $Bobber
@onready var _line: MeshInstance3D = $Line


func _ready() -> void:
	position = view_offset
	rotation_degrees = view_angles_deg
	_player = get_node_or_null(player_path) as Player
	_rng.randomize()
	_bobber.visible = false
	_bobber.top_level = true # la boya vive en el mundo, no pegada a la camara
	_line.top_level = true
	_line.mesh = ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.9, 0.9, 0.85)
	_line.material_override = mat


func _physics_process(delta: float) -> void:
	_update_deck_accel(delta)

	match state:
		State.IDLE:
			if Input.is_action_just_pressed(&"grab"):
				state = State.CASTING
				_charge = 0.0
		State.CASTING:
			_charge = minf(_charge + delta / CAST_CHARGE_SECONDS, 1.0)
			if Input.is_action_just_released(&"grab"):
				_cast()
		State.WAITING:
			_wait_left -= delta
			if Input.is_action_just_pressed(&"grab"):
				_recall() # recoger en vacio: sin castigo, sin espera artificial
			elif _wait_left <= 0.0:
				_start_bite()
		State.BITE:
			_bite_left -= delta
			if Input.is_action_just_pressed(&"grab"):
				_hook()
			elif _bite_left <= 0.0:
				_recall() # el pez se va. La boya se aquieta y ya esta.
		State.FIGHT:
			_step_fight(delta)

	_snap_flash = maxf(_snap_flash - delta * 2.0, 0.0)
	_update_visuals(delta)


## La aceleracion vertical REAL de la cubierta, medida de la velocidad de
## plataforma del CharacterBody (el barco bajo los pies). En tierra firme es
## cero y la formula degenera a pesca de estanque — gratis.
func _update_deck_accel(delta: float) -> void:
	var vy: float = 0.0
	if _player != null and _player.is_on_floor():
		vy = _player.get_platform_velocity().y
	var raw: float = (vy - _prev_platform_vy) / maxf(delta, 1e-5)
	_prev_platform_vy = vy
	# Suavizado: la tension debe respirar con la ola, no vibrar con el tick.
	deck_accel_y = lerpf(deck_accel_y, raw, clampf(8.0 * delta, 0.0, 1.0))


func _cast() -> void:
	# La boya cae donde miras, a distancia segun la carga.
	var cam := get_viewport().get_camera_3d()
	var dist: float = lerpf(CAST_MIN_DIST, CAST_MAX_DIST, _charge)
	var fwd: Vector3 = -cam.global_transform.basis.z
	var flat := Vector2(fwd.x, fwd.z).normalized() * dist
	var origin := cam.global_position
	_cast_point = Vector2(origin.x, origin.z) + flat

	state = State.WAITING
	# Espera 8-25 s del diseño, acortada con la furia: el mar bravo pica antes
	# (y pescar ahi es la apuesta).
	_wait_left = _rng.randf_range(8.0, 25.0) * clampf(1.0 - Ocean.fury * 0.06, 0.4, 1.0)
	_bobber.visible = true


func _recall() -> void:
	state = State.IDLE
	hooked_species = {}
	_bobber.visible = false
	(_line.mesh as ImmediateMesh).clear_surfaces()
	_set_player_lock(false)


func _start_bite() -> void:
	state = State.BITE
	_bite_left = BITE_WINDOW
	hooked_species = FishSpecies.choose(Ocean.fury, _rng)


func _hook() -> void:
	state = State.FIGHT
	fight.start(hooked_species, _rng)
	_set_player_lock(true)


func _step_fight(delta: float) -> void:
	# A/D son la CONTRA mientras luchas: el mismo input que te movia.
	var counter := FightModel.Pull.NONE
	if Input.is_action_pressed(&"move_left"):
		counter = FightModel.Pull.LEFT
	elif Input.is_action_pressed(&"move_right"):
		counter = FightModel.Pull.RIGHT
	var reeling := Input.is_action_pressed(&"grab")

	fight.step(delta, reeling, counter, deck_accel_y)

	# La boya se acerca con el progreso: el sedal recogido SE VE.
	var cam := get_viewport().get_camera_3d()
	var origin := Vector2(cam.global_position.x, cam.global_position.z)
	_cast_point = origin + (_cast_point - origin) * (1.0 - fight.progress * 0.25 * delta * 10.0)

	if fight.snapped:
		_snap_flash = 1.0
		line_snapped.emit()
		_recall()
	elif fight.landed:
		_land()


func _land() -> void:
	var fish: Fish = fish_scene.instantiate()
	get_tree().current_scene.add_child(fish)
	fish.setup(hooked_species)

	# El pez sale volando del agua hacia la cubierta en arco: comedia fisica
	# gratis, y aterriza como rigidbody que ademas flota si vuelve a caer.
	var water := Vector3(_cast_point.x, Ocean.get_height(Vector3(_cast_point.x, 0, _cast_point.y)), _cast_point.y)
	fish.global_position = water
	var to_player := _player.global_position - water
	var flat := Vector3(to_player.x, 0, to_player.z)
	fish.linear_velocity = flat * 1.1 + Vector3.UP * (4.5 + flat.length() * 0.45)
	fish.angular_velocity = Vector3(_rng.randf_range(-6, 6), _rng.randf_range(-6, 6), _rng.randf_range(-6, 6))

	fish_landed.emit(fish)
	_recall()


func _set_player_lock(locked: bool) -> void:
	if _player != null:
		_player.hands_busy = locked


# =============================================================================
#  Visual: la caña ES la interfaz
# =============================================================================

func _update_visuals(delta: float) -> void:
	# Doblado de la caña por tension (o por carga al lanzar). smoothstep para
	# que respire en vez de vibrar.
	var bend: float = 0.0
	match state:
		State.CASTING:
			bend = -_charge * 0.5 # se arma hacia atras
		State.BITE:
			bend = 0.45 + sin(Time.get_ticks_msec() * 0.03) * 0.15 # cabecea: ¡pica!
		State.FIGHT:
			bend = clampf(fight.tension, 0.0, 1.3) * 0.75
			if fight.is_warning():
				# El chirrido visual: vibracion fina cerca de la rotura.
				bend += sin(Time.get_ticks_msec() * 0.09) * 0.08
	_rod_pivot.rotation.x = lerpf(_rod_pivot.rotation.x, -bend, clampf(12.0 * delta, 0, 1))

	# Latigazo comico al romper: la caña rebota.
	if _snap_flash > 0.0:
		_rod_pivot.rotation.x += _snap_flash * sin(_snap_flash * 40.0) * 0.3

	# La boya ride la ola de verdad (la misma funcion que la fisica).
	if _bobber.visible:
		var pos := Vector3(_cast_point.x, 0.0, _cast_point.y)
		pos.y = Ocean.get_height(pos) + 0.05
		if state == State.BITE:
			pos.y -= 0.25 + sin(Time.get_ticks_msec() * 0.02) * 0.1 # se hunde: ¡ahora!
		elif state == State.FIGHT and fight.is_pulling():
			var side := 1.0 if fight.pull_dir == FightModel.Pull.RIGHT else -1.0
			pos.x += side * sin(Time.get_ticks_msec() * 0.008) * 0.6 # el pez pelea, se ve
		_bobber.global_position = _bobber.global_position.lerp(pos, clampf(10.0 * delta, 0, 1))

	_draw_line()


func _draw_line() -> void:
	var im := _line.mesh as ImmediateMesh
	im.clear_surfaces()
	if not _bobber.visible:
		return
	var a := _tip.global_position
	var b := _bobber.global_position
	# Comba del sedal: cuelga cuando esta flojo, se tensa recta en la lucha.
	var slack: float = 1.2
	if state == State.FIGHT:
		slack = lerpf(0.9, 0.05, clampf(fight.tension, 0.0, 1.0))
	var mid := (a + b) * 0.5 + Vector3.DOWN * slack
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in 9:
		var t := float(i) / 8.0
		# Bezier cuadratica a-mid-b
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
