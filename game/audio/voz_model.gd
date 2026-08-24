class_name VozModel
extends RefCounted

## Cuánto os oís, según lo que ruja el mar. La aritmética de la voz por
## proximidad, PURA: cero nodos, cero audio, cero red — igual que `NetPorteo` o
## `AguaEmbarcadaModel`, y por el mismo motivo: lo que decide algo tiene que
## poder probarse sin levantar el juego.
##
## [b]La mecánica[/b] (docs/CLIMA.md §3.5, docs/PLAN.md): en calma os oís de
## popa a proa; en temporal, solo si estáis al lado. La comunicación se degrada
## con el peligro, exactamente cuando más la necesitáis, y el juego de dar
## órdenes se convierte en un juego de gritos de una palabra y señas. Eso ES el
## clímax cooperativo, y sale de encoger un radio.
##
## [b]La regla que evita que esto mienta:[/b] el ruido que tapa la voz NO es una
## curva propia — es EXACTAMENTE la mezcla de las camas de clima que ya suenan
## (`WeatherAudio.ruido01()`). Dos curvas que dicen lo mismo se separan en cuanto
## alguien afina una, y entonces la voz se perdería cuando el jugador no oye
## nada raro, que es la definición de feedback que miente (regla 8).
##
## [b]Y el refugio devuelve el oído.[/b] Meterse en la cabina baja el ruido, así
## que dentro se vuelve a hablar: una razón ACÚSTICA para reunirse, no un cartel.

## Suelo del radio útil, en metros. Por debajo de esto no se baja ni en el peor
## temporal: a bocajarro siempre te oyen. Sin este suelo, un balance mal puesto
## dejaría a dos jugadores pegados sin poder hablar, que se lee como micrófono
## roto y no como tormenta.
const RADIO_MINIMO := 1.5


## Ruido efectivo que tapa la voz, 0..1, ya descontado el refugio.
##
## `interior01` es 0 a la intemperie y 1 dentro de la cabina; `alivio_interior`
## es cuánto de ese ruido se queda fuera al entrar.
static func ruido_efectivo(ruido01: float, interior01: float,
		alivio_interior: float) -> float:
	var r: float = clampf(ruido01, 0.0, 1.0)
	var dentro: float = clampf(interior01, 0.0, 1.0)
	var alivio: float = clampf(alivio_interior, 0.0, 1.0)
	return clampf(r * (1.0 - alivio * dentro), 0.0, 1.0)


## A cuántos metros te siguen entendiendo. Es EL número de la mecánica.
static func radio_util(ruido01: float, interior01: float, radio_calma: float,
		radio_temporal: float, alivio_interior: float) -> float:
	var r := ruido_efectivo(ruido01, interior01, alivio_interior)
	return maxf(lerpf(radio_calma, radio_temporal, r), RADIO_MINIMO)


## Corte del paso-bajo del bus de voz, en Hz: la voz "rota" por el viento.
##
## Se filtra en el BUS y no en cada hablante porque esto no le pasa a la voz del
## otro, le pasa a TU oído: es el viento contra tus orejas el que se come los
## agudos. Y la banda que se pierde es justo la de la inteligibilidad —el mar y
## el viento pican en 300-1500 Hz, la misma banda que la voz (docs/CLIMA.md
## §6.2)—, así que oyes que alguien grita y no distingues qué.
static func corte_lpf(ruido01: float, interior01: float, hz_calma: float,
		hz_temporal: float, alivio_interior: float) -> float:
	var r := ruido_efectivo(ruido01, interior01, alivio_interior)
	# Se interpola en octavas y no en Hz: el oído oye ratios, y en lineal el
	# filtro no haría nada perceptible hasta el final del recorrido.
	var lo: float = log(maxf(hz_temporal, 20.0)) / log(2.0)
	var hi: float = log(maxf(hz_calma, 20.0)) / log(2.0)
	return pow(2.0, lerpf(hi, lo, r))


## Cuánto se entiende a `distancia` metros, 0..1.
##
## Solo para tests y para el HUD de debug: la atenuación de verdad la aplica el
## motor con el `AudioStreamPlayer3D`, que además sabe de posición y de doppler.
## Duplicar aquí su curva sería el mismo número en dos sitios.
static func inteligibilidad(distancia: float, radio: float) -> float:
	if radio <= 0.0:
		return 0.0
	return clampf(1.0 - maxf(distancia, 0.0) / radio, 0.0, 1.0)
