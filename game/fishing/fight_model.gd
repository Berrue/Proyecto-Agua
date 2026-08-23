class_name FightModel
extends RefCounted

## La matematica de la LUCHA con el pez, separada del nodo para poder testearla
## sin simular inputs.
##
## LA FORMULA DEL DOCUMENTO DE DISEÑO — un sistema, dos sensaciones:
##
##     tension = tiron(pez) + k * |aceleracion_vertical(borda)|
##
## Y EL TIRA-Y-AFLOJA (añadido tras el playtest: "solo se clickea y se pesca
## solo"). Sin dos fallos OPUESTOS, la estrategia dominante es mantener el clic
## y esperar — el minijuego no existe (leccion de Fishing Planet). Ahora:
##
##   1. EL PEZ SE LLEVA SEDAL: durante el tiron, el progreso BAJA. Contrar bien
##      (A/D al lado contrario) lo frena a un cuarto — la contra importa en
##      cada tiron, no solo cerca de la rotura.
##   2. RECOGER EN TIRON ES CARO: tension alta Y apenas avanza. Recoger en la
##      PAUSA es la ventana buena. El ritmo tirar/recoger ES el minijuego.
##   3. NO RECOGER TAMBIEN PIERDE: sedal flojo sostenido = el pez escupe el
##      anzuelo (con aviso ANTES, nunca de golpe — la regla de justicia).
##
## El pez ademas SE CANSA: los tirones se acortan y debilitan, las pausas se
## alargan — se ve ganar sin ninguna barra.
##
## Filosofia DREDGE intacta: en calma y con pez pequeño sigue siendo indulgente
## (banda A: "pescas mirando al amigo"); el castigo real crece con el mar y con
## el pez, que es la tesis del juego.

## Umbral de aviso: el carrete chirria (>= 1 s antes de poder romper).
const WARN_TENSION := 0.8
const SNAP_TENSION := 1.0
const SNAP_HOLD_SECONDS := 0.5

## Peso del mar en la formula (furia 5 ~ 0.12-0.24; furia 7-8 ~ 0.36-0.6).
const SEA_K := 0.06

## Recoger en la pausa es la ventana buena; en el tiron, caro y arriesgado.
const REEL_RATE_SLACK := 0.16
const REEL_RATE_PULLING := 0.07
## 0.5 y no menos: con 0.4, mantener el clic contra un bacalao ganaba en 16 s
## sin castigo (lo cazo el test). Con 0.5, recoger durante el tiron SIN contra
## rompe el sedal en banda B+; CON contra queda en ~0.74 — la jugada agresiva
## existe, pero exige la contra. Ese es el gradiente de habilidad.
const REEL_TENSION_PULLING := 0.5
const REEL_TENSION_SLACK := 0.06

## El pez se lleva sedal durante el tiron. La contra correcta lo frena a 1/4.
const RUN_RATE := 0.09
const RUN_COUNTERED_FACTOR := 0.25

## Contrar bien no anula el tiron: lo reduce a un tercio. El mar pone el resto.
const COUNTER_FACTOR := 0.35

## Sedal flojo sostenido: el anzuelo se afloja. Sube parado en pausa, baja al
## recoger. A 1.0 el pez escupe; el aviso (comba exagerada, boya derivando)
## entra en 0.5 — SIEMPRE hay rampa antes del fallo.
const SPIT_BUILD_RATE := 0.4
const SPIT_RECOVER_RATE := 0.8
const SPIT_WARNING := 0.5

## Fatiga: el pez pierde fuelle mientras tira. Se ve ganar sin barras.
const TIRE_RATE := 0.05
const TIRED_PULL_FLOOR := 0.55

enum Pull { NONE, LEFT, RIGHT }

var fish: Dictionary = {}
var progress: float = 0.0 ## 0 = recien picado, 1 = pez en superficie
var tension: float = 0.0
var pull_dir: Pull = Pull.NONE
var stamina: float = 1.0 ## 1 = fresco, 0 = agotado
var spit: float = 0.0 ## 0..1: sedal flojo acumulado
var snapped: bool = false
var escaped: bool = false ## escupio el anzuelo (fallo por defecto de tension)
var landed: bool = false

var _rng: RandomNumberGenerator
var _phase_left: float = 0.0
var _over_tension_time: float = 0.0


func start(species: Dictionary, rng: RandomNumberGenerator) -> void:
	fish = species
	_rng = rng
	progress = 0.0
	tension = 0.0
	stamina = 1.0
	spit = 0.0
	snapped = false
	escaped = false
	landed = false
	pull_dir = Pull.LEFT if rng.randf() < 0.5 else Pull.RIGHT
	_phase_left = rng.randf_range(1.0, 2.2)


func step(delta: float, reeling: bool, counter: Pull, sea_accel_y: float) -> void:
	if snapped or landed or escaped or fish.is_empty():
		return

	# Fases del pez, moduladas por la fatiga: fresco tira 1-3 s y descansa
	# 0.8-2 s; agotado tira poco y descansa mucho.
	_phase_left -= delta
	if _phase_left <= 0.0:
		if pull_dir == Pull.NONE:
			pull_dir = Pull.LEFT if _rng.randf() < 0.5 else Pull.RIGHT
			_phase_left = _rng.randf_range(1.0, 3.0) * (0.4 + 0.6 * stamina)
		else:
			pull_dir = Pull.NONE
			_phase_left = _rng.randf_range(0.8, 2.0) * (1.0 + (1.0 - stamina) * 0.8)

	var countered: bool = (counter == Pull.LEFT and pull_dir == Pull.RIGHT) \
		or (counter == Pull.RIGHT and pull_dir == Pull.LEFT)

	# --- tiron del pez (debilitado por la fatiga) ----------------------------
	var t: float = 0.05
	var pull_strength: float = float(fish[&"pull"]) * (TIRED_PULL_FLOOR + (1.0 - TIRED_PULL_FLOOR) * stamina)
	if pull_dir != Pull.NONE:
		t += pull_strength * (COUNTER_FACTOR if countered else 1.0)
		# EL PEZ SE LLEVA SEDAL: sin contra, a toda vela; con contra, a 1/4.
		progress -= RUN_RATE * (RUN_COUNTERED_FACTOR if countered else 1.0) * delta
		# Tirar cansa al pez — es la unica forma de agotarlo.
		stamina = maxf(stamina - TIRE_RATE * delta, 0.0)

	# --- recogida ------------------------------------------------------------
	if reeling:
		if pull_dir != Pull.NONE:
			t += REEL_TENSION_PULLING
			progress += REEL_RATE_PULLING * delta
		else:
			t += REEL_TENSION_SLACK
			progress += REEL_RATE_SLACK * delta

	# --- sedal flojo: el anzuelo se afloja -----------------------------------
	if pull_dir == Pull.NONE and not reeling:
		spit = minf(spit + SPIT_BUILD_RATE * delta, 1.0)
		if spit >= 1.0:
			escaped = true
	else:
		spit = maxf(spit - SPIT_RECOVER_RATE * delta, 0.0)

	# --- el mar --------------------------------------------------------------
	t += SEA_K * absf(sea_accel_y)

	tension = t
	progress = clampf(progress, 0.0, 1.0)

	# --- rotura --------------------------------------------------------------
	if tension >= SNAP_TENSION:
		_over_tension_time += delta
		if _over_tension_time >= SNAP_HOLD_SECONDS:
			snapped = true
	else:
		_over_tension_time = 0.0

	if progress >= 1.0:
		landed = true


func is_pulling() -> bool:
	return pull_dir != Pull.NONE


func is_warning() -> bool:
	return tension >= WARN_TENSION


## El aviso de que el anzuelo se esta aflojando: comba exagerada y boya a la
## deriva ANTES de perder el pez. "Me aviso", nunca "me robo".
func is_spit_warning() -> bool:
	return spit >= SPIT_WARNING
