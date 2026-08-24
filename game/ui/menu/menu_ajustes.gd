class_name MenuAjustes
extends RefCounted

## Lo que el menú de opciones RECUERDA entre sesiones. Hoy, el micrófono.
##
## Existe por algo pequeño y muy molesto: elegir el aparato una vez y que al
## siguiente arranque el juego vuelva a escuchar por la webcam. Un ajuste que no
## sobrevive al cierre no es un ajuste, es un apaño de esta partida.
##
## Es PURO —solo `ConfigFile`, ni un nodo ni un `AudioServer`— para poder
## probarlo en headless, igual que `MicrofonoModel`. Y no duplica sus reglas: si
## el aparato guardado ya no existe, quien decide qué se abre en su lugar sigue
## siendo [method MicrofonoModel.elegir_dispositivo]. Aquí solo se guarda lo que
## el jugador PIDIÓ; lo que el sistema pueda darle es otro problema.

## `user://` y no el proyecto: es del jugador, no del juego, y en una build
## publicada la carpeta del juego es de solo lectura.
const RUTA := "user://ajustes.cfg"

const SECCION := "microfono"
const CLAVE_DISPOSITIVO := "dispositivo"
const CLAVE_VOLUMEN := "volumen_pct"


## Los ajustes de fábrica: el aparato que ya eligió el sistema operativo y la
## señal tal cual entra (100 % = 0 dB).
static func por_defecto() -> Dictionary:
	return {
		CLAVE_DISPOSITIVO: MicrofonoModel.POR_DEFECTO,
		CLAVE_VOLUMEN: 100.0,
	}


## Lee los ajustes. Nunca falla: sin archivo —primer arranque— o con un archivo
## roto a mano devuelve los de fábrica. Un menú que no abre porque el `.cfg`
## tiene una coma de más deja al jugador sin forma de arreglarlo desde dentro.
static func cargar(ruta: String = RUTA) -> Dictionary:
	var ajustes := por_defecto()
	var cfg := ConfigFile.new()
	if cfg.load(ruta) != OK:
		return ajustes
	var aparato: Variant = cfg.get_value(SECCION, CLAVE_DISPOSITIVO,
		ajustes[CLAVE_DISPOSITIVO])
	if aparato is String and not String(aparato).is_empty():
		ajustes[CLAVE_DISPOSITIVO] = String(aparato)
	var volumen: Variant = cfg.get_value(SECCION, CLAVE_VOLUMEN, ajustes[CLAVE_VOLUMEN])
	if volumen is float or volumen is int:
		ajustes[CLAVE_VOLUMEN] = clampf(float(volumen), 0.0, MicrofonoModel.PCT_MAX)
	return ajustes


## Guarda. El volumen se acota AL ESCRIBIR además de al leer: un archivo con
## `volumen_pct = 5000` no puede acabar en la ganancia del bus ni aunque alguien
## lo edite a mano.
static func guardar(dispositivo: String, volumen_pct: float,
		ruta: String = RUTA) -> Error:
	var cfg := ConfigFile.new()
	# Se relee antes de escribir para no perder secciones que otra pantalla
	# guarde en el futuro (vídeo, audio, idioma): este archivo es de todos.
	cfg.load(ruta)
	var aparato := dispositivo if not dispositivo.is_empty() else MicrofonoModel.POR_DEFECTO
	cfg.set_value(SECCION, CLAVE_DISPOSITIVO, aparato)
	cfg.set_value(SECCION, CLAVE_VOLUMEN, clampf(volumen_pct, 0.0, MicrofonoModel.PCT_MAX))
	return cfg.save(ruta)
