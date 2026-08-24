class_name CamaraMenu
extends Camera3D

## La cámara del menú: un ojo flotando en el mar, sin barco debajo.
##
## Hace DOS cosas y ninguna más: sube y baja con la ola que tenga debajo —se lo
## pregunta a `Ocean`, la única puerta (regla 1)— y deriva muy despacio para que
## el horizonte no sea una foto fija.
##
## [b]Cero rotación por código[/b] (regla 7). En el juego esa regla existe contra
## el mareo; aquí, además, es que el horizonte torcido de un menú es lo primero
## que delata que el fondo es un truco. La inclinación de la cámara se pone UNA
## vez en la escena y no se toca.

## Altura del ojo sobre la superficie, en metros. Un poco más que de pie en
## cubierta: desde aquí se ve la forma de las olas y no solo su cresta.
@export var altura_ojo: float = 2.6

## Cuánto deriva, en m/s. Muy poco a propósito: es la diferencia entre «flota»
## y «alguien está conduciendo esto».
@export var deriva_ms: float = 0.35

## Hacia dónde deriva, en grados (0 = hacia -Z, como mira la cámara por defecto).
@export var rumbo_deg: float = 25.0

## Suavizado del ojo, en 1/s. Copiar la altura de la ola exacta hace que los
## rizos pequeños se lean como temblor de mano; esto los filtra y deja el
## balanceo largo, que es lo que se siente como flotar.
@export var suavizado: float = 2.5

var _ancla := Vector3.ZERO
var _recorrido: float = 0.0
var _altura: float = 0.0


func _ready() -> void:
	_ancla = global_position
	_altura = global_position.y
	current = true


func _process(delta: float) -> void:
	_recorrido += deriva_ms * delta
	var rumbo := deg_to_rad(rumbo_deg)
	var avance := Vector2(sin(rumbo), -cos(rumbo)) * _recorrido
	var x := _ancla.x + avance.x
	var z := _ancla.z + avance.y
	var objetivo := Ocean.get_height(Vector3(x, 0.0, z)) + altura_ojo
	# Suavizado exponencial: independiente de los fotogramas por segundo, que si
	# no el menú flota distinto en cada máquina.
	_altura = lerpf(_altura, objetivo, 1.0 - exp(-suavizado * delta))
	global_position = Vector3(x, _altura, z)
