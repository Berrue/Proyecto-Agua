class_name NetAgua
extends RefCounted

## El codec del agua embarcada. PURO: cero nodos, cero ENet — el mismo contrato
## que `NetMath` y `NetPorteo`, y por el mismo motivo: `Net` es un autoload
## singleton, asi que un RPC no se puede testear y lo unico que queda probable es
## lo que viva aca fuera.
##
## [b]Por que un byte por celda.[/b] docs/CLIMA.md §6.4 preveia replicar "un float
## a ~4 Hz", pero el agregado no basta: el cliente necesita saber QUE celda esta
## anegada para el chapoteo, el HUD y el futuro plano de agua, y sobre todo
## porque la escora ya la esta viendo —el barco se tumba hacia el lado mojado— y
## un HUD que no coincida con lo que se ve seria feedback que miente (regla 8).
##
## Ocho bytes mas uno de banderas es menos que el float y su cabecera de RPC, asi
## que la precision sale gratis: 1/255 es un 0,4% de una celda, y el nivel se
## mueve a centesimas por segundo.

## Bits del byte de estado. APPEND-ONLY: viajan por el cable.
const BIT_NAUFRAGIO := 1
const BIT_ALARMA := 2
## Primera estacion con la camara llena; la siguiente va un bit mas a la
## izquierda. Caben seis en los bits que sobraban, o sea gratis.
##
## Viaja porque el CLIENTE no simula la bomba: alli `carga_camara` es siempre
## cero, asi que sin este bit alguien bombeando desde un invitado no tendria
## forma de enterarse de que la camara se lleno y de que hay que soltar — la
## unica forma de fallar de la mecanica que no se ve sola (regla 8).
const BIT_CAMARA_BASE := 4


static func empaquetar(niveles: PackedFloat32Array, alarma: bool,
		naufragio: bool, camaras: int = 0) -> PackedByteArray:
	var datos := PackedByteArray()
	datos.resize(niveles.size() + 1)
	for i in niveles.size():
		datos[i] = int(roundf(clampf(niveles[i], 0.0, 1.0) * 255.0))
	var banderas: int = 0
	if naufragio:
		banderas |= BIT_NAUFRAGIO
	if alarma:
		banderas |= BIT_ALARMA
	banderas |= (maxi(camaras, 0) * BIT_CAMARA_BASE) & 0xFC
	datos[niveles.size()] = banderas
	return datos


## Devuelve { niveles, alarma, naufragio, camaras }. Un paquete vacio o truncado
## devuelve niveles vacios en vez de reventar: por el cable llega lo que llega.
##
## ⚠️ El numero de celdas se deduce de `datos.size() - 1`, asi que NUNCA se le
## añade un byte al final: la bandera tiene que caber en el que ya hay.
static func desempaquetar(datos: PackedByteArray) -> Dictionary:
	if datos.size() < 1:
		return {&"niveles": PackedFloat32Array(), &"alarma": false,
			&"naufragio": false, &"camaras": 0}
	var n: int = datos.size() - 1
	var niveles := PackedFloat32Array()
	niveles.resize(n)
	for i in n:
		niveles[i] = float(datos[i]) / 255.0
	var banderas: int = datos[n]
	return {
		&"niveles": niveles,
		&"alarma": (banderas & BIT_ALARMA) != 0,
		&"naufragio": (banderas & BIT_NAUFRAGIO) != 0,
		&"camaras": int(banderas / BIT_CAMARA_BASE),
	}


## La intensidad de una ola sobre la borda, cuantizada a un byte para el evento
## one-shot. Es cosmetica (audio y spray), asi que 1/255 sobra de largo.
static func cuantizar_intensidad(intensidad: float) -> int:
	return int(roundf(clampf(intensidad, 0.0, 1.0) * 255.0))


static func descuantizar_intensidad(bruto: int) -> float:
	return clampf(float(bruto) / 255.0, 0.0, 1.0)
