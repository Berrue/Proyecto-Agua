class_name DayNightCycle
extends Node

## Ciclo dia/noche.
##
## [b]La hora del dia es una funcion PURA de Ocean.sim_time.[/b] Es la misma
## regla que gobierna las olas y el tsunami: nada de relojes propios ni de
## `Time.get_ticks_msec()`. Consecuencias:
##
## - En multijugador el cielo se sincroniza GRATIS: la hora ya viaja con el
##   reloj del oceano que los clientes replican de todas formas. Sin esta regla,
##   cada maquina tendria su propio atardecer.
## - Es consultable en el FUTURO igual que el oceano: "¿sera de noche cuando
##   llegue el tsunami?" es una pregunta que el juego puede responder exacta.
## - Pausar la simulacion pausa el cielo, como debe ser.
##
## El nodo solo ESCRIBE en los nodos que le cuelgan por export (sol, luna,
## environment): no crea nada, para que todo siga siendo visible y editable en
## la escena. Convive con TsunamiDirector sin pisarse: el director toca SOLO
## `fog_density` (drama), este nodo toca colores y energias (hora del dia).

signal night_started()
signal day_started()

@export var profile: DayNightProfile

@export_group("Nodos")
@export var sun_path: NodePath
## Opcional. Sin luna, la noche funciona pero es un poco mas oscura.
@export var moon_path: NodePath
@export var environment_path: NodePath

@export_group("Arranque")
## Hora a la que empieza la partida (0-24). 9:00 da ~7 min de luz plena antes
## de que la tarde empiece a caer, con day_length de 20 min.
@export_range(0.0, 24.0) var start_hour: float = 9.0

## La hora se queda clavada en `start_hour` y NO avanza con el reloj del oceano.
##
## Es para pantallas que no son una partida —hoy el menu principal, manana la
## pausa o una postal de marketing—: ahi el mar es un fondo, y un fondo que
## anochece mientras alguien decide si jugar es un reloj corriendo sin motivo.
## La hora sigue siendo una funcion PURA de sim_time (constante es un caso
## particular de pura), asi que nada de lo que cuelga de `phase()` se entera.
@export var hora_congelada: bool = false

## Por debajo de esta energia solar se considera noche (apaga sombras del sol y
## dispara las señales). Umbral sobre la CURVA, no sobre la hora: asi "noche"
## coincide con lo que se ve, no con un numero arbitrario.
const NIGHT_ENERGY_THRESHOLD := 0.05

## Acimut fijo del recorrido solar, para que amanezca y anochezca siempre por
## el mismo lado del mundo y el vigia pueda orientarse por el sol.
const SUN_AZIMUTH_DEG := -30.0

var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _env: Environment
var _sky: ProceduralSkyMaterial
## El cielo propio (game/world/sky.gdshader). Se sigue soportando el
## ProceduralSkyMaterial por si alguna escena vieja lo usa, pero el camino bueno
## es este: es quien dibuja los astros y las nubes.
var _sky_shader: ShaderMaterial
var _debug_hour_offset: float = 0.0
var _was_night: bool = false


func _ready() -> void:
	_sun = get_node_or_null(sun_path) as DirectionalLight3D
	_moon = get_node_or_null(moon_path) as DirectionalLight3D
	var we := get_node_or_null(environment_path) as WorldEnvironment
	if we != null:
		_env = we.environment
		if _env != null and _env.sky != null:
			_sky = _env.sky.sky_material as ProceduralSkyMaterial
			_sky_shader = _env.sky.sky_material as ShaderMaterial
	if _sun == null:
		push_warning("DayNightCycle sin sol asignado: no hace nada.")
	_was_night = is_night()
	_apply(time_of_day())


func _process(_delta: float) -> void:
	var t01 := time_of_day()
	_apply(t01)

	var night := _sun != null and _sun.light_energy < NIGHT_ENERGY_THRESHOLD
	if night and not _was_night:
		night_started.emit()
	elif not night and _was_night:
		day_started.emit()
	_was_night = night


# =============================================================================
#  La hora - funcion pura
# =============================================================================

## Hora del dia normalizada 0..1 para un sim_time dado. PURA: mismo instante de
## simulacion -> misma hora en todas las maquinas.
func phase(sim_time: float) -> float:
	var day_len: float = profile.day_length_seconds if profile != null else 1200.0
	var avance: float = 0.0 if hora_congelada else sim_time / maxf(day_len, 1.0)
	var t: float = (start_hour + _debug_hour_offset) / 24.0 + avance
	return fposmod(t, 1.0)


func time_of_day() -> float:
	return phase(Ocean.sim_time)


## Hora en formato 0-24, para HUD y logs.
func hour() -> float:
	return time_of_day() * 24.0


func clock_text() -> String:
	var h := hour()
	return "%02d:%02d" % [int(h), int(fmod(h, 1.0) * 60.0)]


func is_night() -> bool:
	if profile == null:
		return false
	return profile.sample_energy(profile.sun_energy, time_of_day(), profile.sun_energy_max) \
		< NIGHT_ENERGY_THRESHOLD


## ¿Sera de noche dentro de N segundos? El cielo es consultable en el futuro
## igual que el oceano: sirve para decidir eventos ("el tsunami llega de noche")
## sin predecir nada.
func will_be_night_in(seconds: float) -> bool:
	if profile == null:
		return false
	return profile.sample_energy(profile.sun_energy, phase(Ocean.sim_time + seconds),
		profile.sun_energy_max) < NIGHT_ENERGY_THRESHOLD


## Salto de horas para debug. Toca SOLO el offset del ciclo, jamas sim_time:
## adelantar el reloj del oceano teletransportaria las olas y todo lo que flota.
func advance_hours(hours: float) -> void:
	_debug_hour_offset = fmod(_debug_hour_offset + hours, 24.0)


## Fija la hora del dia (0-24) para debug, por la misma via del offset: el
## deslizador de horario del HUD necesita un destino absoluto, no saltos.
func set_debug_hour(target_hour: float) -> void:
	advance_hours(target_hour - hour())


# =============================================================================
#  Aplicacion a la escena
# =============================================================================

func _apply(t01: float) -> void:
	if profile == null:
		return

	# El sol recorre 360 grados por dia: t01=0.25 amanece en el horizonte,
	# 0.5 esta en lo alto, 0.75 se pone, y de noche queda bajo el mundo.
	var elevation_deg: float = -(t01 * 360.0 - 90.0)

	if _sun != null:
		_sun.rotation_degrees = Vector3(elevation_deg, SUN_AZIMUTH_DEG, 0.0)
		_sun.light_color = profile.sample_color(profile.sun_color, t01, Color.WHITE)
		_sun.light_energy = profile.sample_energy(profile.sun_energy, t01, profile.sun_energy_max)
		# Un sol bajo el horizonte con sombras encendidas sigue costando un pase
		# de sombras: se apaga de noche.
		_sun.shadow_enabled = _sun.light_energy >= NIGHT_ENERGY_THRESHOLD

	if _moon != null:
		# La luna vive en el lado opuesto del cielo. Sin sombras: su unico
		# trabajo es que la noche se lea, no duplicar el coste de la luz.
		_moon.rotation_degrees = Vector3(elevation_deg + 180.0, SUN_AZIMUTH_DEG, 0.0)
		_moon.light_color = profile.moon_color
		_moon.light_energy = profile.sample_energy(profile.moon_energy, t01, profile.moon_energy_max)

	if _env != null:
		_env.ambient_light_color = profile.sample_color(
			profile.ambient_color, t01, _env.ambient_light_color)
		_env.ambient_light_energy = profile.sample_energy(
			profile.ambient_energy, t01, profile.ambient_energy_max)
		# Color de la niebla si; DENSIDAD no: la densidad es del TsunamiDirector,
		# que la usa como instrumento dramatico. Cada uno toca su perilla.
		var fog_col := profile.sample_color(profile.fog_color, t01, _env.fog_light_color)
		# Bajo lluvia la niebla se DESATURA hacia su luminancia (Lagarde: el
		# velo de agua lava el color y produce calima). Es la mitad atmosferica
		# de la lluvia; la otra mitad (densidad) la pone el director.
		var rain: float = Ocean.rain01
		if rain > 0.001:
			var lum: float = fog_col.r * 0.299 + fog_col.g * 0.587 + fog_col.b * 0.114
			fog_col = fog_col.lerp(Color(lum, lum, lum, fog_col.a), 0.7 * rain)
		_env.fog_light_color = fog_col

	if _sky != null:
		var top := profile.sample_color(profile.sky_top, t01, _sky.sky_top_color)
		var horizon := profile.sample_color(profile.sky_horizon, t01, _sky.sky_horizon_color)
		_sky.sky_top_color = top
		_sky.sky_horizon_color = horizon
		_sky.ground_horizon_color = horizon
		_sky.ground_bottom_color = horizon.darkened(0.65)

	if _sky_shader != null:
		_apply_sky_shader(t01, elevation_deg)


## El cielo propio tiene UN SOLO dueño: este nodo. El material lleva colores de
## la hora, direcciones de los astros y estado del clima leido de `Ocean` — si
## lo escribieran dos sistemas se pisarian, que es exactamente el bug que hubo
## con la niebla (color aqui, densidad en el TsunamiDirector).
func _apply_sky_shader(t01: float, elevation_deg: float) -> void:
	var top := profile.sample_color(profile.sky_top, t01, Color.SLATE_GRAY)
	var horizon := profile.sample_color(profile.sky_horizon, t01, Color.SLATE_GRAY)
	_sky_shader.set_shader_parameter(&"sky_top_color", top)
	_sky_shader.set_shader_parameter(&"sky_horizon_color", horizon)
	_sky_shader.set_shader_parameter(&"ground_horizon_color", horizon)
	_sky_shader.set_shader_parameter(&"ground_bottom_color", horizon.darkened(0.65))

	# Direcciones EXPLICITAS de sol y luna. El shader no adivina por indice de
	# luz: con tres DirectionalLight3D en escena (sol, luna y la del rayo) el
	# ProceduralSkyMaterial pintaba un disco por cada una y aparecia un tercer
	# "sol" fantasma en el cielo.
	var sun_basis := Basis.from_euler(
		Vector3(deg_to_rad(elevation_deg), deg_to_rad(SUN_AZIMUTH_DEG), 0.0))
	_sky_shader.set_shader_parameter(&"sun_dir", -sun_basis.z)
	var moon_basis := Basis.from_euler(
		Vector3(deg_to_rad(elevation_deg + 180.0), deg_to_rad(SUN_AZIMUTH_DEG), 0.0))
	_sky_shader.set_shader_parameter(&"moon_dir", -moon_basis.z)

	if _sun != null:
		_sky_shader.set_shader_parameter(&"sun_color", _sun.light_color)
		_sky_shader.set_shader_parameter(&"sun_visible",
			clampf(_sun.light_energy / maxf(profile.sun_energy_max, 0.01), 0.0, 1.0))
	if _moon != null:
		_sky_shader.set_shader_parameter(&"moon_color", _moon.light_color)
		_sky_shader.set_shader_parameter(&"moon_visible",
			clampf(_moon.light_energy / maxf(profile.moon_energy_max, 0.01), 0.0, 1.0))

	# Clima: el cielo se encapota con la furia y las nubes corren con el viento.
	# Se lee de Ocean, la unica puerta (regla 1 del repo).
	_sky_shader.set_shader_parameter(&"sky_time", Ocean.sim_time)
	_sky_shader.set_shader_parameter(&"fury01", clampf(Ocean.fury / 10.0, 0.0, 1.0))
	_sky_shader.set_shader_parameter(&"wind_dir", Ocean.wind_dir_vector())
	_sky_shader.set_shader_parameter(&"wind_speed", Ocean.wind_speed())
	_aplicar_frente()


## El FRENTE de tormenta: la pared de nubes que se ve venir por el horizonte.
##
## Estaba implementado en el shader desde la fase C y clavado a cero, y el
## motivo era exactamente este: dibujar un frente exige saber DE DONDE viene y
## CUANDO llega, y eso no existia hasta que hubo parte. Un frente que aparece
## cuando la furia ya subio no telegrafia nada — llega tarde, que es la unica
## forma en que puede estar mal.
##
## `front01` sale de la furia que VIENE, no de la de ahora: se lee el pico de
## los proximos minutos y el cielo se oscurece por delante del mar. Es la misma
## regla del §3.3 (el mar de fondo llega primero) aplicada a la mitad de
## arriba de la pantalla.
func _aplicar_frente() -> void:
	if not Ocean.tiene_parte():
		# Sin guion no hay futuro que leer, y fabricar uno con la furia de
		# ahora seria inventarse una prediccion. Cielo limpio de frentes.
		_sky_shader.set_shader_parameter(&"front01", 0.0)
		return
	var t: float = Ocean.sim_time
	var viene: float = Ocean.furia_swell(t, FRENTE_VENTANA)
	# Solo cuenta lo que el mar TODAVIA no tiene: cuando la tormenta ya llego,
	# el frente ya paso por encima y deja de leerse como pared en el horizonte.
	var delta: float = viene - Ocean.furia_en(t)
	var front01: float = clampf(delta / FRENTE_DELTA_PLENO, 0.0, 1.0) \
		* clampf(viene / 6.0, 0.0, 1.0)
	_sky_shader.set_shader_parameter(&"front01", front01)
	var ang: float = deg_to_rad(Ocean.rumbo_frente_en(t))
	_sky_shader.set_shader_parameter(&"front_dir", Vector2(cos(ang), sin(ang)))


## Cuanto futuro mira el frente. Mas corto que la ventana del swell (300 s):
## el cielo avisa DESPUES que el mar de fondo, que es el orden real — primero
## llega la ondulacion larga, despues se ve la pared.
const FRENTE_VENTANA := 210.0
## Cuantos puntos de furia de subida pendiente valen un frente a pleno.
const FRENTE_DELTA_PLENO := 3.0
