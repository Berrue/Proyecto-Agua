class_name VozProximidad
extends AudioStreamPlayer3D

## La boca de un tripulante. Un `AudioStreamPlayer3D` que encoge su alcance
## cuando el mar ruge, según [VozModel] y el .tres de balance.
##
## [b]Todavía no hay voz que meterle.[/b] El transporte de voz es la fase R2
## (two-voip sobre `Net`); esto es la MITAD que no depende de ninguna librería y
## que sí se puede diseñar, oír y ajustar hoy: la mecánica. Cuando entre
## two-voip, lo único que cambia es de dónde sale `stream` — el nodo, el radio y
## el filtro ya estarán probados. Mientras tanto se le puede dar cualquier bucle
## como voz de prueba (ver `tests/voz_demo.tscn`).
##
## Se cuelga del jugador, a la altura de la cabeza. La distancia y la dirección
## las resuelve el motor: aquí solo se mueve el RADIO.

## El bus por el que pasa la voz. Propio y separado del clima porque el filtro
## que se le aplica es distinto: al clima se le filtra por estar bajo cubierta,
## a la voz por el viento contra tus orejas.
const BUS := &"Voz"

@export var balance: VozBalance

## Cada cuántos segundos se recalcula. La furia se mueve despacio y esto no es
## física: a 10 Hz sobra y no se nota, y evita tocar el bus 60 veces por segundo
## desde cada boca de la tripulación.
const INTERVALO := 0.1

var _acum: float = 0.0
var _radio: float = 0.0
var _lpf: AudioEffectLowPassFilter


func _ready() -> void:
	if balance == null:
		balance = VozBalance.new()
	_montar_bus()
	bus = BUS
	# La voz de una persona no rebota como un disparo: sin reverb ni doppler, y
	# con atenuación suave, que lo que tiene que decidir el alcance es el RADIO
	# y no una curva de caída rara.
	attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_aplicar(0.0, 0.0)


## Idempotente, como `WeatherAudio._setup_bus()` y `SfxLibrary._setup_buses()`:
## seis bocas en la escena montan el MISMO bus, no seis.
func _montar_bus() -> void:
	var idx := AudioServer.get_bus_index(BUS)
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, BUS)
		AudioServer.set_bus_send(idx, &"Master")
	for i in AudioServer.get_bus_effect_count(idx):
		var ef := AudioServer.get_bus_effect(idx, i)
		if ef is AudioEffectLowPassFilter:
			_lpf = ef as AudioEffectLowPassFilter
			return
	_lpf = AudioEffectLowPassFilter.new()
	AudioServer.add_bus_effect(idx, _lpf)


func _process(delta: float) -> void:
	_acum += delta
	if _acum < INTERVALO:
		return
	_acum = 0.0
	var ruido: float = WeatherAudio.ruido01() if WeatherAudio != null else 0.0
	var interior: float = WeatherAudio.interior01() if WeatherAudio != null else 0.0
	_aplicar(ruido, interior)


func _aplicar(ruido: float, interior: float) -> void:
	_radio = VozModel.radio_util(ruido, interior,
		balance.radio_calma, balance.radio_temporal, balance.alivio_interior)
	# `max_distance` es el corte duro y `unit_size` la forma de la caída. Se
	# mueven JUNTOS: con solo el corte, la voz sonaría a pleno volumen hasta
	# desaparecer de golpe, que es lo que hace que estas cosas suenen a bug.
	max_distance = _radio
	unit_size = maxf(_radio * 0.25, 0.5)

	# El filtro es del OYENTE, no del hablante: es el viento contra TUS orejas.
	# Por eso vive en el bus y no en el reproductor, y por eso da igual cuántas
	# bocas lo escriban — todas escriben el mismo número.
	if _lpf != null:
		_lpf.cutoff_hz = VozModel.corte_lpf(ruido, interior,
			balance.hz_calma, balance.hz_temporal, balance.alivio_interior)


## El radio útil de ahora mismo, en metros. Para el HUD de debug y los tests.
func radio_util() -> float:
	return _radio
