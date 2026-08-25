class_name StretchHose
extends Node3D

## Manguera flexible y desplegable para la bomba manual.
##
## Este componente no conoce al jugador, la bomba ni el barco. Trabaja siempre
## en su propio espacio local: el ancla queda fija al modulo y el agarre se
## convierte desde coordenadas globales cada tick. Por eso una rotacion o un
## traslado brusco del barco no obliga al solver a perseguir cuerpos fisicos.
##
## La manguera tampoco es una goma infinita. Al tirar de ella se va pagando
## longitud hasta [member longitud_maxima]; superado ese limite, el cabezal se
## queda en el punto alcanzable y emite [signal max_length_reached]. La futura
## integracion con el jugador puede usar esa señal para frenar el movimiento o
## mostrar el tiron sin acoplar esas decisiones a esta presentacion.

signal tomada(agarre: Node3D)
signal soltada()
signal tension_changed(tension: float)
signal max_length_reached()

const CANTIDAD_PUNTOS: int = 24
const LADOS_TUBO: int = 8
const LADOS_CUERDA: int = 4
const EPSILON: float = 0.00001
const UMBRAL_TENSION_SIGNAL: float = 0.02

## Cuanto se tiene que mover un punto para merecer un redibujado, al cuadrado.
## 0,25 mm: por debajo no se ve, y una cuerda en reposo nunca se queda del todo
## quieta por el ultimo bit del Verlet.
const UMBRAL_REDIBUJO_SQ: float = 0.00000625

@export_group("Nodos")
## Punto fijo donde la manguera sale de la bomba.
@export var anchor_path: NodePath = ^"Anchor"
## Postura estacionaria opcional del cabezal. Si falta, se genera una S corta
## delante del ancla, sin componente vertical que pueda atravesar la cubierta.
@export var rest_path: NodePath = ^"PickupRest"
## MeshInstance3D que recibe el ImmediateMesh generado en runtime.
@export var hose_mesh_path: NodePath = ^"HoseMesh"
## Area3D agarrable del cabezal. Su transform sigue el extremo de la manguera.
@export var pickup_area_path: NodePath = ^"PickupHead"
## Visual del cabezal. Puede ser hijo del Area3D o un nodo hermano.
@export var pickup_visual_path: NodePath = ^"PickupHead/Visual"

@export_group("Manguera")
@export_range(0.5, 6.0, 0.05, "or_greater") var longitud_inicial: float = 1.8
@export_range(1.0, 12.0, 0.1, "or_greater") var longitud_maxima: float = 6.0
@export_range(0.01, 0.12, 0.005, "or_greater") var radio: float = 0.045
@export_range(0.5, 12.0, 0.1, "or_greater") var velocidad_despliegue: float = 6.0
## Reserva visible para que la manguera no quede como una cuerda perfectamente
## tensa mientras el jugador aun esta dentro de su alcance normal.
@export_range(0.0, 0.75, 0.01) var holgura_objetivo: float = 0.18
## Direccion de respaldo si no hay PickupRest en la escena.
@export var direccion_reposo: Vector3 = Vector3.FORWARD
@export var material_manguera: Material
## Cordón de cáñamo que impide que el cuero colapse al aspirar. Se genera como
## una sucesión de aros: además de reforzar la lectura medieval, evita que el
## tramo dinámico parezca una manguera de goma contemporánea.
@export var material_refuerzo: Material
## Cada cuantos metros va un anillo de cañamo. OJO, es el numero que MAS pesa de
## toda la manguera: cada anillo es un toro completo (8 x 4 secciones = 192
## vertices), asi que a 0,15 m eran ~40 anillos y 7.680 vertices por redibujado —
## el 87 % del coste de dibujar. A 0,30 m se ven igual de bien y cuestan la mitad.
@export_range(0.06, 0.40, 0.01) var separacion_refuerzo: float = 0.30
@export_range(0.001, 0.012, 0.001) var radio_refuerzo: float = 0.004

@export_group("Simulacion")
@export_range(0.0, 30.0, 0.1) var gravedad: float = 9.8
@export_range(0.8, 1.0, 0.001) var amortiguacion: float = 0.975
@export_range(2, 16, 1) var iteraciones_restriccion: int = 8
## Límite local de caída bajo el extremo más bajo. Hasta que existan
## colisiones por segmento, conserva la curva visible sobre cubierta sin
## impedir que el colador baje a una celda inundada situada por debajo.
@export_range(0.0, 1.0, 0.01) var comba_maxima_bajo_extremos: float = 0.18

var _anchor: Node3D
var _rest: Node3D
var _hose_mesh_instance: MeshInstance3D
var _pickup_area: Area3D
var _pickup_visual: Node3D
var _immediate_mesh: ImmediateMesh
## La forma con la que se dibujo por ultima vez, para saber si hace falta rehacer
## la malla. Vale su memoria: 24 vectores contra reconstruir mil vertices.
var _puntos_dibujados: PackedVector3Array = PackedVector3Array()

## Senos y cosenos de los angulos del tubo y de la cuerda. Son CONSTANTES —
## TAU * i / LADOS— y se estaban recalculando una vez por vertice: unas 53.000
## llamadas trigonometricas por reconstruccion. Se calculan al arrancar.
var _cos_tubo: PackedFloat32Array = PackedFloat32Array()
var _sin_tubo: PackedFloat32Array = PackedFloat32Array()
var _cos_cuerda: PackedFloat32Array = PackedFloat32Array()
var _sin_cuerda: PackedFloat32Array = PackedFloat32Array()
## Los ejes de cada anillo y sus normales, reutilizados entre reconstrucciones en
## vez de pedir memoria nueva cada vez.
var _laterales: PackedVector3Array = PackedVector3Array()
var _verticales: PackedVector3Array = PackedVector3Array()
var _normales_anillo: PackedVector3Array = PackedVector3Array()
var _radiales_toro: PackedVector3Array = PackedVector3Array()
var _forma_sucia: bool = true

var _agarre: Node3D
var _puntos := PackedVector3Array()
var _puntos_previos := PackedVector3Array()
var _longitud_desplegada: float = 1.8
var _tension: float = 0.0
var _ultima_tension_emitida: float = -1.0
var _maximo_notificado: bool = false
var _inicializada: bool = false
## Sin colisiones por segmento, un extremo libre caeria para siempre. Durante
## esta fase se inmoviliza donde quedo; la caida y apoyo en suelo se habilitaran
## al integrar la manguera con las colisiones reales del barco.
var _extremo_fijo_suelto: bool = true
var _posicion_extremo_fijo: Vector3 = Vector3.ZERO


func _ready() -> void:
	_anchor = get_node_or_null(anchor_path) as Node3D
	_rest = get_node_or_null(rest_path) as Node3D
	_hose_mesh_instance = get_node_or_null(hose_mesh_path) as MeshInstance3D
	_pickup_area = get_node_or_null(pickup_area_path) as Area3D
	_pickup_visual = get_node_or_null(pickup_visual_path) as Node3D

	if _anchor == null:
		push_warning("StretchHose sin Anchor: se usara el origen local como ancla.")
	if _hose_mesh_instance == null:
		push_warning("StretchHose sin HoseMesh: la simulacion funcionara sin tuberia visible.")
	else:
		_immediate_mesh = ImmediateMesh.new()
		_hose_mesh_instance.mesh = _immediate_mesh
	if _pickup_area == null:
		push_warning("StretchHose sin PickupHead Area3D: no habra volumen agarrable.")
	if _pickup_visual == null:
		push_warning("StretchHose sin visual de cabezal: solo se sincronizara el Area3D.")

	reset_hose()


func _physics_process(delta: float) -> void:
	_simular_paso(delta)


## El dibujado va aqui y no en la fisica: se redibuja como mucho una vez por
## fotograma, y solo cuando la cuerda se ha movido de verdad. Con la manguera
## recogida y quieta esto no hace absolutamente nada, que es lo correcto — antes
## reconstruia la malla entera 120 veces por segundo aunque nadie la tocara.
func _process(_delta: float) -> void:
	if not _forma_sucia:
		return
	_forma_sucia = false
	_actualizar_presentacion()


## ¿Se ha movido la cuerda lo bastante como para valer un redibujado?
##
## El umbral es de un cuarto de milimetro: por debajo de eso el movimiento no se
## ve ni de cerca, y una cuerda en reposo tiembla eternamente por el ultimo bit
## del Verlet. Sin este corte, "solo si se movio" no ahorraria nada.
func _marcar_forma_si_cambio() -> void:
	if _forma_sucia:
		return
	if _puntos_dibujados.size() != _puntos.size():
		_forma_sucia = true
		_puntos_dibujados = _puntos.duplicate()
		return
	for i in _puntos.size():
		if _puntos[i].distance_squared_to(_puntos_dibujados[i]) > UMBRAL_REDIBUJO_SQ:
			_forma_sucia = true
			_puntos_dibujados = _puntos.duplicate()
			return


# =============================================================================
#  API publica e independiente
# =============================================================================

## Toma el extremo usando cualquier Node3D como objetivo. Devuelve false si el
## agarre no es valido o si otra mano ya tiene esta manguera.
func tomar(agarre: Node3D) -> bool:
	if agarre == null or not is_instance_valid(agarre) or esta_tomada():
		return false
	_agarre = agarre
	_extremo_fijo_suelto = false
	_maximo_notificado = false
	_actualizar_objetivo_tomado(0.0)
	tomada.emit(agarre)
	return true


## Libera el extremo y lo deja fijo donde quedo. Es una decision temporal y
## deliberada: sin colision por segmentos, simular caida lo mandaria a traves
## de la cubierta indefinidamente. La futura integracion puede reemplazar este
## apoyo por consultas de suelo sin cambiar la API de tomar/soltar.
func soltar() -> void:
	if not esta_tomada():
		return
	_posicion_extremo_fijo = _puntos[_puntos.size() - 1]
	_extremo_fijo_suelto = true
	_agarre = null
	_maximo_notificado = false
	_actualizar_tension(0.0, true)
	soltada.emit()


func esta_tomada() -> bool:
	return _agarre != null and is_instance_valid(_agarre)


## Posicion real alcanzada por el cabezal, no la posicion pedida por una mano
## que se encuentre mas alla de la longitud maxima.
func get_tip_global_position() -> Vector3:
	if _puntos.is_empty():
		return global_position
	return to_global(_puntos[_puntos.size() - 1])


## Fuerza la longitud pagada dentro de los limites de diseño. Acortar no
## teletransporta los puntos: las restricciones recogen la manguera durante los
## siguientes pasos y mantienen una transicion estable.
func set_deployed_length(nueva_longitud: float) -> void:
	var minimo: float = _longitud_minima_valida()
	_longitud_desplegada = clampf(nueva_longitud, minimo, _longitud_maxima_valida())
	if _longitud_desplegada < _longitud_maxima_valida() - EPSILON:
		_maximo_notificado = false


func get_deployed_length() -> float:
	return _longitud_desplegada


func get_max_length() -> float:
	return _longitud_maxima_valida()


## Devuelve la manguera a una S estable desde el ancla hasta PickupRest. La S
## consume la longitud inicial aun cuando ambos marcadores esten cerca: no hay
## un tramo recto oculto ni un cabezal enviado por debajo de la cubierta.
func reset_hose() -> void:
	_longitud_desplegada = clampf(
		longitud_inicial,
		_longitud_minima_valida(),
		_longitud_maxima_valida()
	)
	var origen: Vector3 = _get_anchor_local_position()
	var destino: Vector3 = _get_rest_local_position(origen)
	var distancia_marcadores: float = origen.distance_to(destino)
	if distancia_marcadores > _longitud_maxima_valida():
		push_warning("PickupRest supera la longitud maxima; se limita al alcance de la manguera.")
		destino = origen + origen.direction_to(destino) * _longitud_maxima_valida()
		distancia_marcadores = _longitud_maxima_valida()
	_longitud_desplegada = maxf(_longitud_desplegada, distancia_marcadores)
	_puntos = _crear_s_de_reposo(origen, destino, _longitud_desplegada)
	_puntos_previos.resize(CANTIDAD_PUNTOS)
	for indice: int in CANTIDAD_PUNTOS:
		_puntos_previos[indice] = _puntos[indice]
	_agarre = null
	_extremo_fijo_suelto = true
	_posicion_extremo_fijo = destino
	_tension = 0.0
	_ultima_tension_emitida = -1.0
	_maximo_notificado = false
	_inicializada = true
	_actualizar_tension(0.0, true)
	_actualizar_presentacion()


# =============================================================================
#  Simulacion Verlet/PBD en el marco local del modulo
# =============================================================================

func _simular_paso(delta: float) -> void:
	if not _inicializada or delta <= 0.0:
		return
	if _agarre != null and not is_instance_valid(_agarre):
		_posicion_extremo_fijo = _puntos[_puntos.size() - 1]
		_extremo_fijo_suelto = true
		_agarre = null
		_maximo_notificado = false
		soltada.emit()

	var objetivo_fijo: Vector3 = _posicion_extremo_fijo
	var fijar_extremo: bool = esta_tomada() or _extremo_fijo_suelto
	if esta_tomada():
		objetivo_fijo = _actualizar_objetivo_tomado(delta)

	var gravedad_local: Vector3 = _gravedad_local()
	var aceleracion_delta: Vector3 = gravedad_local * delta * delta
	var ultimo: int = CANTIDAD_PUNTOS - 1
	var extremo_antes_de_fijar: Vector3 = _puntos[ultimo]
	for indice: int in range(1, CANTIDAD_PUNTOS):
		if fijar_extremo and indice == ultimo:
			continue
		var actual: Vector3 = _puntos[indice]
		var velocidad: Vector3 = (actual - _puntos_previos[indice]) * amortiguacion
		_puntos_previos[indice] = actual
		_puntos[indice] = actual + velocidad + aceleracion_delta

	var ancla_local: Vector3 = _get_anchor_local_position()
	_puntos[0] = ancla_local
	_puntos_previos[0] = ancla_local
	if fijar_extremo:
		# Conservar la posicion fijada del tick anterior hace que, al soltar,
		# el cabezal herede el ultimo movimiento de la mano en vez de frenarse.
		_puntos_previos[ultimo] = extremo_antes_de_fijar
		_puntos[ultimo] = objetivo_fijo

	for _iteracion: int in iteraciones_restriccion:
		_resolver_restricciones(ancla_local, objetivo_fijo, fijar_extremo)

	# AQUI NO SE DIBUJA. Resolver la cuerda es gratis (medido: 0,0 ms); lo que
	# cuesta es reconstruir su malla vertice a vertice desde GDScript, y hacerlo
	# a 120 Hz se comia MEDIO SEGUNDO DE CPU POR SEGUNDO DE JUEGO — el juego caia
	# a 7 fps en cuanto alguien agarraba el colador. La forma de una manguera es
	# presentacion: se redibuja una vez por FRAME, y solo si de verdad se movio.
	_marcar_forma_si_cambio()


## Calcula el objetivo alcanzable y paga manguera al tirar. La posicion pedida
## se limita al radio desplegado; nunca se estiran segmentos para falsear largo.
func _actualizar_objetivo_tomado(delta: float) -> Vector3:
	var ancla_local: Vector3 = _get_anchor_local_position()
	var objetivo_local: Vector3 = to_local(_agarre.global_position)
	var desde_ancla: Vector3 = objetivo_local - ancla_local
	var distancia: float = desde_ancla.length()
	var longitud_deseada: float = minf(
		_longitud_maxima_valida(),
		maxf(_longitud_desplegada, distancia + holgura_objetivo)
	)
	if delta <= 0.0:
		_longitud_desplegada = longitud_deseada
	else:
		_longitud_desplegada = move_toward(
			_longitud_desplegada,
			longitud_deseada,
			velocidad_despliegue * delta
		)

	var alcance: float = minf(distancia, _longitud_desplegada)
	var objetivo_alcanzable: Vector3 = objetivo_local
	if distancia > EPSILON and distancia > alcance:
		objetivo_alcanzable = ancla_local + desde_ancla * (alcance / distancia)

	var tramo_tension: float = maxf(_longitud_desplegada * 0.15, 0.05)
	var inicio_tension: float = _longitud_desplegada - tramo_tension
	var tension_nueva: float = clampf((distancia - inicio_tension) / tramo_tension, 0.0, 1.0)
	_actualizar_tension(tension_nueva)

	var excedio_maximo: bool = distancia >= _longitud_maxima_valida() - EPSILON
	if excedio_maximo and not _maximo_notificado:
		_maximo_notificado = true
		max_length_reached.emit()
	elif distancia < _longitud_maxima_valida() - maxf(holgura_objetivo, 0.05):
		_maximo_notificado = false
	return objetivo_alcanzable


func _resolver_restricciones(
	ancla_local: Vector3,
	objetivo_fijo: Vector3,
	fijar_extremo: bool
) -> void:
	var ultimo: int = CANTIDAD_PUNTOS - 1
	var separacion: float = _longitud_segmento()
	_puntos[0] = ancla_local
	if fijar_extremo:
		_puntos[ultimo] = objetivo_fijo

	# La colisión completa de cada segmento queda para la integración con el
	# barco. Este apoyo provisional evita que la gravedad esconda toda la
	# manguera bajo una cubierta plana. El límite sigue al extremo más bajo: si
	# el colador entra en una sentina inferior, la curva puede acompañarlo.
	var extremo_local: Vector3 = objetivo_fijo if fijar_extremo else _puntos[ultimo]
	var limite_inferior: float = minf(ancla_local.y, extremo_local.y) \
		- comba_maxima_bajo_extremos
	for indice: int in range(1, ultimo):
		if _puntos[indice].y < limite_inferior:
			_puntos[indice].y = limite_inferior
			_puntos_previos[indice].y = maxf(
				_puntos_previos[indice].y,
				limite_inferior
			)

	for indice: int in range(CANTIDAD_PUNTOS - 1):
		var siguiente: int = indice + 1
		var delta_segmento: Vector3 = _puntos[siguiente] - _puntos[indice]
		var distancia: float = delta_segmento.length()
		if distancia <= EPSILON:
			continue
		var correccion: Vector3 = delta_segmento * ((distancia - separacion) / distancia)
		var primero_fijo: bool = indice == 0
		var segundo_fijo: bool = fijar_extremo and siguiente == ultimo
		if primero_fijo and not segundo_fijo:
			_puntos[siguiente] -= correccion
		elif segundo_fijo and not primero_fijo:
			_puntos[indice] += correccion
		elif not primero_fijo and not segundo_fijo:
			_puntos[indice] += correccion * 0.5
			_puntos[siguiente] -= correccion * 0.5

	_puntos[0] = ancla_local
	if fijar_extremo:
		_puntos[ultimo] = objetivo_fijo


func _actualizar_tension(nueva_tension: float, forzar: bool = false) -> void:
	_tension = clampf(nueva_tension, 0.0, 1.0)
	if forzar or absf(_tension - _ultima_tension_emitida) >= UMBRAL_TENSION_SIGNAL:
		_ultima_tension_emitida = _tension
		tension_changed.emit(_tension)


func _gravedad_local() -> Vector3:
	# Se elimina escala antes de invertir: la escala visual de un modulo no debe
	# alterar direccion ni intensidad de la gravedad.
	var base_rotacion: Basis = global_basis.orthonormalized()
	return base_rotacion.inverse() * (Vector3.DOWN * gravedad)


func _get_anchor_local_position() -> Vector3:
	if _anchor == null or not is_instance_valid(_anchor):
		return Vector3.ZERO
	return to_local(_anchor.global_position)


func _get_rest_local_position(origen: Vector3) -> Vector3:
	if _rest != null and is_instance_valid(_rest):
		return to_local(_rest.global_position)
	var direccion_plana := Vector3(direccion_reposo.x, 0.0, direccion_reposo.z)
	if direccion_plana.length_squared() <= EPSILON:
		direccion_plana = Vector3.FORWARD
	# El fallback es deliberadamente compacto: la S absorbe el largo sobrante.
	var separacion: float = minf(_longitud_desplegada * 0.35, 0.65)
	return origen + direccion_plana.normalized() * separacion


## Construye una sinusoide lateral y la remuestrea a distancia casi uniforme.
## La busqueda de amplitud usa el largo de la polilinea final (no una formula
## continua), de modo que los mismos 24 puntos consumen el metraje solicitado.
func _crear_s_de_reposo(
	origen: Vector3,
	destino: Vector3,
	longitud_objetivo: float
) -> PackedVector3Array:
	var distancia_recta: float = origen.distance_to(destino)
	if distancia_recta >= longitud_objetivo - EPSILON:
		return _linea_remuestreada(origen, destino)

	var eje: Vector3 = origen.direction_to(destino)
	if eje.length_squared() <= EPSILON:
		eje = Vector3.FORWARD
	var lateral: Vector3 = Vector3.UP.cross(eje)
	if lateral.length_squared() <= EPSILON:
		lateral = Vector3.RIGHT
	lateral = lateral.normalized()

	var amplitud_baja: float = 0.0
	var amplitud_alta: float = maxf(longitud_objetivo * 0.25, 0.05)
	var candidata: PackedVector3Array = _muestrear_s(origen, destino, lateral, amplitud_alta)
	for _expansion: int in 8:
		if _longitud_de_puntos(candidata) >= longitud_objetivo:
			break
		amplitud_alta *= 2.0
		candidata = _muestrear_s(origen, destino, lateral, amplitud_alta)

	for _busqueda: int in 18:
		var amplitud_media: float = (amplitud_baja + amplitud_alta) * 0.5
		candidata = _muestrear_s(origen, destino, lateral, amplitud_media)
		if _longitud_de_puntos(candidata) < longitud_objetivo:
			amplitud_baja = amplitud_media
		else:
			amplitud_alta = amplitud_media
	return _muestrear_s(origen, destino, lateral, amplitud_alta)


func _linea_remuestreada(origen: Vector3, destino: Vector3) -> PackedVector3Array:
	var resultado := PackedVector3Array()
	resultado.resize(CANTIDAD_PUNTOS)
	for indice: int in CANTIDAD_PUNTOS:
		resultado[indice] = origen.lerp(destino, float(indice) / float(CANTIDAD_PUNTOS - 1))
	return resultado


func _muestrear_s(
	origen: Vector3,
	destino: Vector3,
	lateral: Vector3,
	amplitud: float
) -> PackedVector3Array:
	const MUESTRAS_DENSAS: int = 193
	var densos := PackedVector3Array()
	var acumulados := PackedFloat32Array()
	densos.resize(MUESTRAS_DENSAS)
	acumulados.resize(MUESTRAS_DENSAS)
	var largo_total: float = 0.0
	for indice: int in MUESTRAS_DENSAS:
		var t: float = float(indice) / float(MUESTRAS_DENSAS - 1)
		var punto: Vector3 = origen.lerp(destino, t) + lateral * sin(TAU * t) * amplitud
		densos[indice] = punto
		if indice > 0:
			largo_total += densos[indice - 1].distance_to(punto)
		acumulados[indice] = largo_total

	var resultado := PackedVector3Array()
	resultado.resize(CANTIDAD_PUNTOS)
	resultado[0] = origen
	resultado[CANTIDAD_PUNTOS - 1] = destino
	var indice_denso: int = 1
	for indice: int in range(1, CANTIDAD_PUNTOS - 1):
		var distancia_buscada: float = largo_total * float(indice) / float(CANTIDAD_PUNTOS - 1)
		while indice_denso < MUESTRAS_DENSAS - 1 and acumulados[indice_denso] < distancia_buscada:
			indice_denso += 1
		var previo: int = maxi(indice_denso - 1, 0)
		var tramo: float = acumulados[indice_denso] - acumulados[previo]
		var peso: float = 0.0
		if tramo > EPSILON:
			peso = (distancia_buscada - acumulados[previo]) / tramo
		resultado[indice] = densos[previo].lerp(densos[indice_denso], peso)
	return resultado


func _longitud_de_puntos(puntos: PackedVector3Array) -> float:
	var total: float = 0.0
	for indice: int in range(puntos.size() - 1):
		total += puntos[indice].distance_to(puntos[indice + 1])
	return total


func _longitud_minima_valida() -> float:
	return maxf(0.05 * float(CANTIDAD_PUNTOS - 1), 0.25)


func _longitud_maxima_valida() -> float:
	return maxf(longitud_maxima, _longitud_minima_valida())


func _longitud_segmento() -> float:
	return _longitud_desplegada / float(CANTIDAD_PUNTOS - 1)


# =============================================================================
#  Tuberia y cabezal
# =============================================================================

func _actualizar_presentacion() -> void:
	_actualizar_tuberia()
	_actualizar_cabezal()


## Las tablas de angulos, una vez en la vida del nodo.
func _asegurar_tablas() -> void:
	if not _cos_tubo.is_empty():
		return
	_cos_tubo.resize(LADOS_TUBO)
	_sin_tubo.resize(LADOS_TUBO)
	for i in LADOS_TUBO:
		var a: float = TAU * float(i) / float(LADOS_TUBO)
		_cos_tubo[i] = cos(a)
		_sin_tubo[i] = sin(a)
	_cos_cuerda.resize(LADOS_CUERDA)
	_sin_cuerda.resize(LADOS_CUERDA)
	for i in LADOS_CUERDA:
		var a: float = TAU * float(i) / float(LADOS_CUERDA)
		_cos_cuerda[i] = cos(a)
		_sin_cuerda[i] = sin(a)
	_laterales.resize(CANTIDAD_PUNTOS)
	_verticales.resize(CANTIDAD_PUNTOS)
	_normales_anillo.resize(CANTIDAD_PUNTOS * LADOS_TUBO)
	_radiales_toro.resize(LADOS_TUBO)


func _actualizar_tuberia() -> void:
	if _immediate_mesh == null or _puntos.size() != CANTIDAD_PUNTOS:
		return
	_immediate_mesh.clear_surfaces()
	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material_manguera)

	_asegurar_tablas()
	var laterales := _laterales
	var verticales := _verticales
	var lateral_previo := Vector3.ZERO
	for indice: int in CANTIDAD_PUNTOS:
		var tangente: Vector3 = _tangente_en(indice)
		var lateral: Vector3
		if indice == 0:
			var referencia: Vector3 = Vector3.UP
			if absf(tangente.dot(referencia)) > 0.92:
				referencia = Vector3.RIGHT
			lateral = tangente.cross(referencia).normalized()
		else:
			# Transporte paralelo sencillo: proyectar el eje anterior evita que
			# cada anillo cambie de orientacion arbitrariamente en una curva.
			lateral = lateral_previo - tangente * lateral_previo.dot(tangente)
			if lateral.length_squared() <= EPSILON:
				lateral = tangente.cross(Vector3.UP).normalized()
			else:
				lateral = lateral.normalized()
		var vertical: Vector3 = lateral.cross(tangente).normalized()
		laterales[indice] = lateral
		verticales[indice] = vertical
		lateral_previo = lateral

	# La normal de cada (anillo, lado) se calculaba CUATRO veces —una por cada
	# quad que la toca—, o sea 736 llamadas con su coseno, su seno y su raiz para
	# 192 normales distintas. Se calculan una vez y se leen por indice: mismo
	# resultado exacto, cuatro veces menos trabajo.
	for anillo: int in CANTIDAD_PUNTOS:
		var lat: Vector3 = laterales[anillo]
		var ver: Vector3 = verticales[anillo]
		var base: int = anillo * LADOS_TUBO
		for lado: int in LADOS_TUBO:
			_normales_anillo[base + lado] = (
				lat * _cos_tubo[lado] + ver * _sin_tubo[lado]).normalized()

	for anillo: int in range(CANTIDAD_PUNTOS - 1):
		var u0: float = float(anillo) / float(CANTIDAD_PUNTOS - 1)
		var u1: float = float(anillo + 1) / float(CANTIDAD_PUNTOS - 1)
		var base0: int = anillo * LADOS_TUBO
		var base1: int = base0 + LADOS_TUBO
		for lado: int in LADOS_TUBO:
			var siguiente_lado: int = (lado + 1) % LADOS_TUBO
			var normal00: Vector3 = _normales_anillo[base0 + lado]
			var normal01: Vector3 = _normales_anillo[base0 + siguiente_lado]
			var normal10: Vector3 = _normales_anillo[base1 + lado]
			var normal11: Vector3 = _normales_anillo[base1 + siguiente_lado]
			var p00: Vector3 = _puntos[anillo] + normal00 * radio
			var p01: Vector3 = _puntos[anillo] + normal01 * radio
			var p10: Vector3 = _puntos[anillo + 1] + normal10 * radio
			var p11: Vector3 = _puntos[anillo + 1] + normal11 * radio
			var v0: float = float(lado) / float(LADOS_TUBO)
			var v1: float = float(lado + 1) / float(LADOS_TUBO)

			# Godot usa winding horario para el frente de triangulos 3D.
			_emitir_vertice(p00, normal00, Vector2(u0, v0))
			_emitir_vertice(p10, normal10, Vector2(u1, v0))
			_emitir_vertice(p11, normal11, Vector2(u1, v1))
			_emitir_vertice(p00, normal00, Vector2(u0, v0))
			_emitir_vertice(p11, normal11, Vector2(u1, v1))
			_emitir_vertice(p01, normal01, Vector2(u0, v1))

	_immediate_mesh.surface_end()
	_agregar_refuerzos_de_canamo(laterales)


func _agregar_refuerzos_de_canamo(laterales: PackedVector3Array) -> void:
	if material_refuerzo == null or separacion_refuerzo <= EPSILON \
			or radio_refuerzo <= EPSILON:
		return
	var cantidad: int = maxi(1, int(round(_longitud_desplegada / separacion_refuerzo)))
	var paso: float = _longitud_desplegada / float(cantidad)
	var largo_segmento: float = maxf(_longitud_segmento(), EPSILON)
	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material_refuerzo)

	for banda: int in cantidad:
		var distancia: float = (float(banda) + 0.5) * paso
		var tramo_decimal: float = distancia / largo_segmento
		var tramo: int = mini(int(floor(tramo_decimal)), CANTIDAD_PUNTOS - 2)
		var peso: float = clampf(tramo_decimal - float(tramo), 0.0, 1.0)
		var centro: Vector3 = _puntos[tramo].lerp(_puntos[tramo + 1], peso)
		var tangente: Vector3 = (_puntos[tramo + 1] - _puntos[tramo]).normalized()
		if tangente.length_squared() <= EPSILON:
			tangente = _tangente_en(tramo)
		var lateral: Vector3 = laterales[tramo].lerp(laterales[tramo + 1], peso)
		lateral -= tangente * lateral.dot(tangente)
		if lateral.length_squared() <= EPSILON:
			lateral = tangente.cross(Vector3.UP)
			if lateral.length_squared() <= EPSILON:
				lateral = tangente.cross(Vector3.RIGHT)
		lateral = lateral.normalized()
		var vertical: Vector3 = lateral.cross(tangente).normalized()
		_emitir_toro_de_canamo(centro, tangente, lateral, vertical, banda, cantidad)

	_immediate_mesh.surface_end()


func _emitir_toro_de_canamo(
	centro: Vector3,
	tangente: Vector3,
	lateral: Vector3,
	vertical: Vector3,
	banda: int,
	cantidad: int,
) -> void:
	# Los ocho radiales del anillo, una vez: antes se recalculaban DENTRO de cada
	# vertice, seis veces por cada uno de los 192 vertices del toro.
	for lado: int in LADOS_TUBO:
		_radiales_toro[lado] = (
			lateral * _cos_tubo[lado] + vertical * _sin_tubo[lado]).normalized()

	for lado: int in LADOS_TUBO:
		var lado_siguiente: int = (lado + 1) % LADOS_TUBO
		var radial_0: Vector3 = _radiales_toro[lado]
		var radial_1: Vector3 = _radiales_toro[lado_siguiente]
		var u0: float = (float(banda) + float(lado) / float(LADOS_TUBO)) \
			/ float(cantidad)
		var u1: float = (float(banda) + float(lado + 1) / float(LADOS_TUBO)) \
			/ float(cantidad)
		for seccion: int in LADOS_CUERDA:
			var seccion_siguiente: int = (seccion + 1) % LADOS_CUERDA
			var v0: float = float(seccion) / float(LADOS_CUERDA)
			var v1: float = float(seccion + 1) / float(LADOS_CUERDA)

			_emitir_vertice_toro(centro, tangente, radial_0, seccion, Vector2(u0, v0))
			_emitir_vertice_toro(centro, tangente, radial_1, seccion, Vector2(u1, v0))
			_emitir_vertice_toro(centro, tangente, radial_1, seccion_siguiente, Vector2(u1, v1))
			_emitir_vertice_toro(centro, tangente, radial_0, seccion, Vector2(u0, v0))
			_emitir_vertice_toro(centro, tangente, radial_1, seccion_siguiente, Vector2(u1, v1))
			_emitir_vertice_toro(centro, tangente, radial_0, seccion_siguiente, Vector2(u0, v1))


## Un vertice del toro de cañamo. Recibe el radial YA calculado y el INDICE de
## la seccion en vez del angulo: antes calculaba el coseno y el seno del mismo
## angulo DOS VECES —una para la normal y otra para la posicion— mas el radial
## entero, por cada uno de los 192 vertices de cada anillo.
func _emitir_vertice_toro(
	centro: Vector3,
	tangente: Vector3,
	radial: Vector3,
	seccion: int,
	uv: Vector2,
) -> void:
	var c: float = _cos_cuerda[seccion]
	var sn: float = _sin_cuerda[seccion]
	var normal: Vector3 = (radial * c + tangente * sn).normalized()
	var radio_central: float = radio + radio_refuerzo * 0.65
	var posicion: Vector3 = centro \
		+ radial * (radio_central + radio_refuerzo * c) \
		+ tangente * (radio_refuerzo * sn)
	_emitir_vertice(posicion, normal, uv)


func _emitir_vertice(posicion: Vector3, normal: Vector3, uv: Vector2) -> void:
	_immediate_mesh.surface_set_normal(normal)
	_immediate_mesh.surface_set_uv(uv)
	_immediate_mesh.surface_add_vertex(posicion)


func _normal_anillo(lateral: Vector3, vertical: Vector3, angulo: float) -> Vector3:
	return (lateral * cos(angulo) + vertical * sin(angulo)).normalized()


func _tangente_en(indice: int) -> Vector3:
	var tangente: Vector3
	if indice <= 0:
		tangente = _puntos[1] - _puntos[0]
	elif indice >= CANTIDAD_PUNTOS - 1:
		tangente = _puntos[CANTIDAD_PUNTOS - 1] - _puntos[CANTIDAD_PUNTOS - 2]
	else:
		tangente = _puntos[indice + 1] - _puntos[indice - 1]
	if tangente.length_squared() <= EPSILON:
		return Vector3.FORWARD
	return tangente.normalized()


func _actualizar_cabezal() -> void:
	if _puntos.size() != CANTIDAD_PUNTOS:
		return
	var ultimo: int = CANTIDAD_PUNTOS - 1
	var tangente: Vector3 = _tangente_en(ultimo)
	var arriba: Vector3 = Vector3.UP - tangente * Vector3.UP.dot(tangente)
	if arriba.length_squared() <= EPSILON:
		arriba = Vector3.RIGHT
	arriba = arriba.normalized()
	var derecha: Vector3 = arriba.cross(tangente).normalized()
	var transform_local := Transform3D(Basis(derecha, arriba, tangente).orthonormalized(), _puntos[ultimo])
	var transform_mundo: Transform3D = global_transform * transform_local

	if _pickup_area != null:
		_pickup_area.global_transform = transform_mundo
	# Si el visual ya es descendiente del Area3D, hereda su movimiento y se
	# conserva cualquier offset de modelado que tenga en la escena.
	if _pickup_visual != null and (
		_pickup_area == null or not _pickup_area.is_ancestor_of(_pickup_visual)
	):
		_pickup_visual.global_transform = transform_mundo


# =============================================================================
#  Instrumentacion tipada para tests headless
# =============================================================================

## Ejecuta un paso determinista sin depender del SceneTree.
func debug_step(delta: float) -> void:
	_simular_paso(delta)


func debug_get_points_local() -> PackedVector3Array:
	return _puntos.duplicate()


func debug_get_anchor_local_position() -> Vector3:
	return _get_anchor_local_position()


func debug_get_target_local_position() -> Vector3:
	if not esta_tomada():
		return _puntos[_puntos.size() - 1] if not _puntos.is_empty() else Vector3.ZERO
	return to_local(_agarre.global_position)


func debug_get_deployed_length() -> float:
	return _longitud_desplegada


func debug_get_polyline_length() -> float:
	var total: float = 0.0
	for indice: int in range(_puntos.size() - 1):
		total += _puntos[indice].distance_to(_puntos[indice + 1])
	return total


func debug_get_max_segment_error() -> float:
	var error_maximo: float = 0.0
	var separacion: float = _longitud_segmento()
	for indice: int in range(_puntos.size() - 1):
		var largo: float = _puntos[indice].distance_to(_puntos[indice + 1])
		error_maximo = maxf(error_maximo, absf(largo - separacion))
	return error_maximo


func debug_get_tension() -> float:
	return _tension


func debug_is_at_max_length() -> bool:
	return _maximo_notificado


func debug_get_mesh_surface_count() -> int:
	return _immediate_mesh.get_surface_count() if _immediate_mesh != null else 0
