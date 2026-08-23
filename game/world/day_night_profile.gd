class_name DayNightProfile
extends Resource

## Perfil de un ciclo dia/noche completo. Se edita como recurso desde el editor:
## los colores son [Gradient] y las energias son [Curve], ambos muestreados por
## la hora del dia normalizada (0 = medianoche, 0.25 = amanecer, 0.5 = mediodia,
## 0.75 = atardecer).
##
## Las curvas se guardan NORMALIZADAS (0..1) y se escalan por los `*_max`: asi
## se puede subir la energia del sol sin redibujar la curva.

## Duracion del dia completo en segundos de simulacion. 1200 = 20 min: una run
## de 25-40 min arranca de dia y la noche cae a mitad de la travesia.
@export var day_length_seconds: float = 1200.0

@export_group("Cielo")
@export var sky_top: Gradient
@export var sky_horizon: Gradient

@export_group("Sol")
@export var sun_color: Gradient
@export var sun_energy: Curve
@export var sun_energy_max: float = 1.7

@export_group("Luna")
## La luna existe para que la noche sea JUGABLE. Un friendslop necesita que se
## vea el barco y a los compañeros: noche azul oscura, nunca negra.
@export var moon_color := Color(0.55, 0.65, 0.85)
@export var moon_energy: Curve
@export var moon_energy_max: float = 0.22

@export_group("Ambiente")
@export var ambient_color: Gradient
@export var ambient_energy: Curve
@export var ambient_energy_max: float = 0.5
@export var fog_color: Gradient


func sample_color(gradient: Gradient, t01: float, fallback: Color) -> Color:
	if gradient == null:
		return fallback
	return gradient.sample(t01)


func sample_energy(curve: Curve, t01: float, max_value: float) -> float:
	if curve == null:
		return max_value
	return curve.sample_baked(t01) * max_value
