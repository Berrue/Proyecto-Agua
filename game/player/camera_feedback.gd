class_name CameraFeedback
extends Camera3D

## Feedback de camara con presupuesto ANTI-MAREO estricto. Somos primera persona
## sobre un barco que YA rota de verdad, asi que:
##
## - CERO rotacion añadida por codigo, jamas. (El consejo "rotacional es mejor"
##   de Eiserloh es para tercera persona; su propia charla avisa "tread
##   carefully in VR". Traslacional-solo aqui es interpretacion nuestra derivada
##   de Eiserloh + las guias de confort de Meta, y es deliberada: que nadie lo
##   "corrija" de vuelta.)
## - Shake = offset TRASLACIONAL de la posicion local, 2.5 cm max, trauma^2 con
##   ruido Perlin, <0.4 s. El apuntado del raton nunca se toca.
## - FOV kick con tope duro de ±5 grados, un solo tween reutilizado.
## - La viñeta de tension hace DOBLE servicio: dramatiza la zona roja Y ocluye
##   el flujo optico del mar en la periferia — la unica tecnica de camara que
##   REDUCE el mareo en vez de arriesgarlo (guias de confort de Meta).
## - Todo cuelga de `effects_enabled`: el toggle existe desde el primer build
##   (Fatshark tiene hilos de nauseas reales por un FOV kick sin toggle).

@export var effects_enabled: bool = true

var _trauma: float = 0.0
var _base_fov: float = 78.0
var _base_pos := Vector3.ZERO
var _noise := FastNoiseLite.new()
var _noise_t: float = 0.0
var _fov_tween: Tween
var _vignette: ColorRect
var _tension: float = 0.0


func _ready() -> void:
	_base_fov = fov
	_base_pos = position
	_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_noise.frequency = 2.0
	_build_vignette()


func _process(delta: float) -> void:
	_trauma = maxf(_trauma - 1.5 * delta, 0.0)
	_noise_t += delta * 18.0

	var offset := Vector3.ZERO
	if effects_enabled and _trauma > 0.0:
		var amp: float = _trauma * _trauma * 0.025 # trauma^2, 2.5 cm max
		offset = Vector3(
			_noise.get_noise_2d(_noise_t, 0.0),
			_noise.get_noise_2d(0.0, _noise_t),
			0.0) * amp
	position = _base_pos + offset

	if _vignette != null:
		var target: float = clampf((_tension - 0.6) / 0.4, 0.0, 1.0) * 0.35 \
			if effects_enabled else 0.0
		var mat := _vignette.material as ShaderMaterial
		var cur: float = mat.get_shader_parameter(&"strength")
		# SIEMPRE lerp continuo: un escalon leeria como flash.
		mat.set_shader_parameter(&"strength", lerpf(cur, target, clampf(6.0 * delta, 0.0, 1.0)))


## Sacudida traslacional. Presupuesto por evento (del plan, ya podado por el
## critico): rotura 0.6, pez aterrizando 0.4. El BITE NO suma trauma — su
## protagonista de camara es el punch-in de FOV y apilar los dos esta prohibido.
func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


## Kick de FOV: no rota nada (el horizonte no se mueve). Tope duro ±5 grados.
## Un unico tween: el kick nuevo cancela al viejo.
func kick_fov(delta_deg: float, in_time: float, hold: float, out_time: float) -> void:
	if not effects_enabled:
		return
	delta_deg = clampf(delta_deg, -5.0, 5.0)
	if _fov_tween != null and _fov_tween.is_valid():
		_fov_tween.kill()
	_fov_tween = create_tween()
	_fov_tween.tween_property(self, "fov", _base_fov + delta_deg, in_time) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	if hold > 0.0:
		_fov_tween.tween_interval(hold)
	_fov_tween.tween_property(self, "fov", _base_fov, out_time) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)


## Tension actual de la caña (0-1): alimenta la viñeta. Llamar cada frame desde
## la herramienta activa; 0 cuando no hay lucha.
func set_tension(tension_norm: float) -> void:
	_tension = clampf(tension_norm, 0.0, 1.0)


func _build_vignette() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
// Viñeta radial: oscurece SOLO los bordes. strength la anima CameraFeedback
// con lerp continuo — nunca a saltos.
uniform float strength : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	float d = distance(UV, vec2(0.5));
	float edge = smoothstep(0.38, 0.72, d);
	COLOR = vec4(0.01, 0.02, 0.04, edge * strength);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter(&"strength", 0.0)
	_vignette.material = mat
	layer.add_child(_vignette)
