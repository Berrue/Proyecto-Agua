class_name Portable3D
extends FloatingBody3D

## Un objeto que se puede llevar en las manos: el farol, un pez, mañana el
## bichero o la caja de herramientas. Nacio como generalizacion del farol de
## tormenta (docs/PORTEO.md); la primera regla del sistema es que NO hay
## inventario de bolsillos — lo que llevas esta en tus manos, a la vista de
## todos, y una ola te lo puede arrancar.
##
## Del objeto portado, el mundo solo necesita saber TRES cosas: quien lo lleva
## o de que gancho cuelga, y en que estado esta. Todo lo demas es presentacion
## local. Ese minimo es deliberado: cuando entre la red (F4), el estado se
## replica con dos ids y un enum, y la transferencia de autoridad al agarrar
## se cuelga de tomar()/soltar() sin redibujar nada.
##
## Los verbos congelan la fisica en mano (freeze kinematico + capa 0): sobre
## una cubierta que cabecea, un objeto colgado de un joint "persigue" a la
## camara y se siente de goma. Rigido con la vista = "lo llevo"; con retraso =
## "me persigue". Es la leccion del farol y se hereda tal cual.

signal tomado(portador: Node3D)
signal soltado()
signal colgado(gancho: Node3D)
signal encinturado()

enum Estado { SUELTO, EN_MANO, COLGADO, EN_CINTURON }

@export_group("Porteo")
## Cuantas manos ocupa llevarlo. Con 1 segui saltando y usando la otra mano;
## con 2 caminas (lento) pero no saltas ni podes lanzar la caña. El deficit de
## manos ES el diseño (DISENO.md §2): este numero es la moneda.
@export_range(1, 2) var manos: int = 1

## Nombre que muestra el prompt del HUD ("Coger farol de tormenta").
@export var nombre: String = "Objeto"

## ¿Se puede colgar de un gancho? El farol si; un pez no tiene asa.
@export var colgable: bool = false

## ¿Cabe en el cinturon? SOLO objetos chicos declarados (radio, llave del
## motor). Jamas peces ni herramientas grandes: el cinturon es calidad de
## vida, no un escape de la tesis del deficit de manos (docs/PORTEO.md).
@export var en_cinturon: bool = false

## Como queda orientado en la mano. El bichero se lleva como una pica (punta
## adelante), no como un poste clavado en la nariz.
@export var agarre_rotacion_deg := Vector3.ZERO

## Colgado, cuanto baja hasta que el asa toca el gancho. Sin esto queda
## clavado por el centro y parece pegado con cola.
@export var colgado_offset := Vector3(0.0, -0.12, 0.0)

var estado: Estado = Estado.SUELTO
var portador: Node3D = null
var gancho: Node3D = null

## Hueco del cinturon donde quedo guardado (-1 = en ningun cinturon). Hace
## falta saberlo: el Portador elige el marker por el TAMAÑO de su lista y su
## poda borra desde el medio, asi que sin este dato dos objetos pueden acabar
## compartiendo marker — y en red hay que poder reconstruir en QUE hueco esta.
var hueco_cinturon: int = -1

## Identidad de red del cuerpo (-1 = no censado). Lo escribe el censo de `Net`;
## la tabla de verdad vive alli, esto es solo la vuelta rapida nodo -> id.
var id_red: int = -1

var _capa_original: int = 1
var _mascara_original: int = 1


func _ready() -> void:
	super()
	_capa_original = collision_layer
	_mascara_original = collision_mask


## Peso que leen el HUD y la lentitud del porteo. Por defecto la masa fisica;
## el pez lo pisa con sus kg de especie (que son ademas su valor de cuota).
func peso_kg() -> float:
	return mass


# =============================================================================
#  Los verbos
# =============================================================================

## Lo coge un jugador. `agarre` es el Marker3D de su viewmodel: el objeto se
## cuelga de ahi y sigue la camara sin un frame de retraso, que es la
## diferencia entre "lo llevo" y "me persigue".
func tomar(nuevo_portador: Node3D, agarre: Node3D) -> bool:
	if estado == Estado.EN_MANO:
		return false
	_desenganchar()
	portador = nuevo_portador
	estado = Estado.EN_MANO
	_congelar(true)
	reparent(agarre, false)
	transform = Transform3D(
		Basis.from_euler(agarre_rotacion_deg * (PI / 180.0)), Vector3.ZERO)
	visible = true # por si venia del cinturon
	_tras_cambio()
	tomado.emit(nuevo_portador)
	return true


## Al cinturon: colgado del cuerpo, sin ocupar manos. Sigue siendo VISIBLE
## (principio 1: lo que llevas se ve — en tu sombra, y mañana en tu copia de
## red); lo que se apaga es su fisica, igual que en la mano.
func guardar_en(cinto: Node3D, hueco: int = -1) -> bool:
	if not en_cinturon or estado == Estado.EN_CINTURON:
		return false
	_desenganchar()
	estado = Estado.EN_CINTURON
	hueco_cinturon = hueco
	_congelar(true)
	reparent(cinto, false)
	transform = Transform3D.IDENTITY
	_tras_cambio()
	encinturado.emit()
	return true


## Lo cuelga de un gancho fijo. Recuperas la mano y la zona se queda ocupada:
## dejarlo ahi es una DECISION con coste, no un bolsillo.
func colgar_en(nuevo_gancho: Node3D) -> bool:
	if nuevo_gancho == null or not colgable:
		return false
	# El gancho se consulta y se ocupa DENTRO del verbo. Antes lo hacia el
	# llamador (`Portador._colgar`) y este era el unico de los cuatro verbos
	# que ademas no llamaba `_desenganchar()`: por el camino del Portador no se
	# notaba, pero por un RPC directo dejaba el gancho anterior ocupado para
	# siempre y permitia colgar DOS objetos del mismo sitio.
	if nuevo_gancho.has_method(&"libre") and not bool(nuevo_gancho.call(&"libre")):
		return false
	_desenganchar()
	gancho = nuevo_gancho
	estado = Estado.COLGADO
	_congelar(true)
	reparent(nuevo_gancho, false)
	transform = Transform3D(Basis(), colgado_offset)
	if nuevo_gancho.has_method(&"ocupar"):
		nuevo_gancho.call(&"ocupar")
	_tras_cambio()
	colgado.emit(nuevo_gancho)
	return true


## Lo suelta al mundo con la velocidad de quien lo soltaba (o la del lanzamiento:
## lanzar ES soltar con mas velocidad). En cubierta el gesto es dejarlo, pero si
## te lo arranca una ola mientras corres sale despedido con la inercia que ya
## tenia. Sin esto se queda flotando en el sitio y parece que el mundo hace
## trampas.
## `quien`, si se pasa, EXIGE ser el portador actual. Sin esa guarda el verbo
## deja que cualquiera suelte el objeto de cualquiera — invisible mientras el
## unico camino es tu propio Portador, fatal en cuanto un RPC llama al verbo.
func soltar(en: Node, velocidad := Vector3.ZERO, quien: Node3D = null) -> bool:
	if quien != null and portador != quien:
		return false
	var mundo := global_transform
	_desenganchar()
	estado = Estado.SUELTO
	reparent(en, false)
	global_transform = mundo
	_congelar(false)
	linear_velocity = velocidad
	_tras_cambio()
	soltado.emit()
	return true


# =============================================================================
#  Interno
# =============================================================================

## Hook para las subclases que reaccionan al cambio de estado (el farol mueve
## aqui sus sombras). La base no necesita hacer nada.
func _tras_cambio() -> void:
	pass


## Congelado de PORTEO: lo llevas vos (o un compañero), asi que ademas de
## apagarle la fisica hay que sacarlo de las capas de colision para que no
## empuje a nadie ni cuente en ningun area.
func _congelar(on: bool) -> void:
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = on
	# Apagar el _physics_process del FloatingBody3D mientras esta en la mano no
	# es una optimizacion: es lo que impide que el empuje del oceano siga
	# acumulandose sobre un cuerpo congelado y lo dispare al soltarlo.
	set_physics_process(not on)
	collision_layer = 0 if on else _capa_original
	collision_mask = 0 if on else _mascara_original
	# En los DOS sentidos: al congelar, para no guardarse una fuerza vieja
	# dentro; al descongelar, porque el objeto acaba de aparecer en otro sitio
	# y su historia de agua ya no significa nada (ver el porque completo en
	# `FloatingBody3D.olvidar_historial_agua`).
	olvidar_historial_agua()
	if not on:
		angular_velocity = Vector3.ZERO


## Congelado de RED: el cuerpo es del host y aca solo se dibuja lo que el host
## dice. Misma disciplina que el barco replicado de R0, con UNA diferencia que
## no es un detalle: la capa y la mascara se CONSERVAN.
##
## Un cuerpo replicado sigue siendo un cuerpo del mundo — la Zona de la bodega
## mira la capa 1, asi que con capa 0 la cuota del cliente marcaria cero
## mientras el pizarron del host marca sesenta kilos, y no habria un solo
## error en ninguna de las dos pantallas.
func congelar_por_red(on: bool) -> void:
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = on
	set_physics_process(not on)
	olvidar_historial_agua()
	if not on:
		angular_velocity = Vector3.ZERO
		linear_velocity = Vector3.ZERO


func _desenganchar() -> void:
	if gancho != null and gancho.has_method(&"liberar"):
		gancho.call(&"liberar")
	gancho = null
	portador = null
	hueco_cinturon = -1
