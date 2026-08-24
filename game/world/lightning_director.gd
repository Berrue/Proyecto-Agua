class_name LightningDirector
extends Node

## Rayos y truenos (docs/CLIMA.md §2, fase C).
##
## [b]Los rayos no se sortean: se DERIVAN.[/b] El tiempo se parte en slots de
## SLOT_SECONDS y un hash de (semilla, slot) decide si hay rayo, de que tipo,
## en que azimut, a que distancia y con cuantos pulsos. Consecuencias:
##
## - Los 6 clientes ven EL MISMO rayo en el mismo instante sin replicar un byte,
##   igual que el oleaje (patron del mod Thunderhead: la semilla del rayo fija
##   hasta su geometria).
## - Es consultable en el FUTURO: el director dramatico puede mirar los slots
##   proximos y "reservar" un rayo para el momento que le interese.
## - Nada de Timer ni de randf() en la programacion: eso daria a cada cliente su
##   propia tormenta (regla 4 del repo).
##
## [b]El destello es PROMOCION DE BANDA, no brillo.[/b] Sube 1-2 bandas de la
## rampa cuantizada del agua (uniform global `lightning01`) en vez de aclarar
## con bloom: asi el frame de flash se lee como un cel de anime y, sobre todo,
## el salto de luminancia es un valor DISCRETO y auditable — lo que hace
## verificable el limite fotosensible.
##
## [b]El slot se CONGELA al empezar.[/b] La furia NO es un valor replicado: es
## estado integrado local (rate limit de 0.4/s) que el host gotea a 10 Hz, asi
## que entre dos paquetes las maquinas difieren hasta ~0.04 puntos. Leer la
## furia en vivo dentro del sampler hacia que esa diferencia volteara decisiones
## BOOLEANAS: el rayo existia en una pantalla y no en la otra. Ahora la furia
## entra CUANTIZADA, se muestrea UNA vez al empezar el slot, y a partir de ahi
## destello, bolt y trueno se sirven del mismo dato congelado.
##
## [b]Con un PARTE en vigor esto deja de hacer falta[/b] (docs/CLIMA.md fase D).
## Si hay guion, la furia es funcion pura de t: el sampler la evalua en el `t0`
## del propio slot y el rayo sale identico en las 6 maquinas sin cuantizar nada
## y sin depender de cuando llego un paquete. La cuantizacion sigue viva para
## el carril manual (toybox, debug, escenas sin parte), donde la furia sigue
## siendo estado integrado local y la deriva sigue existiendo.
##
## Ojo con el orden: la furia se pide para el `t0` del slot, no para «ahora».
## Con guion eso es lo correcto Y lo consultable; sin guion, `Ocean.furia_en()`
## devuelve la de ahora, que es la respuesta honesta cuando no hay futuro
## escrito.
##
## [b]Limite fotosensible (XAG 118 / WCAG 2.3.1), no negociable:[/b] nunca mas
## de 3 destellos en una ventana de 1 s. Se cumple POR CONSTRUCCION (MAX_PULSES
## y el margen dentro del slot), no por tuning. Y existe `reduce_flashes` desde
## el primer build — jamas etiquetado como "apto para epilepsia" (es
## responsabilidad legal): describe el efecto, no promete seguridad medica.

## Cada cuanto se le pregunta al hash si hay rayo.
const SLOT_SECONDS := 6.0
## El instante del rayo vive dentro de [MARGIN, SLOT - MARGIN]: garantiza al
## menos 2*MARGIN entre dos eventos consecutivos, o sea que dos tandas de
## pulsos JAMAS caen en la misma ventana de 1 s.
const SLOT_MARGIN := 1.2
## Techo de pulsos por evento. Un rayo real tiene 3-4 return strokes separados
## 40-50 ms; nos quedamos en 3 porque el cuarto ya viola el criterio WCAG.
const MAX_PULSES := 3
const PULSE_GAP := 0.045
const PULSE_DECAY := 0.055
const TAIL_DECAY := 0.32
const TAIL_LEVEL := 0.16
## Reparto sheet/bolt: solo el 25 % de los rayos reales son nube-tierra, asi
## que la mayoria son resplandores sin geometria (y ademas son los baratos).
const BOLT_CHANCE := 0.28
const SOUND_SPEED := 343.0
## Intervalo minimo entre dos rayos forzados desde el HUD.
const MIN_FORCED_GAP := 1.5
## Paso de cuantizacion de la furia que entra al sampler. Grueso a proposito:
## tiene que ser MAYOR que la deriva de red entre dos paquetes (~0.04).
const FURY_QUANTUM := 0.5

## [b]El «lightning jump»[/b] (NASA/NOAA, docs/CLIMA.md §2.4): un salto brusco de
## la frecuencia de rayos PRECEDE a la meteorologia severa entre 10 y 30
## minutos. La naturaleza usa la cadencia como telegrafia, y es de las pocas
## señales de tormenta que se leen desde muy lejos.
##
## Solo se puede implementar con PARTE: hace falta saber que furia VA a haber,
## no la de ahora. Sin guion, `Ocean.furia_swell()` devuelve la furia actual, el
## salto sale cero y el director se comporta exactamente como antes.
const VENTANA_SALTO := 900.0
## Cuanta de la actividad electrica de la tormenta que viene ya se ve desde
## aqui. No es un numero de gameplay: es lo lejos que llega un resplandor de
## nube contra lo lejos que llega el ruido o la ola.
const ANTICIPO := 0.75
## Mascara de luz del destello: todo MENOS la capa 2, que es la del oceano. El
## agua ya sube de banda con lightning01; si ademas la iluminara esta luz, el
## termino `ambient_level` del shader sumaria un valor PLANO a toda la
## superficie (mire donde mire la normal) y borraria las bandas que el destello
## acaba de promocionar.
const FLASH_CULL_MASK := 0xFFFFF & ~0b10

@export_group("Nodos")
## Luz dedicada al rayo. Aparte del sol a proposito: el ciclo dia/noche escribe
## la energia del sol cada frame y se pisarian. Sin sombras — un pico de 2
## frames no justifica re-renderizar el shadow map.
@export var flash_light_path: NodePath
@export var environment_path: NodePath

@export_group("Accesibilidad")
## Sustituye el multi-pulso por una rampa unica y suave, con la mitad de delta.
## La telegrafia (retardo hasta el trueno, chisporroteo del metal) sobrevive
## intacta: la opcion no penaliza jugabilidad.
@export var reduce_flashes: bool = false

@export_group("Cadencia")
## Furia por debajo de la cual no hay actividad electrica.
@export var fury_threshold: float = 3.0
## Probabilidad de rayo por slot en furia 10.
@export var max_rate: float = 0.75
## Energia extra de la luz de flash en el pico.
@export var flash_light_energy: float = 3.2
## Cuanto multiplica el cielo en el pico.
@export var flash_sky_boost: float = 2.4

var _light: DirectionalLight3D
var _env: Environment
var _base_bg: float = 1.0
var _fired: Dictionary = {}
## Slots ya resueltos. Un slot se congela la primera vez que se consulta DESPUES
## de haber empezado; los futuros se recalculan (son prevision, no compromiso).
## Destello, bolt y trueno leen todos de aqui: antes el audio estaba congelado
## pero la imagen se re-derivaba cada frame, asi que un cambio de furia en mitad
## del destello partia imagen y sonido.
var _slots: Dictionary = {}
var _prev_t: float = 0.0
## Vencimiento del trueno forzado, en sim_time. No un SceneTreeTimer: ese corre
## en tiempo real, ignora la pausa y sobrevive a la muerte del nodo.
var _forced_thunder_due: float = -1.0
var _forced_thunder_dist: float = 0.0
## Rayo forzado por el HUD de debug. No rompe el determinismo de los demas:
## es una capa aparte que solo existe en la maquina que aprieta el boton.
var _forced_t0: float = -1000.0
var _forced: Dictionary = {}
var _bolt: MeshInstance3D
var _bolt_mat: ShaderMaterial
var _bolt_texs: Array[ImageTexture] = []


func _ready() -> void:
	_light = get_node_or_null(flash_light_path) as DirectionalLight3D
	var we := get_node_or_null(environment_path) as WorldEnvironment
	if we != null:
		_env = we.environment
		if _env != null:
			_base_bg = _env.background_energy_multiplier
	if _light != null:
		_light.shadow_enabled = false
		_light.light_energy = 0.0
		_light.light_cull_mask = FLASH_CULL_MASK
	# Cambiar de semilla (unirse a una partida) invalida todo lo congelado.
	Ocean.waves_regenerated.connect(_reset_state)
	_prev_t = Ocean.sim_time
	_build_bolt()


func _reset_state() -> void:
	_slots.clear()
	_fired.clear()
	_forced_t0 = -1000.0
	_forced_thunder_due = -1.0


func _process(_delta: float) -> void:
	var t: float = Ocean.sim_time
	# El reloj lo escribe el host: al unirse SALTA, y lo congelado deja de valer.
	if absf(t - _prev_t) > SLOT_SECONDS:
		_reset_state()
	_prev_t = t

	# Resolver (y por tanto congelar) el slot en curso antes de nada.
	var _cur: Dictionary = _strike(int(floor(t / SLOT_SECONDS)))
	var flash: float = intensity_at(t)

	if _light != null:
		_light.light_energy = flash * flash_light_energy
	if _env != null:
		_env.background_energy_multiplier = _base_bg * (1.0 + flash * (flash_sky_boost - 1.0))
	# El uniform global lo leen los materiales toon (el agua promociona banda).
	RenderingServer.global_shader_parameter_set(&"lightning01", flash)

	_fire_due_thunder(t)
	_update_bolt(t)


## Si el director muere en pleno destello, el uniform global y el cielo se
## quedarian CLAVADOS en su valor de pico: el mundo entero permaneceria
## quemado y nada lo devolveria.
func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set(&"lightning01", 0.0)
	if _env != null:
		_env.background_energy_multiplier = _base_bg
	if _light != null:
		_light.light_energy = 0.0


# =============================================================================
#  El rayo visible
# =============================================================================

## Las siluetas se hornean al arrancar (misma filosofia que el audio: cero
## assets). Cuatro variantes bastan: la mayoria de los destellos son
## resplandor sin geometria, asi que un bolt se ve cada varios eventos.
const BOLT_VARIANTS := 4
const BOLT_LIFE := 0.45
const BOLT_REVEAL := 0.10


func _build_bolt() -> void:
	for i in BOLT_VARIANTS:
		_bolt_texs.append(_make_bolt_texture(1000 + i * 977))

	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	_bolt_mat = ShaderMaterial.new()
	_bolt_mat.shader = load("res://game/world/lightning_bolt.gdshader")
	_bolt_mat.set_shader_parameter(&"bolt_tex", _bolt_texs[0])
	_bolt = MeshInstance3D.new()
	_bolt.mesh = quad
	_bolt.material_override = _bolt_mat
	_bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bolt.visible = false
	# Diferido: en _ready la escena aun se instancia y add_child directo falla.
	add_child.call_deferred(_bolt)


## El rayo activo AHORA, si lo hay: el del slot actual, el del anterior (su
## vida puede cruzar la frontera) o el forzado por el HUD.
func _active_bolt(t: float) -> Dictionary:
	var fage: float = t - _forced_t0
	# Acotado por LOS DOS lados: sin cota inferior, cualquier t anterior al
	# forzado cumplia la condicion y el rayo de debug secuestraba el canal si el
	# reloj retrocedia (al unirse a una partida, por ejemplo).
	if fage >= 0.0 and fage <= BOLT_LIFE:
		return {
			&"t0": _forced_t0,
			&"azimuth": float(_forced.get(&"azimuth", 0.6)),
			&"distance": float(_forced.get(&"distance", 400.0)),
			&"seed": 7,
		}
	var slot: int = int(floor(t / SLOT_SECONDS))
	for s in [slot, slot - 1]:
		var st: Dictionary = _strike(s)
		if not bool(st.get(&"active", false)) or not bool(st.get(&"bolt", false)):
			continue
		var age: float = t - float(st[&"t0"])
		if age >= 0.0 and age <= BOLT_LIFE:
			return st
	return {}


func _update_bolt(t: float) -> void:
	if _bolt == null or not _bolt.is_inside_tree():
		return
	var st: Dictionary = _active_bolt(t)
	if st.is_empty():
		_bolt.visible = false
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		_bolt.visible = false
		return

	var age: float = t - float(st[&"t0"])
	# Muy lejos el rayo seria un pelo invisible: se acerca para el DIBUJO (su
	# distancia real sigue mandando en el retardo del trueno, que es lo que el
	# jugador usa para medir).
	var d: float = minf(float(st[&"distance"]), 520.0)
	var h: float = clampf(d * 0.75, 40.0, 320.0)
	var az: float = float(st[&"azimuth"])
	var pos := cam.global_position + Vector3(sin(az), 0.0, cos(az)) * d
	pos.y = h * 0.5

	_bolt.scale = Vector3(h * 0.28, h, 1.0)
	_bolt.global_position = pos
	# Encara a la camara girando SOLO en Y: inclinarlo delataria el billboard.
	_bolt.rotation = Vector3(0.0, atan2(
		cam.global_position.x - pos.x, cam.global_position.z - pos.z), 0.0)

	var variant: int = int(st.get(&"seed", 0)) % BOLT_VARIANTS
	_bolt_mat.set_shader_parameter(&"bolt_tex", _bolt_texs[absi(variant)])
	_bolt_mat.set_shader_parameter(&"y_progress", clampf(age / BOLT_REVEAL, 0.0, 1.0))
	# Escalones discretos, no fundido: 2 tramos y fuera.
	var fade: float = 1.0
	if age > BOLT_LIFE * 0.45:
		fade = 0.55
	if age > BOLT_LIFE * 0.78:
		fade = 0.0
	_bolt_mat.set_shader_parameter(&"fade_step", fade)
	_bolt.visible = fade > 0.0


## Silueta por desplazamiento de punto medio (la receta clasica de Tuts+):
## puntos a lo largo de la vertical desplazados en perpendicular, mas ramas
## que se afinan hacia la punta.
func _make_bolt_texture(seed_val: int) -> ImageTexture:
	const W := 64
	const H := 256
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	var main := _midpoint_path(rng, Vector2(W * 0.5, 0.0),
		Vector2(W * 0.5 + rng.randf_range(-10.0, 10.0), H - 1.0), 6, W * 0.20)
	_stamp_path(img, main, 1.0)

	for _b in rng.randi_range(2, 4):
		var i: int = rng.randi_range(int(main.size() * 0.15), int(main.size() * 0.8))
		var start: Vector2 = main[i]
		# Las ramas se acortan hacia abajo: nacen gruesas arriba y mueren cerca
		# de la punta, como en un rayo real.
		var remain: float = 1.0 - float(i) / float(main.size())
		var dir := Vector2(rng.randf_range(-0.75, 0.75), 1.0).normalized()
		var finish: Vector2 = start + dir * (float(H) * 0.32 * remain)
		_stamp_path(img, _midpoint_path(rng, start, finish, 4, W * 0.09), 0.65)

	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _midpoint_path(rng: RandomNumberGenerator, a: Vector2, b: Vector2,
		depth: int, sway: float) -> PackedVector2Array:
	var pts := PackedVector2Array([a, b])
	var amp: float = sway
	for _d in depth:
		var next := PackedVector2Array()
		for i in pts.size() - 1:
			var p0: Vector2 = pts[i]
			var p1: Vector2 = pts[i + 1]
			var mid: Vector2 = (p0 + p1) * 0.5
			var perp := (p1 - p0).normalized().orthogonal()
			next.append(p0)
			next.append(mid + perp * rng.randf_range(-amp, amp))
		next.append(pts[pts.size() - 1])
		pts = next
		amp *= 0.55
	return pts


## Pincel radial pequeño con max(): los cruces de ramas no se suman ni saturan.
func _stamp_path(img: Image, pts: PackedVector2Array, intensity: float) -> void:
	var w: int = img.get_width()
	var h: int = img.get_height()
	for i in pts.size() - 1:
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[i + 1]
		var steps: int = maxi(int(p0.distance_to(p1)), 1)
		for s in steps + 1:
			var p: Vector2 = p0.lerp(p1, float(s) / float(steps))
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var x: int = int(p.x) + dx
					var y: int = int(p.y) + dy
					if x < 0 or y < 0 or x >= w or y >= h:
						continue
					var fall: float = 1.0 - Vector2(dx, dy).length() / 2.6
					if fall <= 0.0:
						continue
					var v: float = intensity * fall
					var cur: float = img.get_pixel(x, y).r
					if v > cur:
						img.set_pixel(x, y, Color(v, v, v, 1.0))


# =============================================================================
#  La programacion determinista
# =============================================================================

## El rayo del slot [param i], congelado si el slot ya empezo.
func _strike(i: int) -> Dictionary:
	if _slots.has(i):
		return _slots[i]
	var st: Dictionary = strike_at_slot(i)
	# Solo se congela lo que YA empezo: congelar el futuro lo ataria a la furia
	# de hoy, y la consulta a futuro debe seguir siendo una prevision viva.
	if float(i) * SLOT_SECONDS <= Ocean.sim_time:
		_slots[i] = st
	return st


## Derivacion pura de (semilla, slot, furia cuantizada). El juego usa _strike(),
## que ademas congela; esta queda publica para los tests.
func strike_at_slot(i: int) -> Dictionary:
	var out := {&"active": false}
	var fury: float = _furia_del_slot(i)
	# La CADENCIA la manda la tormenta que viene; la DISTANCIA, la de aqui. De
	# esa separacion sale sola la imagen correcta: relampagos de nube mudos en
	# el horizonte con el mar todavia planchado.
	var electrica: float = _furia_electrica_del_slot(i, fury)
	if electrica < fury_threshold:
		return out
	var span: float = maxf(10.0 - fury_threshold, 0.001)
	var rate: float = max_rate * pow(clampf((electrica - fury_threshold) / span, 0.0, 1.0), 1.4)
	if _rand(i, 1) >= rate:
		return out

	var t0: float = float(i) * SLOT_SECONDS + SLOT_MARGIN \
		+ _rand(i, 2) * (SLOT_SECONDS - 2.0 * SLOT_MARGIN)

	# Cruce CONTINUO hacia la tormenta encima. Antes era un escalon duro en
	# furia 6 entre dos rangos DISJUNTOS (1400-3000 m y 180-2200 m): dos
	# maquinas a un lado y otro del umbral daban, para el MISMO destello,
	# truenos separados varios segundos y con clip distinto.
	var near: float = clampf((fury - 5.0) / 2.5, 0.0, 1.0)
	var r3: float = _rand(i, 3)
	var dist: float = lerpf(
		lerpf(1400.0, 3000.0, r3),
		lerpf(180.0, 2200.0, pow(r3, 1.6)),
		near)
	return {
		&"active": true,
		&"t0": t0,
		&"pulses": 2 + int(_rand(i, 4) * float(MAX_PULSES - 1)),
		&"azimuth": _rand(i, 5) * TAU,
		&"distance": dist,
		# Los bolts tambien aparecen de forma gradual, no de golpe en furia 6.
		&"bolt": _rand(i, 6) < BOLT_CHANCE * near,
		&"seed": i,
	}


## La furia con la que se decide un slot.
##
## CON PARTE: se evalua el guion en el instante en que el slot empieza. Es puro,
## identico en todas las maquinas, y ademas consultable — un slot dentro de dos
## minutos se resuelve igual hoy que cuando llegue.
##
## SIN PARTE: la furia es estado integrado local que el host gotea a 10 Hz, asi
## que entra CUANTIZADA. Dos maquinas cuya furia difiera por la deriva (~0.04)
## caen en el mismo escalon y deciden lo mismo. Acota la divergencia sin
## eliminarla; es lo mejor que se puede hacer sin guion.
func _furia_del_slot(i: int) -> float:
	var t0: float = float(i) * SLOT_SECONDS
	if Ocean.tiene_parte():
		return clampf(Ocean.furia_en(t0), 0.0, 10.0)
	return floorf(clampf(Ocean.fury, 0.0, 10.0) / FURY_QUANTUM) * FURY_QUANTUM


## La furia que decide CUANTOS rayos hay en un slot, que no es la misma que
## decide donde caen.
##
## Es el maximo entre la furia de aqui y una fraccion de la que viene en los
## proximos 15 minutos. Consecuencias, todas deseadas y ninguna con codigo
## especial:
##
## - Con mar de furia 2 y un temporal de 9 acercandose, la electrica sube a
##   ~6.75: hay actividad de sobra ANTES de que el mar se entere.
## - Pero `near` se calcula con la furia de AQUI, que sigue siendo 2, asi que
##   esos rayos salen todos en el rango lejano (1400-3000 m)...
## - ...y `bolt` se multiplica por ese mismo `near` = 0, asi que son TODOS
##   resplandores de nube sin geometria. Que es exactamente lo que dice la
##   investigacion: sheet lightning silencioso en el horizonte.
##
## Sin parte no hace nada: `furia_swell` devuelve la furia actual, el maximo es
## ella misma, y la cadencia es la de siempre.
func _furia_electrica_del_slot(i: int, fury: float) -> float:
	if not Ocean.tiene_parte():
		return fury
	var t0: float = float(i) * SLOT_SECONDS
	var viene: float = Ocean.furia_swell(t0, VENTANA_SALTO)
	return maxf(fury, viene * ANTICIPO)


## Intensidad del destello en un instante ARBITRARIO, 0..1. Pura: sirve para
## el frame actual y para consultar el futuro.
func intensity_at(t: float) -> float:
	var best: float = 0.0
	var slot: int = int(floor(t / SLOT_SECONDS))
	# Se miran el slot actual y el anterior: la cola de un destello puede
	# cruzar la frontera.
	for s in [slot, slot - 1]:
		var st: Dictionary = _strike(s)
		if not bool(st.get(&"active", false)):
			continue
		best = maxf(best, _envelope(t - float(st[&"t0"]), int(st[&"pulses"])))
	var fage: float = t - _forced_t0
	if fage >= 0.0:
		best = maxf(best, _envelope(fage, int(_forced.get(&"pulses", 3))))
	return clampf(best, 0.0, 1.0)


## Envolvente temporal del destello. Multi-pulso porque un rayo real son 3-4
## return strokes separados 40-50 ms: ese parpadeo ES la firma del relampago.
func _envelope(dt: float, pulses: int) -> float:
	if dt < 0.0 or dt > 2.5:
		return 0.0
	if reduce_flashes:
		# Rampa unica: 50 ms de ataque, ~300 ms de caida, mitad de delta.
		var rise: float = clampf(dt / 0.05, 0.0, 1.0)
		return 0.5 * rise * exp(-maxf(dt - 0.05, 0.0) / 0.3)
	var total: float = 0.0
	var n: int = clampi(pulses, 1, MAX_PULSES)
	for k in n:
		var tk: float = float(k) * PULSE_GAP
		if dt < tk:
			continue
		var peak: float = 1.0 - 0.2 * float(k)
		total = maxf(total, peak * exp(-(dt - tk) / PULSE_DECAY))
	total = maxf(total, TAIL_LEVEL * exp(-dt / TAIL_DECAY))
	return total


# =============================================================================
#  El trueno: se agenda por la distancia de CADA oyente
# =============================================================================

## El sonido tarda d/343: ver el destello y contar hasta el trueno es
## telegrafia diegetica de la distancia, y sale gratis porque cada cliente
## deriva el mismo rayo y aplica SU propio retardo.
func _fire_due_thunder(t: float) -> void:
	var slot: int = int(floor(t / SLOT_SECONDS))

	# Solo suenan truenos de slots CONGELADOS: son los que de verdad se vieron.
	for s in _slots.keys():
		if _fired.has(s):
			continue
		var st: Dictionary = _slots[s]
		if not bool(st.get(&"active", false)):
			continue
		var d: float = float(st[&"distance"])
		if t >= float(st[&"t0"]) + d / SOUND_SPEED:
			WeatherAudio.play_thunder(d)
			_fired[s] = true

	# El trueno del rayo forzado, tambien en sim_time.
	if _forced_thunder_due >= 0.0 and t >= _forced_thunder_due:
		WeatherAudio.play_thunder(_forced_thunder_dist)
		_forced_thunder_due = -1.0

	# Poda por distancia ABSOLUTA: podando solo por debajo, las claves del
	# futuro (que aparecen si el reloj salta hacia atras) serian inmortales.
	for key in _fired.keys():
		if absi(int(key) - slot) > 6:
			_fired.erase(key)
	for key in _slots.keys():
		if absi(int(key) - slot) > 6:
			_slots.erase(key)


# =============================================================================
#  Debug
# =============================================================================

## Fuerza un rayo AHORA a la distancia dada. Solo para el HUD: no toca la
## secuencia determinista, se suma encima.
func force_strike(distance_m: float) -> void:
	# El techo de destellos vale TAMBIEN para el boton de debug: aporreandolo
	# se podrian encadenar 5 destellos en un segundo, que es exactamente lo que
	# el resto del sistema garantiza por construccion que no pasa.
	var now: float = Ocean.sim_time
	var gap: float = now - _forced_t0
	if gap >= 0.0 and gap < MIN_FORCED_GAP:
		return
	# Y NO BASTA con separarlo del forzado anterior: intensity_at() combina las
	# dos capas con maxf, asi que un forzado encima de uno programado apila 3+3
	# pulsos dentro de la misma ventana de 1 s. El techo fotosensible vale
	# tambien para el boton de debug.
	if intensity_at(now) > 0.02:
		return
	var slot_now: int = int(floor(now / SLOT_SECONDS))
	for s in [slot_now - 1, slot_now, slot_now + 1]:
		var st: Dictionary = _strike(s)
		if bool(st.get(&"active", false)) and absf(now - float(st[&"t0"])) < MIN_FORCED_GAP:
			return
	_forced_t0 = now
	# El rayo de debug cae DELANTE de la camara (con un sesgo lateral para que
	# no tape el centro de la vista): forzar uno que aparece a tu espalda no
	# sirve para juzgar nada.
	var az: float = 0.6
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var fwd: Vector3 = -cam.global_basis.z
		az = atan2(fwd.x, fwd.z) + 0.35
	_forced = {&"pulses": MAX_PULSES, &"distance": distance_m, &"azimuth": az}
	# El trueno del forzado se agenda en sim_time, como todo lo demas.
	_forced_thunder_due = now + distance_m / SOUND_SPEED
	_forced_thunder_dist = distance_m


## Segundos hasta el proximo rayo, o INF. Es la consulta al futuro que la fase D
## usara para que el director dramatico reserve un rayo.
func seconds_to_next_strike() -> float:
	var t: float = Ocean.sim_time
	var slot: int = int(floor(t / SLOT_SECONDS))
	# Prevision con la furia de AHORA: si el dial se mueve, cambia. Es una
	# estimacion para el HUD y para que el director dramatico mire adelante,
	# no un compromiso.
	for s in range(slot, slot + 12):
		var st: Dictionary = _strike(s)
		if bool(st.get(&"active", false)) and float(st[&"t0"]) > t:
			return float(st[&"t0"]) - t
	return INF


# =============================================================================
#  Hash determinista
# =============================================================================

## 0..1 a partir de (semilla del oceano, slot, sal). Entero de 32 bits mezclado
## a mano: nada de RandomNumberGenerator con estado, que dependeria del orden
## de las llamadas.
func _rand(slot: int, salt: int) -> float:
	var h: int = (Ocean.ocean_seed * 374761393) + (slot * 668265263) + (salt * 2246822519)
	h &= 0xFFFFFFFF
	h = (h ^ (h >> 13)) * 1274126177
	h &= 0xFFFFFFFF
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / 16777215.0
