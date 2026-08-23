@tool
class_name BuoyancyProbe3D
extends Marker3D

## Una celda de flotabilidad. Se cuelga como hija de un [FloatingBody3D].
##
## El empuje sale del VOLUMEN sumergido de la celda, no de un muelle puntual.
## Eso generaliza a formas cualquiera sin afinado manual, y regala una mecanica
## de supervivencia entera: inundar un compartimento es bajar [member flooding]
## de esa celda, y el barco se escora solo hacia donde entra el agua sin que
## haya que escribir nada de logica ni un solo elemento de HUD.

## Volumen de agua que desplaza la celda cuando esta completamente sumergida, en m3.
@export var volume: float = 1.0:
	set(value):
		volume = maxf(value, 0.0001)
		update_gizmos()

## Altura vertical de la celda, en metros. Define la banda en la que la celda
## pasa de seca a totalmente sumergida; suavizar esa transicion es lo que mata
## el jitter cuando la superficie oscila justo a la altura de la sonda.
@export var height: float = 1.0:
	set(value):
		height = maxf(value, 0.01)
		update_gizmos()

## Area de referencia para el arrastre hidrodinamico, en m2.
@export var drag_area: float = 1.0

## 0 = celda seca y con empuje pleno. 1 = celda anegada, sin empuje.
@export_range(0.0, 1.0) var flooding: float = 0.0

## Se llena de agua al quedar sumergida y se vacia al salir. Ponlo en false para
## bidones sellados y flotadores.
@export var floodable: bool = false

## Litros por segundo que entran mientras la celda esta sumergida.
@export var flood_rate: float = 0.0

var submersion: float = 0.0 ## Metros de sonda por debajo de la superficie.
var submerged_fraction: float = 0.0 ## 0..1


## Fraccion sumergida a partir de la profundidad, suavizada en la banda de
## transicion. Sin este suavizado la fuerza salta de golpe y el cuerpo tiembla.
func compute_submerged_fraction(depth: float) -> float:
	return clampf(depth / height, 0.0, 1.0)


func effective_buoyancy() -> float:
	return 1.0 - clampf(flooding, 0.0, 1.0)
