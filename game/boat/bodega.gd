class_name Bodega
extends AnimatableBody3D

## La celda de bodega: donde la captura deja de ser un rigidbody a la deriva y
## empieza a ser cuota (DISENO.md: "estiba: porteo a la bodega").
##
## Cuenta por PRESENCIA FISICA, no por snap: el pez estibado sigue siendo un
## cuerpo — rueda con la escora, reparte peso, y una ola lo bastante grande
## puede sacarlo por encima de la pared. "El botin esta en riesgo hasta el
## puerto" es literal; las escotillas que cierran la celda son una mejora
## futura, no un candado gratis.
##
## Detalle que hace el sistema honesto sin una linea extra: un pez EN LA MANO
## va con la colision apagada (Portable3D lo congela en capa 0), asi que
## cruzar la celda con el no suma — cuenta cuando lo SUELTAS dentro. Y sacarlo
## de la celda (con la mano o con una ola) descuenta solo, porque el area lo
## ve salir.
##
## Es AnimatableBody3D y no StaticBody3D a proposito: cuelga del barco y se
## mueve con cada ola; el cuerpo cinematico le da velocidad real a los
## contactos, que es lo que deja al pescado DORMIR dentro en vez de vibrar.
##
## Y por eso mismo la escena lleva `sync_to_physics = false`. Con el valor por
## defecto (true) el nodo se reescribe cada paso con la pose que le devuelve el
## servidor de fisica; esa pose va un paso por detras del casco, que en ese
## mismo paso ya se movio, asi que el desfase se cobra sobre la posicion LOCAL
## y la celda se despega del socket para siempre (medido: 30 cm y 1 grado en el
## primer segundo con furia 1.0, y sin recuperarse). Colgando de un RigidBody3D
## la unica verdad valida es el arbol de escena: manda el socket, y el cuerpo
## cinematico sigue reportando su movimiento al solver igual que antes. Lo
## protege `tests/bodega_tests.tscn`.
##
## La tapa de madera lleva un pizarron de tiza: el peso sigue siendo diegetico
## sin convertir una pieza medieval en una pantalla electronica.

signal carga_cambiada(kg: float)

const COLOR_TIZA: Color = Color("ded7bd")
const COLOR_AVISO: Color = Color("d8b46b")
const COLOR_LLENA: Color = Color("c9765f")

@export_group("Carga")
@export_range(1.0, 5000.0, 1.0, "or_greater") var capacidad_kg: float = 250.0:
	set(value):
		capacidad_kg = maxf(value, 1.0)
		if is_node_ready():
			_refrescar()

## Kilos contados dentro de la celda. Es el numero de la cuota fisica.
var kg: float = 0.0

## Cada pez con el peso que se le conto al entrar: si su setup() cambiara
## despues, descontamos lo mismo que sumamos.
var _dentro: Dictionary = {}

var _cartel: Label3D
var _piezas: Label3D
var _marcas_tiza: Array[MeshInstance3D] = []


func _ready() -> void:
	# La celda cuelga del casco y estan unidos rigidamente: cualquier contacto
	# fisico entre ambos es parasito, y un cuerpo cinematico "gana" siempre —
	# con mar gruesa el casco acabaria empujado por su propia bodega. Se
	# excluyen mutuamente, pase lo que pase con las formas.
	var ancestro := get_parent()
	while ancestro != null and not (ancestro is PhysicsBody3D):
		ancestro = ancestro.get_parent()
	if ancestro != null:
		add_collision_exception_with(ancestro as PhysicsBody3D)
		# El GLB conserva una tapa gris de referencia en este socket. Al montar
		# la bodega completa se oculta por nombre (estable entre reexportaciones)
		# para que no quede delante del pizarrón medieval.
		var tapa_anterior := ancestro.find_child(
			"HatchHoldAft", true, false) as GeometryInstance3D
		if tapa_anterior != null:
			tapa_anterior.visible = false

	var zona := $Zona as Area3D
	zona.body_entered.connect(_al_entrar)
	zona.body_exited.connect(_al_salir)

	# El cartel pide su fuente a la fabrica (regla 11) — desde codigo, porque
	# un .tscn no puede llamar a GameTypography. Numero + unidad = Atkinson.
	var titulo := $Tapa/Pizarron/Titulo as Label3D
	_cartel = $Tapa/Pizarron/Cartel as Label3D
	_piezas = $Tapa/Pizarron/Piezas as Label3D
	for indice in range(1, 6):
		var marca := get_node_or_null(
			"Tapa/Pizarron/Marcas/Marca%d" % indice) as MeshInstance3D
		if marca != null:
			_marcas_tiza.append(marca)
	if titulo != null:
		titulo.font = GameTypography.display_hud()
	if _cartel != null:
		_cartel.font = GameTypography.display_brand()
	if _piezas != null:
		_piezas.font = GameTypography.ui_regular()
	_refrescar()


func _al_entrar(body: Node3D) -> void:
	var pez := body as Fish
	if pez == null or _dentro.has(pez):
		return
	var peso: float = pez.peso_kg()
	_dentro[pez] = peso
	kg += peso
	_refrescar()
	carga_cambiada.emit(kg)


func _al_salir(body: Node3D) -> void:
	if not _dentro.has(body):
		return
	kg -= float(_dentro[body])
	_dentro.erase(body)
	# El flotante acumula pelusa; que el vacio vuelva a ser exactamente cero.
	if _dentro.is_empty():
		kg = 0.0
	_refrescar()
	carga_cambiada.emit(kg)


func _refrescar() -> void:
	if _cartel != null:
		_cartel.text = "%s de %s kg" % [_formatear_kg(kg), _formatear_kg(capacidad_kg)]
		var proporcion: float = kg / maxf(capacidad_kg, 1.0)
		if proporcion >= 1.0:
			_cartel.modulate = COLOR_LLENA
		elif proporcion >= 0.75:
			_cartel.modulate = COLOR_AVISO
		else:
			_cartel.modulate = COLOR_TIZA
	if _piezas != null:
		var cantidad: int = _dentro.size()
		_piezas.text = (
			"sin piezas" if cantidad == 0
			else "%d %s" % [cantidad, "pieza" if cantidad == 1 else "piezas"])
		for indice in _marcas_tiza.size():
			_marcas_tiza[indice].visible = indice < cantidad


func cantidad_peces() -> int:
	return _dentro.size()


func esta_llena() -> bool:
	return kg >= capacidad_kg


func _formatear_kg(valor: float) -> String:
	if is_equal_approx(valor, roundf(valor)):
		return "%.0f" % valor
	return "%.1f" % valor
