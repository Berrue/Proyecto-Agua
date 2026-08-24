extends Node

## Arnes de RENDIMIENTO. Es el unico test del repo que no comprueba que algo
## este BIEN, sino que sea BARATO: cronometra la flotabilidad y sale con codigo
## != 0 si se pasa del presupuesto duro de F2.
##
##   godot --headless --path . tests/perf_tests.tscn
##
## [b]Por que headless.[/b] La flotabilidad es fisica pura —`Ocean` (funcion
## analitica) mas `FloatingBody3D`— y no toca la GPU ni una sola vez, asi que se
## mide entera sin RenderingDevice y se puede colgar de CI. La OTRA mitad del
## criterio de F2 (frame time en tormenta) SI necesita ventana y GPU, y por eso
## vive aparte en `tests/capture_perf.tscn`, que no es un test sino un informe.
##
## [b]Por que existe.[/b] F2 tiene dos criterios duros de rendimiento y hasta
## hoy no habia ni una sola medicion de coste en el proyecto: cero `ticks_usec`
## en veintiun arneses, todos de correccion. Y el siguiente trabajo de F2 es el
## clipmap, que multiplica la geometria del mar por ~8. Estos numeros son la
## LINEA BASE contra la que se va a comparar, y por eso van ANTES y no despues:
## una linea base tomada despues del cambio no es una linea base.
##
## [b]La regla 2 no aplica aqui.[/b] La prohibicion de `Time.get_ticks_msec()`
## es DENTRO de `addons/ocean/` y es sobre ALIMENTAR al oceano: el reloj del
## agua es `Ocean.sim_time` y solo ese, porque `ticks` arranca en un instante
## distinto en cada maquina y desincroniza las seis pantallas. Cronometrar
## codigo desde `tests/` es otra cosa: aqui el reloj no entra en ninguna
## formula, solo cuenta microsegundos de pared y se tira.

# =============================================================================
#  El presupuesto (docs/PLAN.md, criterios duros de F2)
# =============================================================================

## Presupuesto de la flotabilidad, en microsegundos por tick de fisica.
## Textual de F2: «flotabilidad <2 ms con 200 sondas».
##
## A 120 Hz (project.godot) el tick entero dura 8333 us, asi que 2 ms son el
## 24 % del tick: es un TECHO con holgura para que quepan el resto de sistemas
## del host, no un objetivo al que acercarse.
const PRESUPUESTO_USEC := 2000.0

## Las sondas del criterio. Es el presupuesto del HOST: el cliente interpola los
## props y solo necesita ~10 sondas (jugador local, camara y audio), asi que
## este numero no se le puede exigir a la maquina mas lenta de la partida.
const SONDAS_OBJETIVO := 200

## Barriles necesarios para llegar a 200 sondas exactas: el barco aporta 8 y
## cada barril 2 (ProbeTop + ProbeBottom). 8 + 96*2 = 200.
const BARRILES := 96

## Furia a la que se mide el criterio. Tormenta y no calma a proposito: con mar
## plano la mitad de las sondas quedan sobre el agua y salen por el `continue`
## de `FloatingBody3D`, asi que medir en calma da un numero barato por la razon
## equivocada.
const FURIA_TORMENTA := 9.0

# =============================================================================
#  Parametros de la medicion
# =============================================================================

## Semilla explicita (regla 4). Una linea base tiene que ser reproducible entre
## ejecuciones y comparable contra la de despues del clipmap.
const SEMILLA := 20260824

## Ticks de asentado antes de medir nada. Durante la caida inicial casi ninguna
## sonda esta mojada y el coste sale artificialmente bajo.
const SETTLE_TICKS := 900

## Ticks medidos por escenario. Son ticks de fisica reales: 240 a 120 Hz son
## 2 s de reloj, bastante para que un p99 signifique algo sin que el arnes se
## eternice.
const MUESTRAS := 240

## Ticks que se corren y se TIRAN al empezar cada escenario. Los primeros pagan
## el reacomodo de los cuerpos al nuevo estado del mar y la cache fria.
const CALENTAMIENTO := 60

## Repeticiones del micro-benchmark del campo de olas.
const MICRO_REPETICIONES := 200

var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0
var _sumidero: float = 0.0 ## Acumula resultados para que nada parezca codigo muerto.


func _ready() -> void:
	print_rich("[b]--- Pruebas de rendimiento (criterios duros de F2) ---[/b]")
	_print_entorno()
	_test_micro_campo_de_olas()
	await _test_coste_flotabilidad()
	_report()


func _check(condition: bool, label: String, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("  ok    %s" % label)
	else:
		var line := "  FALLO %s%s" % [label, ("  ->  " + detail) if detail != "" else ""]
		print(line)
		_failures.append(label + (" :: " + detail if detail != "" else ""))


func _report() -> void:
	print("")
	if _failures.is_empty():
		print_rich("[color=green][b]%d/%d comprobaciones OK[/b][/color]" % [_checks, _checks])
		get_tree().quit(0)
	else:
		print_rich("[color=red][b]%d de %d comprobaciones han fallado:[/b][/color]" % [
			_failures.size(), _checks])
		for f in _failures:
			print("   - " + f)
		get_tree().quit(1)


## Sin esto los numeros no significan nada: el coste depende de la CPU, de si el
## binario es debug (GDScript paga comprobaciones extra) y del tick rate.
func _print_entorno() -> void:
	print("")
	print("  Godot %s  |  build %s  |  %s  |  %d Hz  |  %d olas" % [
		String(Engine.get_version_info()["string"]),
		"debug" if OS.has_feature("debug") else "release",
		String(ProjectSettings.get_setting("physics/3d/physics_engine", "?")),
		Engine.physics_ticks_per_second,
		Ocean.WAVE_COUNT])
	print("  CPU: %s" % OS.get_processor_name())
	print("  presupuesto: %.0f us/tick con %d sondas (el tick dura %.0f us)" % [
		PRESUPUESTO_USEC, SONDAS_OBJETIVO,
		1e6 / float(maxi(Engine.physics_ticks_per_second, 1))])
	if OS.has_feature("debug"):
		print("  OJO: build debug. Los numeros son CONSERVADORES; en export salen mas bajos.")
	print("")


# =============================================================================
#  1. El campo de olas solo, sin fisica alrededor
# =============================================================================

## Cuanto cuestan 200 consultas a `Ocean.sample()` y nada mas.
##
## Es el numero que el plan estimo a ojo («~200 sondas x 3 iteraciones x 8 olas
## ~ 10k evaluaciones trigonometricas por tick = 0,1-0,3 ms») y que F2 exige
## medir en vez de suponer. Hoy son 12 olas y 3 iteraciones de punto fijo, o sea
## 4 pasadas de 12 olas por consulta: 9600 evaluaciones por tick.
##
## Va aparte de la pasada real porque separa las dos preguntas que un dia habra
## que responder: si esto se pasa del presupuesto, lo que hay que bajar a
## C#/GDExtension es el EVALUADOR (el plan ya lo contempla); si esto cabe y la
## pasada completa no, el problema esta en `FloatingBody3D` y se arregla en
## GDScript.
func _test_micro_campo_de_olas() -> void:
	Ocean.regenerate(SEMILLA)
	Ocean.set_fury_immediate(FURIA_TORMENTA)

	# Repartidos en espiral aurea sobre el mismo radio que ocuparan los cuerpos.
	# Consultar 200 veces el MISMO punto mediria la cache del procesador, no el
	# campo de olas.
	var puntos := PackedVector2Array()
	puntos.resize(SONDAS_OBJETIVO)
	for i in SONDAS_OBJETIVO:
		var ang: float = TAU * float(i) * 0.6180339887
		var r: float = 4.0 + 26.0 * sqrt(float(i) / float(SONDAS_OBJETIVO))
		puntos[i] = Vector2(cos(ang) * r, sin(ang) * r)

	for _i in 20:
		_sumidero += _pasada_micro(puntos)

	var m := PackedFloat32Array()
	m.resize(MICRO_REPETICIONES)
	for i in MICRO_REPETICIONES:
		var t0: int = Time.get_ticks_usec()
		_sumidero += _pasada_micro(puntos)
		m[i] = float(Time.get_ticks_usec() - t0)
	m.sort()

	var p50: float = _percentil(m, 0.50)
	print("  Campo de olas solo (%d consultas a Ocean.sample, furia %.0f):" % [
		SONDAS_OBJETIVO, FURIA_TORMENTA])
	print("    min %.1f us   p50 %.1f us   p95 %.1f us   peor %.1f us   |   %.2f us por consulta" % [
		m[0], p50, _percentil(m, 0.95), m[m.size() - 1], p50 / float(SONDAS_OBJETIVO)])

	# Un cronometro roto (resolucion insuficiente, o alguien midiendo un lote
	# demasiado pequeño) devolveria ceros y el arnes entero pasaria en verde
	# sin haber medido nada. Es el fallo silencioso de un test de rendimiento.
	_check(p50 > 0.0, "el cronometro tiene resolucion para el lote que se mide",
		"p50 = %.1f us" % p50)
	# Es un subconjunto estricto de la pasada real: si esto solo ya no cabe, el
	# criterio esta perdido y ademas se sabe exactamente donde.
	_check(p50 < PRESUPUESTO_USEC, "el campo de olas solo cabe en el presupuesto",
		"p50 %.1f us de %.0f us" % [p50, PRESUPUESTO_USEC])


func _pasada_micro(puntos: PackedVector2Array) -> float:
	var suma: float = 0.0
	for p in puntos:
		var s: Dictionary = Ocean.sample(Vector3(p.x, 0.0, p.y))
		suma += float(s[&"height"])
	return suma


# =============================================================================
#  2. La flotabilidad completa: 200 sondas de verdad, en cuerpos de verdad
# =============================================================================

## EL criterio. Monta el barco y 96 barriles (200 sondas exactas) y cronometra
## la pasada de flotabilidad entera, tick a tick.
##
## [b]Como se mide sin mentir.[/b] A los cuerpos se les apaga el
## `_physics_process` del motor y se les llama a mano, una vez por tick de
## fisica, dentro del cronometro. La simulacion sigue siendo EXACTAMENTE la
## misma (una llamada por cuerpo y por tick, y las fuerzas se publican como
## `constant_force`, que no depende del orden), pero el intervalo medido
## contiene la flotabilidad y NADA MAS: ni el solver de Jolt, ni el jugador, ni
## `AguaEmbarcada`. Medir el tick entero mediria el motor, que no es lo que el
## criterio acota.
func _test_coste_flotabilidad() -> void:
	Ocean.regenerate(SEMILLA)
	Ocean.set_fury_immediate(FURIA_TORMENTA)
	Ocean.clear_events()

	var cuerpos: Array[FloatingBody3D] = []

	var barco: FloatingBody3D = load("res://game/boat/fishing_boat.tscn").instantiate()
	add_child(barco)
	barco.global_position = Vector3(0, 3, 0)
	cuerpos.append(barco)

	# Los barriles van en anillos alrededor del casco, no en un monton: apilados
	# se empujan entre ellos y la mitad acaba fuera del agua, que es justo el
	# caso barato. El radio minimo (10 m) deja libre la proa, que llega a 6,4 m.
	var escena_barril: PackedScene = load("res://game/boat/barrel.tscn")
	const POR_ANILLO := 16
	for i in BARRILES:
		var barril: FloatingBody3D = escena_barril.instantiate()
		add_child(barril)
		var anillo: int = i / POR_ANILLO
		var k: int = i % POR_ANILLO
		var ang: float = TAU * (float(k) / float(POR_ANILLO) + 0.37 * float(anillo))
		var r: float = 10.0 + 3.5 * float(anillo)
		barril.global_position = Vector3(cos(ang) * r, 1.0 + 0.15 * float(k), sin(ang) * r)
		cuerpos.append(barril)

	var sondas: int = 0
	for cuerpo in cuerpos:
		sondas += cuerpo.probe_count()
	# Fallo silencioso de manual: si el barco o el barril cambian de numero de
	# celdas, este arnes seguiria pasando en verde midiendo 190 sondas y
	# diciendo que el criterio de 200 se cumple.
	_check(sondas == SONDAS_OBJETIVO,
		"la escena de medida tiene las %d sondas del criterio" % SONDAS_OBJETIVO,
		"contadas %d (barco %d + %d barriles)" % [sondas, barco.probe_count(), BARRILES])

	for _i in SETTLE_TICKS:
		await get_tree().physics_frame

	# A partir de aqui la flotabilidad la conduce este arnes, no el motor.
	var divisores := PackedInt32Array()
	for cuerpo in cuerpos:
		divisores.append(cuerpo.tick_divisor)
		cuerpo.set_physics_process(false)

	# --- Escenarios ---------------------------------------------------------
	# Los tres primeros fuerzan `tick_divisor = 1` en todo: el criterio habla de
	# 200 sondas, y con los divisores de las escenas los barriles solo calculan
	# ticks alternos, asi que la mitad de las muestras no tendrian 200 sondas
	# dentro. Con divisor 1 CADA tick medido es un tick de 200 sondas.
	for cuerpo in cuerpos:
		cuerpo.tick_divisor = 1

	Ocean.set_fury_immediate(0.0)
	var calma: PackedFloat32Array = await _escenario(cuerpos)

	Ocean.set_fury_immediate(FURIA_TORMENTA)
	var tormenta: PackedFloat32Array = await _escenario(cuerpos)

	# Con un tsunami vivo, `Ocean.sample()` suma a cada consulta la onda N y su
	# velocidad. Se lanza con MUCHA antelacion a proposito: `OceanEvents` no
	# tiene atajo por distancia —el coste depende de que el evento este activo,
	# no de donde este—, asi que con la cresta lejos se mide el sobrecoste puro
	# sin que el barco salga volando y falsee que sondas estan mojadas.
	var tier: TsunamiTier = load("res://resources/tsunami_tiers/tier_3_leviatan.tres")
	Ocean.spawn_tsunami_tier(Vector3.ZERO, 90.0, 300.0, tier)
	var con_tsunami: PackedFloat32Array = await _escenario(cuerpos)
	Ocean.clear_events()

	# Lo que corre HOY en el juego: los divisores de las escenas.
	for i in cuerpos.size():
		cuerpos[i].tick_divisor = divisores[i]
	var como_hoy: PackedFloat32Array = await _escenario(cuerpos)

	# Y al final del todo, SOLO el barco (8 sondas). No es un escenario de
	# juego: es la validacion del propio arnes. Si el cronometro estuviera
	# midiendo cualquier otra cosa que no fuese la flotabilidad, el coste por
	# sonda con 8 y con 200 no se pareceria en nada. Va el ultimo porque deja a
	# los barriles sin conducir, y sin conducir se hunden.
	for cuerpo in cuerpos:
		cuerpo.tick_divisor = 1
	var solo_barco: Array[FloatingBody3D] = [barco]
	var ocho: PackedFloat32Array = await _escenario(solo_barco)

	# --- Informe ------------------------------------------------------------
	print("")
	print("  Pasada de flotabilidad, %d sondas (us por tick de fisica):" % sondas)
	print("    %-34s %8s %8s %8s %8s %8s %10s" % [
		"escenario", "min", "p50", "p95", "p99", "peor", "us/sonda"])
	_fila("calma (furia 0)", calma, sondas)
	_fila("tormenta (furia %.0f)" % FURIA_TORMENTA, tormenta, sondas)
	_fila("tormenta + tsunami en vuelo", con_tsunami, sondas)
	_fila("como esta hoy (divisores de escena)", como_hoy, -1)
	_fila("solo el barco (8 sondas, validacion)", ocho, barco.probe_count())
	print("")

	var p50_tormenta: float = _percentil(tormenta, 0.50)
	var p50_tsunami: float = _percentil(con_tsunami, 0.50)
	var tick_usec: float = 1e6 / float(maxi(Engine.physics_ticks_per_second, 1))
	print("    El tick de fisica dura %.0f us: la flotabilidad en tormenta se lleva el %.0f %%." % [
		tick_usec, 100.0 * p50_tormenta / tick_usec])
	# La fila «como esta hoy» es BIMODAL por construccion: con `tick_divisor = 2`
	# los barriles calculan en ticks alternos, asi que hay ticks de 200 sondas y
	# ticks de 8. Su mediana no significa nada (cae en la mitad barata), y por eso
	# el ahorro se calcula sobre la MEDIA, que es el coste amortizado de verdad.
	print("    Los divisores de escena reparten el coste en ticks alternos (fila bimodal:")
	print("    el min son las 8 sondas del barco). Amortizado ahorran un %.0f %%." % [
		100.0 * (1.0 - _media(como_hoy) / maxf(_media(tormenta), 0.001))])
	print("    Para cumplir el criterio hay que bajar de %.2f us por sonda; hoy son %.2f." % [
		PRESUPUESTO_USEC / float(SONDAS_OBJETIVO), p50_tormenta / float(sondas)])
	print("")

	# Suelo medido: el ruido de una maquina de escritorio compartida solo puede
	# SUMAR tiempo, nunca restarlo, asi que el minimo es lo mas parecido a "lo
	# que cuesta este codigo cuando le dan la CPU entera".
	var por_sonda_8: float = ocho[0] / float(barco.probe_count())
	var por_sonda_200: float = tormenta[0] / float(sondas)
	print("    Suelo (min) por sonda: %.2f us con 8 sondas, %.2f us con %d." % [
		por_sonda_8, por_sonda_200, sondas])
	print("")

	# El criterio se juzga por la MEDIANA, no por el peor ni por el p99. No es
	# ablandarlo: el presupuesto acota lo que cuesta el CODIGO, y en una maquina
	# de escritorio compartida (aqui conviven varias sesiones del proyecto) la
	# cola mide al planificador de Windows robando el nucleo, no una regresion.
	# Por eso se imprimen igualmente min, p95, p99 y peor: si la mediana se
	# acerca al techo, la cola es lo siguiente que hay que mirar.
	_check(p50_tormenta < PRESUPUESTO_USEC,
		"CRITERIO F2: flotabilidad con %d sondas en tormenta < %.0f us" % [
			SONDAS_OBJETIVO, PRESUPUESTO_USEC],
		"p50 %.1f us (min %.1f, peor %.1f)" % [
			p50_tormenta, tormenta[0], tormenta[tormenta.size() - 1]])
	_check(p50_tsunami < PRESUPUESTO_USEC,
		"...y sigue cabiendo con un tsunami en vuelo",
		"p50 %.1f us (min %.1f, peor %.1f)" % [
			p50_tsunami, con_tsunami[0], con_tsunami[con_tsunami.size() - 1]])

	# Banda ancha a proposito: con 200 sondas muchas quedan secas y salen por el
	# `continue`, asi que el coste por sonda NO tiene por que coincidir. Lo que
	# esta comprobacion descarta es el fallo gordo y silencioso de un arnes de
	# rendimiento: que el intervalo cronometrado no contenga la flotabilidad y
	# el numero sea de otra cosa. Eso daria ordenes de magnitud, no un 50 %.
	var razon: float = por_sonda_8 / maxf(por_sonda_200, 0.001)
	_check(razon > 0.33 and razon < 3.0,
		"lo cronometrado escala con el numero de sondas (o sea, ES la flotabilidad)",
		"%.2f us/sonda con 8 frente a %.2f con %d" % [por_sonda_8, por_sonda_200, sondas])

	if p50_tormenta >= PRESUPUESTO_USEC:
		_diagnostico(p50_tormenta, tormenta[0], sondas)

	for cuerpo in cuerpos:
		cuerpo.queue_free()


## Calienta, mide y devuelve las muestras YA ORDENADAS.
func _escenario(cuerpos: Array[FloatingBody3D]) -> PackedFloat32Array:
	await _correr(cuerpos, CALENTAMIENTO)
	var m: PackedFloat32Array = await _correr(cuerpos, MUESTRAS)
	m.sort()
	return m


## Corre `ticks` ticks conduciendo la flotabilidad a mano y devuelve lo que
## costo cada pasada, en microsegundos.
func _correr(cuerpos: Array[FloatingBody3D], ticks: int) -> PackedFloat32Array:
	var dt: float = 1.0 / float(maxi(Engine.physics_ticks_per_second, 1))
	var out := PackedFloat32Array()
	out.resize(ticks)
	for i in ticks:
		await get_tree().physics_frame
		var t0: int = Time.get_ticks_usec()
		for cuerpo in cuerpos:
			cuerpo._physics_process(dt)
		out[i] = float(Time.get_ticks_usec() - t0)
	return out


func _fila(etiqueta: String, m: PackedFloat32Array, sondas: int) -> void:
	var p50: float = _percentil(m, 0.50)
	var por_sonda := "-"
	if sondas > 0:
		por_sonda = "%.2f" % (p50 / float(sondas))
	print("    %-34s %8.1f %8.1f %8.1f %8.1f %8.1f %10s" % [
		etiqueta, m[0], p50, _percentil(m, 0.95), _percentil(m, 0.99),
		m[m.size() - 1], por_sonda])


## Que hacer cuando el criterio no se cumple. Un numero en rojo sin la lectura
## al lado se convierte en un test que la gente aprende a ignorar.
func _diagnostico(p50_tormenta: float, suelo: float, sondas: int) -> void:
	print("")
	print("  --- El criterio NO se cumple. Lectura: ---")
	print("  * Se pasa por x%.1f en mediana, y por x%.1f incluso en el MINIMO medido" % [
		p50_tormenta / PRESUPUESTO_USEC, suelo / PRESUPUESTO_USEC])
	print("    (%.0f us). El suelo importa porque el ruido de la maquina solo suma:" % suelo)
	print("    no hay lectura del dato en la que esto quepa hoy en el presupuesto.")
	print("  * El plan ya previo esta bifurcacion (docs/PLAN.md,")
	print("    seccion Lenguaje): «si falla, se baja a C#/GDExtension SOLO el evaluador")
	print("    de altura, no el proyecto entero». La tabla de arriba dice cuanto del")
	print("    coste es el evaluador (`Ocean.sample`) y cuanto es FloatingBody3D.")
	print("  * La estimacion de sobremesa del plan era 0,1-0,3 ms por tick. La medida")
	print("    la desmiente: %.2f ms. Por eso F2 exigia medir en vez de suponer." % [
		p50_tormenta / 1000.0])
	if OS.has_feature("debug"):
		print("  * OJO ANTES DE DECIDIR NADA: esto es un build DEBUG (el binario del")
		print("    editor). La VM de GDScript paga comprobaciones por instruccion que un")
		print("    export no paga, y el criterio de F2 habla del juego exportado. Este")
		print("    numero es un TECHO, no la cifra final: falta repetirlo sobre un export")
		print("    (hoy no se puede, no hay templates de 4.7.2 instalados).")
	print("  * Palancas ya disponibles y medidas, de mas a menos barata:")
	print("      - `tick_divisor` en los props (la fila «como esta hoy» lo cuantifica),")
	print("      - menos sondas por cuerpo en lo que nadie mira de cerca,")
	print("      - menos olas (%d hoy) o menos iteraciones de punto fijo (3 hoy): las dos" % Ocean.WAVE_COUNT)
	print("        tocan la PARIDAD con el shader, asi que no son gratis (regla 3).")
	print("    Coste actual: %.2f us por sonda y tick." % (p50_tormenta / float(sondas)))
	print("")


func _media(m: PackedFloat32Array) -> float:
	if m.is_empty():
		return 0.0
	var suma: float = 0.0
	for v in m:
		suma += v
	return suma / float(m.size())


## Percentil por rango mas cercano sobre una muestra YA ordenada. Sin
## interpolar: con 240 muestras el valor interpolado no dice nada que el crudo
## no diga, y el crudo es siempre una medida que ocurrio de verdad.
func _percentil(ordenadas: PackedFloat32Array, q: float) -> float:
	if ordenadas.is_empty():
		return 0.0
	var idx: int = clampi(int(ceil(q * float(ordenadas.size()))) - 1, 0, ordenadas.size() - 1)
	return ordenadas[idx]
