class_name OceanWaveProxy
extends RefCounted

## Campo de olas de Gerstner. ES la verdad del agua para fisica, red, IA y audio.
##
## [b]Este archivo implementa EXACTAMENTE la misma matematica que[/b]
## [code]addons/ocean/shaders/ocean_waves.gdshaderinc[/code]. Si tocas una
## formula aqui, tocala tambien alli, y mira las esferas de
## [code]addons/ocean/debug/parity_markers.gd[/code] en el editor: si se
## despegan del agua, hay deriva CPU/GPU. El lado CPU (determinismo, inversion)
## lo cubre [code]tests/f1_tests.gd[/code] en headless; el test GPU automatico
## sigue pendiente porque headless no tiene RenderingDevice.
##
## Es una funcion PURA de (posicion, tiempo, semilla, estado del mar): dos
## maquinas con la misma semilla y el mismo reloj calculan el mismo mar sin
## intercambiar un solo byte de geometria.

const MAX_WAVES := 16
const GRAVITY := 9.81

## Por encima de esto la ola de Gerstner se auto-intersecta, la inversion por
## punto fijo deja de converger y la flotabilidad se vuelve caotica.
const STEEPNESS_LIMIT := 0.85

## Relacion amplitud/longitud a la que una ola real rompe (H/L ~ 1/7, a = H/2).
const WAVE_BREAK_RATIO := 0.078

# --- Congelado por semilla: NO cambia al mover el dial de furia ---------------
# Si estos valores se remuestrearan al cambiar la furia, la superficie daria un
# salto visible y la fisica un tiron. Solo se mueven las amplitudes.
var _dir: PackedVector2Array = PackedVector2Array()
var _wavelength: PackedFloat32Array = PackedFloat32Array()
var _k: PackedFloat32Array = PackedFloat32Array()
var _omega: PackedFloat32Array = PackedFloat32Array()
var _domega: PackedFloat32Array = PackedFloat32Array()
var _phase: PackedFloat32Array = PackedFloat32Array()

# --- Recalculado al mover el dial --------------------------------------------
var _amp: PackedFloat32Array = PackedFloat32Array()
var _q: float = 0.0

var count: int = 0
var measured_hs: float = 0.0 ## Hs real tras aplicar el limite de rotura.


## Muestrea longitudes de onda, direcciones y fases. Se llama UNA vez por partida.
func generate(rng_seed: int, wave_count: int = 12, wind_dir_deg: float = 0.0) -> void:
	count = clampi(wave_count, 1, MAX_WAVES)
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed # semilla explicita: NUNCA el RNG global

	_dir.resize(count)
	_wavelength.resize(count)
	_k.resize(count)
	_omega.resize(count)
	_domega.resize(count)
	_phase.resize(count)
	_amp.resize(count)

	# Longitudes de onda de swell largo a rizado, en progresion geometrica. El
	# rango es ancho a proposito: al subir la furia lo que se mueve es DONDE
	# esta la energia dentro del rango, no el rango.
	#
	# El minimo esta atado al tamaño de celda de la malla (~2 m en F1): por
	# debajo de unas 4 celdas por longitud de onda la ola no se puede
	# representar y solo produce aliasing.
	var l_max := 420.0
	var l_min := 9.0
	var divisor := float(maxi(count - 1, 1))
	var ratio: float = pow(l_min / l_max, 1.0 / divisor)
	var wind := deg_to_rad(wind_dir_deg)

	for i in count:
		var wl: float = l_max * pow(ratio, float(i))
		_wavelength[i] = wl
		_k[i] = TAU / wl
		_omega[i] = sqrt(GRAVITY * _k[i]) # dispersion en aguas profundas
		_phase[i] = rng.randf() * TAU

		# Las olas largas (swell) llegan alineadas con el viento; las cortas se
		# abren. Es lo que impide que el mar parezca un peine.
		var t: float = float(i) / divisor
		var spread: float = lerpf(0.12, 1.05, t)
		var ang: float = wind + rng.randfn(0.0, spread)
		_dir[i] = Vector2(cos(ang), sin(ang))

	# Ancho de banda en frecuencia de cada modo. Hace falta para integrar el
	# espectro: la energia de un modo es S(w) * dw, no S(w) a secas.
	for i in count:
		var lo: float = _omega[maxi(i - 1, 0)]
		var hi: float = _omega[mini(i + 1, count - 1)]
		var span: float = absf(hi - lo)
		_domega[i] = span * 0.5 if count > 1 else _omega[i]
		if is_zero_approx(_domega[i]):
			_domega[i] = _omega[i] * 0.5


## Longitudes de onda entre las que la banda larga puede ADELANTARSE al viento.
## Por debajo de la corta, nada se adelanta (el rizado lo hace el viento de
## AHORA, y un rizado que llega antes que su viento es imposible y se ve raro);
## por encima de la larga, el adelanto es pleno. El swell real de un temporal
## lejano son ondas de 200-400 m, y estas dos cifras las encierran.
const SWELL_BANDA_CORTA := 150.0
const SWELL_BANDA_LARGA := 250.0


## Reparte la energia del mar entre las olas ya congeladas.
## [param hs] altura significativa objetivo en metros (escala Douglas).
## [param choppiness] 0..0.85. Cuanto mas alto, mas puntiagudas las crestas.
## [param hs_swell] Hs de la MAR DE FONDO, que puede venir de una tormenta que
## todavia no ha llegado (docs/CLIMA.md §3.3: «el mar de fondo llega primero»).
## Solo alimenta las olas LARGAS, y solo si supera a [param hs]. Por defecto
## -1 = «la misma que hs», o sea el comportamiento de siempre, bit a bit.
## [param hs_origen] Hs de la TORMENTA que genera ese swell, para su periodo.
## Es la definicion fisica de mar de fondo: energia moderada (capada por quien
## llama) pero el PERIODO del temporal lejano — Tp ~ 4·sqrt(Hs_tormenta), olas
## de cientos de metros. Sin esto el precursor se normaliza a su Hs capado con
## periodo corto (~50 m de longitud), la mascara de bandas largas lo filtra
## entero, y el «anuncio» es exactamente cero — medido, no teorico.
##
## [b]Por que solo las largas:[/b] la ondulacion larga viaja mas rapido que el
## grupo que la genero y recorre miles de km perdiendo poca energia; el rizado
## corto se disipa en decenas. Por eso un mar de fondo anuncia tormentas que
## todavia estan a horas, y por eso adelantarlo ENTERO —rizado incluido— seria
## simplemente traer la tormenta antes, no telegrafiarla.
func set_sea_state(hs: float, choppiness: float, hs_swell: float = -1.0,
		hs_origen: float = -1.0) -> void:
	if count == 0:
		return

	# Espectro JONSWAP. El pico se desplaza hacia olas LARGAS al subir el
	# viento, igual que en el mar de verdad, y como solo cambian las amplitudes
	# la transicion es continua: no hay popping ni saltos de fase.
	#
	# La parte que de verdad importa visualmente es la COLA w^-5. Una envolvente
	# simetrica (una gaussiana en log de la longitud de onda, por ejemplo) deja
	# toda la energia en el swell largo, y entonces un mar de Hs 9 m se ve PLANO
	# desde cubierta porque son colinas de 200 m sin un solo detalle encima. La
	# cola de alta frecuencia es lo que le da textura al agua.
	var peak_period: float = 4.0 * sqrt(maxf(hs, 0.04)) # Tp ~ 4*sqrt(Hs)
	var wp: float = TAU / peak_period
	var gamma := 3.3

	var base := _amplitudes_jonswap(hs, wp, gamma)

	# La MAR DE FONDO, si viene una tormenta. Se toma el maximo por modo y no la
	# suma: sumar dos espectros normalizados a Hs distintos da un Hs total que
	# no es ninguno de los dos, y el dial dejaria de significar lo que dice.
	if hs_swell > hs:
		# El periodo sale del ORIGEN (la tormenta), no de la energia capada.
		var origen: float = maxf(hs_origen, hs_swell)
		var wp_swell: float = TAU / (4.0 * sqrt(maxf(origen, 0.04)))
		var swell := _amplitudes_jonswap(hs_swell, wp_swell, gamma)
		for i in count:
			var largo: float = smoothstep(SWELL_BANDA_CORTA, SWELL_BANDA_LARGA, _wavelength[i])
			base[i] = maxf(base[i], swell[i] * largo)

	var hs_to_amp := 4.0 / sqrt(2.0)
	var actual_sum_sq: float = 0.0
	for i in count:
		# Limite de rotura por ola: una ola no puede ser mas alta que ~L/7. Al
		# saturar, el mar deja de crecer en vez de explotar. Es fisicamente
		# correcto y ademas impide que la fisica se vuelva loca en furia alta.
		var a: float = minf(base[i], _wavelength[i] * WAVE_BREAK_RATIO)
		_amp[i] = a
		actual_sum_sq += a * a

	# Sale del reparto REAL, asi que con mar de fondo adelantada el HUD marca el
	# Hs que el barco siente de verdad, no el que la furia prometeria.
	measured_hs = hs_to_amp * sqrt(actual_sum_sq)

	# Q uniforme tal que suma(Q * a * k) == choppiness. Repartirlo asi (en vez de
	# fijar un Q por ola) mantiene el total acotado sea cual sea la mezcla.
	var s: float = 0.0
	for i in count:
		s += _amp[i] * _k[i]
	_q = 0.0 if s <= 0.0 else clampf(choppiness, 0.0, STEEPNESS_LIMIT) / s


## Suma de steepness. Por encima de STEEPNESS_LIMIT la superficie se pliega.
func steepness_sum() -> float:
	var s: float = 0.0
	for i in count:
		s += _q * _amp[i] * _k[i]
	return s


# =============================================================================
#  Evaluacion - espejo exacto de ocean_waves.gdshaderinc
# =============================================================================

## Desplazamiento desde la posicion de reposo [param p]. Devuelve (dx, altura, dz).
func displacement(p: Vector2, t: float) -> Vector3:
	var d := Vector3.ZERO
	for i in count:
		var dir: Vector2 = _dir[i]
		var amp: float = _amp[i]
		var theta: float = _k[i] * dir.dot(p) - _omega[i] * t + _phase[i]
		var c: float = cos(theta)
		d.y += amp * sin(theta)
		d.x += _q * amp * dir.x * c
		d.z += _q * amp * dir.y * c
	return d


## Altura del agua en una coordenada del MUNDO.
##
## Invierte el desplazamiento horizontal por punto fijo. Sin esto, con
## choppiness alta el objeto flota visiblemente AL LADO de la ola en vez de
## encima, y falla justo en tormenta, que es cuando mas importa.
func height_at(world_xz: Vector2, t: float) -> float:
	return displacement(_solve_rest_position(world_xz, t), t).y


## Altura Y velocidad de la superficie en una sola pasada.
##
## La inversion por punto fijo es lo caro de todo el sistema (3 iteraciones x N
## olas), y pedir altura y velocidad por separado la resuelve DOS veces para el
## mismo punto. Cada sonda de flotabilidad necesita las dos cosas en cada tick,
## asi que esto es literalmente la mitad del coste de la fisica del agua.
func sample_at(world_xz: Vector2, t: float) -> Dictionary:
	var p := _solve_rest_position(world_xz, t)
	var height: float = 0.0
	var vel := Vector3.ZERO
	for i in count:
		var dir: Vector2 = _dir[i]
		var amp: float = _amp[i]
		var w: float = _omega[i]
		var theta: float = _k[i] * dir.dot(p) - w * t + _phase[i]
		var s: float = sin(theta)
		var c: float = cos(theta)
		height += amp * s
		vel.y -= amp * w * c
		var qaws: float = _q * amp * w * s
		vel.x += qaws * dir.x
		vel.z += qaws * dir.y
	return {&"height": height, &"velocity": vel}


## Velocidad de la superficie. Amortiguar contra ESTO (y no contra el mundo) es
## lo que hace que un cuerpo cabalgue la ola en vez de parecer pegado, y de paso
## regala las corrientes.
func surface_velocity_at(world_xz: Vector2, t: float) -> Vector3:
	var p := _solve_rest_position(world_xz, t)
	var v := Vector3.ZERO
	for i in count:
		var dir: Vector2 = _dir[i]
		var amp: float = _amp[i]
		var w: float = _omega[i]
		var theta: float = _k[i] * dir.dot(p) - w * t + _phase[i]
		v.y -= amp * w * cos(theta)
		var qaws: float = _q * amp * w * sin(theta)
		v.x += qaws * dir.x
		v.z += qaws * dir.y
	return v


## Normal de la superficie, analitica.
func normal_at(world_xz: Vector2, t: float) -> Vector3:
	var p := _solve_rest_position(world_xz, t)
	var tangent := Vector3(1.0, 0.0, 0.0)
	var binormal := Vector3(0.0, 0.0, 1.0)
	for i in count:
		var dir: Vector2 = _dir[i]
		var amp: float = _amp[i]
		var k: float = _k[i]
		var theta: float = k * dir.dot(p) - _omega[i] * t + _phase[i]
		var qaks: float = _q * amp * k * sin(theta)
		var akc: float = amp * k * cos(theta)

		tangent.x -= qaks * dir.x * dir.x
		tangent.y += akc * dir.x
		tangent.z -= qaks * dir.x * dir.y

		binormal.x -= qaks * dir.x * dir.y
		binormal.y += akc * dir.y
		binormal.z -= qaks * dir.y * dir.y
	return binormal.cross(tangent).normalized()


## Jacobiano del desplazamiento horizontal. J < 0 = la cresta rompe aqui.
## Es el mismo numero que pinta la espuma en el shader: lo que ves es lo que duele.
func jacobian_at(world_xz: Vector2, t: float) -> float:
	return jacobian_en_reposo(_solve_rest_position(world_xz, t), t)


## El jacobiano en una posicion DE REPOSO, sin invertir nada.
##
## Es la mitad que de verdad espeja al shader: `ocean_jacobian()` recibe la
## posicion de reposo directamente, porque en el vertex shader la malla YA esta
## en reposo. `jacobian_at()` existe aparte porque quien pregunta desde el juego
## tiene una posicion de MUNDO (donde esta el barco) y hay que invertir antes.
##
## Estaban fundidas en una sola funcion, y eso hacia imposible compararse con la
## GPU: al darles el mismo punto a las dos, una lo trataba como reposo y la otra
## lo invertia, y el test de paridad acusaba una divergencia de 0.22 que no
## existia. Separarlas es lo que deja al golden comparar lo mismo con lo mismo.
func jacobian_en_reposo(p: Vector2, t: float) -> float:
	var dxdx: float = 0.0
	var dzdz: float = 0.0
	var dxdz: float = 0.0
	for i in count:
		var dir: Vector2 = _dir[i]
		var theta: float = _k[i] * dir.dot(p) - _omega[i] * t + _phase[i]
		var qak: float = _q * _amp[i] * _k[i] * sin(theta)
		dxdx -= qak * dir.x * dir.x
		dzdz -= qak * dir.y * dir.y
		dxdz -= qak * dir.x * dir.y
	return (1.0 + dxdx) * (1.0 + dzdz) - dxdz * dxdz


func _solve_rest_position(world_xz: Vector2, t: float) -> Vector2:
	var p := world_xz
	for _iter in 3:
		var d := displacement(p, t)
		p = world_xz - Vector2(d.x, d.z)
	return p


# =============================================================================
#  Empaquetado para el shader
# =============================================================================

## Los uniforms del shader salen de la MISMA tabla que usa la CPU. Nunca se
## mantienen dos listas de constantes: es asi como empieza la deriva silenciosa.
func pack_a() -> PackedVector4Array:
	var out := PackedVector4Array()
	out.resize(MAX_WAVES)
	for i in count:
		out[i] = Vector4(_dir[i].x, _dir[i].y, _amp[i], _k[i])
	return out


func pack_b() -> PackedVector4Array:
	var out := PackedVector4Array()
	out.resize(MAX_WAVES)
	for i in count:
		out[i] = Vector4(_omega[i], _phase[i], _q, 0.0)
	return out


## Amplitudes JONSWAP normalizadas para un Hs dado, sin aplicar el limite de
## rotura. Extraido para poder evaluar DOS estados de mar (el de ahora y el de
## fondo) con exactamente la misma matematica: si divergieran, la mar de fondo
## seria un espectro distinto y no «el mismo mar mas grande».
func _amplitudes_jonswap(hs: float, wp: float, gamma: float) -> PackedFloat32Array:
	var pesos := PackedFloat32Array()
	pesos.resize(count)
	var sum_sq: float = 0.0
	for i in count:
		var w: float = _omega[i]
		var sigma: float = 0.07 if w <= wp else 0.09
		var r: float = exp(-pow(w - wp, 2.0) / (2.0 * sigma * sigma * wp * wp))
		var s_val: float = pow(w, -5.0) * exp(-1.25 * pow(wp / w, 4.0)) * pow(gamma, r)
		# a = sqrt(2 * S(w) * dw); el factor 2 se absorbe en la normalizacion.
		var peso: float = sqrt(maxf(s_val * _domega[i], 0.0))
		pesos[i] = peso
		sum_sq += peso * peso

	# Hs = 4*sqrt(m0) y m0 = suma(a^2)/2  =>  suma(a^2) = (Hs / 2.8284)^2
	var hs_to_amp := 4.0 / sqrt(2.0)
	var escala: float = 0.0 if sum_sq <= 0.0 else sqrt(pow(hs / hs_to_amp, 2.0) / sum_sq)
	for i in count:
		pesos[i] = pesos[i] * escala
	return pesos
