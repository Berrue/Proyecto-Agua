class_name TipoCebo
extends Resource

## Un cebo. Se edita como recurso desde el editor, igual que los tiers de caña
## y de tsunami (los .tres viven en resources/cebos/).
##
## [b]Que compra el cebo:[/b] TIEMPO y ATENCION del pez, jamas peces que el mar
## no da. Son sus dos ejes:
##
## - [member espera_factor] recorta la espera entre lanzamiento y picada. Es el
##   multiplicador de piezas por salida que el soporte de borda NO era: con el
##   cebo bueno caben casi el doble de ciclos en el mismo rato.
## - [member sesgo] inclina el sorteo hacia el pez GORDO de la banda que ya te
##   toca. No sube la banda: en calma no aparece un atun por mucho cebo que
##   eches. La tesis del juego (el pez caro vive donde el mar es peor) no se
##   compra en la lonja — igual que la telegrafia del sonar no compra justicia.
##
## El cebo se consume por PICADA, no por lanzamiento: el pez se lo come tanto
## si lo subes como si te lo roba. Perder un pez cebado escuece doble, y eso
## esta bien: es la unica forma de que gastar cebo sea una decision.

## Nombre corto: el prompt del cubo y el HUD de debug.
@export var nombre: String = "Cebo"

@export_group("Lo que compra")
## Multiplica la espera hasta la picada. 1.0 = sin efecto; 0.5 = la mitad.
@export_range(0.1, 1.0) var espera_factor: float = 1.0
## Cuanto inclina el sorteo hacia las especies de tu banda alta. 0 = nada;
## 1.0 = las de tu furia doblan su peso frente a las triviales.
@export_range(0.0, 3.0) var sesgo: float = 0.0

@export_group("Pinta")
## Color del contenido del cubo: el cebo se distingue de un vistazo en cubierta.
@export var color: Color = Color(0.55, 0.45, 0.3)


## Resumen legible para el prompt y los logs de playtest.
func resumen() -> String:
	var partes := PackedStringArray()
	if espera_factor < 1.0:
		partes.append("espera -%d%%" % int(round((1.0 - espera_factor) * 100.0)))
	if sesgo > 0.0:
		partes.append("atrae al grande")
	return "  ·  ".join(partes) if not partes.is_empty() else "sin efecto"
