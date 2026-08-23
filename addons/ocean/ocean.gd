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
	return _proxy.height_at(Vector2(world_pos.x, world_pos.z), sim_time)


func get_height_at(world_pos: Vector3, t: float) -> float:
	return _proxy.height_at(Vector2(world_pos.x, world_pos.z), t)


## Cuanto esta sumergido un punto. Positivo = bajo el agua.
func get_submersion(world_pos: Vector3) -> float:
	return get_height(world_pos) - world_pos.y


func get_displacement(world_xz: Vector2, t: float) -> Vector3:
	return _proxy.displacement(world_xz, t)


## Altura y velocidad de la superficie en UNA sola resolucion del punto fijo.
## Usalo siempre que necesites las dos cosas (o sea, en toda la flotabilidad):
## pedirlas por separado duplica el coste de lo mas caro del sistema.
func sample(world_pos: Vector3) -> Dictionary:
	return _proxy.sample_at(Vector2(world_pos.x, world_pos.z), sim_time)


func get_surface_velocity(world_pos: Vector3) -> Vector3:
	return _proxy.surface_velocity_at(Vector2(world_pos.x, world_pos.z), sim_time)


func get_normal(world_pos: Vector3) -> Vector3:
	return _proxy.normal_at(Vector2(world_pos.x, world_pos.z), sim_time)


## Jacobiano del desplazamiento. Menor que 0 = la ola ROMPE aqui.
##
## Es el mismo numero con el que el shader pinta la espuma, asi que la espuma
## marca literalmente donde te va a doler: el feedback visual y el mecanico
## salen del mismo sitio y el jugador siempre puede leer el mar.
func get_breaking(world_pos: Vector3) -> float:
	return _proxy.jacobian_at(Vector2(world_pos.x, world_pos.z), sim_time)


func is_breaking(world_pos: Vector3) -> bool:
	return get_breaking(world_pos) < 0.0


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


func set_paused(value: bool) -> void:
	_paused = value


## Acceso directo al proxy. Solo para tests de paridad y herramientas de debug.
func get_proxy() -> OceanWaveProxy:
	return _proxy
