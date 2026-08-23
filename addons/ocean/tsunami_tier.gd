class_name TsunamiTier
extends Resource

## Un escalon de tsunami. Se edita como recurso desde el editor.
##
## [b]Por que no basta con subir la altura.[/b] Si solo se escala la amplitud, un
## tier mayor sale igual de ancho pero mucho mas empinado: deja de leerse como un
## tsunami y pasa a ser un acantilado vertical que aparece de golpe. Un tsunami
## de verdad que trae mas energia es mas alto Y mas largo Y mas rapido.
##
## Por eso [member size_multiplier] mueve las tres cosas a la vez, cada una con
## la ley que le toca:
##
## [codeblock]
## amplitud  = base * m            lineal: es LA cifra del tier
## anchura   = base * sqrt(m)      sublineal: crece, pero deja que se empine
## celeridad = base * sqrt((h+A)/(h+A_base))   onda solitaria: c = sqrt(g(h+A))
## [/codeblock]
##
## El resultado es una escalada que se nota en las tres dimensiones que el
## jugador percibe: cuanto sube el agua, cuanto dura el castigo, y cuanto tiempo
## tiene para reaccionar.

## Base del tier 1. Los demas escalan desde aqui.
const BASE_AMPLITUDE := 19.0
const BASE_CELERITY := 45.0
const BASE_WIDTH := 90.0

## Nombre corto, el que ve el jugador en el aviso.
@export var tier_name: String = "MURO"

## 1.0 = base. 1.5 = un 50% mas grande. 2.2 = un 120% mas grande.
@export var size_multiplier: float = 1.0

@export_group("Forma de la onda N")
## A cuantas anchuras por delante viaja la depresion. Subirlo da mas aviso.
@export var lead: float = 12.0
## Cuanto mas ancha es la depresion que la cresta. Es lo que alarga la retirada.
@export var spread: float = 9.0
## Profundidad de la retirada, relativa a la amplitud.
@export_range(0.0, 1.0) var depression: float = 0.55


func amplitude() -> float:
	return BASE_AMPLITUDE * size_multiplier


## Sublineal a proposito: si la anchura creciera igual que la altura, todos los
## tiers tendrian exactamente la misma pendiente y se verian iguales de cerca.
func width() -> float:
	return BASE_WIDTH * sqrt(size_multiplier)


## Velocidad de una onda solitaria, c = sqrt(g*(h+A)): las olas mas altas viajan
## mas rapido, asi que un tier mayor tambien te da menos tiempo de reaccion.
func celerity() -> float:
	var h := OceanEvents.EFFECTIVE_DEPTH
	return BASE_CELERITY * sqrt((h + amplitude()) / (h + BASE_AMPLITUDE))


## Metros que baja el mar en el punto mas bajo de la retirada.
func retreat_depth() -> float:
	return amplitude() * depression


## Cuanto dura aproximadamente la retirada, en segundos.
func retreat_seconds() -> float:
	return 2.0 * spread * width() / celerity()


## Resumen legible, para el HUD y para los logs de playtest.
func summary() -> String:
	return "%s  ·  %.0f m de muro  ·  %.0f m de retirada  ·  %.0f m/s" % [
		tier_name, amplitude(), retreat_depth(), celerity()]
