class_name TsunamiDirector
extends Node

## MODO TSUNAMI. Dirige la secuencia completa: tormenta, retirada, aviso, muro.
##
## [b]Los actos no son temporizadores.[/b] Se derivan de preguntarle al oceano
## cuando va a llegar la cresta a donde esta el jugador. Como todo el sistema es
## una funcion pura de t, esa pregunta se contesta exacta y al instante, en
## cualquier maquina, sin predecir nada. Un solver con estado (SWE, wave
## particles, FFT) no puede hacer esto: tendria que simular hasta el futuro para
## saber que va a pasar.
##
## Consecuencia practica: el HUD, el audio subsonico, la niebla que se abre y la
## IA leen todos el mismo numero y no pueden desincronizarse entre si.
##
## [b]Y la retirada del mar no esta scripteada.[/b] El perfil del tsunami es una
## onda N con una depresion viajando por delante de la cresta, asi que el agua se
## va sola. El barco se queda escorado, los barriles ruedan y el nadador es
## arrastrado mar adentro sin una sola linea de codigo dedicada a ello.

enum Act {
	CALMA, ## Mar manejable. Todavia no pasa nada.
	TORMENTA, ## La furia sube. El tsunami ya viene pero esta lejos.
	RETIRADA, ## El agua se va. Silencio. Todo el mundo entiende sin que se lo expliquen.
	AVISO, ## Linea blanca en el horizonte. Quedan segundos.
	IMPACTO, ## El muro.
	RESACA, ## Lo que quede, flotando.
}

signal act_changed(act: Act, seconds_to_impact: float)
signal tier_launched(tier: TsunamiTier)

const ACT_NAMES: Dictionary = {
	Act.CALMA: "CALMA",
	Act.TORMENTA: "TORMENTA",
	Act.RETIRADA: "EL MAR SE RETIRA",
	Act.AVISO: "AVISO",
	Act.IMPACTO: "IMPACTO",
	Act.RESACA: "RESACA",
}

## Nodo cuya posicion define "aqui" para toda la telegrafia.
@export var reference_path: NodePath

@export var environment_path: NodePath

@export_group("Secuencia")
## Segundos de mar en calma antes de que empiece a subir la furia.
@export var calm_seconds: float = 8.0
## Segundos desde que arranca la tormenta hasta que se lanza el tsunami.
@export var storm_seconds: float = 30.0
## Cuanto tarda la cresta en llegar desde que se lanza.
@export var lead_seconds: float = 95.0

@export_group("Umbrales de acto")
## La RETIRADA arranca cuando faltan retreat_seconds() * este factor para el
## impacto: el acto dura lo que dura la retirada DE ESE TIER, no un numero fijo.
@export var retreat_act_factor: float = 1.5
## Segundos antes de la cresta en que RETIRADA pasa a AVISO (la linea blanca en
## el horizonte). Numero de playtest: mas corto = menos margen para asegurarse.
@export var warning_seconds: float = 8.0
## Segundos despues de la cresta que siguen contando como IMPACTO.
@export var impact_tail_seconds: float = 6.0
## Segundos despues de la cresta en que termina la RESACA (y se reinicia el
## ciclo si `loop` esta activo). La RESACA es sagrada: recuento y risas.
@export var aftermath_seconds: float = 25.0

@export_group("Mar")
@export var fury_calm: float = 2.5
@export var fury_storm: float = 7.5
@export var fury_impact: float = 9.0

@export_group("El muro")
## Los tres escalones, en orden. Se editan como recursos desde el editor.
@export var tiers: Array[TsunamiTier] = []
## Cual se lanza. Con `cycle_tiers` activo, es solo el punto de partida.
@export var tier_index: int = 0
## Al repetir, sube al siguiente tier. Es la mejor forma de SENTIR la escalada:
## los tres seguidos en una sola sesion.
@export var cycle_tiers: bool = true
@export var from_direction_deg: float = 90.0

@export_group("Control")
@export var autostart: bool = true
## Al terminar, vuelve a empezar. Util para iterar sin reiniciar la escena.
@export var loop: bool = true

var act: Act = Act.CALMA
var seconds_to_impact: float = INF

var _reference: Node3D
var _environment: WorldEnvironment
var _elapsed: float = 0.0
var _launched: bool = false
var _running: bool = false
var _base_fog: float = 0.0


func _ready() -> void:
	_reference = get_node_or_null(reference_path) as Node3D
	_environment = get_node_or_null(environment_path) as WorldEnvironment
	if _environment != null and _environment.environment != null:
		_base_fog = _environment.environment.fog_density
	# En un cliente el mar lo escribe el host: arrancar aca llamaria a
	# `clear_events()` + `set_fury_immediate()` ANTES incluso de que haya
	# conexion, y despues pisaria el goteo cada tick.
	if autostart and not _es_cliente():
		start()


## Cede el mar al host SIN tocar nada global. No se puede usar `stop()`: llama
## a `Ocean.clear_events()` y borraria la tabla de eventos que el paquete de
## bienvenida acaba de plantar — o sea que unirse a mitad de tsunami borraria
## el tsunami.
func ceder_al_host() -> void:
	_running = false


func _es_cliente() -> bool:
	return Net != null and Net.rol == Net.Rol.CLIENTE


## Limpia la tabla de eventos POR LA VIA REPLICADA. Un `Ocean.clear_events()`
## pelado desde la escena solo borra la copia local: el host limpiaba la suya
## al reiniciar el bucle y el cliente se quedaba con el evento viejo marcado
## activo. Como su cresta ya habia pasado, no aportaba altura y nadie lo
## notaba... hasta que los DOS slots quedaban quemados y, del tercer tsunami
## en adelante, el cliente veia MAR PLANO bajo un barco que subia diecinueve
## metros. En solitario `pedir_debug` devuelve false y esto es lo de siempre.
func _limpiar_mar() -> void:
	if not Net.pedir_debug(Net.Debug.LIMPIAR, 0.0):
		Ocean.clear_events()


func start() -> void:
	_elapsed = 0.0
	_launched = false
	_running = true
	_limpiar_mar()
	Ocean.set_fury_immediate(fury_calm)
	Ocean.rain_scale = 1.0
	_set_act(Act.CALMA)


func stop() -> void:
	_running = false
	_limpiar_mar()
	# Si el director muere a mitad de RETIRADA, la lluvia no puede quedarse
	# cortada para siempre: el lanzador manual hereda un clima sano.
	Ocean.rain_scale = 1.0


func _physics_process(delta: float) -> void:
	if not _running:
		return
	# El guard tiene que estar AQUI y no solo en `Net`: los autoloads procesan
	# ANTES que `current_scene`, asi que `_update_sea()` es la ULTIMA escritura
	# de `Ocean.fury` y `rain_scale` de cada tick y le gana siempre al
	# `_estado_mar` que acaba de llegar. Un guard puesto solo en la red da test
	# verde y falla en partida.
	if _es_cliente():
		_running = false
		return
	_elapsed += delta

	if not _launched and _elapsed >= calm_seconds + storm_seconds:
		_launch()

	_update_act()
	_update_sea()
	_update_atmosphere()


func _launch() -> void:
	_launched = true
	var tier := current_tier()
	if tier == null:
		push_warning("TsunamiDirector sin tiers asignados.")
		return
	var here := _reference.global_position if _reference != null else Vector3.ZERO
	# Se pide POR TIEMPO DE LLEGADA, no por posicion de origen: lo que el
	# diseñador quiere decidir es cuando llega el muro, no desde donde sale.
	#
	# Un tier mas grande viaja mas rapido, asi que si el tiempo de aviso fuera
	# fijo el LEVIATAN daria MENOS margen real que el MURO. Se alarga en
	# proporcion para que la escalada sea de tamaño y no de injusticia.
	var reach: float = lead_seconds * sqrt(tier.size_multiplier)
	# En red la ola la reparte el host con un `t0` explicito, para que las seis
	# maquinas evaluen LA MISMA onda y el aviso no mienta en cinco pantallas.
	# En solitario, `pedir_tsunami` devuelve false y esto es lo de siempre.
	if not Net.pedir_tsunami(here, from_direction_deg, reach, tier):
		Ocean.spawn_tsunami_tier(here, from_direction_deg, reach, tier)
	print("Tsunami lanzado: ", tier.summary())
	tier_launched.emit(tier)


## El tier que se va a lanzar (o se acaba de lanzar).
func current_tier() -> TsunamiTier:
	if tiers.is_empty():
		return null
	return tiers[clampi(tier_index, 0, tiers.size() - 1)]


func _update_act() -> void:
	if not _launched:
		seconds_to_impact = INF
		_set_act(Act.CALMA if _elapsed < calm_seconds else Act.TORMENTA)
		return

	var here := _reference.global_position if _reference != null else Vector3.ZERO
	seconds_to_impact = Ocean.time_until_tsunami(here)

	# El umbral de RETIRADA se DERIVA del tier, no se fija a mano: la retirada del
	# LEVIATAN dura ~49 s y la del MURO ~36, asi que un numero fijo etiquetaria
	# mal los actos justo en el tier mas espectacular.
	var tier := current_tier()
	var retreat_start: float = tier.retreat_seconds() * retreat_act_factor if tier != null else 55.0

	var next: Act
	if seconds_to_impact > retreat_start:
		next = Act.TORMENTA
	elif seconds_to_impact > warning_seconds:
		next = Act.RETIRADA
	elif seconds_to_impact > 0.0:
		next = Act.AVISO
	elif seconds_to_impact > -impact_tail_seconds:
		next = Act.IMPACTO
	else:
		next = Act.RESACA
	_set_act(next)

	if act == Act.RESACA and seconds_to_impact < -aftermath_seconds:
		if loop:
			if cycle_tiers and not tiers.is_empty():
				tier_index = (tier_index + 1) % tiers.size()
			start()
		else:
			_running = false


func _set_act(next: Act) -> void:
	if next == act:
		return
	act = next
	act_changed.emit(act, seconds_to_impact)


func _update_sea() -> void:
	# El dial de furia se mueve solo; el rate limit de Ocean se encarga de que
	# la transicion sea continua y no haya popping.
	#
	# La lluvia acompaña la furia (rampa automatica de Ocean) EXCEPTO de la
	# RETIRADA en adelante: cortarla ahi es telegrafia — el silencio subito de
	# la lluvia mientras el agua se va dice "esto no es una tormenta normal"
	# sin una sola linea de UI (docs/CLIMA.md §1.2). Vuelve en la RESACA.
	match act:
		Act.CALMA:
			Ocean.fury = fury_calm
			Ocean.rain_scale = 1.0
		Act.TORMENTA:
			Ocean.fury = fury_storm
			Ocean.rain_scale = 1.0
		Act.RETIRADA:
			# El oleaje de viento AFLOJA mientras el agua se va. Ese silencio
			# relativo es lo que hace que la retirada de miedo en vez de parecer
			# un bug: el mar se queda quieto justo antes del golpe.
			Ocean.fury = fury_storm - 2.0
			Ocean.rain_scale = 0.0
		Act.AVISO, Act.IMPACTO:
			Ocean.fury = fury_impact
			Ocean.rain_scale = 0.0
		Act.RESACA:
			Ocean.fury = fury_storm
			Ocean.rain_scale = 1.0


func _update_atmosphere() -> void:
	if _environment == null or _environment.environment == null:
		return
	var env := _environment.environment
	# La niebla es el instrumento dramatico: espesa durante la tormenta para que
	# no veas lo que viene, y se ABRE de golpe en el aviso para que lo veas todo
	# de una vez y no tengas tiempo de hacer nada.
	var target := _base_fog
	match act:
		Act.TORMENTA:
			target = _base_fog * 1.9
		Act.RETIRADA:
			target = _base_fog * 1.35
		Act.AVISO, Act.IMPACTO:
			target = _base_fog * 0.45
	# La lluvia espesa la niebla POR ENCIMA de lo que pide el acto (Lagarde:
	# las gotas comen visibilidad lejana). Como rain_scale ya es 0 en
	# RETIRADA/AVISO, la apertura dramatica pre-impacto no se contamina.
	target += _base_fog * 1.5 * Ocean.rain01
	# Rampa sobre el delta de FISICA (= reloj de simulacion): determinista en
	# partida. La version funcion-pura-de-t llega con el guion comprometido de
	# furia (docs/CLIMA.md fase D) — un tween aqui seria irreproducible para un
	# late joiner (§7).
	env.fog_density = move_toward(env.fog_density, target, _base_fog * 1.6 * get_physics_process_delta_time())


## Si el director lleva la secuencia, o si la ha tomado el lanzador manual.
func is_running() -> bool:
	return _running


func act_name() -> String:
	return ACT_NAMES.get(act, "?")
