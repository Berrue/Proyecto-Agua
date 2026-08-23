extends Node

## AUTOLOAD `Ocean` - la UNICA puerta al agua.
##
## Fisica, nado, daño, IA, camara, audio y VFX preguntan aqui y solo aqui. Nadie
## consulta la altura del agua por ningun otro camino, y nada de esto toca la GPU.
##
## [b]Por que no se lee la GPU:[/b] `texture_get_data()` es una parada sincrona, y
## sobre todo cada cliente leeria SU textura de SU GPU con SU frameskip, asi que
## las alturas divergirian entre maquinas sin ningun error ni warning. El barco
## acabaria en sitios distintos en cada pantalla. Aqui el agua es una funcion
## analitica pura, asi que los 6 clientes coinciden replicando una semilla, un
## reloj y un float.
##
## [b]Prohibido[/b] llamar a `Time.get_ticks_msec()` u `OS.get_ticks_msec()` desde
## `addons/ocean/`: arrancan en momentos distintos en cada maquina y producen
## oceanos desfasados minutos. Solo [member sim_time] alimenta el oceano.

signal sea_state_changed()
signal waves_regenerated()
signal events_changed()
## Se emite una vez cuando un tsunami entra en el radio de aviso.
signal tsunami_incoming(seconds_out: float)

## Escala Douglas: altura significativa (m) para cada punto del dial de furia.
## Se interpola en Hs y NUNCA en velocidad de viento: Hs escala como U^2, asi que
## interpolar U deja el dial muerto de 0 a 5 y explosivo de 8 a 10.
const DOUGLAS_HS: Array[float] = [0.0, 0.1, 0.5, 1.25, 2.5, 4.0, 6.0, 9.0, 14.0, 18.0, 25.0]

## Cuanto puede moverse el dial por segundo. Sin este limite el mar gana energia
## a saltos y se ve el cambio; con el, crece de forma continua.
const FURY_RATE_LIMIT := 0.4

const WAVE_COUNT := 12

## Reloj de simulacion. En multijugador lo escribe el host (NetworkTime).
var sim_time: float = 0.0

## Semilla del mar. Se replica una vez al unirse y define el oleaje entero.
var ocean_seed: int = 0

var wind_direction_deg: float = 30.0

var _proxy := OceanWaveProxy.new()
var _events := OceanEvents.new()
var _warned_tsunami: bool = false

## Tier del tsunami en curso, para que el HUD y el audio sepan de que va.
var current_tier: TsunamiTier = null
var _fury: float = 3.0
var _fury_target: float = 3.0
var _paused: bool = false


func _ready() -> void:
	regenerate(ocean_seed)


func _physics_process(delta: float) -> void:
	if _paused:
		return
	sim_time += delta
	if not is_equal_approx(_fury, _fury_target):
		var step: float = FURY_RATE_LIMIT * delta
		_fury = move_toward(_fury, _fury_target, step)
		_apply_sea_state()


## Vuelve a muestrear longitudes de onda, direcciones y fases. Solo al empezar
## partida: hacerlo en caliente produce un salto visible en la superficie.
func regenerate(new_seed: int) -> void:
	ocean_seed = new_seed
	_proxy.generate(new_seed, WAVE_COUNT, wind_direction_deg)
	_apply_sea_state()
	waves_regenerated.emit()


# =============================================================================
#  El dial de furia
# =============================================================================

## Furia del mar, 0 (espejo) a 10 (tsunami). Una sola perilla mueve el mundo.
var fury: float:
	get:
		return _fury
	set(value):
		_fury_target = clampf(value, 0.0, 10.0)


## Salta al valor sin rampa. Solo para debug y para el arranque de partida.
func set_fury_immediate(value: float) -> void:
	_fury_target = clampf(value, 0.0, 10.0)
	_fury = _fury_target
	_apply_sea_state()


## Altura significativa objetivo para la furia actual, en metros.
func target_hs() -> float:
	var f: float = clampf(_fury, 0.0, 10.0)
	var i: int = int(floor(f))
	if i >= DOUGLAS_HS.size() - 1:
		return DOUGLAS_HS[-1]
	return lerpf(DOUGLAS_HS[i], DOUGLAS_HS[i + 1], f - float(i))


## Hs que el mar alcanza de verdad. Puede quedar por debajo del objetivo porque
## las olas saturan al llegar a su limite de rotura: eso es correcto, un mar real
## tampoco crece sin limite.
func measured_hs() -> float:
	return _proxy.measured_hs


func steepness_sum() -> float:
	return _proxy.steepness_sum()


func _apply_sea_state() -> void:
	var t: float = clampf(_fury, 0.0, 10.0) / 10.0
	# Las crestas se afilan al subir la furia, pero nunca pasan del limite de
	# auto-interseccion: por encima, la inversion por punto fijo deja de
	# converger y la flotabilidad se vuelve caotica.
	var choppiness: float = lerpf(0.15, OceanWaveProxy.STEEPNESS_LIMIT, t)
	_proxy.set_sea_state(target_hs(), choppiness)
	sea_state_changed.emit()


# =============================================================================
#  API de consulta - lo unico que el resto del juego necesita saber
# =============================================================================

## Altura del agua bajo (o sobre) una posicion del mundo.
func get_height(world_pos: Vector3) -> float:
	var xz := Vector2(world_pos.x, world_pos.z)
	return _proxy.height_at(xz, sim_time) + _events.height_at(xz, sim_time)


## Altura en un instante ARBITRARIO. Como todo el sistema es funcion pura de t,
## esto permite consultar el FUTURO: es lo que hace posible telegrafiar el
## tsunami sin ningun sistema adicional de prediccion.
func get_height_at(world_pos: Vector3, t: float) -> float:
	var xz := Vector2(world_pos.x, world_pos.z)
	return _proxy.height_at(xz, t) + _events.height_at(xz, t)


## Cuanto esta sumergido un punto. Positivo = bajo el agua.
func get_submersion(world_pos: Vector3) -> float:
	return get_height(world_pos) - world_pos.y


func get_displacement(world_xz: Vector2, t: float) -> Vector3:
	return _proxy.displacement(world_xz, t)


## Altura y velocidad de la superficie en UNA sola resolucion del punto fijo.
## Usalo siempre que necesites las dos cosas (o sea, en toda la flotabilidad):
## pedirlas por separado duplica el coste de lo mas caro del sistema.
func sample(world_pos: Vector3) -> Dictionary:
	var xz := Vector2(world_pos.x, world_pos.z)
	var out: Dictionary = _proxy.sample_at(xz, sim_time)
	if _events.has_active():
		out[&"height"] = float(out[&"height"]) + _events.height_at(xz, sim_time)
		out[&"velocity"] = (out[&"velocity"] as Vector3) + _events.velocity_at(xz, sim_time)
	return out


func get_surface_velocity(world_pos: Vector3) -> Vector3:
	var xz := Vector2(world_pos.x, world_pos.z)
	return _proxy.surface_velocity_at(xz, sim_time) + _events.velocity_at(xz, sim_time)


func get_normal(world_pos: Vector3) -> Vector3:
	return _proxy.normal_at(Vector2(world_pos.x, world_pos.z), sim_time)


## Jacobiano del desplazamiento. Menor que 0 = la ola ROMPE aqui.
##
## Es el mismo numero con el que el shader pinta la espuma, asi que la espuma
## marca literalmente donde te va a doler: el feedback visual y el mecanico
## salen del mismo sitio y el jugador siempre puede leer el mar.
func get_breaking(world_pos: Vector3) -> float:
	var xz := Vector2(world_pos.x, world_pos.z)
	return _proxy.jacobian_at(xz, sim_time) - _events.break_penalty_at(xz, sim_time)


func is_breaking(world_pos: Vector3) -> bool:
	return get_breaking(world_pos) < 0.0


# =============================================================================
#  Tsunami
# =============================================================================

## Lanza un tsunami que llegara a [param target] dentro de [param seconds].
##
## Se especifica asi, y no por posicion de origen, porque lo que el diseñador
## quiere decidir es CUANDO llega, no desde donde sale. El origen se calcula
## hacia atras.
func spawn_tsunami(target: Vector3, from_direction_deg: float, seconds: float,
		amplitude: float = 18.0, celerity: float = 45.0, width: float = 90.0,
		lead: float = 12.0, spread: float = 9.0, depression: float = 0.55) -> int:
	var ang := deg_to_rad(from_direction_deg)
	# El tsunami avanza HACIA el objetivo desde la direccion indicada.
	var dir := Vector2(-cos(ang), -sin(ang))
	var target_xz := Vector2(target.x, target.z)
	# Se le da margen de sobra por detras para que el perfil entero (incluida la
	# depresion que va por delante) este ya formado al entrar en escena.
	var origin := target_xz - dir * (celerity * seconds)
	var idx := _events.spawn(origin, dir, amplitude, celerity, width, sim_time,
		lead, spread, depression)
	if idx >= 0:
		_warned_tsunami = false
		events_changed.emit()
	return idx


## Lanza un tsunami de un TIER concreto. Es la via normal: los numeros sueltos de
## `spawn_tsunami()` quedan para debug y para los tests.
func spawn_tsunami_tier(target: Vector3, from_direction_deg: float, seconds: float,
		tier: TsunamiTier) -> int:
	if tier == null:
		push_warning("spawn_tsunami_tier() sin tier: no se lanza nada.")
		return -1
	current_tier = tier
	return spawn_tsunami(target, from_direction_deg, seconds,
		tier.amplitude(), tier.celerity(), tier.width(),
		tier.lead, tier.spread, tier.depression)


## Segundos hasta que la cresta alcance este punto. INF si no hay tsunami.
func time_until_tsunami(world_pos: Vector3) -> float:
	return _events.time_until_crest(Vector2(world_pos.x, world_pos.z), sim_time)


func has_tsunami() -> bool:
	return _events.has_active()


func clear_events() -> void:
	_events.clear_all()
	_warned_tsunami = false
	current_tier = null
	events_changed.emit()


func get_events() -> OceanEvents:
	return _events


# =============================================================================
#  Puente al shader
# =============================================================================

## Los uniforms salen de la MISMA tabla que usa la CPU. Nunca dos listas.
func apply_to_material(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter(&"wave_a", _proxy.pack_a())
	mat.set_shader_parameter(&"wave_b", _proxy.pack_b())
	mat.set_shader_parameter(&"wave_count", _proxy.count)
	mat.set_shader_parameter(&"ocean_time", sim_time)
	# Una sola perilla normalizada. El shader la mapea entre rangos que el
	# artista controla desde el material, asi que subir la furia oscurece el
	# agua, llena el mar de espuma y afila el detalle sin tocar codigo.
	mat.set_shader_parameter(&"fury01", clampf(_fury / 10.0, 0.0, 1.0))
	# Las bandas de color se normalizan con el estado del mar. Sin esto, con
	# olas de 12 m el gradiente satura y todo el oceano se pinta del color de
	# cresta: las bandas dejan de comunicar altura justo cuando mas importa.
	mat.set_shader_parameter(&"height_scale", 0.6 / maxf(_proxy.measured_hs, 0.4))
	var packed: Array = _events.pack()
	mat.set_shader_parameter(&"event_a", packed[0])
	mat.set_shader_parameter(&"event_b", packed[1])
	mat.set_shader_parameter(&"event_c", packed[2])


func set_paused(value: bool) -> void:
	_paused = value


## Acceso directo al proxy. Solo para tests de paridad y herramientas de debug.
func get_proxy() -> OceanWaveProxy:
	return _proxy
