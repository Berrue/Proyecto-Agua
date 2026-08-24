extends Node

## AUTOLOAD `Ocean` - la UNICA puerta al agua.
##
## Fisica, nado, daño, IA, camara, audio y VFX preguntan aqui y solo aqui. Nadie
## consulta la altura del agua por ningun otro camino, y nada de esto toca la GPU.
##
## [b]Por que no se lee la GPU:[/b] `texture_get_data()` es una parada sincrona, y
## sobre todo cada cliente leeria SU textura de SU GPU con SU frameskip, asi que
## las alturas divergirian entre maquinas sin ningun error ni warning. El barco
## acabaria en sitios distintos en cada pantalla. Aqui el agua es una funcion
## analitica pura, asi que los 6 clientes coinciden replicando una semilla, un
## reloj y un float.
##
## [b]Prohibido[/b] llamar a `Time.get_ticks_msec()` u `OS.get_ticks_msec()` desde
## `addons/ocean/`: arrancan en momentos distintos en cada maquina y producen
## oceanos desfasados minutos. Solo [member sim_time] alimenta el oceano.

signal sea_state_changed()
signal waves_regenerated()
signal events_changed()
## Se emite una vez cuando un tsunami entra en el radio de aviso.
signal tsunami_incoming(seconds_out: float)
## Se emite al fijar, limpiar, suspender o reanudar el parte meteorologico.
signal parte_cambiado()
## El guion llego a su ultimo nudo. La salida es FINITA y esto es su final:
## «se acabo la marea». Se emite UNA vez por parte. Hoy no lo escucha nadie —
## el cierre en puerto es F7— pero el clima ya sabe decir cuando se acaba, que
## era la mitad que faltaba.
signal clima_agotado()

## Escala Douglas: altura significativa (m) para cada punto del dial de furia.
## Se interpola en Hs y NUNCA en velocidad de viento: Hs escala como U^2, asi que
## interpolar U deja el dial muerto de 0 a 5 y explosivo de 8 a 10.
const DOUGLAS_HS: Array[float] = [0.0, 0.1, 0.5, 1.25, 2.5, 4.0, 6.0, 9.0, 14.0, 18.0, 25.0]

## Velocidad de viento (m/s) por punto de furia, de la tabla Beaufort marina de
## NOAA cruzada con Douglas (docs/CLIMA.md §3.4). Aqui SI se interpola en U
## porque es la salida (audio, particulas, empuje), no la fuente de la energia
## del mar: las olas siguen saliendo de DOUGLAS_HS.
const WIND_MS: Array[float] = [0.0, 2.5, 4.5, 8.5, 11.5, 14.5, 19.5, 23.0, 28.0, 33.0, 38.0]

## Cuanto puede moverse el dial por segundo. Sin este limite el mar gana energia
## a saltos y se ve el cambio; con el, crece de forma continua.
const FURY_RATE_LIMIT := 0.4

const WAVE_COUNT := 12

## Reloj de simulacion. En multijugador lo escribe el host (NetworkTime).
var sim_time: float = 0.0

## Semilla del mar. Se replica una vez al unirse y define el oleaje entero.
var ocean_seed: int = 0

var wind_direction_deg: float = 30.0

## Cuanto Hs, COMO MUCHO, puede adelantar la mar de fondo sobre el mar que ya
## hay. En metros y no en puntos de furia, y ahi esta toda la gracia: portar el
## ANTICIPO de los rayos (0.75 de la furia que viene) daba furia 2 con Hs 8,67 m
## — o sea la tormenta entera llegando antes, con el HUD marcando furia 2 y el
## rizado corto aplastado un 42 %. Un tope absoluto se auto-limita solo: en mar
## grande la banda larga ya lleva mas que esto y el resultado es identico al de
## siempre; en mar chico son 1,5 m de cabeceo largo que se sienten y se ven.
const PRECURSOR_HS_MAX := 1.5
## Cuanto futuro mira la mar de fondo. Mas que el frente del cielo (210 s) y
## menos que la cadencia de rayos (900 s): ese es el orden real en que una
## tormenta se anuncia — primero relampaguea el horizonte, despues llega la
## ondulacion larga, despues se ve la pared de nubes, y al final el viento.
const PRECURSOR_VENTANA := 300.0

## Cuanto puede moverse rain01 por segundo. La lluvia arranca y para con rampa
## corta: sin pop visual del moteado, pero lo bastante rapida para que el corte
## de la RETIRADA se sienta "en seco" (~1.5 s desde tormenta plena).
const RAIN_RATE_LIMIT := 0.6

## Periodos (s) y pesos de las rachas. Tres zonas del espectro real de Van der
## Hoven (docs/CLIMA.md §4.1): vaiven lento ~45 s, LA racha visible ~10-20 s,
## y turbulencia de 2-7 s que da textura a bandera y audio. Suma de senos y no
## FastNoiseLite a proposito: es evaluable identica en cualquier maquina y en
## cualquier t (futuro incluido), como el resto del oceano.
const GUST_PERIODS: Array[float] = [47.0, 19.0, 11.0, 7.3, 4.3, 2.6]
const GUST_WEIGHTS: Array[float] = [0.30, 0.24, 0.18, 0.12, 0.09, 0.07]

## Las manchas de racha (cat's paws) y las estrias avanzan casi a la velocidad
## del viento base; algo menos para que se puedan leer venir.
const WIND_DRIFT_SCALE := 0.8

var _proxy := OceanWaveProxy.new()
var _events := OceanEvents.new()
var _warned_tsunami: bool = false

## Tier del tsunami en curso, para que el HUD y el audio sepan de que va.
var current_tier: TsunamiTier = null
var _fury: float = 3.0
var _fury_target: float = 3.0
var _paused: bool = false

# --- Clima (ver seccion mas abajo) -------------------------------------------
## Cuanto llueve, 0..1. La lluvia es INDEPENDIENTE de la furia (decision de
## diseño 2026-08-23: furia 9 con cielo seco es valida — la lluvia es un
## mutador del parte meteorologico, no una consecuencia del dial). Lo fija el
## debug hoy y el parte/director cuando exista (CLIMA.md fase D).
var rain_level: float = 0.0
## Lo escribe el director por acto: la RETIRADA corta la lluvia aunque este
## lloviendo — ese silencio subito telegrafia el tsunami (docs/CLIMA.md §1.2).
var rain_scale: float = 1.0
var _rain: float = 0.0
## Fases de las rachas, muestreadas de la semilla en regenerate(): mismo mar,
## mismas rachas, en las 6 maquinas.
var _gust_phases: PackedFloat32Array = PackedFloat32Array()
## El guion del clima, si lo hay. null = CARRIL MANUAL (toybox, debug, tests):
## todo se comporta exactamente como antes de que el parte existiera.
var _parte: ParteMeteorologico = null
## Proxy aparte para consultar el mar en un instante con OTRA furia. Se crea
## solo si alguien pregunta por el futuro, y con la MISMA semilla: si las fases
## no coinciden, la prediccion seria de un mar distinto.
var _proxy_futuro: OceanWaveProxy = null
var _furia_futura: float = -1.0
var _swell_futuro := Vector2(-1.0, -1.0)
## Ultimo (Hs capado, Hs de origen) de mar de fondo aplicado al banco. La furia
## puede estar quieta y la mar de fondo moverse igual (la ventana se desliza),
## asi que sin esto el precursor solo se actualizaria cuando la furia cambia —
## o sea casi nunca justo en la calma, que es cuando el precursor ES la feature.
var _swell_aplicado := Vector2(-1.0, -1.0)
## `clima_agotado` se emite UNA vez por parte, no cada frame pasado el final.
var _agotado_avisado: bool = false
## Avance acumulado de las manchas de viento sobre el agua, en metros de mundo.
## Es estado integrado (como la propia furia rate-limited): cuando exista el
## guion comprometido de furia (CLIMA.md fase D) pasara a integral cerrada.
var _wind_drift := Vector2.ZERO


func _ready() -> void:
	regenerate(ocean_seed)


func _physics_process(delta: float) -> void:
	if _paused:
		return
	sim_time += delta
	if _parte != null:
		# CARRIL COMPROMETIDO. Nada de rate limit: la pendiente ya viene acotada
		# en el guion, y acotada donde toca (en metros de Hs, no en puntos de
		# dial). Aplicar el limite otra vez aqui haria que el mar persiguiera
		# un blanco que huye a su misma velocidad.
		var f: float = clampf(_parte.valor_en(ParteMeteorologico.FURIA, sim_time), 0.0, 10.0)
		_fury_target = f
		# Umbral para no re-espectrar (y no emitir `sea_state_changed`) 60 veces
		# por segundo: sobre el spline la furia SIEMPRE se esta moviendo un
		# poco. 0.005 de dial son 3.5 cm de Hs en el peor tramo — invisible.
		# Se re-espectra si se movio la furia O la mar de fondo. Lo segundo
		# importa justo cuando lo primero no pasa: con el mar planchado y una
		# tormenta acercandose, la furia esta quieta y el precursor es lo unico
		# que crece.
		var sw := _swell_en(sim_time)
		if absf(f - _fury) > 0.005 or (sw - _swell_aplicado).length() > 0.02:
			_fury = f
			_apply_sea_state()
		# La lluvia tambien sale del guion, pero CON su rampa. El spline ya es
		# suave, asi que `move_toward` lo sigue clavado; el limite solo muerde
		# donde hace falta, que es el escalon de `rain_scale` — el corte de la
		# RETIRADA. Sin rampa ese corte pasaba de 1.1-1.5 s a UN frame, y el
		# moteado del agua da un pop: es justo el pop que RAIN_RATE_LIMIT
		# existe para evitar (docs/CLIMA.md §1.2).
		#
		# `rain_scale` sigue siendo el carril inmediato del director, igual que
		# `force_strike` se suma sobre los rayos deterministas.
		var objetivo: float = clampf(_parte.valor_en(ParteMeteorologico.LLUVIA, sim_time), 0.0, 1.0) \
			* clampf(rain_scale, 0.0, 1.0)
		_rain = move_toward(_rain, objetivo, RAIN_RATE_LIMIT * delta)
		if not _agotado_avisado and parte_agotado():
			_agotado_avisado = true
			clima_agotado.emit()
	else:
		# CARRIL MANUAL. Identico a antes del parte.
		if not is_equal_approx(_fury, _fury_target):
			var step: float = FURY_RATE_LIMIT * delta
			_fury = move_toward(_fury, _fury_target, step)
			_apply_sea_state()
		_rain = move_toward(_rain, rain_target(), RAIN_RATE_LIMIT * delta)
	# Deriva con el viento BASE (sin racha): la furia ya esta rate-limited, asi
	# que el patron avanza suave y no da tirones cuando el dial se mueve.
	_wind_drift += wind_dir_vector() * (wind_base_speed() * WIND_DRIFT_SCALE * delta)


## Vuelve a muestrear longitudes de onda, direcciones y fases. Solo al empezar
## partida: hacerlo en caliente produce un salto visible en la superficie.
func regenerate(new_seed: int) -> void:
	ocean_seed = new_seed
	_proxy.generate(new_seed, WAVE_COUNT, wind_direction_deg)
	# El proxy de consulta al futuro lleva la semilla vieja dentro: dejarlo
	# vivo haria que las predicciones fueran de otro mar sin avisar.
	_proxy_futuro = null
	_furia_futura = -1.0
	# Fases de racha propias, con RNG aparte para no perturbar la secuencia del
	# proxy: cambiar el clima no puede recolocar las olas.
	var rng := RandomNumberGenerator.new()
	rng.seed = new_seed ^ 0x57494E44 # "WIND"
	_gust_phases.resize(GUST_PERIODS.size())
	for i in GUST_PERIODS.size():
		_gust_phases[i] = rng.randf() * TAU
	_apply_sea_state()
	waves_regenerated.emit()


# =============================================================================
#  El dial de furia
# =============================================================================

## Furia del mar, 0 (espejo) a 10 (tsunami). Una sola perilla mueve el mundo.
var fury: float:
	get:
		return _fury
	set(value):
		_tomar_mando_manual("Ocean.fury")
		_fury_target = clampf(value, 0.0, 10.0)


## Salta al valor sin rampa. Solo para debug y para el arranque de partida.
func set_fury_immediate(value: float) -> void:
	_tomar_mando_manual("set_fury_immediate()")
	_fury_target = clampf(value, 0.0, 10.0)
	_fury = _fury_target
	_apply_sea_state()


## Mover la furia a mano con un parte en vigor lo DESCARTA, y lo dice.
##
## CLAUDE.md declara sagrada la perilla del HUD: «en manos de alguien haciendo
## de dios ES la herramienta de validacion del juego». Un guion que la ignorase
## en silencio la volveria inservible — moves el dial, no pasa nada, y a los
## dos frames el parte lo repisa. Decision de diseño (2026-08-24): la mano
## BORRA el guion y lo suyo manda. Nada de suspender-y-reanudar: era poder
## deshacer algo que en la practica nadie quiere deshacer, y el aviso acababa
## recomendando una salida que en red ni siquiera existia.
func _tomar_mando_manual(quien: String) -> void:
	if _parte == null:
		return
	_parte = null
	push_warning(("Ocean: %s con un parte en vigor. El parte queda DESCARTADO: "
		+ "a partir de aqui manda la mano.") % quien)
	# La señal NO es decorativa: es como la capa de red se entera de que el
	# guion murio aqui. Descartarlo en silencio dejaria al host en carril manual
	# goteando una furia que los clientes ignoran (porque su copia del parte
	# seguiria en vigor) — seis mares distintos y cero errores en consola.
	parte_cambiado.emit()


## Altura significativa (m) para UNA furia cualquiera. Estatica y pura: el
## generador del parte la necesita para acotar la pendiente en metros, y esa
## cuenta tiene que salir de esta tabla y no de una copia.
static func hs_para_furia(f: float) -> float:
	f = clampf(f, 0.0, 10.0)
	var i: int = int(floor(f))
	if i >= DOUGLAS_HS.size() - 1:
		return DOUGLAS_HS[-1]
	return lerpf(DOUGLAS_HS[i], DOUGLAS_HS[i + 1], f - float(i))


## Velocidad de viento base (m/s) para UNA furia cualquiera.
static func viento_para_furia(f: float) -> float:
	f = clampf(f, 0.0, 10.0)
	var i: int = int(floor(f))
	if i >= WIND_MS.size() - 1:
		return WIND_MS[-1]
	return lerpf(WIND_MS[i], WIND_MS[i + 1], f - float(i))


## Altura significativa objetivo para la furia actual, en metros.
func target_hs() -> float:
	return hs_para_furia(_fury)


## Hs que el mar alcanza de verdad. Puede quedar por debajo del objetivo porque
## las olas saturan al llegar a su limite de rotura: eso es correcto, un mar real
## tampoco crece sin limite.
func measured_hs() -> float:
	return _proxy.measured_hs


func steepness_sum() -> float:
	return _proxy.steepness_sum()


func _apply_sea_state() -> void:
	var t: float = clampf(_fury, 0.0, 10.0) / 10.0
	# Las crestas se afilan al subir la furia, pero nunca pasan del limite de
	# auto-interseccion: por encima, la inversion por punto fijo deja de
	# converger y la flotabilidad se vuelve caotica.
	var choppiness: float = lerpf(0.15, OceanWaveProxy.STEEPNESS_LIMIT, t)
	_swell_aplicado = _swell_en(sim_time)
	_proxy.set_sea_state(target_hs(), choppiness, _swell_aplicado.x, _swell_aplicado.y)
	sea_state_changed.emit()


## El par (Hs capado, Hs de la tormenta de origen) de la mar de fondo en un
## instante. La energia va acotada a [constant PRECURSOR_HS_MAX] metros sobre
## el mar de ese momento — es un anuncio, no la tormenta llegando antes — pero
## el ORIGEN viaja entero, porque de el sale el periodo: mar de fondo es
## precisamente energia moderada con el periodo de un temporal lejano. Sin
## guion no hay futuro que leer y devuelve el mar de siempre: no-op exacto en
## el carril manual.
func _swell_en(t: float) -> Vector2:
	var hs_ahora: float = hs_para_furia(furia_en(t))
	if not tiene_parte():
		return Vector2(hs_ahora, hs_ahora)
	var origen: float = hs_para_furia(furia_swell(t, PRECURSOR_VENTANA))
	return Vector2(minf(origen, hs_ahora + PRECURSOR_HS_MAX), origen)


## Solo la energia (Hs) de la mar de fondo. Para el HUD y los tests.
func hs_swell_en(t: float) -> float:
	return _swell_en(t).x


# =============================================================================
#  API de consulta - lo unico que el resto del juego necesita saber
# =============================================================================

## Altura del agua bajo (o sobre) una posicion del mundo.
func get_height(world_pos: Vector3) -> float:
	var xz := Vector2(world_pos.x, world_pos.z)
	return _proxy.height_at(xz, sim_time) + _events.height_at(xz, sim_time)


## Altura en un instante ARBITRARIO. Como todo el sistema es funcion pura de t,
## esto permite consultar el FUTURO: es lo que hace posible telegrafiar el
## tsunami sin ningun sistema adicional de prediccion.
##
## [b]Con un parte en vigor la promesa se cumple entera.[/b] Antes tenia un
## asterisco: la capa de eventos (el tsunami) SI era analitica en t, pero el
## oleaje de viento se evaluaba con las amplitudes de AHORA, asi que si la
## furia subia en esos 60 s la respuesta era incorrecta y nadie se enteraba.
## Ahora el mar de viento se re-espectra con la furia que el guion promete para
## ese instante.
func get_height_at(world_pos: Vector3, t: float) -> float:
	var xz := Vector2(world_pos.x, world_pos.z)
	return _proxy_en(t).height_at(xz, t) + _events.height_at(xz, t)


## El banco de olas correspondiente a la furia de un instante.
##
## Devuelve el proxy de siempre salvo que haya parte Y la furia de ese instante
## se aparte de la actual: solo entonces paga un re-espectrado, y sobre un
## proxy aparte para no tocar el mar que la fisica esta usando. El coste queda
## confinado a quien pregunta explicitamente por otro momento.
func _proxy_en(t: float) -> OceanWaveProxy:
	if _parte == null:
		return _proxy
	var f: float = clampf(_parte.valor_en(ParteMeteorologico.FURIA, t), 0.0, 10.0)
	var sw := _swell_en(t)
	# La cache va sobre el PAR (furia, mar de fondo). Con solo la furia, dos
	# instantes con la misma furia y distinto precursor devolverian el mismo
	# mar: `get_height_at()` prediria una altura que no va a pasar, que es la
	# regla 8 rota justo en la funcion que existe para no romperla.
	if absf(f - _fury) < 0.02 and (sw - _swell_aplicado).length() < 0.02:
		return _proxy
	if _proxy_futuro == null:
		# MISMA semilla: si las fases no coinciden, esto predeciria un mar
		# distinto en vez del mismo mar mas tarde.
		_proxy_futuro = OceanWaveProxy.new()
		_proxy_futuro.generate(ocean_seed, WAVE_COUNT, wind_direction_deg)
		_furia_futura = -1.0
	if absf(f - _furia_futura) > 0.001 or (sw - _swell_futuro).length() > 0.001:
		_furia_futura = f
		_swell_futuro = sw
		_proxy_futuro.set_sea_state(hs_para_furia(f),
			lerpf(0.15, OceanWaveProxy.STEEPNESS_LIMIT, f / 10.0), sw.x, sw.y)
	return _proxy_futuro


## Cuanto esta sumergido un punto. Positivo = bajo el agua.
func get_submersion(world_pos: Vector3) -> float:
	return get_height(world_pos) - world_pos.y


func get_displacement(world_xz: Vector2, t: float) -> Vector3:
	return _proxy.displacement(world_xz, t)


## Altura y velocidad de la superficie en UNA sola resolucion del punto fijo.
## Usalo siempre que necesites las dos cosas (o sea, en toda la flotabilidad):
## pedirlas por separado duplica el coste de lo mas caro del sistema.
func sample(world_pos: Vector3) -> Dictionary:
	var xz := Vector2(world_pos.x, world_pos.z)
	var out: Dictionary = _proxy.sample_at(xz, sim_time)
	if _events.has_active():
		out[&"height"] = float(out[&"height"]) + _events.height_at(xz, sim_time)
		out[&"velocity"] = (out[&"velocity"] as Vector3) + _events.velocity_at(xz, sim_time)
	return out


func get_surface_velocity(world_pos: Vector3) -> Vector3:
	var xz := Vector2(world_pos.x, world_pos.z)
	return _proxy.surface_velocity_at(xz, sim_time) + _events.velocity_at(xz, sim_time)


func get_normal(world_pos: Vector3) -> Vector3:
	return _proxy.normal_at(Vector2(world_pos.x, world_pos.z), sim_time)


## Jacobiano del desplazamiento. Menor que 0 = la ola ROMPE aqui.
##
## Es el mismo numero con el que el shader pinta la espuma, asi que la espuma
## marca literalmente donde te va a doler: el feedback visual y el mecanico
## salen del mismo sitio y el jugador siempre puede leer el mar.
func get_breaking(world_pos: Vector3) -> float:
	var xz := Vector2(world_pos.x, world_pos.z)
	return _proxy.jacobian_at(xz, sim_time) - _events.break_penalty_at(xz, sim_time)


func is_breaking(world_pos: Vector3) -> bool:
	return get_breaking(world_pos) < 0.0


# =============================================================================
#  Tsunami
# =============================================================================

## Lanza un tsunami que llegara a [param target] dentro de [param seconds].
##
## Se especifica asi, y no por posicion de origen, porque lo que el diseñador
## quiere decidir es CUANDO llega, no desde donde sale. El origen se calcula
## hacia atras.
## `t0` es el instante en que la cresta pasa por el origen. Por defecto usa el
## reloj de QUIEN LLAMA, que es lo correcto en solitario; en red lo fija el
## host y viaja explicito, porque el reloj del cliente va un retardo de
## interpolacion por detras y la ola saldria tarde — a 45 m/s, 0,12 s son 5,4
## metros de frente desplazado y un error de ETA en cada pantalla.
##
## Y NO se compensa el retardo a proposito: el barco del cliente vive en ese
## mismo pasado, asi que ola y casco se encuentran bien por construccion. Es
## el contrato 2 cobrando.
func spawn_tsunami(target: Vector3, from_direction_deg: float, seconds: float,
		amplitude: float = 18.0, celerity: float = 45.0, width: float = 90.0,
		lead: float = 12.0, spread: float = 9.0, depression: float = 0.55,
		t0: float = -INF) -> int:
	var ang := deg_to_rad(from_direction_deg)
	# El tsunami avanza HACIA el objetivo desde la direccion indicada.
	var dir := Vector2(-cos(ang), -sin(ang))
	var target_xz := Vector2(target.x, target.z)
	# Se le da margen de sobra por detras para que el perfil entero (incluida la
	# depresion que va por delante) este ya formado al entrar en escena.
	var origin := target_xz - dir * (celerity * seconds)
	var idx := _events.spawn(origin, dir, amplitude, celerity, width,
		sim_time if t0 == -INF else t0, lead, spread, depression)
	if idx >= 0:
		_warned_tsunami = false
		events_changed.emit()
	else:
		# Los slots son DOS. Desbordarlos era completamente mudo: ni avisaba ni
		# emitia `events_changed`, asi que un cliente con el hueco quemado veia
		# mar plano mientras su barco, host-autoritativo, subia diecinueve
		# metros. Un fallo asi tiene que gritar.
		push_error("Ocean: no queda hueco de evento libre (MAX_EVENTS=%d). " % OceanEvents.MAX_EVENTS
			+ "El tsunami NO se lanzo — limpia los eventos activos antes.")
	return idx


## Lanza un tsunami de un TIER concreto. Es la via normal: los numeros sueltos de
## `spawn_tsunami()` quedan para debug y para los tests.
func spawn_tsunami_tier(target: Vector3, from_direction_deg: float, seconds: float,
		tier: TsunamiTier, t0: float = -INF) -> int:
	if tier == null:
		push_warning("spawn_tsunami_tier() sin tier: no se lanza nada.")
		return -1
	current_tier = tier
	return spawn_tsunami(target, from_direction_deg, seconds,
		tier.amplitude(), tier.celerity(), tier.width(),
		tier.lead, tier.spread, tier.depression, t0)


# =============================================================================
#  Puertas para la red (docs/RED.md). Todas ADITIVAS: nada de lo de arriba
#  cambia de comportamiento cuando se juega en solitario.
# =============================================================================

## La furia a la que el dial esta yendo, no la que se ve ahora mismo.
func fury_objetivo() -> float:
	return _fury_target


## Fija las DOS furias a la vez. El cliente recibe del host el valor ya rampado
## y su objetivo: metiendo solo el actual por el setter normal, el rate limit
## se aplicaria DOS veces y el mar del cliente perseguiria un blanco que huye a
## su misma velocidad. Y no se usa `set_fury_immediate` porque ese salta toda
## la superficie de golpe.
func set_fury_red(actual: float, objetivo: float) -> void:
	if _parte != null:
		# Con guion en vigor la furia del cable SOBRA: las dos maquinas evaluan
		# el mismo spline en el mismo reloj y llegan al mismo numero solas. Y
		# aceptarla seria peor que redundante — el goteo de 10 Hz metaria un
		# escalon entre paquetes justo en la curva que existe para no tenerlos.
		#
		# Ojo: esto vale porque el parte se replica entero al unirse y al
		# generarlo (ver `_hola` y `Debug.PARTE` en network_manager). Si algun
		# dia una maquina pudiera tener un parte DISTINTO, esto divergiria en
		# silencio, que es justo lo que el parte vino a arreglar.
		return
	_fury = clampf(actual, 0.0, 10.0)
	_fury_target = clampf(objetivo, 0.0, 10.0)
	_apply_sea_state()


## Los eventos en vuelo, para el paquete de bienvenida.
func events_pack() -> Array:
	return _events.pack()


## Planta la tabla de eventos que manda el host (el host es la verdad) y avisa.
##
## El `events_changed.emit()` NO es opcional: es el UNICO camino que empuja los
## uniforms de evento al shader — `apply_frame_to_material` manda tiempo,
## lluvia, racha y viento, pero NO los eventos. Olvidarlo deja la CPU con
## tsunami y la GPU con un espejo: el barco volando sobre agua lisa, sin un
## solo error en ninguna consola.
func events_unpack(datos: Array) -> void:
	_events.unpack(datos)
	_warned_tsunami = false
	events_changed.emit()


## Segundos hasta que la cresta alcance este punto. INF si no hay tsunami.
func time_until_tsunami(world_pos: Vector3) -> float:
	return _events.time_until_crest(Vector2(world_pos.x, world_pos.z), sim_time)


func has_tsunami() -> bool:
	return _events.has_active()


func clear_events() -> void:
	_events.clear_all()
	_warned_tsunami = false
	current_tier = null
	events_changed.emit()


func get_events() -> OceanEvents:
	return _events


# =============================================================================
#  Clima - lluvia y viento (docs/CLIMA.md, fase A)
# =============================================================================
#  Vive aqui y no en un autoload aparte porque deriva EXACTAMENTE de lo que
#  Ocean ya posee y replica: (sim_time, semilla, furia). Un reloj, una pausa,
#  una semilla — y el shader recibe clima y olas por la misma tuberia.

## Intensidad de lluvia 0..1, con rampa (RAIN_RATE_LIMIT). Es lo que leen el
## shader, la niebla y (fase B) el audio y las particulas.
var rain01: float:
	get:
		return _rain


## Objetivo de lluvia: lo que pide el parte (rain_level) recortado por el acto
## (rain_scale). La furia NO entra aqui a proposito.
func rain_target() -> float:
	return clampf(rain_level, 0.0, 1.0) * clampf(rain_scale, 0.0, 1.0)


## Racha 0..1 en un instante ARBITRARIO. Funcion pura de (t, semilla), como la
## altura del agua: consultable en el futuro, asi el silbido de jarcia y las
## manchas sobre el agua pueden ANTICIPAR la racha igual que se telegrafia el
## tsunami.
func gust01_at(t: float) -> float:
	if _gust_phases.is_empty():
		return 0.5
	var n: float = 0.0
	for i in GUST_PERIODS.size():
		n += GUST_WEIGHTS[i] * sin(TAU * t / GUST_PERIODS[i] + _gust_phases[i])
	return clampf(0.5 + 0.5 * n, 0.0, 1.0)


func gust01() -> float:
	return gust01_at(sim_time)


## Velocidad de viento base (m/s) para la furia actual, sin racha.
func wind_base_speed() -> float:
	return viento_para_furia(_fury)


## Velocidad de viento instantanea (m/s): la base respirando con la racha.
## Rango ±30% — un temporal real dobla en las rachas lo que baja en las calmas.
func wind_speed() -> float:
	return wind_base_speed() * (0.7 + 0.6 * gust01())


## Direccion del viento como vector unitario XZ. La base es wind_direction_deg
## (la misma que alinea el espectro JONSWAP); oscila ±12 grados con la octava
## mas lenta de la racha — girar rapido la direccion marea la lectura.
func wind_dir_vector() -> Vector2:
	var wobble: float = 0.0
	if not _gust_phases.is_empty():
		wobble = deg_to_rad(12.0) * sin(TAU * sim_time / GUST_PERIODS[0] + _gust_phases[0])
	var ang := deg_to_rad(wind_direction_deg) + wobble
	return Vector2(cos(ang), sin(ang))


## Avance acumulado del patron de viento sobre el agua (m). Para el shader.
func wind_drift() -> Vector2:
	return _wind_drift


# =============================================================================
#  El parte meteorologico (docs/CLIMA.md fase D)
# =============================================================================
#  El clima deja de ser un valor que alguien escribe cada frame y pasa a ser un
#  guion consultable. Todo esto es ADITIVO: sin parte, el oceano se comporta
#  exactamente como antes.

## Pone un guion en vigor. Desde el frame siguiente, furia y lluvia salen de el.
func fijar_parte(nuevo: ParteMeteorologico) -> void:
	_parte = nuevo
	_agotado_avisado = false
	_proxy_futuro = null
	_furia_futura = -1.0
	_swell_futuro = Vector2(-1.0, -1.0)
	if nuevo != null:
		# Sin esto el mar tardaria un frame en obedecer, y quien fije el parte
		# junto con el reloj (una escena dirigida, una captura) veria la furia
		# vieja en su primer fotograma.
		_fury = clampf(nuevo.valor_en(ParteMeteorologico.FURIA, sim_time), 0.0, 10.0)
		_fury_target = _fury
		# Con `rain_scale` incluido: es la MISMA formula que el bucle. Sin el,
		# quien se unia durante la RETIRADA (rain_scale = 0) veia un fotograma
		# de lluvia que el acto habia cortado.
		_rain = clampf(nuevo.valor_en(ParteMeteorologico.LLUVIA, sim_time), 0.0, 1.0) \
			* clampf(rain_scale, 0.0, 1.0)
		_apply_sea_state()
	parte_cambiado.emit()


## Genera y pone en vigor el parte de una salida. La via normal.
##
## [param duracion] en segundos, o -1 (lo normal) para que la sortee la semilla
## entre 10 y 25 minutos. Que la duracion viva EN EL GENERADOR y no en cada
## llamador es lo que arreglo el numero duplicado: lo tenian a la vez el HUD y
## el manejador de red, con valores que ni siquiera eran intercambiables (en
## solitario mandaba uno y en red el otro).
func generar_parte(techo_furia: float, duracion: float = -1.0,
		desde_ahora: bool = true) -> ParteMeteorologico:
	var nuevo := GeneradorParte.generar(ocean_seed, techo_furia, duracion, _fury,
		sim_time if desde_ahora else 0.0)
	fijar_parte(nuevo)
	return nuevo


func limpiar_parte() -> void:
	fijar_parte(null)


func tiene_parte() -> bool:
	return _parte != null


## El guion ya paso su ultimo nudo. Sigue en vigor y sigue respondiendo —
## `valor_en` mantiene el ultimo valor, que es lo correcto: un parte que se
## acaba deja el mar como lo dejo, no lo devuelve a cero— pero a partir de aqui
## el clima esta CONGELADO y la consulta al futuro ya no promete nada. Hoy
## nadie lo renueva (solo el HUD de debug escribe partes), asi que al menos
## tiene que poder verse.
func parte_agotado() -> bool:
	return _parte != null and sim_time > _parte.duracion()


func parte() -> ParteMeteorologico:
	return _parte


## Furia en un instante arbitrario. Sin parte devuelve la de ahora, que es la
## respuesta honesta: sin guion, la mejor prediccion del futuro es el presente.
func furia_en(t: float) -> float:
	if _parte == null:
		return _fury
	return clampf(_parte.valor_en(ParteMeteorologico.FURIA, t), 0.0, 10.0)


func lluvia_en(t: float) -> float:
	if _parte == null:
		return rain_target()
	return clampf(_parte.valor_en(ParteMeteorologico.LLUVIA, t), 0.0, 1.0) \
		* clampf(rain_scale, 0.0, 1.0)


## Viento base (m/s) en un instante arbitrario, sin racha.
func viento_en(t: float) -> float:
	return viento_para_furia(furia_en(t))


## La furia MAS ALTA que viene en la ventana. Es lo que permite que el mar de
## fondo se adelante a la tormenta (docs/CLIMA.md §3.3): la banda larga del
## oleaje lee el futuro y empieza a crecer antes de que llegue el viento.
func furia_swell(t: float, ventana: float = 240.0) -> float:
	if _parte == null:
		return _fury
	return _parte.furia_swell(t, ventana)


## De donde viene el frente, en grados. Alimenta `front_dir` del cielo.
func rumbo_frente_en(t: float) -> float:
	# `tiene_parte()` y no `_parte != null`: con el guion SUSPENDIDO este era el
	# unico accesor que seguia respondiendo del parte, asi que el cielo dibujaba
	# el frente de una tormenta que el mar ya no iba a tener.
	if not tiene_parte() or not _parte.tiene(ParteMeteorologico.RUMBO):
		return wind_direction_deg
	return _parte.valor_en(ParteMeteorologico.RUMBO, t)


# =============================================================================
#  Puente al shader
# =============================================================================

## Los uniforms salen de la MISMA tabla que usa la CPU. Nunca dos listas.
func apply_to_material(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter(&"wave_a", _proxy.pack_a())
	mat.set_shader_parameter(&"wave_b", _proxy.pack_b())
	mat.set_shader_parameter(&"wave_count", _proxy.count)
	mat.set_shader_parameter(&"ocean_time", sim_time)
	# Una sola perilla normalizada. El shader la mapea entre rangos que el
	# artista controla desde el material, asi que subir la furia oscurece el
	# agua, llena el mar de espuma y afila el detalle sin tocar codigo.
	mat.set_shader_parameter(&"fury01", clampf(_fury / 10.0, 0.0, 1.0))
	# Las bandas de color se normalizan con el estado del mar. Sin esto, con
	# olas de 12 m el gradiente satura y todo el oceano se pinta del color de
	# cresta: las bandas dejan de comunicar altura justo cuando mas importa.
	mat.set_shader_parameter(&"height_scale", 0.6 / maxf(_proxy.measured_hs, 0.4))
	var packed: Array = _events.pack()
	mat.set_shader_parameter(&"event_a", packed[0])
	mat.set_shader_parameter(&"event_b", packed[1])
	mat.set_shader_parameter(&"event_c", packed[2])


## Uniforms que cambian CADA frame (tiempo y clima). Los llama OceanSurface3D
## en _process; separados de apply_to_material() para no re-empaquetar las olas
## enteras 60 veces por segundo.
func apply_frame_to_material(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter(&"ocean_time", sim_time)
	mat.set_shader_parameter(&"rain01", _rain)
	mat.set_shader_parameter(&"gust01", gust01())
	mat.set_shader_parameter(&"wind_dir", wind_dir_vector())
	mat.set_shader_parameter(&"wind_drift", _wind_drift)


func set_paused(value: bool) -> void:
	_paused = value


## Acceso directo al proxy. Solo para tests de paridad y herramientas de debug.
func get_proxy() -> OceanWaveProxy:
	return _proxy
