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

@export_group("Mar")
@export var fury_calm: float = 2.5
@export var fury_storm: float = 7.5
@export var fury_impact: float = 9.0

@export_group("El muro")
@export var amplitude: float = 19.0
@export var celerity: float = 45.0
@export var width: float = 90.0
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
	if autostart:
		start()


func start() -> void:
	_elapsed = 0.0
	_launched = false
	_running = true
	Ocean.clear_events()
	Ocean.set_fury_immediate(fury_calm)
	_set_act(Act.CALMA)


func stop() -> void:
	_running = false
	Ocean.clear_events()


func _physics_process(delta: float) -> void:
	if not _running:
		return
	_elapsed += delta

	if not _launched and _elapsed >= calm_seconds + storm_seconds:
		_launch()

	_update_act()
	_update_sea()
	_update_atmosphere()


func _launch() -> void:
	_launched = true
	var here := _reference.global_position if _reference != null else Vector3.ZERO
	# Se pide POR TIEMPO DE LLEGADA, no por posicion de origen: lo que el
	# diseñador quiere decidir es cuando llega el muro, no desde donde sale.
	Ocean.spawn_tsunami(here, from_direction_deg, lead_seconds, amplitude, celerity, width)


func _update_act() -> void:
	if not _launched:
		seconds_to_impact = INF
		_set_act(Act.CALMA if _elapsed < calm_seconds else Act.TORMENTA)
		return

	var here := _reference.global_position if _reference != null else Vector3.ZERO
	seconds_to_impact = Ocean.time_until_tsunami(here)

	# Los umbrales estan atados a la forma de la onda N: con lead=12, spread=9 y
	# W/c = 2 s, la depresion empieza a notarse ~55 s antes de la cresta.
	var next: Act
	if seconds_to_impact > 55.0:
		next = Act.TORMENTA
	elif seconds_to_impact > 8.0:
		next = Act.RETIRADA
	elif seconds_to_impact > 0.0:
		next = Act.AVISO
	elif seconds_to_impact > -6.0:
		next = Act.IMPACTO
	else:
		next = Act.RESACA
	_set_act(next)

	if act == Act.RESACA and seconds_to_impact < -25.0:
		if loop:
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
	match act:
		Act.CALMA:
			Ocean.fury = fury_calm
		Act.TORMENTA:
			Ocean.fury = fury_storm
		Act.RETIRADA:
			# El oleaje de viento AFLOJA mientras el agua se va. Ese silencio
			# relativo es lo que hace que la retirada de miedo en vez de parecer
			# un bug: el mar se queda quieto justo antes del golpe.
			Ocean.fury = fury_storm - 2.0
		Act.AVISO, Act.IMPACTO:
			Ocean.fury = fury_impact
		Act.RESACA:
			Ocean.fury = fury_storm


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
	env.fog_density = move_toward(env.fog_density, target, _base_fog * 1.6 * get_physics_process_delta_time())


func act_name() -> String:
	return ACT_NAMES.get(act, "?")
