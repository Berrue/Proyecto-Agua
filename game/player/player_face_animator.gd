class_name PlayerFaceAnimator
extends Node

## Capa facial aditiva del pescador.
##
## Vive FUERA del AnimationTree corporal a proposito: el arbol puede seguir
## escribiendo Head/Neck para caminar, nadar o pescar, mientras esta capa solo
## toca blend shapes y mallas hoja de la cara. Asi una expresion no pelea por
## huesos ni obliga a duplicar cada clip corporal con una version facial.
##
## Hay dos caminos con la misma API:
## - si el GLB trae morphs con nombres conocidos, usa esos morphs;
## - si no (el pescador de bloques original), mueve ojo_L/R, ceja_L/R y boca.
##
## La busqueda es por nombres estables, no por paths del importador. Reexportar
## el GLB puede cambiar la profundidad del arbol, pero no debe cambiar esos
## nombres. Si falta un canal, se degrada en silencio y el resto sigue vivo.

@export_group("Parpadeo")
@export var blink_interval_min: float = 2.2
@export var blink_interval_max: float = 5.8
@export var blink_duration: float = 0.16
@export var closed_eye_scale: float = 0.12

@export_group("Mirada")
@export var saccade_interval_min: float = 0.35
@export var saccade_interval_max: float = 1.25
@export var saccade_strength: float = 0.42
@export var gaze_response: float = 22.0
@export var eye_travel_m: float = 0.012

@export_group("Expresion")
@export var expression_response: float = 10.0
@export var brow_angle_deg: float = 11.0
@export var brow_lift_m: float = 0.012
@export var mouth_smile_width: float = 0.30
@export var mouth_talk_open: float = 1.8


# Los aliases incluyen el contrato preferido del modelo nuevo y los nombres del
# GLB historico. Se normalizan (sin guiones, puntos, espacios ni mayusculas).
const PART_ALIASES: Dictionary = {
	&"eye_l": ["Eye_L", "ojo_L", "LeftEye", "EyeLeft", "eyeball_L"],
	&"eye_r": ["Eye_R", "ojo_R", "RightEye", "EyeRight", "eyeball_R"],
	&"pupil_l": ["Pupil_L", "pupila_L", "LeftPupil", "PupilLeft"],
	&"pupil_r": ["Pupil_R", "pupila_R", "RightPupil", "PupilRight"],
	&"brow_l": ["Brow_L", "ceja_L", "LeftBrow", "Eyebrow_L"],
	&"brow_r": ["Brow_R", "ceja_R", "RightBrow", "Eyebrow_R"],
	&"mouth": ["Mouth", "FaceMouthMesh", "boca", "MouthMain", "Labios"],
	&"mouth_corner_l": ["MouthCorner_L", "comisura_L", "LipCorner_L"],
	&"mouth_corner_r": ["MouthCorner_R", "comisura_R", "LipCorner_R"],
}

# Morphs preferidos: blink_L/R, look_left/right/up/down, smile, tense, talk y
# effort. Tambien se reconocen nombres habituales de ARKit para que un futuro
# rework facial no necesite un adaptador solo por venir de otra herramienta.
const BLEND_ALIASES: Dictionary = {
	&"blink": ["blink", "blink_both", "eye_blink", "eyes_closed"],
	&"blink_l": ["blink_L", "blink_left", "eyeBlinkLeft", "eye_blink_L"],
	&"blink_r": ["blink_R", "blink_right", "eyeBlinkRight", "eye_blink_R"],
	&"look_left": ["look_left", "eyeLookOutLeft", "eyeLookInRight"],
	&"look_right": ["look_right", "eyeLookInLeft", "eyeLookOutRight"],
	&"look_up": ["look_up", "eyeLookUpLeft", "eyeLookUpRight"],
	&"look_down": ["look_down", "eyeLookDownLeft", "eyeLookDownRight"],
	&"smile": ["smile", "mouthSmileLeft", "mouthSmileRight", "happy"],
	&"tense": ["tense", "mouthPressLeft", "mouthPressRight", "browDown",
		"browDownLeft", "browDownRight"],
	&"talk": ["talk", "mouth_open", "jawOpen", "viseme_aa"],
	&"effort": ["effort", "squint", "eyeSquintLeft", "eyeSquintRight",
		"mouthFrownLeft", "mouthFrownRight"],
}


var model: Node3D = null
var body_animator: PlayerAnimator = null

var _parts: Dictionary = {}
var _base_transforms: Dictionary = {}
var _blend_channels: Dictionary = {}
var _blend_base: Dictionary = {}

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _time: float = 0.0

var _blink_elapsed: float = -1.0
var _next_blink: float = 1.0
var _blink_value: float = 0.0

var _gaze: Vector2 = Vector2.ZERO
var _gaze_target: Vector2 = Vector2.ZERO
var _next_saccade: float = 0.0
var _look_override: bool = false
var _look_hold: float = 0.0

var _smile: float = 0.0
var _tension: float = 0.0
var _speech: float = 0.0
var _effort: float = 0.0
var _target_smile: float = 0.0
var _target_tension: float = 0.0
var _target_speech: float = 0.0
var _target_effort: float = 0.0
var _manual_smile: float = 0.0
var _manual_tension: float = 0.0
var _manual_effort: float = 0.0

var _emote_smile: float = 0.0
var _emote_tension: float = 0.0
var _emote_effort: float = 0.0
var _emote_left: float = 0.0
var _forced: bool = false


## Descubre los canales disponibles y empieza la animacion autonoma.
## `random_seed` distinto de cero hace reproducibles parpadeos y saccades para
## tests/capturas. En juego la instancia aporta una semilla local: es solo
## presentacion y no participa de la simulacion de red.
func setup(face_model: Node3D, random_seed: int = 0) -> bool:
	teardown()
	if face_model == null:
		return false
	model = face_model
	_rng.seed = random_seed if random_seed != 0 else int(face_model.get_instance_id())
	_forced = false
	_manual_smile = 0.0
	_manual_tension = 0.0
	_manual_effort = 0.0
	_target_smile = 0.0
	_target_tension = 0.0
	_target_speech = 0.0
	_target_effort = 0.0
	_smile = 0.0
	_tension = 0.0
	_speech = 0.0
	_effort = 0.0
	clear_emote()
	_discover_parts()
	_discover_blend_shapes()
	_time = 0.0
	_blink_elapsed = -1.0
	_blink_value = 0.0
	_gaze = Vector2.ZERO
	_gaze_target = Vector2.ZERO
	_look_override = false
	_look_hold = 0.0
	_schedule_blink()
	_schedule_saccade()
	var usable := _has_any_feature()
	set_process(usable)
	if usable:
		_apply_face()
	return usable


## Restaura exactamente los transforms y pesos encontrados durante setup().
## Sirve al reemplazar un modelo en caliente y evita dejar una boca abierta al
## liberar este nodo durante una captura.
func teardown() -> void:
	_restore_parts()
	_restore_blends()
	set_process(false)
	model = null
	body_animator = null
	_parts.clear()
	_base_transforms.clear()
	_blend_channels.clear()
	_blend_base.clear()


func _exit_tree() -> void:
	teardown()


func _process(delta: float) -> void:
	advance(delta)


## Paso publico para tests y capturas deterministas. En juego lo llama _process.
func advance(delta: float) -> void:
	if model == null:
		return
	var dt: float = maxf(delta, 0.0)
	_time += dt
	if _forced:
		_apply_face()
		return
	_step_emote(dt)
	_compose_targets_from_context()
	_blink_value = _step_blink(dt)
	_step_gaze(dt)
	var k: float = 1.0 - exp(-expression_response * dt) if dt > 0.0 else 0.0
	_smile = lerpf(_smile, _target_smile, k)
	_tension = lerpf(_tension, _target_tension, k)
	_speech = lerpf(_speech, _target_speech, k)
	_effort = lerpf(_effort, _target_effort, k)
	_apply_face()


## Sonrisa y tension son intenciones de alto nivel, ambas en 0..1. Si coinciden,
## la tension domina un poco: una sonrisa bajo tormenta queda apretada, no se
## suma hasta deformar la boca al doble.
func set_expression(smile: float, tension: float) -> void:
	_forced = false
	_manual_smile = clampf(smile, 0.0, 1.0)
	_manual_tension = clampf(tension, 0.0, 1.0)


## `intensity` permite conectar en el futuro el RMS/visema de la voz. Sin esa
## señal, true + 1.0 ya produce una cadencia no mecanica legible a distancia.
func set_speaking(active: bool, intensity: float = 1.0) -> void:
	_forced = false
	_target_speech = clampf(intensity, 0.0, 1.0) if active else 0.0


## Atajo para una señal continua de voz (0..1), por ejemplo un envelope de VoIP.
func set_speech_level(level: float) -> void:
	_forced = false
	_target_speech = clampf(level, 0.0, 1.0)


## Esfuerzo mezcla entrecerrar ojos, cejas y boca; no rota Head ni Neck.
func set_effort(amount: float) -> void:
	_forced = false
	_manual_effort = clampf(amount, 0.0, 1.0)


## Lee locomotion/water/rod del arbol corporal sin tocarlo. En una copia remota
## alcanza con alimentar su PlayerAnimator: la cara reacciona al estado visual
## que ya existe y no necesita otro paquete de red solo para fruncir el gesto.
func bind_body_animator(animator: PlayerAnimator) -> void:
	body_animator = animator


## Emotes breves superpuestos al estado corporal. Nombres publicos:
## smile/feliz, tense/preocupado, effort/esfuerzo y neutral.
func play_emote(emote: StringName, intensity: float = 1.0,
		hold_seconds: float = 1.25) -> void:
	_forced = false
	_emote_smile = 0.0
	_emote_tension = 0.0
	_emote_effort = 0.0
	var amount: float = clampf(intensity, 0.0, 1.0)
	match _normalize(String(emote)):
		"smile", "happy", "feliz", "sonrisa":
			_emote_smile = amount
		"tense", "worried", "tenso", "preocupado":
			_emote_tension = amount
		"effort", "strain", "esfuerzo":
			_emote_effort = amount
		"neutral", "neutro", "":
			pass
		_:
			push_warning("PlayerFaceAnimator: emote desconocido '%s'" % emote)
	# Cero significa un impulso de un frame, no un emote eterno. La ausencia de
	# emote usa su propio estado (valores en cero), no un timer ambiguo.
	_emote_left = maxf(hold_seconds, 0.001)


func clear_emote() -> void:
	_emote_smile = 0.0
	_emote_tension = 0.0
	_emote_effort = 0.0
	_emote_left = 0.0


## Fuerza un estado sin smoothing. Es el equivalente facial de
## PlayerAnimator.force(): util para thumbnails y tests de pose.
func force_expression(smile: float, tension: float, speech: float, effort: float) -> void:
	force(smile, tension, speech, effort)


## Pose facial estable: no avanza parpadeo, mirada, habla ni contexto corporal
## hasta release_force(). Es lo que deben usar las capturas para no depender del
## frame exacto en que se renderizan.
func force(smile: float, tension: float, speech: float, effort: float,
		gaze: Vector2 = Vector2.ZERO, blink: float = 0.0) -> void:
	_forced = true
	_target_smile = clampf(smile, 0.0, 1.0)
	_target_tension = clampf(tension, 0.0, 1.0)
	_target_speech = clampf(speech, 0.0, 1.0)
	_target_effort = clampf(effort, 0.0, 1.0)
	_smile = _target_smile
	_tension = _target_tension
	_speech = _target_speech
	_effort = _target_effort
	_gaze = gaze.limit_length(1.0)
	_gaze_target = _gaze
	_blink_value = clampf(blink, 0.0, 1.0)
	_apply_face()


func release_force() -> void:
	_forced = false


## Mira en coordenadas anatomicas del personaje: +X = su derecha, +Y = arriba.
## El modelo mira a +Z, por eso el fallback convierte derecha a -X local.
## `hold_seconds < 0` sostiene la mirada hasta clear_look().
func look_toward(direction: Vector2, hold_seconds: float = 0.75) -> void:
	_forced = false
	_gaze_target = direction.limit_length(1.0)
	_look_override = true
	_look_hold = hold_seconds


func clear_look() -> void:
	_look_override = false
	_look_hold = 0.0
	_next_saccade = 0.0


func trigger_blink() -> void:
	_forced = false
	_blink_elapsed = 0.0


## Vuelve a neutro y restaura las piezas de inmediato.
func reset() -> void:
	_forced = false
	_manual_smile = 0.0
	_manual_tension = 0.0
	_manual_effort = 0.0
	clear_emote()
	_target_smile = 0.0
	_target_tension = 0.0
	_target_speech = 0.0
	_target_effort = 0.0
	_smile = 0.0
	_tension = 0.0
	_speech = 0.0
	_effort = 0.0
	_blink_elapsed = -1.0
	_blink_value = 0.0
	_gaze = Vector2.ZERO
	_gaze_target = Vector2.ZERO
	_look_override = false
	_restore_parts()
	_restore_blends()


## Contrato inspeccionable para tests, herramientas y modelos futuros.
func capabilities() -> Dictionary:
	var has_eyes: bool = _part(&"eye_l") != null or _part(&"eye_r") != null
	var has_pupils: bool = _part(&"pupil_l") != null or _part(&"pupil_r") != null
	var has_brows: bool = _part(&"brow_l") != null or _part(&"brow_r") != null
	var has_mouth: bool = _part(&"mouth") != null
	return {
		"blink": _has_blend(&"blink") or _has_blend(&"blink_l")
			or _has_blend(&"blink_r") or has_eyes,
		"gaze": _has_blend(&"look_left") or _has_blend(&"look_right")
			or _has_blend(&"look_up") or _has_blend(&"look_down")
			or has_pupils or has_eyes,
		"expression": _has_blend(&"smile") or _has_blend(&"tense")
			or _has_blend(&"effort") or has_brows or has_mouth,
		"speaking": _has_blend(&"talk") or has_mouth,
		"blend_shape_channels": _blend_channels.size(),
		"part_channels": _parts.size(),
	}


## Lectura sin efectos para QA y debug. La jugabilidad no debe depender de
## estos valores: son presentacion local y pueden variar entre clientes.
func debug_state() -> Dictionary:
	return {
		"smile": _smile,
		"tension": _tension,
		"speech": _speech,
		"effort": _effort,
		"blink": _blink_value,
		"gaze": _gaze,
		"forced": _forced,
	}


func _discover_parts() -> void:
	for raw: Node in model.find_children("*", "MeshInstance3D", true, false):
		var part := raw as MeshInstance3D
		var canonical := _canonical_name(String(part.name), PART_ALIASES)
		if canonical == &"" or _parts.has(canonical):
			continue
		_parts[canonical] = part
		_base_transforms[part.get_instance_id()] = {
			"node": part,
			"transform": part.transform,
		}


func _discover_blend_shapes() -> void:
	for raw: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := raw as MeshInstance3D
		# PrimitiveMesh (BoxMesh/SphereMesh) no expone la API de morphs aunque
		# tambien herede Mesh. El guard evita errores en fixtures y accesorios.
		if mesh_node.mesh == null or not mesh_node.mesh.has_method("get_blend_shape_count"):
			continue
		for index: int in mesh_node.mesh.get_blend_shape_count():
			var shape_name := String(mesh_node.mesh.get_blend_shape_name(index))
			var canonical := _canonical_name(shape_name, BLEND_ALIASES)
			if canonical == &"":
				continue
			if not _blend_channels.has(canonical):
				_blend_channels[canonical] = []
			var channels: Array = _blend_channels[canonical]
			channels.append({"mesh": mesh_node, "index": index})
			_blend_channels[canonical] = channels
			_blend_base[_blend_key(mesh_node, index)] = mesh_node.get_blend_shape_value(index)


func _canonical_name(raw_name: String, table: Dictionary) -> StringName:
	var normalized := _normalize(raw_name)
	for canonical: StringName in table:
		for alias: String in table[canonical]:
			if normalized == _normalize(alias):
				return canonical
	return &""


func _normalize(value: String) -> String:
	return value.to_lower().replace("_", "").replace("-", "").replace(".", "").replace(" ", "")


func _part(canonical: StringName) -> Node3D:
	return _parts.get(canonical, null) as Node3D


func _has_blend(canonical: StringName) -> bool:
	return _blend_channels.has(canonical) and not (_blend_channels[canonical] as Array).is_empty()


func _has_any_feature() -> bool:
	var caps := capabilities()
	return (bool(caps["blink"]) or bool(caps["gaze"])
		or bool(caps["expression"]) or bool(caps["speaking"]))


func _schedule_blink() -> void:
	var low: float = minf(blink_interval_min, blink_interval_max)
	var high: float = maxf(blink_interval_min, blink_interval_max)
	_next_blink = _rng.randf_range(low, high)


func _step_emote(delta: float) -> void:
	if _emote_left <= 0.0:
		return
	_emote_left -= delta
	if _emote_left <= 0.0:
		clear_emote()


func _compose_targets_from_context() -> void:
	var body_locomotion: float = 0.0
	var body_water: float = 0.0
	var body_rod: float = 0.0
	if is_instance_valid(body_animator) and body_animator.tree != null:
		body_locomotion = float(body_animator.tree.get(
			&"parameters/locomotion/blend_amount"))
		body_water = float(body_animator.tree.get(&"parameters/water/blend_amount"))
		body_rod = float(body_animator.tree.get(&"parameters/rod/blend_amount"))
	var contextual_effort: float = clampf(body_locomotion * 0.16
		+ body_water * 0.52 + body_rod * 0.12, 0.0, 1.0)
	var contextual_tension: float = clampf(body_water * 0.18 + body_rod * 0.68, 0.0, 1.0)
	_target_smile = maxf(_manual_smile, _emote_smile)
	_target_tension = maxf(_manual_tension, maxf(_emote_tension, contextual_tension))
	_target_effort = maxf(_manual_effort, maxf(_emote_effort, contextual_effort))


func _step_blink(delta: float) -> float:
	if _blink_elapsed < 0.0:
		_next_blink -= delta
		if _next_blink <= 0.0:
			_blink_elapsed = 0.0
		else:
			return 0.0
	_blink_elapsed += delta
	var duration: float = maxf(blink_duration, 0.001)
	var phase: float = _blink_elapsed / duration
	if phase >= 1.0:
		_blink_elapsed = -1.0
		_schedule_blink()
		return 0.0
	# Cierra un poco mas rapido de lo que abre; la asimetria evita el pulso
	# triangular que se lee como una persiana mecanica.
	if phase < 0.42:
		return smoothstep(0.0, 1.0, phase / 0.42)
	return 1.0 - smoothstep(0.0, 1.0, (phase - 0.42) / 0.58)


func _schedule_saccade() -> void:
	var low: float = minf(saccade_interval_min, saccade_interval_max)
	var high: float = maxf(saccade_interval_min, saccade_interval_max)
	_next_saccade = _rng.randf_range(low, high)


func _step_gaze(delta: float) -> void:
	if _look_override:
		if _look_hold >= 0.0:
			_look_hold -= delta
			if _look_hold <= 0.0:
				clear_look()
	else:
		_next_saccade -= delta
		if _next_saccade <= 0.0:
			var angle: float = _rng.randf_range(0.0, TAU)
			# sqrt concentra menos muestras en el centro y da pequeños saltos de
			# fijacion, sin mandar los ojos siempre al borde.
			var radius: float = sqrt(_rng.randf()) * clampf(saccade_strength, 0.0, 1.0)
			_gaze_target = Vector2(cos(angle), sin(angle)) * radius
			_schedule_saccade()
	var k: float = 1.0 - exp(-gaze_response * delta) if delta > 0.0 else 0.0
	_gaze = _gaze.lerp(_gaze_target, k)


func _speech_open() -> float:
	if _speech <= 0.0001:
		return 0.0
	if _forced:
		return _speech
	# Dos frecuencias no armonicas dan silabas irregulares sin RNG por frame.
	# El resultado sigue siendo reproducible para una captura con tiempo fijo.
	var cadence: float = 0.52 + 0.30 * sin(_time * 11.7) + 0.18 * sin(_time * 17.3 + 0.8)
	return _speech * clampf(cadence, 0.08, 1.0)


func _apply_face() -> void:
	_restore_parts()
	_restore_blends()
	var tense: float = clampf(_tension + _effort * 0.55, 0.0, 1.0)
	var smile: float = _smile * (1.0 - tense * 0.65)
	var squint: float = clampf(_effort * 0.30 + _tension * 0.10, 0.0, 0.45)
	var eye_close: float = clampf(_blink_value + (1.0 - _blink_value) * squint, 0.0, 1.0)
	var talk: float = _speech_open()

	_apply_blend_blink(eye_close)
	_write_blend(&"look_left", maxf(-_gaze.x, 0.0))
	_write_blend(&"look_right", maxf(_gaze.x, 0.0))
	_write_blend(&"look_up", maxf(_gaze.y, 0.0))
	_write_blend(&"look_down", maxf(-_gaze.y, 0.0))
	_write_blend(&"smile", smile)
	_write_blend(&"tense", tense)
	_write_blend(&"talk", talk)
	_write_blend(&"effort", _effort)

	_apply_eye_parts(eye_close)
	_apply_brow_parts(smile, tense)
	_apply_mouth_parts(smile, tense, talk)


func _apply_blend_blink(amount: float) -> void:
	if _has_blend(&"blink"):
		_write_blend(&"blink", amount)
	else:
		_write_blend(&"blink_l", amount)
		_write_blend(&"blink_r", amount)


func _apply_eye_parts(eye_close: float) -> void:
	var use_part_blink: bool = (not _has_blend(&"blink")
		and not _has_blend(&"blink_l") and not _has_blend(&"blink_r"))
	var pupil_l := _part(&"pupil_l")
	var pupil_r := _part(&"pupil_r")
	var has_pupils: bool = pupil_l != null or pupil_r != null
	var use_part_gaze: bool = has_pupils or not (
		_has_blend(&"look_left") or _has_blend(&"look_right")
		or _has_blend(&"look_up") or _has_blend(&"look_down"))

	for eye_name: StringName in [&"eye_l", &"eye_r"]:
		var eye := _part(eye_name)
		if eye == null:
			continue
		var base := _base_transform(eye)
		if use_part_blink:
			var scale_y: float = lerpf(1.0, clampf(closed_eye_scale, 0.02, 1.0), eye_close)
			base.basis = base.basis * Basis.from_scale(Vector3(1.0, scale_y, 1.0))
		if use_part_gaze and not has_pupils:
			base.origin += Vector3(-_gaze.x, _gaze.y, 0.0) * eye_travel_m
		eye.transform = base

	if use_part_gaze and has_pupils:
		for pupil_name: StringName in [&"pupil_l", &"pupil_r"]:
			var pupil := _part(pupil_name)
			if pupil == null:
				continue
			var base := _base_transform(pupil)
			base.origin += Vector3(-_gaze.x, _gaze.y, 0.0) * eye_travel_m
			pupil.transform = base


func _apply_brow_parts(smile: float, tense: float) -> void:
	for brow_name: StringName in [&"brow_l", &"brow_r"]:
		var brow := _part(brow_name)
		if brow == null:
			continue
		var base := _base_transform(brow)
		var side: float = -1.0 if brow_name == &"brow_l" else 1.0
		var angle: float = deg_to_rad(brow_angle_deg) * tense * side
		base.basis = base.basis * Basis(Vector3.FORWARD, angle)
		base.origin.y += brow_lift_m * (smile * 0.55 + _effort * 0.45 - tense * 0.18)
		brow.transform = base


func _apply_mouth_parts(smile: float, tense: float, talk: float) -> void:
	var mouth := _part(&"mouth")
	if mouth != null:
		var base := _base_transform(mouth)
		var fallback_smile: float = 0.0 if _has_blend(&"smile") else smile
		var fallback_tense: float = 0.0 if _has_blend(&"tense") else tense
		var fallback_talk: float = 0.0 if _has_blend(&"talk") else talk
		var fallback_effort: float = 0.0 if _has_blend(&"effort") else _effort
		var sx: float = 1.0 + fallback_smile * mouth_smile_width - fallback_tense * 0.14
		var sy: float = (1.0 + fallback_talk * mouth_talk_open + fallback_effort * 0.38
			- fallback_smile * 0.18 + fallback_tense * 0.12)
		base.basis = base.basis * Basis.from_scale(Vector3(maxf(sx, 0.2), maxf(sy, 0.2), 1.0))
		base.origin.y += fallback_smile * 0.006 - fallback_effort * 0.004
		mouth.transform = base

	for corner_name: StringName in [&"mouth_corner_l", &"mouth_corner_r"]:
		var corner := _part(corner_name)
		if corner == null:
			continue
		var base := _base_transform(corner)
		var side: float = -1.0 if corner_name == &"mouth_corner_l" else 1.0
		base.origin += Vector3(side * smile * 0.004,
			smile * 0.009 - tense * 0.004 - _effort * 0.004, 0.0)
		corner.transform = base


func _base_transform(part: Node3D) -> Transform3D:
	var entry: Dictionary = _base_transforms.get(part.get_instance_id(), {})
	var base: Transform3D = entry.get("transform", part.transform)
	return base


func _restore_parts() -> void:
	for raw: Variant in _base_transforms.values():
		var entry: Dictionary = raw
		var part := entry.get("node", null) as Node3D
		if is_instance_valid(part):
			var base: Transform3D = entry["transform"]
			part.transform = base


func _blend_key(mesh_node: MeshInstance3D, index: int) -> String:
	return "%d:%d" % [mesh_node.get_instance_id(), index]


func _write_blend(canonical: StringName, amount: float) -> void:
	if not _blend_channels.has(canonical):
		return
	for raw: Variant in _blend_channels[canonical]:
		var channel: Dictionary = raw
		var mesh_node := channel["mesh"] as MeshInstance3D
		var index: int = int(channel["index"])
		if not is_instance_valid(mesh_node):
			continue
		var base: float = float(_blend_base.get(_blend_key(mesh_node, index), 0.0))
		mesh_node.set_blend_shape_value(index,
			clampf(base + clampf(amount, 0.0, 1.0) * (1.0 - base), -1.0, 1.0))


func _restore_blends() -> void:
	for raw_channels: Variant in _blend_channels.values():
		var channels: Array = raw_channels
		for raw: Variant in channels:
			var channel: Dictionary = raw
			var mesh_node := channel["mesh"] as MeshInstance3D
			var index: int = int(channel["index"])
			if is_instance_valid(mesh_node):
				mesh_node.set_blend_shape_value(index,
					float(_blend_base.get(_blend_key(mesh_node, index), 0.0)))
