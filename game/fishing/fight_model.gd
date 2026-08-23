class_name FightModel
extends RefCounted

## La matematica de la LUCHA con el pez, separada del nodo para poder testearla
## sin simular inputs.
##
## LA FORMULA DEL DOCUMENTO DE DISEÑO — un sistema, dos sensaciones:
##
##     tension = tiron(pez) + k * |aceleracion_vertical(borda)|
##
## El segundo termino es lo que une la pesca con el mar: la aceleracion de la
## cubierta entra DIRECTA en la tension del sedal, asi que pescar con furia 7 es
## objetivamente mas dificil con el mismo input — sin rubber-banding posible,
## porque la aceleracion sale de la fisica real del barco, no de un dial oculto.
##
## Filosofia DREDGE ("fishing should not be frustrating"): fallar la contra o
## recoger en mal momento SUBE LA TENSION, pero el unico fallo real es la rotura
## sostenida — y rompe el sedal con un latigazo comico, jamas castiga mas alla
## del pez perdido.

## Umbral de aviso: el carrete chirria (>= 1 s antes de poder romper).
const WARN_TENSION := 0.8
## Rotura: tension >= 1.0 sostenida este tiempo.
const SNAP_TENSION := 1.0
const SNAP_HOLD_SECONDS := 0.5

## Peso del mar en la formula. Con furia 5 la borda acelera ~2-4 m/s2
## (contribucion 0.12-0.24); con furia 7-8, ~6-10 m/s2 (0.36-0.6): la pesca
## "heroica" vive al borde del chirrido todo el tiempo.
const SEA_K := 0.06

## Recoger con el pez TIRANDO es la apuesta; recoger en la pausa es gratis.
const REEL_RATE_SLACK := 0.16
const REEL_RATE_PULLING := 0.07
const REEL_TENSION_PULLING := 0.28
const REEL_TENSION_SLACK := 0.06

## Contrar bien no anula el tiron: lo reduce a un tercio. El mar pone el resto.
const COUNTER_FACTOR := 0.35

enum Pull { NONE, LEFT, RIGHT }

var fish: Dictionary = {}
var progress: float = 0.0 ## 0 = recien picado, 1 = pez en superficie
var tension: float = 0.0
var pull_dir: Pull = Pull.NONE
var snapped: bool = false
var landed: bool = false

var _rng: RandomNumberGenerator
var _phase_left: float = 0.0
var _over_tension_time: float = 0.0


func start(species: Dictionary, rng: RandomNumberGenerator) -> void:
	fish = species
	_rng = rng
	progress = 0.0
	tension = 0.0
	snapped = false
	landed = false
	# El primer tiron llega enseguida: la picada ES el gancho.
	pull_dir = Pull.LEFT if rng.randf() < 0.5 else Pull.RIGHT
	_phase_left = rng.randf_range(1.0, 2.2)


## Un tick de lucha.
## [param reeling] el jugador esta recogiendo.
## [param counter] hacia donde tira EL JUGADOR (la contra correcta es la
## opuesta al pez).
## [param sea_accel_y] aceleracion vertical de la borda, m/s2.
func step(delta: float, reeling: bool, counter: Pull, sea_accel_y: float) -> void:
	if snapped or landed or fish.is_empty():
		return

	# Fases del pez: tira 1-3 s, descansa 0.8-2 s. La pausa es la ventana de
	# recogida limpia: el ritmo del juego es leer ese vaiven.
	_phase_left -= delta
	if _phase_left <= 0.0:
		if pull_dir == Pull.NONE:
			pull_dir = Pull.LEFT if _rng.randf() < 0.5 else Pull.RIGHT
			_phase_left = _rng.randf_range(1.0, 3.0)
		else:
			pull_dir = Pull.NONE
			_phase_left = _rng.randf_range(0.8, 2.0)

	# --- tiron del pez -------------------------------------------------------
	var t: float = 0.05 # el sedal nunca esta del todo muerto
	if pull_dir != Pull.NONE:
		var countered: bool = (counter == Pull.LEFT and pull_dir == Pull.RIGHT) \
			or (counter == Pull.RIGHT and pull_dir == Pull.LEFT)
		t += float(fish[&"pull"]) * (COUNTER_FACTOR if countered else 1.0)

	# --- recogida ------------------------------------------------------------
	if reeling:
		if pull_dir != Pull.NONE:
			t += REEL_TENSION_PULLING
			progress += REEL_RATE_PULLING * delta
		else:
			t += REEL_TENSION_SLACK
			progress += REEL_RATE_SLACK * delta

	# --- el mar --------------------------------------------------------------
	t += SEA_K * absf(sea_accel_y)

	tension = t

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
