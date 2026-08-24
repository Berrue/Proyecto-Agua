class_name CuboCebo
extends Marker3D

## El cubo de cebo de cubierta (PESCA.md paso 3). Es la pieza VISIBLE que
## exige la regla del arbol de mejoras: nada de "+20% de pesca" en un menu —
## el cebo es un balde con un nivel que baja a la vista de toda la tripulacion.
##
## Es MOBILIARIO, no una mejora: el cubo siempre esta a bordo y lo que se
## compra en puerto es lo que lleva dentro (el sink de DISENO §3). Por eso
## `cargas` es lo unico que la lonja tocara el dia que exista.
##
## El ciclo que crea: cebas (E), pescas ~6 picadas, vuelves a por mas. Ese
## viaje es el mismo gesto que la bodega — trabajo de cubierta con ritmo, no
## una tarea por lance. Y si el cubo se vacia no pasa nada grave: la caña
## pesca a pelo, solo que la espera vuelve a ser larga.

## Lo que queda dentro, en picadas. Lo rellena el puerto (futuro).
@export var cargas: int = 24
## Que cebo es. Sin tipo asignado, el cubo esta vacio a todos los efectos.
@export var tipo: TipoCebo
## Con cuantas cargas se ve el balde a tope. Solo afecta al dibujo del nivel.
@export var capacidad_visual: int = 24

@onready var _contenido: MeshInstance3D = $Contenido

var _material: StandardMaterial3D
var _escala_llena: float = 1.0
var _centro_lleno: float = 0.0


func _ready() -> void:
	if _contenido != null:
		# La escena es la unica fuente de verdad del balde lleno: se captura
		# antes de tocar nada para que _refrescar sea reentrante.
		_escala_llena = maxf(_contenido.scale.y, 0.001)
		_centro_lleno = _contenido.position.y
		var base := _contenido.get_surface_override_material(0) as StandardMaterial3D
		# Duplicado: dos cubos con cebos distintos no pueden compartir material
		# o el segundo repintaria al primero en silencio.
		_material = base.duplicate() if base != null else StandardMaterial3D.new()
		_contenido.set_surface_override_material(0, _material)
	_refrescar()


func vacio() -> bool:
	return cargas <= 0 or tipo == null


## Cebar la caña que se asome. Devuelve true solo si se movio cebo de verdad,
## para que un E fallido caiga al porteo normal (igual que el soporte).
func cebar(rod: FishingRod) -> bool:
	if rod == null or vacio():
		return false
	var cogidas := rod.cebar(tipo, cargas)
	if cogidas <= 0:
		return false
	cargas -= cogidas
	_refrescar()
	return true


## El nivel del balde ES el contador: baja segun lo que queda y se apaga al
## vaciarse. Nadie tiene que abrir un menu para saber si hay cebo a bordo.
func _refrescar() -> void:
	if _contenido == null:
		return
	if vacio():
		_contenido.visible = false
		return
	_contenido.visible = true
	if _material != null and tipo != null:
		_material.albedo_color = tipo.color
	# Un fondo minimo aunque quede una sola carga: un balde con "nada" dentro
	# se lee como vacio y mentiria justo cuando aun te queda un lance.
	var lleno: float = clampf(float(cargas) / float(maxi(capacidad_visual, 1)), 0.12, 1.0)
	_contenido.scale.y = _escala_llena * lleno
	# La malla mengua hacia ABAJO (el cebo se posa en el fondo), no hacia el
	# centro: si encogiera centrada, el cebo levitaria dentro del balde.
	_contenido.position.y = _centro_lleno - _escala_llena * (1.0 - lleno) * 0.5


## Resumen para el prompt: que cebo es y cuanto queda.
func resumen() -> String:
	if vacio():
		return "cubo de cebo vacío"
	return "%s  ·  %d" % [tipo.nombre, cargas]
