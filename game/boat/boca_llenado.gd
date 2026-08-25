class_name BocaLlenado
extends Marker3D

## La boca de llenado del tanque: donde se vuelca el bidón.
##
## Es el otro extremo del sistema de nafta. El tanque vive en [Gobierno] y el
## combustible en [BidonNafta]; esto es el sitio físico donde uno pasa al otro,
## y por eso repostar es una acción con lugar y con duración en vez de un botón
## de menú.
##
## [b]A ritmo visible, y se puede parar.[/b] Volcar un bidón entero lleva unos
## segundos ([member MotorNaftaBalance.ritmo_repostaje_l_s]), y durante ese rato
## el que reposta tiene las manos ocupadas y está quieto en la popa. Eso es lo
## que convierte "voy a echar nafta" en una decisión de CUÁNDO: hacerlo en la
## calma es gratis y hacerlo con mar hecha es apostar. Se puede cortar a la
## mitad —`E` otra vez— porque un gesto de cinco segundos que no se puede
## abortar es un lockout, y un lockout es el "me robó" que prohíbe la regla 8.
##
## La nafta no se fabrica: cada tick se le pide al bidón lo que de verdad tiene
## ([method BidonNafta.sacar]) y se le entrega al tanque lo que de verdad cabe
## ([method Gobierno.repostar]), así que el total a bordo se conserva por
## construcción.

## Empezó a caer nafta. Para el sonido del chorro y el gesto de volcar.
signal vertido_empezado()
## Dejó de caer, y por qué: "lleno", "vacío", "lo cortaron" o "se alejó".
signal vertido_terminado(causa: String)
## Litros que acaban de entrar en el tanque este tick. Para la aguja y el HUD.
signal vertido(litros: float)

## A qué distancia se corta el chorro solo. Si el que vierte se va, el bidón se
## va con él: seguir llenando desde tres metros sería nafta de la nada.
const ALCANCE := 2.2

var _gobierno: Gobierno
var _bidon: BidonNafta = null


func _ready() -> void:
	_gobierno = _buscar_gobierno()
	if _gobierno == null:
		push_error("BocaLlenado no encontró el Gobierno del barco.")
		set_physics_process(false)


## La boca cuelga de un socket, así que el barco queda varios padres arriba.
func _buscar_gobierno() -> Gobierno:
	var n := get_parent()
	while n != null:
		var b := n as FloatingBody3D
		if b != null:
			return b.get_node_or_null(^"Gobierno") as Gobierno
		n = n.get_parent()
	return null


func vertiendo() -> bool:
	return _bidon != null


## ¿Tiene sentido ofrecer el gesto? Ni con el bidón seco ni con el tanque lleno:
## un prompt que invita a algo que no va a pasar es feedback que miente.
func puede_verter(bidon: BidonNafta) -> bool:
	if bidon == null or _gobierno == null or _gobierno.motor == null:
		return false
	if bidon.vacio():
		return false
	return _gobierno.litros < _gobierno.motor.tanque_l


func empezar(bidon: BidonNafta) -> bool:
	if not puede_verter(bidon):
		return false
	_bidon = bidon
	vertido_empezado.emit()
	return true


func parar(causa: String = "lo cortaron") -> void:
	if _bidon == null:
		return
	_bidon = null
	vertido_terminado.emit(causa)


func _physics_process(delta: float) -> void:
	if _bidon == null or _gobierno == null or _gobierno.motor == null:
		return
	if not is_instance_valid(_bidon):
		parar("se perdió el bidón")
		return
	# Si el que vierte se va, el chorro se corta solo.
	if _bidon.global_position.distance_to(global_position) > ALCANCE:
		parar("se alejó")
		return

	var m := _gobierno.motor
	# Cuánto cabría este tick, y cuánto hay de verdad para darlo. Se pregunta
	# primero al tanque y después al bidón, y se mueve el MÍNIMO de los dos.
	var cabe := MotorModel.paso_repostaje(_gobierno.litros, m.tanque_l,
			_bidon.litros, m.ritmo_repostaje_l_s, delta)
	if cabe <= 0.0:
		parar("lleno" if _gobierno.litros >= m.tanque_l else "vacío")
		return
	var pasan := _bidon.sacar(cabe)
	_gobierno.litros += pasan
	vertido.emit(pasan)
	if _bidon.vacio():
		parar("vacío")
	elif _gobierno.litros >= m.tanque_l:
		parar("lleno")
