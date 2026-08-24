class_name ParteMeteorologico
extends RefCounted

## El clima de la salida, ESCRITO ANTES DE ZARPAR (docs/CLIMA.md §8 item 14).
##
## Hoy la furia es un termostato: tiene un valor ahora, alguien lo mueve, y
## nadie —ni el juego— sabe que va a marcar dentro de dos minutos. Esto es un
## horario de trenes: una curva completa, dibujada de punta a punta, que
## cualquiera puede consultar en CUALQUIER instante, pasado o futuro.
##
## No predice el clima: [b]es[/b] el clima. La unica fuente.
##
## [b]Tres propiedades[/b], y las tres se pagan juntas:
##   1. [b]Consultable a futuro.[/b] `valor_en(&"furia", t + 120)` responde de
##      verdad. Es lo que hace honesto a `Ocean.get_height_at()` y lo que
##      permite que el mar de fondo llegue ANTES que el viento (§3.3).
##   2. [b]Identico en las 6 maquinas.[/b] Hoy el host manda la CURVA entera
##      (~medio kB, una vez, en el paquete de bienvenida y al generarlo), no la
##      receta: `Ocean.generar_parte()` escribe el guion desde la furia y el
##      reloj DE QUIEN LO PIDE, y esos dos numeros difieren entre maquinas, asi
##      que la misma semilla daria partes parecidos pero no iguales. Derivarlo
##      en cada cliente exige antes fijar el origen del guion (el arranque de
##      acto), que es trabajo de la fase de sesiones.
##   3. [b]Inmutable en el futuro cercano.[/b] Nadie edita dentro de
##      [constant HORIZONTE] segundos. Suena a limitacion y es LA garantia: la
##      telegrafia no puede mentir porque el guion ya esta escrito.
##
## Interpolacion Hermite [b]C1[/b]. Con C0 se ve el quiebro de aceleracion en
## el mar: la pendiente salta y las crestas dan un tiron en el frame del nudo.
##
## [b]Esta clase no sabe de la regla lluvia/furia[/b] — solo guarda y evalua
## curvas. El invariante («si sube la lluvia sube la furia») lo hace cumplir
## quien REDACTA el parte, que es [GeneradorParte]. Es a proposito: el parte es
## papel, y el papel no discute con quien lo escribe.

## Canales. Cada uno es una curva independiente sobre el mismo reloj.
const FURIA := &"furia"
const LLUVIA := &"lluvia"
## Rumbo del frente de tormenta en grados. Alimenta `front_dir` del cielo.
const RUMBO := &"rumbo"

## Cuanto futuro es intocable, en segundos. El director no puede editar dentro
## de esta ventana — y ese es justo el tiempo que las olas largas necesitan
## para llegar antes que el viento.
const HORIZONTE := 90.0

## canal -> keyframes ordenados por t. Cada uno es (t, valor, pendiente); un
## Vector3 en vez de un diccionario porque asi el parte entero viaja por la red
## como un PackedVector3Array sin serializar nada a mano.
var _canales: Dictionary = {}


## Escribe un keyframe. Devuelve false y NO escribe si viola el contrato.
##
## [param ahora] es el reloj de quien llama; dejalo en -INF para saltarse el
## horizonte (generacion inicial, tests, herramientas). Pasarlo es lo que
## convierte la promesa en contrato.
func comprometer(canal: StringName, t: float, valor: float,
		pendiente: float = 0.0, ahora: float = -INF) -> bool:
	if not is_finite(t) or not is_finite(valor) or not is_finite(pendiente):
		push_error("ParteMeteorologico: keyframe no finito en '%s'." % canal)
		return false
	if ahora > -INF and t < ahora + HORIZONTE:
		push_error(("ParteMeteorologico: '%s' en t=%.1f viola el horizonte "
			+ "(ahora=%.1f, minimo=%.1f). El futuro cercano es INMUTABLE: si "
			+ "esto se permite, la telegrafia miente.") % [canal, t, ahora, ahora + HORIZONTE])
		return false

	var kf: PackedVector3Array = _canales.get(canal, PackedVector3Array())
	# Reescribir un keyframe existente es legal (misma t exacta); insertar
	# desordenado no, porque la evaluacion asume orden y fallaria en silencio.
	var i: int = _indice_de(kf, t)
	if i >= 0 and is_equal_approx(kf[i].x, t):
		kf[i] = Vector3(t, valor, pendiente)
	else:
		kf.insert(i + 1, Vector3(t, valor, pendiente))
	_canales[canal] = kf
	return true


## Valor del canal en un instante arbitrario. Fuera del guion escrito, mantiene
## el primer/ultimo valor: un parte que se acaba deja el mar como lo dejo, no
## lo devuelve a cero.
func valor_en(canal: StringName, t: float) -> float:
	var kf: PackedVector3Array = _canales.get(canal, PackedVector3Array())
	if kf.is_empty():
		return 0.0
	if t <= kf[0].x:
		return kf[0].y
	if t >= kf[-1].x:
		return kf[-1].y
	var i: int = _indice_de(kf, t)
	return _hermite(kf[i], kf[i + 1], t)


## Minimo y maximo del canal en [desde, hasta], como (min, max).
##
## EXACTO, no muestreado: los extremos de un Hermite cubico salen de las raices
## de su derivada, que es una cuadratica. Muestrear se comeria justo el pico de
## una racha corta, que es lo unico que esta consulta existe para encontrar.
func extremos_en(canal: StringName, desde: float, hasta: float) -> Vector2:
	if hasta < desde:
		var tmp := desde
		desde = hasta
		hasta = tmp
	var kf: PackedVector3Array = _canales.get(canal, PackedVector3Array())
	if kf.is_empty():
		return Vector2.ZERO

	var lo: float = valor_en(canal, desde)
	var hi: float = lo
	var v_fin: float = valor_en(canal, hasta)
	lo = minf(lo, v_fin)
	hi = maxf(hi, v_fin)

	for i in kf.size() - 1:
		var a := kf[i]
		var b := kf[i + 1]
		if b.x <= desde or a.x >= hasta:
			continue
		# Nudo interior: cae dentro de la ventana, cuenta como candidato.
		if a.x > desde:
			lo = minf(lo, a.y)
			hi = maxf(hi, a.y)
		for t_crit in _criticos(a, b):
			if t_crit <= desde or t_crit >= hasta:
				continue
			var v: float = _hermite(a, b, t_crit)
			lo = minf(lo, v)
			hi = maxf(hi, v)
	return Vector2(lo, hi)


## La furia MAS ALTA que viene en la ventana.
##
## Hoy lo leen dos sitios: el frente del cielo (`DayNightCycle._aplicar_frente`)
## y la cadencia de rayos (`LightningDirector._furia_electrica_del_slot`, el
## «lightning jump»). Lo que TODAVIA no lo lee es el banco de olas: adelantar
## la banda larga del oleaje —«el mar de fondo llega primero», docs/CLIMA.md
## §3.3— sigue pendiente, aunque el dato que le faltaba ya esta aqui.
##
## Ojo declarado: como maximo sobre ventana deslizante es continuo pero tiene
## QUIEBROS DE DERIVADA cuando cambia el argumento que gana. Es aceptable para
## una envolvente lenta, pero el test de continuidad tiene que cubrir el caso.
func furia_swell(t: float, ventana: float = 240.0) -> float:
	return extremos_en(FURIA, t, t + ventana).y


func tiene(canal: StringName) -> bool:
	return _canales.has(canal) and not (_canales[canal] as PackedVector3Array).is_empty()


func canales() -> Array:
	return _canales.keys()


func keyframes(canal: StringName) -> PackedVector3Array:
	return _canales.get(canal, PackedVector3Array())


## Instante del ultimo keyframe escrito, en cualquier canal.
func duracion() -> float:
	var fin: float = 0.0
	for canal: StringName in _canales:
		var kf: PackedVector3Array = _canales[canal]
		if not kf.is_empty():
			fin = maxf(fin, kf[-1].x)
	return fin


## Descarta el guion entero. La partida siguiente escribe el suyo.
func limpiar() -> void:
	_canales.clear()


# =============================================================================
#  Red (docs/RED.md). Hoy es el camino NORMAL, no la excepcion: el host manda
#  la curva entera al generar el parte y en el paquete de bienvenida. Es medio
#  kB una sola vez, y a cambio hace imposible que dos maquinas generen partes
#  que se parezcan pero no sean iguales — que es lo que pasaria derivandolos
#  de la semilla mientras el origen del guion siga siendo «el reloj y la furia
#  de quien pulso el boton».
# =============================================================================

func empaquetar() -> Dictionary:
	var out: Dictionary = {}
	for canal: StringName in _canales:
		out[canal] = (_canales[canal] as PackedVector3Array).duplicate()
	return out


func desempaquetar(datos: Dictionary) -> void:
	_canales.clear()
	for canal: Variant in datos:
		var kf: PackedVector3Array = datos[canal]
		_canales[StringName(canal)] = kf.duplicate()


# =============================================================================
#  Interno
# =============================================================================

## Indice del ultimo keyframe con t <= [param t], o -1 si t va antes de todos.
## Busqueda binaria: un parte de una salida larga son cientos de nudos y esto
## lo llama la fisica.
func _indice_de(kf: PackedVector3Array, t: float) -> int:
	var lo: int = 0
	var hi: int = kf.size() - 1
	var out: int = -1
	while lo <= hi:
		var mid: int = (lo + hi) / 2
		if kf[mid].x <= t:
			out = mid
			lo = mid + 1
		else:
			hi = mid - 1
	return out


## Hermite cubico entre dos keyframes. `a.z`/`b.z` son las pendientes en
## unidades por SEGUNDO, asi que se escalan por la duracion del tramo.
func _hermite(a: Vector3, b: Vector3, t: float) -> float:
	var h: float = b.x - a.x
	if h <= 0.0001:
		return b.y
	var s: float = (t - a.x) / h
	var s2: float = s * s
	var s3: float = s2 * s
	var h00: float = 2.0 * s3 - 3.0 * s2 + 1.0
	var h10: float = s3 - 2.0 * s2 + s
	var h01: float = -2.0 * s3 + 3.0 * s2
	var h11: float = s3 - s2
	return h00 * a.y + h10 * h * a.z + h01 * b.y + h11 * h * b.z


## Instantes en los que la derivada del tramo se anula (0, 1 o 2).
func _criticos(a: Vector3, b: Vector3) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var h: float = b.x - a.x
	if h <= 0.0001:
		return out
	# d/ds del Hermite: una cuadratica en s.
	var m0: float = h * a.z
	var m1: float = h * b.z
	var qa: float = 6.0 * a.y + 3.0 * m0 - 6.0 * b.y + 3.0 * m1
	var qb: float = -6.0 * a.y - 4.0 * m0 + 6.0 * b.y - 2.0 * m1
	var qc: float = m0

	if absf(qa) < 1e-9:
		# Degenera a lineal: una sola raiz, y solo si la pendiente no es nula.
		if absf(qb) > 1e-9:
			var s_lin: float = -qc / qb
			if s_lin > 0.0 and s_lin < 1.0:
				out.append(a.x + s_lin * h)
		return out

	var disc: float = qb * qb - 4.0 * qa * qc
	if disc < 0.0:
		return out
	var raiz: float = sqrt(disc)
	for s in [(-qb + raiz) / (2.0 * qa), (-qb - raiz) / (2.0 * qa)]:
		if s > 0.0 and s < 1.0:
			out.append(a.x + s * h)
	return out
