extends Node

## Autoload `Microfono`. Qué aparato está escuchando y con cuánta ganancia.
##
## Es la mitad de ENTRADA de la voz por proximidad: [VozProximidad] decide a qué
## distancia te oyen, esto decide si el juego te oye a TI. Son problemas
## distintos y fallan por motivos distintos — el 90 % de los "no me oye nadie"
## de cualquier juego con voz es un micrófono mal elegido, no la red.
##
## [b]Se puede usar antes de que exista la voz en red.[/b] No depende de Steam ni
## de two-voip: abre el micro, lo amplifica y deja mirar el nivel. Cuando entre
## el transporte de voz, lo que hará es leer del MISMO bus.
##
## [b]No te oyes a ti mismo.[/b] El bus está silenciado hacia Master a propósito:
## enrutar el micrófono a los altavoces es la receta exacta del acoplamiento, y
## con dos jugadores sin cascos en la misma habitación se convierte en un
## chillido. Para probar el micro está [member monitor], que lo abre a sabiendas.
##
## La aritmética vive en [MicrofonoModel], puro y testeable: aquí no hay
## micrófonos que probar en headless.

signal dispositivo_cambiado(nombre: String)
signal volumen_cambiado(pct: float)
## El aparato elegido dejó de existir (cascos desenchufados) y se cayó al del
## sistema. Se avisa en vez de dejar al jugador mudo sin saberlo (regla 8).
signal dispositivo_perdido(anterior: String)

const BUS := &"Microfono"

## Cada cuánto se relee la lista de aparatos, en segundos. Enumerar dispositivos
## de audio toca el sistema operativo y no es gratis; enchufar unos cascos no es
## algo que pase sesenta veces por segundo.
const INTERVALO_SONDEO := 2.0

var _idx: int = -1
var _amplify: AudioEffectAmplify
var _capture: AudioEffectCapture
var _player: AudioStreamPlayer
var _pct: float = 100.0
var _pico: float = 0.0
var _acum: float = 0.0
var _preferido: String = MicrofonoModel.POR_DEFECTO


func _ready() -> void:
	_montar_bus()
	_montar_captura()
	set_process(true)


## Idempotente, como el resto de buses del repo (`WeatherAudio._setup_bus`).
func _montar_bus() -> void:
	_idx = AudioServer.get_bus_index(BUS)
	if _idx == -1:
		AudioServer.add_bus()
		_idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_idx, BUS)
		AudioServer.set_bus_send(_idx, &"Master")
	# Silenciado hacia Master: el micrófono se MIDE, no se escucha. Sin esto, el
	# primer arranque del juego con altavoces es un pitido.
	AudioServer.set_bus_mute(_idx, true)

	for i in AudioServer.get_bus_effect_count(_idx):
		var ef := AudioServer.get_bus_effect(_idx, i)
		if ef is AudioEffectAmplify:
			_amplify = ef as AudioEffectAmplify
		elif ef is AudioEffectCapture:
			_capture = ef as AudioEffectCapture
	# El orden importa: primero se amplifica y DESPUÉS se captura, para que el
	# nivel que se ve en pantalla sea el que va a salir por el cable. Un medidor
	# que enseña la señal antes de la ganancia miente sobre lo que oirán los
	# demás, que es justo lo que se está ajustando.
	if _amplify == null:
		_amplify = AudioEffectAmplify.new()
		AudioServer.add_bus_effect(_idx, _amplify, 0)
	if _capture == null:
		_capture = AudioEffectCapture.new()
		AudioServer.add_bus_effect(_idx, _capture)
	_aplicar_volumen()


## El micrófono en sí. `AudioStreamMicrophone` solo captura si el proyecto tiene
## `audio/driver/enable_input`; sin eso Godot ni abre el aparato y esto se queda
## mudo sin error ninguno.
func _montar_captura() -> void:
	if not bool(ProjectSettings.get_setting("audio/driver/enable_input", false)):
		push_warning("Microfono: 'audio/driver/enable_input' esta apagado; no se va a capturar nada.")
		return
	_player = AudioStreamPlayer.new()
	_player.name = "EntradaMicrofono"
	_player.stream = AudioStreamMicrophone.new()
	_player.bus = BUS
	_player.autoplay = true
	add_child(_player)
	_player.play()


# =============================================================================
#  Qué aparato escucha
# =============================================================================

## Los micrófonos que ve el sistema. El primero es siempre "Default".
func dispositivos() -> PackedStringArray:
	return AudioServer.get_input_device_list()


## El que está abierto AHORA, tal y como lo llama el sistema.
func dispositivo() -> String:
	return AudioServer.input_device


## Elige aparato. Si el nombre no existe se cae al del sistema en vez de dejar el
## micro mudo, y devuelve lo que de verdad quedó abierto.
func usar_dispositivo(nombre: String) -> String:
	_preferido = nombre
	var elegido := MicrofonoModel.elegir_dispositivo(dispositivos(), nombre)
	if AudioServer.input_device != elegido:
		AudioServer.input_device = elegido
		dispositivo_cambiado.emit(elegido)
	return elegido


# =============================================================================
#  Cuánto se le sube
# =============================================================================

## Ganancia de entrada en por ciento, 0..200. 100 % es la señal tal cual entra.
var volumen_pct: float:
	get:
		return _pct
	set(value):
		var v: float = clampf(value, 0.0, MicrofonoModel.PCT_MAX)
		if is_equal_approx(v, _pct):
			return
		_pct = v
		_aplicar_volumen()
		volumen_cambiado.emit(_pct)


func _aplicar_volumen() -> void:
	if _amplify != null:
		_amplify.volume_db = MicrofonoModel.porcentaje_a_db(_pct)


# =============================================================================
#  Que se vea que coge algo
# =============================================================================

## Nivel de entrada 0..1, listo para pintar una barra. Es lo que convierte esto
## en un DETECTOR y no en una lista: sin ver el indicador saltar al hablar, el
## jugador no tiene forma de saber cuál de los cuatro "Micrófono (Realtek)" es
## el suyo.
func nivel01() -> float:
	return MicrofonoModel.barra(_pico)


## El pico crudo 0..1, sin curva. Para los tests.
func pico() -> float:
	return _pico


func _process(delta: float) -> void:
	if _capture != null:
		var disponibles := _capture.get_frames_available()
		if disponibles > 0:
			# Se vacía SIEMPRE el buffer, aunque nadie mire el nivel: un
			# `AudioEffectCapture` que no se lee se llena y empieza a descartar
			# con warnings en consola cada frame.
			var nuevo := MicrofonoModel.pico(_capture.get_buffer(disponibles))
			_pico = maxf(nuevo, _pico)
	# Caída suave: un pico que se quedara clavado no dejaría ver el ritmo de la
	# voz, y uno que cayera de golpe parpadearía.
	_pico = maxf(_pico - delta * 1.5, 0.0)

	_acum += delta
	if _acum < INTERVALO_SONDEO:
		return
	_acum = 0.0
	_vigilar_desconexion()


## ¿Se llevaron el micrófono? Pasa constantemente con cascos USB y bluetooth.
func _vigilar_desconexion() -> void:
	var lista := dispositivos()
	if not MicrofonoModel.se_perdio(lista, _preferido):
		return
	var anterior := _preferido
	usar_dispositivo(MicrofonoModel.POR_DEFECTO)
	dispositivo_perdido.emit(anterior)
