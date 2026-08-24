class_name NetTripulacion
extends RefCounted

## Quién está a bordo y con cuánto retardo: la lista que sale con TAB.
##
## Pura y testeable, como el resto de lo que decide algo en `game/net/`
## (`NetMath`, `NetPorteo`, `NetLag`). Aquí vive el formato de la fila, el orden
## en que se pintan, el saneado de los nombres, la lectura del retardo y el
## códec del paquete — todo lo que se puede equivocar sin que salte un error.
##
## [b]La tabla la mide el HOST y la reparte.[/b] No es una decisión de estilo:
## un cliente solo conoce SU retardo contra el host (es el único con quien tiene
## un socket abierto), así que el ping de los demás no lo puede saber ni
## aproximar. El host los tiene todos de primera mano.

## El peer del host en Godot es siempre el 1.
const HOST := 1

## Sin red no hay peer que valga; la fila propia se numera así para que
## `es_host` sea falso y nadie confunda «solo» con «hosteando».
const SIN_RED := 0

## Tope del nombre. Corto a propósito: la lista se lee de un vistazo mientras el
## barco se hunde, no es un perfil.
const NOMBRE_MAX := 16
const NOMBRE_POR_DEFECTO := "Marinero"

## Retardo que todavía no se sabe (o que no aplica, como el del host consigo
## mismo). Negativo y no cero: cero es un ping buenísimo, no una ausencia.
const MS_DESCONOCIDO := -1

## Umbrales de lectura, en ms de ida y vuelta. No son de balance: por debajo de
## 60 ms el tira-y-afloja de la caña se siente local, y pasados ~140 el agarre
## pesimista del porteo empieza a notarse como «se me adelantó».
const MS_BUENO := 60
const MS_REGULAR := 140

enum Calidad { BUENA, REGULAR, MALA, DESCONOCIDA }


## Un nombre que se pueda pintar: sin bordes, sin saltos de línea y acotado.
## Llega por la red desde otra máquina, así que se sanea SIEMPRE al recibirlo:
## un nombre de 4 kB o con un salto de línea desmonta la lista entera.
static func limpiar_nombre(bruto: String) -> String:
	var limpio := bruto.replace("\n", " ").replace("\r", " ").replace("\t", " ")
	limpio = limpio.strip_edges()
	while limpio.contains("  "):
		limpio = limpio.replace("  ", " ")
	if limpio.is_empty():
		return NOMBRE_POR_DEFECTO
	return limpio.substr(0, NOMBRE_MAX)


static func fila(peer: int, nombre: String, ms: int, soy_yo: bool) -> Dictionary:
	return {
		"peer": peer,
		"nombre": limpiar_nombre(nombre),
		"ms": ms,
		"es_host": peer == HOST,
		"soy_yo": soy_yo,
	}


## El host primero y el resto por nombre. El orden tiene que ser ESTABLE entre
## refrescos: una lista que se reordena sola cada segundo, mientras los pings
## bailan, no se puede leer.
static func ordenar(filas: Array) -> Array:
	var copia := filas.duplicate()
	copia.sort_custom(_antes_que)
	return copia


static func _antes_que(a: Dictionary, b: Dictionary) -> bool:
	if bool(a["es_host"]) != bool(b["es_host"]):
		return bool(a["es_host"])
	var na := String(a["nombre"])
	var nb := String(b["nombre"])
	if na != nb:
		return na.naturalnocasecmp_to(nb) < 0
	# Dos tripulantes con el mismo nombre pasa (dos ventanas en la misma
	# máquina es EL ciclo de trabajo del repo): desempata el peer.
	return int(a["peer"]) < int(b["peer"])


static func texto_ms(ms: int) -> String:
	if ms < 0:
		return "—"
	return "%d ms" % ms


static func calidad(ms: int) -> Calidad:
	if ms < 0:
		return Calidad.DESCONOCIDA
	if ms <= MS_BUENO:
		return Calidad.BUENA
	if ms <= MS_REGULAR:
		return Calidad.REGULAR
	return Calidad.MALA


## El paquete: peer, nombre y ms en fila. Plano y sin bits apretados a mano
## porque va UNA vez por segundo y como mucho lleva seis tripulantes — el códec
## de bytes es para el lote de cuerpos, que va a 20 Hz.
static func empaquetar(filas: Array) -> Array:
	var datos: Array = []
	for f: Dictionary in filas:
		datos.append(int(f["peer"]))
		datos.append(String(f["nombre"]))
		datos.append(int(f["ms"]))
	return datos


## Y la vuelta. `mi_peer` es quien lo desempaqueta, para marcar su propia fila.
## Tolera un paquete truncado o con basura en vez de romperse: viene de la red.
static func desempaquetar(datos: Array, mi_peer: int) -> Array:
	var filas: Array = []
	var i := 0
	while i + 2 < datos.size():
		var peer: int = int(datos[i]) if datos[i] is int or datos[i] is float else -1
		var nombre: String = String(datos[i + 1]) if datos[i + 1] is String else ""
		var ms: int = int(datos[i + 2]) if datos[i + 2] is int or datos[i + 2] is float else MS_DESCONOCIDO
		i += 3
		if peer < 0:
			continue
		filas.append(fila(peer, nombre, ms, peer == mi_peer))
	return ordenar(filas)
