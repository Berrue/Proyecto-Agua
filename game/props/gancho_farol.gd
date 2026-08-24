class_name GanchoFarol
extends Marker3D

## Un gancho fijo donde colgar el farol. Cubierta, bodega, mamparo de maquinas.
##
## Los ganchos son la mitad del diseño del farol: sin ellos el objeto obliga a
## elegir entre luz y manos todo el rato, que cansa. Con ellos, iluminar una
## zona es una DECISION con coste (dejas el farol ahi, y ahi se queda hasta que
## alguien vuelva a por el).
##
## El balanceo no es decoracion: un farol colgado que oscila con el cabeceo
## mueve las sombras de toda la cubierta, y ese movimiento es la lectura
## periferica mas barata que tenemos del estado del mar. Sale de la aceleracion
## real del gancho, asi que no puede mentir.

## Cuanto se inclina el farol por cada g de aceleracion lateral, en radianes.
const INCLINACION_POR_G := 0.55

## Rigidez y amortiguacion del pendulo. ~1,1 Hz es el ritmo de un farol de
## barco de verdad: lento, pesado, nada de gelatina.
const RIGIDEZ := 48.0
const AMORTIGUACION := 3.4

## Tope de inclinacion. Un farol colgado no da la vuelta por muy mal que se
## ponga: el asa lo impide, y verlo girar 90 grados parece un bug.
const TOPE_RAD := 0.42

var ocupado: bool = false

var _ang := Vector2.ZERO
var _vel := Vector2.ZERO
var _pos_previa := Vector3.ZERO
var _vel_previa := Vector3.ZERO
var _iniciado: bool = false


## ¿Puede este gancho aceptar el farol ahora mismo?
func libre() -> bool:
	return not ocupado


func ocupar() -> void:
	ocupado = true


func liberar() -> void:
	ocupado = false


func _physics_process(delta: float) -> void:
	if delta <= 0.0:
		return
	var pos := global_position
	if not _iniciado:
		_pos_previa = pos
		_iniciado = true
		return

	var vel := (pos - _pos_previa) / delta
	var acel := (vel - _vel_previa) / delta
	_pos_previa = pos
	_vel_previa = vel

	if not ocupado:
		return

	# La aceleracion del gancho, leida en el espacio del propio gancho: lo que
	# empuja al farol es el barco moviendose bajo el, no el mundo.
	var local := global_transform.basis.inverse() * acel
	var objetivo := Vector2(
		clampf(-local.x / 9.81, -3.0, 3.0),
		clampf(-local.z / 9.81, -3.0, 3.0)
	) * INCLINACION_POR_G

	# Muelle amortiguado en dos ejes. Sin el tope, un slam de tier 3 tira el
	# farol contra el techo.
	_vel += (objetivo - _ang) * RIGIDEZ * delta
	_vel -= _vel * minf(AMORTIGUACION * delta, 1.0)
	_ang += _vel * delta
	_ang.x = clampf(_ang.x, -TOPE_RAD, TOPE_RAD)
	_ang.y = clampf(_ang.y, -TOPE_RAD, TOPE_RAD)

	for hijo: Node in get_children():
		var n := hijo as Node3D
		if n != null:
			n.rotation = Vector3(_ang.y, 0.0, _ang.x)
