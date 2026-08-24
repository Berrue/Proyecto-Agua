class_name NetLag
extends RefCounted

## Latencia simulada, para poder jugar el playtest con 80-150 ms sin salir de
## localhost (docs/RED.md, R1). PURA: se drena contra un reloj que le pasan,
## asi que se testea sin ENet y sin escena.
##
## Sustituye a una promesa vacia: RED.md decia "netfox trae el toggle", pero
## `addons/` solo contiene `ocean` — no habia una linea de codigo detras. Y
## vendorizar netfox entero para esto costaria su fila en THIRD_PARTY.md
## (regla 9) y una auditoria, cuando lo que hace falta son cuarenta lineas.
##
## Se simula en RECEPCION, no en emision. Es deliberado: lo que queremos
## probar es como se comporta el BUFFER de interpolacion del cliente frente al
## jitter, y eso se modela llegando tarde. Ademas deja el camino de produccion
## intacto — con `demora_ms == 0` la primera linea de `encolar()` devuelve
## false y el coste es una comparacion.
##
## Dos promesas que el simulador NO puede romper:
##  1. El orden DENTRO de un canal se conserva SIEMPRE. `unreliable_ordered`
##     es una garantia del transporte; romperla aca manda al equipo a cazar
##     durante dias un bug del juego que no existe. Un simulador que miente es
##     peor que no tener ninguno.
##  2. ENTRE canales SI puede reordenar — y debe, porque esa es justamente la
##     carrera real que ya existe hoy entre el `_chau` fiable y el
##     `_estado_jugador` no fiable.

enum Canal { FIABLE, ORDENADO }

## Demora base en milisegundos (ida). 0 = desactivado.
var demora_ms: float = 0.0
## Variacion simetrica alrededor de la demora base.
var jitter_ms: float = 0.0
## 0..1. Solo se aplica al canal ORDENADO: perder un paquete "fiable" no es
## algo que ENet permita, y simularlo probaria un mundo que no existe.
var perdida: float = 0.0

var _colas: Array[Array] = [[], []]
## El instante de entrega del ultimo mensaje encolado en cada canal, para que
## el jitter no pueda adelantar a un mensaje anterior (promesa 1).
var _ultimo_por_canal: PackedFloat64Array = PackedFloat64Array([0.0, 0.0])
var _rng := RandomNumberGenerator.new()
## Mientras se drena, `encolar()` deja pasar: si no, cada mensaje entregado se
## volveria a encolar y no se entregaria nunca.
var _drenando: bool = false


func _init() -> void:
	_rng.seed = 20260823


## Semilla EXPLICITA (regla 4). Si el jitter fuera irreproducible, dos maquinas
## de desarrollo no podrian reproducir el bug de la otra y el propio test
## flakearia de vez en cuando, que es peor que no tenerlo.
func sembrar(semilla: int) -> void:
	_rng.seed = semilla


func configurar(demora: float, jitter: float, perdida01: float) -> void:
	demora_ms = maxf(demora, 0.0)
	jitter_ms = maxf(jitter, 0.0)
	perdida = clampf(perdida01, 0.0, 1.0)


func activo() -> bool:
	return demora_ms > 0.0 or jitter_ms > 0.0 or perdida > 0.0


## Encola un mensaje. Devuelve true si SE ENCOLO (y entonces el llamador debe
## hacer `return` sin ejecutar el cuerpo del RPC); false si tiene que seguir
## de largo, que es el caso de produccion y el caso del drenaje.
func encolar(canal: int, ahora: float, metodo: Callable, args: Array) -> bool:
	if _drenando or not activo():
		return false
	if canal == Canal.ORDENADO and perdida > 0.0 and _rng.randf() < perdida:
		return true # se perdio: encolado a la nada, el llamador no ejecuta
	var espera: float = (demora_ms + _rng.randf_range(-jitter_ms, jitter_ms)) * 0.001
	var entrega: float = ahora + maxf(espera, 0.0)
	# Promesa 1: nunca antes que el anterior de SU canal.
	entrega = maxf(entrega, _ultimo_por_canal[canal])
	_ultimo_por_canal[canal] = entrega
	_colas[canal].append({&"t": entrega, &"metodo": metodo, &"args": args})
	return true


## Entrega todo lo vencido, en orden dentro de cada canal.
func drenar(ahora: float) -> void:
	if _drenando:
		return
	_drenando = true
	for canal in _colas.size():
		var cola: Array = _colas[canal]
		while not cola.is_empty() and float(cola[0][&"t"]) <= ahora:
			var msg: Dictionary = cola.pop_front()
			var metodo: Callable = msg[&"metodo"]
			if metodo.is_valid():
				metodo.callv(msg[&"args"])
	_drenando = false


func pendientes() -> int:
	return _colas[Canal.FIABLE].size() + _colas[Canal.ORDENADO].size()


func limpiar() -> void:
	for cola: Array in _colas:
		cola.clear()
	_ultimo_por_canal.fill(0.0)


## Para el overlay. Un mundo con lag falso que no se anuncia es feedback que
## miente igual que un mundo desincronizado (regla 8).
func resumen() -> String:
	if not activo():
		return ""
	var texto := "lag %.0f" % demora_ms
	if jitter_ms > 0.0:
		texto += "±%.0f" % jitter_ms
	texto += " ms"
	if perdida > 0.0:
		texto += "  ·  %.0f%% pérdida" % (perdida * 100.0)
	return texto
