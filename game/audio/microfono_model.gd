class_name MicrofonoModel
extends RefCounted

## La aritmética del micrófono: qué aparato se coge y cuánto se le sube.
## PURA — cero nodos, cero `AudioServer` —, igual que el resto de modelos del
## repo, porque es lo único que se puede probar sin una tarjeta de sonido: en
## headless no hay micrófonos, así que si estas reglas vivieran dentro del nodo
## no habría forma de comprobarlas.

## Lo que Godot llama al dispositivo por defecto del sistema. No es un nombre
## que se pueda traducir ni inventar: es la cadena literal que devuelve
## `AudioServer.get_input_device_list()` y la única que acepta al escribirla.
const POR_DEFECTO := "Default"

## Tope de ganancia, en por ciento. 200 % son +6 dB: el doble de amplitud. Más
## que eso no arregla un micrófono flojo, solo sube el ruido de sala con él.
const PCT_MAX := 200.0

## Silencio de verdad. Godot trata -80 dB como apagado en todo el repo
## (`WeatherAudio.DB_SILENT`), y aquí hace falta porque `linear_to_db(0)` es
## -infinito y eso ensucia buses y serializaciones.
const DB_SILENCIO := -80.0


## De por ciento a decibelios. 0 % = mudo, 100 % = tal cual entra, 200 % = +6 dB.
##
## La conversión es logarítmica porque el oído lo es: subir un mando "al doble"
## tiene que sonar al doble, no sumar un número. Una rampa lineal en dB haría
## que la mitad del recorrido del mando no hiciera casi nada.
static func porcentaje_a_db(pct: float) -> float:
	var p: float = clampf(pct, 0.0, PCT_MAX)
	if p <= 0.0:
		return DB_SILENCIO
	return linear_to_db(p / 100.0)


## La inversa, para pintar el mando a partir de lo que ya hay puesto en el bus.
static func db_a_porcentaje(db: float) -> float:
	if db <= DB_SILENCIO:
		return 0.0
	return clampf(db_to_linear(db) * 100.0, 0.0, PCT_MAX)


## Qué dispositivo se abre de verdad, dado lo que hay conectado y lo que el
## jugador eligió la última vez.
##
## Existe por un caso que pasa siempre: el jugador elige sus cascos USB, cierra,
## los desenchufa y vuelve a abrir. Sin este apaño, Godot se queda con un nombre
## que ya no existe y el micrófono no captura NADA, sin un solo error — el
## jugador solo sabe que nadie le oye. Se cae al dispositivo del sistema, que es
## lo que el sistema operativo ya decidió que funciona.
static func elegir_dispositivo(disponibles: PackedStringArray,
		preferido: String) -> String:
	if preferido != "" and disponibles.has(preferido):
		return preferido
	return POR_DEFECTO


## ¿Se perdió el aparato que el jugador había elegido? Para poder AVISARLE en vez
## de dejarle mudo en silencio (regla 8: el fallo se cuenta, no se esconde).
static func se_perdio(disponibles: PackedStringArray, preferido: String) -> bool:
	return preferido != "" and preferido != POR_DEFECTO \
		and not disponibles.has(preferido)


## Pico de la señal, 0..1, a partir de un bloque de muestras capturadas.
##
## Pico y no media: lo que el jugador quiere ver al hablar es que el indicador
## SALTA, y una media de la ventana entera se come justamente los golpes de voz.
static func pico(muestras: PackedVector2Array) -> float:
	var maximo: float = 0.0
	for m in muestras:
		maximo = maxf(maximo, maxf(absf(m.x), absf(m.y)))
	return clampf(maximo, 0.0, 1.0)


## El pico convertido en una barra que se pueda mirar, 0..1.
##
## En dB y no en amplitud: la voz normal de conversación se mueve en amplitudes
## de 0,05-0,2, o sea que una barra lineal se quedaría pegada a la izquierda y
## parecería que el micrófono no coge nada. `suelo_db` es dónde empieza la barra.
static func barra(pico01: float, suelo_db: float = -50.0) -> float:
	if pico01 <= 0.0:
		return 0.0
	var db: float = linear_to_db(pico01)
	return clampf((db - suelo_db) / (0.0 - suelo_db), 0.0, 1.0)
