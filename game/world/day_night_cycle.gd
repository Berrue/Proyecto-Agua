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
	var t: float = (start_hour + _debug_hour_offset) / 24.0 + sim_time / maxf(day_len, 1.0)
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
		_env.fog_light_color = profile.sample_color(
			profile.fog_color, t01, _env.fog_light_color)

	if _sky != null:
		var top := profile.sample_color(profile.sky_top, t01, _sky.sky_top_color)
		var horizon := profile.sample_color(profile.sky_horizon, t01, _sky.sky_horizon_color)
		_sky.sky_top_color = top
		_sky.sky_horizon_color = horizon
		_sky.ground_horizon_color = horizon
		_sky.ground_bottom_color = horizon.darkened(0.65)
