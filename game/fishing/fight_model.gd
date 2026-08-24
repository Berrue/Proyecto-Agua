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
##
## TIERS (feedback del playtest: "el sedal rompe demasiado rapido"). La ventana
## de reaccion tras entrar en zona de rotura ya no es plana: la fija el TIER
## del pez (SNAP_HOLD_BY_TIER) y la alarga la caña montada (RodTier). La caña
## ademas multiplica la tension que aguanta el sedal y la velocidad del
## carrete. Puerta BLANDA a proposito: ninguna caña prohibe ningun pez — la
## fisica decide, el feedback la cuenta (regla 8), y todo se normaliza contra
## el limite REAL del sedal montado: el chirrido dice "cerca de TU rotura".

## Umbral de aviso, como fraccion del limite del sedal: el carrete chirria
## con margen antes de poder romper, monte lo que monte la caña.
const WARN_TENSION := 0.8
const SNAP_TENSION := 1.0
## La ventana de reaccion: segundos de sobrecarga SOSTENIDA antes del snap,
## por tier del pez (indice tier-1). Del playtest: 0.5 s planos para todos
## rompian "demasiado rapido" — el que aprende con sardinas necesita margen
## real para soltar el clic; el que pelea la legendaria ya sabe lo que hace.
## La banda A perdona mas del doble que la C, y bajar de ~0.45 s convertiria
## la rotura en un robo (regla 8: siempre se avisa, siempre da tiempo).
const SNAP_HOLD_BY_TIER: Array[float] = [1.5, 1.0, 0.65, 0.45]

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

## Lo que aporta la caña montada (RodTier). 1.0/1.0 = la caña de iniciacion.
var line_strength: float = 1.0
var reel_factor: float = 1.0
## Ventana de reaccion vigente: la del tier del pez + la gracia de la caña.
var snap_hold: float = SNAP_HOLD_BY_TIER[0]

var _rng: RandomNumberGenerator
var _phase_left: float = 0.0
var _over_tension_time: float = 0.0


func start(species: Dictionary, rng: RandomNumberGenerator, rod: RodTier = null) -> void:
	fish = species
	_rng = rng
	progress = 0.0
	tension = 0.0
	stamina = 1.0
	spit = 0.0
	snapped = false
	escaped = false
	landed = false
	_over_tension_time = 0.0 # una lucha nueva no hereda la sobrecarga de la anterior
	var tier: int = FishSpecies.tier_of(species)
	snap_hold = SNAP_HOLD_BY_TIER[clampi(tier - 1, 0, SNAP_HOLD_BY_TIER.size() - 1)]
	line_strength = 1.0
	reel_factor = 1.0
	if rod != null:
		line_strength = rod.line_strength
		reel_factor = rod.reel_factor
		snap_hold += rod.snap_hold_bonus
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

	# --- recogida (el carrete de la caña multiplica lo recogido) -------------
	if reeling:
		if pull_dir != Pull.NONE:
			t += REEL_TENSION_PULLING
			progress += REEL_RATE_PULLING * reel_factor * delta
		else:
			t += REEL_TENSION_SLACK
			progress += REEL_RATE_SLACK * reel_factor * delta

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

	# --- rotura: sobrecarga sostenida contra el sedal MONTADO ----------------
	if tension >= max_tension():
		_over_tension_time += delta
		if _over_tension_time >= snap_hold:
			snapped = true
	else:
		_over_tension_time = 0.0

	if progress >= 1.0:
		landed = true


## La tension que aguanta el sedal de la caña montada. Todo el feedback se
## normaliza contra ESTA cifra: chirrido, color y HUD dicen "cerca de TU
## limite", no de uno ideal que el jugador no puede conocer.
func max_tension() -> float:
	return SNAP_TENSION * line_strength


func is_pulling() -> bool:
	return pull_dir != Pull.NONE


func is_warning() -> bool:
	return tension >= WARN_TENSION * line_strength


## El aviso de que el anzuelo se esta aflojando: comba exagerada y boya a la
## deriva ANTES de perder el pez. "Me aviso", nunca "me robo".
func is_spit_warning() -> bool:
	return spit >= SPIT_WARNING
