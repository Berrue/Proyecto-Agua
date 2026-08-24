class_name VozBalance
extends Resource

## Los números de la voz por proximidad, editables sin tocar código
## (`resources/audio/voz_proximidad.tres`). Es balance de diseño, no física:
## decide cuánto cuesta comunicarse, que es una palanca de dificultad social.

@export_group("Radio útil")
## A cuántos metros os oís con el mar en calma. 40 m cubre el pesquero entero de
## popa a proa con margen: en calma la conversación es libre y ese es el punto
## de partida contra el que se nota la pérdida.
@export var radio_calma: float = 40.0

## Y a cuántos con el temporal encima. 9 m es MENOS que la eslora del barco
## (13 m), y esa es exactamente la mecánica: en el pico no puedes darle una
## orden al de proa desde el timón, tienes que ir, señalar, o gritar una sola
## palabra y rezar.
##
## ⚠️ Los dos docs no dicen lo mismo: `docs/CLIMA.md` §3.5 dice «~40 m en F0 →
## 8-10 m en F9» y `docs/PLAN.md` dice «en calma os oís a 30 m, en tormenta a
## 3». Se toman los de CLIMA porque son la conclusión del documento de
## investigación y no el eslogan del pitch; los de PLAN dejan el radio de
## temporal en la mitad del ancho del barco, que probablemente sea pasarse.
## Queda para playtest: es un número de diseño y se mueve desde aquí.
@export var radio_temporal: float = 9.0

@export_group("El filtro del oído")
## Corte del paso-bajo con el mar en calma: abierto, la voz entera.
@export var hz_calma: float = 20500.0

## Y con el temporal: 1400 Hz deja el cuerpo de la voz pero se lleva la banda
## que distingue las consonantes, así que oyes QUE grita y no QUÉ grita.
@export var hz_temporal: float = 1400.0

@export_group("Refugio")
## Cuánto ruido se queda fuera al meterse en la cabina, 0..1. A 0,7 el peor
## temporal se oye dentro como un mar medio, y el radio útil vuelve a subir:
## es la razón acústica para reunirse dentro (docs/CLIMA.md §3.5), y la que
## convierte la timonera en un sitio al que se va a hablar, no solo a mirar.
@export_range(0.0, 1.0) var alivio_interior: float = 0.7
