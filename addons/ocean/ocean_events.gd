class_name OceanEvents
extends RefCounted

## Capa de EVENTOS: tsunamis y olas monstruo. Se suma al campo de olas base.
##
## [b]Por que esto no puede salir de un espectro.[/b] Un espectro (JONSWAP, TMA,
## Tessendorf, FFT...) es estadisticamente ESTACIONARIO por construccion:
## describe un mar en equilibrio con el viento. No existe ningun valor de viento,
## fetch ni choppiness que produzca un frente solitario y dirigido. Quien adopte
## una base FFT creyendo que "subiendo el viento sale el tsunami" lo descubre en
## el mes 6, con el climax del juego sin implementar. Por eso el tsunami se
## AUTORA: es analitico, barato y esta bajo control del diseñador.
##
## [b]Onda N, no una simple joroba.[/b] El perfil lleva una DEPRESION viajando
## por delante de la cresta, que es lo que hace un tsunami de verdad. Eso
## significa que la retirada del mar (el momento en que el agua se va, aparece el
## fondo y todo se queda en silencio) no esta scripteada: EMERGE de la misma
## formula. La flotabilidad, el nado y la carga suelta reaccionan solos.
##
## [b]Y la telegrafia sale gratis.[/b] Al ser funcion pura de t, cualquier
## cliente puede evaluarla en el FUTURO y saber al milisegundo cuando llega la
## ola a un punto. El aviso previo no necesita ningun sistema adicional.
##
## Espejo exacto de las funciones `ocean_event_*` de `ocean_waves.gdshaderinc`.

const MAX_EVENTS := 2

## Cuanto penaliza al Jacobiano la pendiente del frente. Es lo que hace que la
## cara del tsunami se pinte BLANCA y que `Ocean.get_breaking()` dispare alli el
## revolcon: el aviso visual y el daño salen del mismo numero.
const SLOPE_BREAK_SCALE := 8.0

## Profundidad efectiva para la velocidad de particula (u = c*eta/(h+eta)).
## No hay batimetria en mar abierto, asi que es un parametro de diseño honesto.
## Tiene que quedar MUY por encima de la retirada mas profunda que pueda pedir un
## tier: si eta se acerca a -h, la columna de agua se vacia, el denominador tiende
## a cero y la velocidad se dispara.
const EFFECTIVE_DEPTH := 45.0

## Tope de la velocidad de particula, como fraccion de la celeridad.
##
## No es un numero arbitrario: en una onda solitaria, cuando la velocidad del
## agua se acerca a la de la ola, la cresta adelanta a su propia base y la ola
## ROMPE. Ese regimen ya lo modelamos aparte (el Jacobiano), asi que aqui se
## acota y ya esta. Sin este tope, un tier grande produce corrientes de cientos
## de m/s y los cuerpos las siguen fielmente hasta salir despedidos: el fallo
## parece de la flotabilidad, pero es del agua.
const MAX_PARTICLE_FRACTION := 0.6


class Tsunami:
	var origin := Vector2.ZERO
	var direction := Vector2(0.0, 1.0) ## unitaria
	var amplitude: float = 18.0 ## altura de la cresta, m
	var celerity: float = 45.0 ## velocidad de avance, m/s
	var width: float = 90.0 ## semianchura de la cresta, m
	var t0: float = 0.0 ## sim_time en que la cresta pasa por el origen

	## Forma de la onda N. `lead` es a cuantas anchuras por delante viaja la
	## depresion, `spread` cuanto mas ancha es que la cresta, y `depression` su
	## profundidad relativa. Con los valores por defecto el mar empieza a
	## retirarse casi un minuto antes de que llegue el muro, baja unos 10 m en su
## punto mas bajo, y vuelve a subir justo antes del impacto.
	var lead: float = 12.0
	var spread: float = 9.0
	var depression: float = 0.55

	var active: bool = false


var events: Array[Tsunami] = []


func _init() -> void:
	for _i in MAX_EVENTS:
		events.append(Tsunami.new())


## Lanza un tsunami. Devuelve el indice, o -1 si no hay hueco libre.
func spawn(origin: Vector2, direction: Vector2, amplitude: float, celerity: float,
		width: float, t0: float, lead: float = 12.0, spread: float = 9.0,
		depression: float = 0.55) -> int:
	for i in events.size():
		if not events[i].active:
			var e := events[i]
			e.origin = origin
			e.direction = direction.normalized()
			e.amplitude = amplitude
			e.celerity = maxf(celerity, 0.1)
			e.width = maxf(width, 1.0)
			e.t0 = t0
			e.lead = lead
			e.spread = spread
			e.depression = clampf(depression, 0.0, 1.0)
			e.active = true
			return i
	return -1


## El inverso exacto de `pack()`: reconstruye la tabla de eventos desde los
## tres PackedVector4Array. Lo usa la red para que quien se une a mitad de
## tsunami vea la MISMA ola que los demas — no una nueva, la misma, con su
## `t0` original intacto.
func unpack(datos: Array) -> void:
	if datos.size() < 3:
		return
	var a := datos[0] as PackedVector4Array
	var b := datos[1] as PackedVector4Array
	var c := datos[2] as PackedVector4Array
	for i in events.size():
		var e := events[i]
		if i >= a.size() or i >= b.size() or i >= c.size():
			e.active = false
			continue
		e.origin = Vector2(a[i].x, a[i].y)
		e.direction = Vector2(a[i].z, a[i].w)
		if e.direction.length_squared() < 1e-6:
			e.direction = Vector2(0.0, 1.0)
		e.direction = e.direction.normalized()
		e.amplitude = b[i].x
		e.celerity = maxf(b[i].y, 0.1)
		e.width = maxf(b[i].z, 1.0)
		e.t0 = b[i].w
		e.lead = c[i].x
		e.spread = c[i].y
		e.depression = clampf(c[i].z, 0.0, 1.0)
		e.active = c[i].w > 0.5


func clear_all() -> void:
	for e in events:
		e.active = false


func has_active() -> bool:
	for e in events:
		if e.active:
			return true
	return false


# =============================================================================
#  Evaluacion - espejo exacto de ocean_waves.gdshaderinc
# =============================================================================

## sech(x)^2, en forma numericamente estable. `cosh` desborda para |x| grande;
## esta forma tiende suavemente a cero.
static func sech2(x: float) -> float:
	var e: float = exp(-absf(x))
	var s: float = 2.0 * e / (1.0 + e * e)
	return s * s


## Derivada de sech(x)^2 respecto a x.
static func dsech2(x: float) -> float:
	var e: float = exp(-absf(x))
	var s: float = 2.0 * e / (1.0 + e * e)
	var th: float = (1.0 - e * e) / (1.0 + e * e)
	if x < 0.0:
		th = -th
	return -2.0 * s * s * th


## Coordenada de fase del evento en un punto. Positiva = todavia no ha llegado.
func _phase(e: Tsunami, p: Vector2, t: float) -> float:
	var d: float = (p - e.origin).dot(e.direction)
	return (d - e.celerity * (t - e.t0)) / e.width


## Altura que el evento añade en un punto del mundo.
func height_at(p: Vector2, t: float) -> float:
	var total: float = 0.0
	for e in events:
		if not e.active:
			continue
		var u := _phase(e, p, t)
		# Cresta menos depresion adelantada. La depresion esta en u POSITIVO
		# porque las fases positivas son las que todavia no han llegado, o sea
		# las que el jugador ve venir primero.
		total += e.amplitude * (
			sech2(u) - e.depression * sech2((u - e.lead) / e.spread))
	return total


## Pendiente del frente en la direccion de avance (m/m).
func slope_at(p: Vector2, t: float) -> float:
	var total: float = 0.0
	for e in events:
		if not e.active:
			continue
		var u := _phase(e, p, t)
		total += (e.amplitude / e.width) * (
			dsech2(u) - (e.depression / e.spread) * dsech2((u - e.lead) / e.spread))
	return total


## Velocidad del agua que aporta el evento.
##
## La vertical sale gratis de la pendiente: como eta depende de (d - c*t), se
## cumple que d(eta)/dt = -c * d(eta)/dd. La horizontal usa la velocidad de
## particula de una onda solitaria, u = c*eta/(h+eta), que es lo que EMPUJA el
## barco con la cresta y lo ARRASTRA mar adentro durante la retirada.
func velocity_at(p: Vector2, t: float) -> Vector3:
	var vel := Vector3.ZERO
	for e in events:
		if not e.active:
			continue
		var u := _phase(e, p, t)
		var eta: float = e.amplitude * (
			sech2(u) - e.depression * sech2((u - e.lead) / e.spread))
		var slope: float = (e.amplitude / e.width) * (
			dsech2(u) - (e.depression / e.spread) * dsech2((u - e.lead) / e.spread))

		vel.y += -e.celerity * slope

		# Doble proteccion: el denominador nunca se acerca a cero, y ademas la
		# velocidad resultante se acota a una fraccion de la celeridad.
		var denom: float = maxf(EFFECTIVE_DEPTH + eta, EFFECTIVE_DEPTH * 0.35)
		var limit: float = e.celerity * MAX_PARTICLE_FRACTION
		var push: float = clampf(e.celerity * eta / denom, -limit, limit)
		vel.x += e.direction.x * push
		vel.z += e.direction.y * push
	return vel


## Penalizacion al Jacobiano por la pendiente del frente. Restarla del Jacobiano
## del oleaje hace que la cara del tsunami cuente como rotura, con un solo numero
## compartido entre el shader y la fisica.
func break_penalty_at(p: Vector2, t: float) -> float:
	return absf(slope_at(p, t)) * SLOPE_BREAK_SCALE


# =============================================================================
#  Telegrafia
# =============================================================================

## Segundos hasta que la CRESTA alcance este punto. Negativo si ya paso, INF si
## no hay ningun tsunami activo.
##
## Esto es lo que un enfoque con estado (SWE, wave particles, FFT) no puede dar:
## al ser funcion pura de t, el cliente evalua el futuro directamente. El aviso
## previo, el audio subsonico y el HUD no necesitan ningun sistema aparte.
func time_until_crest(p: Vector2, t: float) -> float:
	var best: float = INF
	for e in events:
		if not e.active:
			continue
		var d: float = (p - e.origin).dot(e.direction)
		var arrival: float = e.t0 + d / e.celerity
		best = minf(best, arrival - t)
	return best


## Empaquetado para el shader: 3 vec4 por evento.
func pack() -> Array:
	var a := PackedVector4Array()
	var b := PackedVector4Array()
	var c := PackedVector4Array()
	a.resize(MAX_EVENTS)
	b.resize(MAX_EVENTS)
	c.resize(MAX_EVENTS)
	for i in events.size():
		var e := events[i]
		a[i] = Vector4(e.origin.x, e.origin.y, e.direction.x, e.direction.y)
		b[i] = Vector4(e.amplitude, e.celerity, e.width, e.t0)
		c[i] = Vector4(e.lead, e.spread, e.depression, 1.0 if e.active else 0.0)
	return [a, b, c]
