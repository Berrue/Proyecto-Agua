class_name SoporteCania
extends Marker3D

## El soporte de borda de la caña (DISENO §1, paso 3): clavarla libera las
## manos SIN dejar de pescar. La caña clavada sigue su maquina entera —
## espera, toques falsos, mordisco — y este soporte es su cuerpo visible: se
## dobla con el muelle REAL de la caña (`set_doblado` lo alimenta fishing_rod
## con su _bend cada frame), asi que la señal de estacion no puede mentir
## (regla 8). El "!" sobre la boya y el chomp posicional ya son top_level:
## siguen funcionando aunque nadie sostenga la caña.
##
## El precio es la ventana: la picada dura lo que dura, y retomar la caña (E)
## consume parte. Clavarla y alejarse es una APUESTA — oir el chomp, cruzar
## la cubierta y llegar a tiempo es contenido, no friccion.

## Inclinacion de reposo, apuntando fuera de la borda (-Z local del socket).
const BASE_RAD := -0.55

## Cuanto baja la punta por unidad de doblez de la caña. Exagerado a
## proposito: la señal tiene que leerse desde la otra punta de la cubierta.
const DOBLEZ_ESCALA := 0.6

var ocupado: bool = false

@onready var _cana: Node3D = $CanaVisual


func _ready() -> void:
	_cana.visible = false
	_cana.rotation.x = BASE_RAD


func libre() -> bool:
	return not ocupado


func ocupar() -> void:
	ocupado = true
	if _cana != null:
		_cana.visible = true


func liberar() -> void:
	ocupado = false
	if _cana != null:
		_cana.visible = false
		_cana.rotation.x = BASE_RAD


## La caña clavada se dobla hacia el agua con la picada.
func set_doblado(doblez: float) -> void:
	if _cana != null:
		_cana.rotation.x = BASE_RAD - doblez * DOBLEZ_ESCALA


## De donde sale el sedal mientras la caña vive aqui.
func punta() -> Node3D:
	return get_node_or_null(^"CanaVisual/Punta") as Node3D
