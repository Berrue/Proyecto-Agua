extends Node

## PARIDAD CPU/GPU del oleaje. El seguro de vida contra la deriva silenciosa.
##
##   godot --headless --path . tests/parity_tests.tscn
##
## [b]Contra que protege.[/b] El oleaje esta escrito dos veces —`wave_proxy.gd`
## para la fisica, `ocean_waves.gdshaderinc` para lo que se ve— y tienen que ser
## espejos exactos (regla 3). Si divergen, el barco flota a una altura y la
## pantalla dibuja otra. El fallo NO produce ningun error: cada pantalla se ve
## perfecta por separado, y solo se nota cuando alguien mira muy fijo. Hasta hoy
## la unica defensa era mirar unas esferas a ojo con `parity_markers.gd`.
##
## [b]Por que este test no habla con la GPU.[/b] Porque no puede: en headless
## Godot no tiene `RenderingDevice` y el shader no se puede ejecutar (verificado,
## ver docs/PLAN.md §Verificacion). Asi que la GPU contesto ANTES, en una maquina
## con pantalla, y sus respuestas viven en `tests/golden/ocean_golden.res`. Aqui
## solo se evalua la CPU y se compara contra esa tabla — y eso si corre en
## cualquier parte, incluida una CI sin tarjeta grafica.
##
## [b]Si este test falla despues de tocar una formula del agua[/b], lo mas
## probable es que la tabla este vieja: hay que regenerarla con
## `addons/ocean/debug/golden_gen.tscn` (necesita ventana y GPU) y commitearla
## en el MISMO commit. Regenerar es obligatorio, no opcional.

const RUTA := "res://tests/golden/ocean_golden.res"

var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0


func _ready() -> void:
	print_rich("[b]--- Paridad CPU/GPU del oleaje (golden vectors) ---[/b]")
	var previa_semilla: int = Ocean.ocean_seed
	var previa_furia: float = Ocean.fury
	var previo_t: float = Ocean.sim_time
	Ocean.limpiar_parte()

	var tabla: GoldenOceano = load(RUTA) as GoldenOceano
	_check(tabla != null, "existe la tabla golden",
		"falta %s — generala con addons/ocean/debug/golden_gen.tscn" % RUTA)
	if tabla == null:
		_report()
		return

	_check(not tabla.esta_vacia(), "la tabla tiene todas sus muestras",
		"esperaba %d y hay %d" % [tabla.total_muestras(), tabla.valores.size()])
	if tabla.esta_vacia():
		_report()
		return

	print("  tabla generada: %s" % tabla.generado)
	print("  %d muestras (%d semillas x %d furias x %d instantes x %d componentes x %d puntos)" % [
		tabla.total_muestras(), tabla.semillas.size(), tabla.furias.size(),
		tabla.tiempos.size(), GoldenOceano.COMPONENTES, GoldenOceano.LADO * GoldenOceano.LADO])

	_comparar(tabla)
	_test_la_tabla_no_es_trivial(tabla)
	_test_el_test_puede_fallar(tabla)

	Ocean.regenerate(previa_semilla)
	Ocean.set_fury_immediate(previa_furia)
	Ocean.sim_time = previo_t
	_report()


## LA comparacion. Recorre la tabla entera y evalua la CPU en los mismos puntos.
func _comparar(tabla: GoldenOceano) -> void:
	var nombres: Array[String] = ["desplazamiento x", "altura", "desplazamiento z", "jacobiano"]
	var peor_global: float = 0.0

	for comp in GoldenOceano.COMPONENTES:
		var peor: float = 0.0
		var donde: String = ""
		for s in tabla.semillas.size():
			Ocean.regenerate(tabla.semillas[s])
			for f in tabla.furias.size():
				Ocean.set_fury_immediate(tabla.furias[f])
				var proxy := Ocean.get_proxy()
				for t in tabla.tiempos.size():
					var tt: float = tabla.tiempos[t]
					for j in GoldenOceano.LADO:
						for i in GoldenOceano.LADO:
							var esperado: float = tabla.valores[tabla.indice(s, f, t, comp, j, i)]
							var real: float = _cpu(proxy, comp, GoldenOceano.punto(i, j), tt)
							var e: float = absf(real - esperado)
							if e > peor:
								peor = e
								donde = "semilla %d, furia %.1f, t=%.1f, punto (%d,%d): gpu %.6f, cpu %.6f" % [
									tabla.semillas[s], tabla.furias[f], tt, i, j, esperado, real]
		peor_global = maxf(peor_global, peor)
		_check(peor <= GoldenOceano.TOLERANCIA,
			"%s: la CPU coincide con la GPU (peor %.6f m)" % [nombres[comp], peor], donde)

	print("  peor diferencia global: %.6f m  (tolerancia %.6f)" % [
		peor_global, GoldenOceano.TOLERANCIA])


## Una tabla de ceros pasaria la comparacion si la CPU tambien diera cero. Se
## comprueba que la referencia tenga relieve de verdad — si no, este arnes seria
## un sello de goma.
func _test_la_tabla_no_es_trivial(tabla: GoldenOceano) -> void:
	var maximo: float = 0.0
	var no_cero: int = 0
	for v in tabla.valores:
		maximo = maxf(maximo, absf(v))
		if absf(v) > 0.01:
			no_cero += 1
	_check(maximo > 1.0, "la tabla tiene olas de verdad (max %.2f m)" % maximo)
	var fraccion: float = float(no_cero) / float(maxi(tabla.valores.size(), 1))
	_check(fraccion > 0.5, "y no es casi toda ceros (%.0f %% con valor)" % (fraccion * 100.0))


## Y el test tiene que poder FALLAR. Se rompe la formula a proposito —moviendo
## la furia, que cambia las amplitudes— y se comprueba que la comparacion lo
## caza. Sin esto, un bug que hiciera `_cpu()` devolver siempre el valor
## esperado dejaria el arnes en verde para siempre.
func _test_el_test_puede_fallar(tabla: GoldenOceano) -> void:
	if tabla.semillas.is_empty() or tabla.furias.size() < 2:
		return
	Ocean.regenerate(tabla.semillas[0])
	# La tabla de la furia [0] comparada contra una CPU puesta en la furia [1].
	Ocean.set_fury_immediate(tabla.furias[1])
	var proxy := Ocean.get_proxy()
	var peor: float = 0.0
	for j in GoldenOceano.LADO:
		for i in GoldenOceano.LADO:
			var esperado: float = tabla.valores[tabla.indice(0, 0, 0, 1, j, i)]
			peor = maxf(peor, absf(_cpu(proxy, 1, GoldenOceano.punto(i, j), tabla.tiempos[0]) - esperado))
	_check(peor > GoldenOceano.TOLERANCIA * 100.0,
		"con la formula alterada a proposito, la comparacion SI falla (%.3f m)" % peor,
		"el arnes no detecta una divergencia evidente: es un sello de goma")


func _cpu(proxy: OceanWaveProxy, comp: int, p: Vector2, t: float) -> float:
	if comp == 3:
		# EN REPOSO: `jacobian_at()` invierte la posicion primero, porque quien
		# pregunta desde el juego da una de mundo. El shader recibe la de
		# reposo. Confundirlas hacia ver 0.22 m de divergencia inexistente.
		return proxy.jacobian_en_reposo(p, t)
	var d: Vector3 = proxy.displacement(p, t)
	if comp == 0:
		return d.x
	if comp == 1:
		return d.y
	return d.z


func _check(condition: bool, label: String, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("  ok    %s" % label)
	else:
		print("  FALLO %s%s" % [label, ("  ->  " + detail) if detail != "" else ""])
		_failures.append(label + ((" -> " + detail) if detail != "" else ""))


func _report() -> void:
	print("")
	if _failures.is_empty():
		print_rich("[color=green][b]%d/%d comprobaciones de paridad OK[/b][/color]" % [_checks, _checks])
		get_tree().quit(0)
	else:
		print_rich("[color=red][b]%d de %d han fallado:[/b][/color]" % [_failures.size(), _checks])
		for f in _failures:
			print("   - " + f)
		print("")
		print("Si acabas de tocar una formula del agua, REGENERA la tabla:")
		print("  <godot 4.7.2> --path . addons/ocean/debug/golden_gen.tscn")
		get_tree().quit(1)
