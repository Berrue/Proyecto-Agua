class_name NetMath
extends RefCounted

## La matematica pura de la costura de red (docs/RED.md). Sin nodos, sin
## Ocean, sin ENet: solo transformadas y relojes, para que los tests headless
## la claven sin levantar una partida. Si un jugador flota despegado de la
## cubierta ajena o el barco replicado "respira" contra el agua, el bug esta
## en quien LLAMA a esto — estas cuatro funciones tienen test.


## Contrato 1 (RED.md): los jugadores viajan en espacio LOCAL del barco.
static func a_local(barco: Transform3D, mundo: Transform3D) -> Transform3D:
	return barco.affine_inverse() * mundo


## ...y cada maquina los compone contra SU copia del barco.
static func a_mundo(barco: Transform3D, local: Transform3D) -> Transform3D:
	return barco * local


## Contrato 2: el reloj del cliente PERSIGUE al del host, jamas salta. La
## correccion por tick esta acotada a max_slew*delta (una dilatacion del
## tiempo de a lo sumo ese porcentaje): el oceano es funcion pura de t, asi
## que un salto de reloj seria un teletransporte de la superficie entera — la
## misma violacion anti-popping que prohibimos en las olas rebeldes.
static func corregir_reloj(actual: float, objetivo: float, delta: float,
		max_slew: float) -> float:
	return actual + clampf(objetivo - actual, -max_slew * delta, max_slew * delta)


## Interpola el transform del barco entre dos snapshots {t, pos, rot}. Fuera
## del rango se CLAMPA al extremo: extrapolar un barco cabeceando inventa
## posiciones que el host nunca produjo, y con mar gruesa se nota.
static func interpolar_snapshots(a: Dictionary, b: Dictionary, t: float) -> Transform3D:
	var lapso: float = maxf(float(b[&"t"]) - float(a[&"t"]), 1e-6)
	var f: float = clampf((t - float(a[&"t"])) / lapso, 0.0, 1.0)
	var rot: Quaternion = (a[&"rot"] as Quaternion).slerp(b[&"rot"] as Quaternion, f)
	var pos: Vector3 = (a[&"pos"] as Vector3).lerp(b[&"pos"] as Vector3, f)
	return Transform3D(Basis(rot), pos)


# =============================================================================
#  El codec del lote de cuerpos (R1)
# =============================================================================
#
# Todos los cuerpos replicados de un tick viajan en UN solo PackedByteArray.
# Un RPC por prop pagaria la cabecera de Variant de Godot por cada argumento y
# multiplicaria el fanout por el numero de cuerpos; asi es un paquete por tick
# pase lo que pase.
#
# Formato:  [t: f64] + por cuerpo [id: u16][flags: u8][pos: 3 x f32][rot: 4 x f16]
#           = 8 B de cabecera + 23 B por cuerpo.
#
# El cuaternion va en f16 porque su error (~1e-3 rad) es invisible en un prop y
# ahorra 8 B por cuerpo. La POSICION se queda en f32 a proposito: el mundo mide
# cientos de metros y ahi f16 si se nota. Y `t` va en f64 como el resto de los
# relojes del sistema: `Ocean.sim_time` crece sin techo durante la sesion.

const CUERPO_BYTES := 23
const LOTE_CABECERA := 8

## El transform de este cuerpo va en el marco LOCAL del barco (contrato 1 de
## RED.md). Se decide por cuerpo y por tick: un barril en cubierta lo lleva,
## un farol que flota a 200 m no.
const FLAG_LOCAL := 1

## Este es el ULTIMO snapshot de este cuerpo: se quedo quieto. El receptor lo
## guarda como transform de reposo y deja de esperar mas — de ahi sale que el
## regimen estable de R1 cueste CERO bytes por segundo.
const FLAG_DORMIDO := 2

## Tope de bytes por lote. El MTU de ENet ronda los 1400 B y un paquete NO
## fiable que lo cruce se FRAGMENTA: perder un fragmento pierde el tick entero,
## justo en tier 3 que es cuando mas cuerpos hay volando. Por eso el sobrante
## rota entre ticks en vez de ensanchar el paquete.
const MTU_SEGURO := 1200


## `cuerpos` es Array[Dictionary] con {id: int, flags: int, pos: Vector3, rot: Quaternion}.
static func empaquetar_cuerpos(t: float, cuerpos: Array[Dictionary]) -> PackedByteArray:
	var datos := PackedByteArray()
	datos.resize(LOTE_CABECERA + cuerpos.size() * CUERPO_BYTES)
	datos.encode_double(0, t)
	var o: int = LOTE_CABECERA
	for c in cuerpos:
		datos.encode_u16(o, int(c[&"id"]))
		datos.encode_u8(o + 2, int(c[&"flags"]))
		var p: Vector3 = c[&"pos"]
		datos.encode_float(o + 3, p.x)
		datos.encode_float(o + 7, p.y)
		datos.encode_float(o + 11, p.z)
		var q: Quaternion = c[&"rot"]
		datos.encode_half(o + 15, q.x)
		datos.encode_half(o + 17, q.y)
		datos.encode_half(o + 19, q.z)
		datos.encode_half(o + 21, q.w)
		o += CUERPO_BYTES
	return datos


## Devuelve {t: float, cuerpos: Array[Dictionary]} con la misma forma. Un
## buffer truncado devuelve el `t` y los cuerpos COMPLETOS que haya, sin
## reventar: un paquete mordido no puede tirar el tick entero.
static func desempaquetar_lote(datos: PackedByteArray) -> Dictionary:
	var salida: Dictionary = {&"t": 0.0, &"cuerpos": ([] as Array[Dictionary])}
	if datos.size() < LOTE_CABECERA:
		return salida
	salida[&"t"] = datos.decode_double(0)
	var cuerpos: Array[Dictionary] = []
	var o: int = LOTE_CABECERA
	while o + CUERPO_BYTES <= datos.size():
		var q := Quaternion(
			datos.decode_half(o + 15), datos.decode_half(o + 17),
			datos.decode_half(o + 19), datos.decode_half(o + 21))
		# El redondeo a f16 deja el cuaternion ligeramente fuera de la esfera
		# unidad, y `Basis(q)` con un cuaternion sin normalizar es un error de
		# Godot en tiempo de ejecucion. Normalizar aca es obligatorio, no
		# higiene. Si el paquete trae basura y sale un cuaternion nulo, se
		# sustituye por la identidad en vez de propagar NaN al transform.
		q = q.normalized() if q.length_squared() > 1e-6 else Quaternion.IDENTITY
		cuerpos.append({
			&"id": datos.decode_u16(o),
			&"flags": datos.decode_u8(o + 2),
			&"pos": Vector3(datos.decode_float(o + 3), datos.decode_float(o + 7),
				datos.decode_float(o + 11)),
			&"rot": q,
		})
		o += CUERPO_BYTES
	salida[&"cuerpos"] = cuerpos
	return salida


## Cuantos cuerpos caben en un lote sin cruzar el MTU seguro.
static func cuerpos_por_paquete() -> int:
	return (MTU_SEGURO - LOTE_CABECERA) / CUERPO_BYTES


## Elige del buffer (ordenado por t) el transform para el instante t. Con un
## solo snapshot, ese; con varios, el par que abraza a t (o el extremo).
static func muestrear_buffer(buffer: Array[Dictionary], t: float) -> Transform3D:
	if buffer.is_empty():
		return Transform3D.IDENTITY
	if buffer.size() == 1 or t <= float(buffer[0][&"t"]):
		var s := buffer[0]
		return Transform3D(Basis(s[&"rot"] as Quaternion), s[&"pos"] as Vector3)
	for i in range(1, buffer.size()):
		if t <= float(buffer[i][&"t"]):
			return interpolar_snapshots(buffer[i - 1], buffer[i], t)
	var ultimo := buffer[-1]
	return Transform3D(Basis(ultimo[&"rot"] as Quaternion), ultimo[&"pos"] as Vector3)
