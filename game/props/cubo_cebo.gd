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
##
## [b]La forma[/b] sale de `tools/build_bait_bucket.py` (balde de duelas y
## herrajes, cebo con sardinas y gusanos). El cebo viene partido en dos piezas
## a proposito, porque el nivel de un balde no es un tapon que se estira:
## [code]BaitFill[/code] es la masa —se escala— y [code]BaitMound[/code] el
## copete —solo se posa encima—. Un solido unico escalado en Y se leia como
## un bote de pintura, y al bajar el nivel sacaba un anillo por la pared.

## Lo que queda dentro, en picadas. Lo rellena el puerto (futuro).
@export var cargas: int = 24
## Que cebo es. Sin tipo asignado, el cubo esta vacio a todos los efectos.
@export var tipo: TipoCebo
## Con cuantas cargas se ve el balde a tope. Solo afecta al dibujo del nivel.
@export var capacidad_visual: int = 24

## Un fondo minimo aunque quede una sola carga: un balde con "nada" dentro se
## lee como vacio y mentiria justo cuando aun te queda un lance.
const NIVEL_MINIMO: float = 0.12
## Cuanto encoge el copete con el balde casi vacio. No es adorno: al bajar, la
## superficie util se estrecha con la duela, y un copete de tamaño fijo
## acabaria atravesando la madera.
const COPETE_MINIMO: float = 0.62

@onready var _visual: Node3D = $Visual

var _relleno: MeshInstance3D
var _monton: Node3D
# Calibre del interior util, leido del propio modelo (los empties BaitGauge*).
# Vive en el GLB y no en constantes de aqui para que retocar el balde en
# Blender no exija acordarse de un segundo juego de numeros en Godot.
var _radio_fondo: float = 0.0
var _radio_boca: float = 0.0
var _altura_fondo: float = 0.0
var _altura_boca: float = 0.0
var _materiales: Array[StandardMaterial3D] = []


func _ready() -> void:
	_cablear_visual()
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


## Resumen para el prompt: que cebo es y cuanto queda.
func resumen() -> String:
	if vacio():
		return "cubo de cebo vacío"
	return "%s  ·  %d" % [tipo.nombre, cargas]


## Fraccion de altura que ocupa el cebo ahora mismo. Publica porque es lo que
## un test puede comprobar sin mirar mallas.
func nivel() -> float:
	if capacidad_visual <= 0:
		return 1.0
	return clampf(float(cargas) / float(capacidad_visual), NIVEL_MINIMO, 1.0)


func _cablear_visual() -> void:
	if _visual == null:
		return
	_relleno = _visual.find_child("BaitFill", true, false) as MeshInstance3D
	_monton = _visual.find_child("BaitMound", true, false) as Node3D
	var fondo := _visual.find_child("BaitGaugeBase", true, false) as Node3D
	var boca := _visual.find_child("BaitGaugeRim", true, false) as Node3D
	if fondo != null and boca != null:
		_radio_fondo = absf(fondo.position.x)
		_altura_fondo = fondo.position.y
		_radio_boca = absf(boca.position.x)
		_altura_boca = boca.position.y

	# Un material por malla y DUPLICADO: dos cubos con cebos distintos no
	# pueden compartir material o el segundo repintaria al primero en silencio.
	_materiales.clear()
	for nodo in [_relleno, _monton]:
		if nodo == null:
			continue
		for hijo in _mallas_de(nodo):
			var base := hijo.get_surface_override_material(0) as StandardMaterial3D
			if base == null and hijo.mesh != null:
				base = hijo.mesh.surface_get_material(0) as StandardMaterial3D
			var propio: StandardMaterial3D = (
				base.duplicate() if base != null else StandardMaterial3D.new()
			)
			# El color del cebo TIÑE el moteado del modelo en vez de taparlo:
			# el GLB trae color por vertice (sardinas oscuras sobre masa clara)
			# y el albedo lo multiplica. Se activa siempre porque una malla sin
			# color por vertice lo da blanco, y multiplicar por blanco no hace
			# nada: asi el tinte funciona igual con o sin moteado.
			propio.vertex_color_use_as_albedo = true
			hijo.set_surface_override_material(0, propio)
			_materiales.append(propio)


func _mallas_de(nodo: Node) -> Array[MeshInstance3D]:
	var mallas: Array[MeshInstance3D] = []
	if nodo is MeshInstance3D:
		mallas.append(nodo as MeshInstance3D)
	for hijo in nodo.find_children("*", "MeshInstance3D", true, false):
		mallas.append(hijo as MeshInstance3D)
	return mallas


## El nivel del balde ES el contador: baja segun lo que queda y se apaga al
## vaciarse. Nadie tiene que abrir un menu para saber si hay cebo a bordo.
func _refrescar() -> void:
	var lleno: bool = not vacio()
	if _relleno != null:
		_relleno.visible = lleno
	if _monton != null:
		_monton.visible = lleno
	if not lleno:
		return

	if tipo != null:
		for material in _materiales:
			material.albedo_color = tipo.color

	var fraccion: float = nivel()
	if _radio_boca <= 0.0:
		return

	# El balde se abre hacia la boca, asi que la masa tambien tiene que
	# estrecharse al bajar o se saldria por la duela. `k` es exactamente el
	# radio interior a la altura de la superficie: el cebo la toca al ras a
	# cualquier nivel, y por debajo va siempre por dentro de la madera.
	var k: float = (_radio_fondo + (_radio_boca - _radio_fondo) * fraccion) / _radio_boca
	if _relleno != null:
		_relleno.scale = Vector3(k, fraccion, k)
	if _monton != null:
		# El copete SE POSA en la superficie: nunca se estira. Un monton de
		# sardinas aplastado en Y es lo que delataba que aquello era una malla.
		_monton.position.y = lerpf(_altura_fondo, _altura_boca, fraccion)
		_monton.scale = Vector3.ONE * lerpf(COPETE_MINIMO, 1.0, fraccion)
