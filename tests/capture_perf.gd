extends Node

## Herramienta de medida del FRAME TIME en tormenta: la mitad del criterio de
## rendimiento de F2 que no se puede comprobar sin GPU.
##
##   godot --path . tests/capture_perf.tscn -- --perf-out=<archivo> --perf-res=1920x1080
##
## [b]No es un test, es un informe[/b] (por eso `capture_`, como
## `capture_weather` o `capture_shots`): no puede salir en rojo porque el numero
## bueno depende de la maquina, y el criterio de F2 se enuncia contra una GPU
## concreta —la GTX 1060, el minimo que fijo F0— que no es la de desarrollo. Lo
## que hace es imprimir la tabla para que una persona la juzgue. La parte que SI
## se puede automatizar (la flotabilidad, que es CPU pura) esta en
## `tests/perf_tests.tscn` y esa si sale con codigo != 0.
##
## [b]Por que percentiles y no la media.[/b] «Frame time estable» es una
## afirmacion sobre la COLA de la distribucion, no sobre su centro: 200 frames
## a 8 ms y 3 frames a 60 ms dan una media excelente y se juegan fatal, porque
## lo que el jugador nota es el tiron. Por eso el informe da p50/p95/p99, el
## peor frame, y cuantos frames se pasaron de 60 y de 30 fps.
##
## [b]Por que en tormenta de verdad (furia 7-9).[/b] Es donde el criterio
## aplica y donde se juntan todos los costes a la vez: crestas afiladas (mas
## detalle en el shader), espuma, lluvia con sus particulas y sus estrias, y un
## barco cabeceando que mueve la camara y por tanto el snapping de la malla.
##
## [b]Por que ademas cuenta pasos de fisica.[/b] Porque si no, la cola de la
## tabla parece del renderizado y se buscaria donde no esta. La fisica va a
## 120 Hz y los frames no van a ese ritmo, asi que un frame se traga a veces un
## paso y a veces dos — y cada paso arrastra una pasada entera de flotabilidad.
## El desglose del final separa las dos poblaciones y deja ver quien pone la
## cola de verdad.
##
## [b]Para que sirve ahora mismo.[/b] El siguiente trabajo de F2 es el clipmap
## (anillos concentricos + morph), que multiplica la geometria del mar por ~8.
## Esta tabla es la LINEA BASE contra la que hay que comparar, y por eso se
## imprimen tambien las cifras de la malla actual: 512 m, 255 subdivisiones,
## celda de 2 m. Repetir el comando despues del clipmap y poner las dos tablas
## una al lado de la otra es la comprobacion entera.

# =============================================================================
#  Que se mide
# =============================================================================

## (etiqueta, furia, lluvia, lanzar tsunami)
##
## `calma` no sobra: sin una referencia barata no se sabe cuanto de lo que
## cuesta un frame es "el juego" y cuanto es "la tormenta", que es exactamente
## la pregunta que habra que responder cuando entre el clipmap.
const SEGMENTOS: Array = [
	["calma (furia 1)", 1.0, 0.0, false],
	["tormenta furia 7, seca", 7.0, 0.0, false],
	["tormenta furia 8 + lluvia", 8.0, 1.0, false],
	["tormenta furia 9 + lluvia", 9.0, 1.0, false],
	["furia 9 + lluvia + tsunami", 9.0, 1.0, true],
]

## Semilla explicita (regla 4): la linea base tiene que ser reproducible y
## comparable con la de despues del clipmap.
const SEMILLA := 20260824

## Frames que se corren y se TIRAN al entrar en cada segmento. No es cortesia:
## los primeros frames tras cambiar de estado pagan compilacion de pipelines,
## arranque de los emisores de particulas y la rampa de lluvia. Contarlos
## envenena el p99 con costes que solo ocurren una vez en la vida.
const CALENTAMIENTO_FRAMES := 120

## Frames medidos por segmento. Con 600, el p99 es el sexto peor frame: un
## numero que significa algo en vez de ser un solo pico.
const MUESTRA_FRAMES := 600

## 60 fps y 30 fps en microsegundos. El criterio de F2 dice "estable", no un
## numero; estos dos son los umbrales que el jugador NOTA, y el porcentaje de
## frames que los cruza es la traduccion honesta de "estable".
const FRAME_60_USEC := 16667.0
const FRAME_30_USEC := 33333.0

## Relacion p99/p50 por encima de la cual la cola se despega lo bastante de la
## mediana para sentirse como tirones aunque el promedio sea bueno.
const RATIO_ESTABLE := 1.5

## Segundos hasta que la cresta del tsunami llegue al barco. Calibrado para que
## caiga por la MITAD de la ventana medida (calentamiento + medio segmento a la
## tasa que sale en esta maquina): con el lead corto llegaba al final y el peor
## frame del juego se quedaba fuera de la muestra, que es justo el que hay que
## fotografiar.
const TSUNAMI_LEAD_S := 4.0

## Por debajo de esta fraccion del frame, el tiempo de GPU no es quien manda: el
## cuello esta en la CPU y optimizar geometria no movera la tabla.
const FRACCION_GPU_MANDA := 0.7

var _lineas: PackedStringArray = PackedStringArray()
var _veredictos: PackedStringArray = PackedStringArray()
var _desgloses: PackedStringArray = PackedStringArray()
var _salida: String = ""

## Pasos de fisica ocurridos desde el ultimo frame. Ver la cabecera: es LA
## explicacion de la cola, y sin contarlo la cola parece del renderizado.
var _pasos: int = 0


func _physics_process(_delta: float) -> void:
	_pasos += 1


func _ready() -> void:
	var ancho: int = 0
	var alto: int = 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--perf-out="):
			_salida = arg.substr("--perf-out=".length())
		elif arg.begins_with("--perf-res="):
			var partes: PackedStringArray = arg.substr("--perf-res=".length()).split("x")
			if partes.size() == 2:
				ancho = int(partes[0])
				alto = int(partes[1])

	# Sale en rojo SOLO en este caso, y no porque sea un test: es que la
	# peticion no tiene sentido y callarse dejaria a alguien creyendo que midio
	# el frame time cuando no habia ni ventana ni GPU.
	if DisplayServer.get_name() == "headless":
		push_error("capture_perf necesita ventana y GPU: el frame time no existe en headless. "
			+ "Quita --headless. (La flotabilidad, que si es CPU pura, se mide en "
			+ "tests/perf_tests.tscn.)")
		get_tree().quit(1)
		return

	# LO MAS IMPORTANTE DE TODO EL ARCHIVO. Con vsync puesto, todos los frames
	# duran exactamente un refresco del monitor: los percentiles saldrian
	# clavados en 16,7 ms, el informe diria "perfectamente estable" y no habria
	# medido absolutamente nada.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	if ancho > 0 and alto > 0:
		DisplayServer.window_set_size(Vector2i(ancho, alto))

	var toybox: Node3D = load("res://game/world/toybox.tscn").instantiate()
	add_child(toybox)
	# El jugador captura el raton en su _ready; en una medida automatica eso
	# solo secuestra el escritorio.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	Ocean.regenerate(SEMILLA)
	Ocean.clear_events()

	# Ojo de cubierta mirando al horizonte: es el encuadre CARO (el mar ocupa
	# media pantalla hasta el borde de la malla) y ademas es como se juega. Una
	# camara cenital miraria mucha menos agua y daria un numero optimista.
	var cam := Camera3D.new()
	cam.fov = 78.0 # el mismo que la camara del jugador
	cam.far = 4000.0
	add_child(cam)
	cam.current = true

	var vp_rid: RID = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, true)

	var superficie := toybox.get_node_or_null(^"OceanSurface") as OceanSurface3D
	var barco := toybox.get_node_or_null(^"FishingBoat") as Node3D

	_cabecera(superficie)

	for _i in 60:
		await get_tree().process_frame

	for segmento: Array in SEGMENTOS:
		var etiqueta: String = segmento[0]
		Ocean.set_fury_immediate(float(segmento[1]))
		Ocean.rain_level = float(segmento[2])
		Ocean.clear_events()
		if bool(segmento[3]):
			# La cresta tiene que ATRAVESAR la ventana de medida: el frame caro
			# del tsunami es el de la ola encima, no el de la ola lejos.
			var tier: TsunamiTier = load("res://resources/tsunami_tiers/tier_3_leviatan.tres")
			Ocean.spawn_tsunami_tier(Vector3.ZERO, 90.0, TSUNAMI_LEAD_S, tier)

		# La lluvia tiene rampa (RAIN_RATE_LIMIT): medir mientras sube seria
		# medir un estado que no existe en el juego.
		var guarda: int = 0
		while absf(Ocean.rain01 - Ocean.rain_target()) > 0.01 and guarda < 600:
			await _frame(cam, barco)
			guarda += 1
		for _i in CALENTAMIENTO_FRAMES:
			await _frame(cam, barco)

		var pared := PackedFloat32Array()
		var gpu := PackedFloat32Array()
		var pasos := PackedInt32Array()
		pared.resize(MUESTRA_FRAMES)
		gpu.resize(MUESTRA_FRAMES)
		pasos.resize(MUESTRA_FRAMES)
		var anterior: int = Time.get_ticks_usec()
		_pasos = 0
		for i in MUESTRA_FRAMES:
			await _frame(cam, barco)
			var ahora: int = Time.get_ticks_usec()
			pared[i] = float(ahora - anterior)
			anterior = ahora
			pasos[i] = _pasos
			_pasos = 0
			# En ms, y de un frame ya terminado (la consulta a la GPU llega con
			# retraso). Para percentiles da igual: no se empareja con el frame
			# de pared, se resume por separado.
			gpu[i] = RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)

		_fila(etiqueta, pared, gpu, pasos)

	Ocean.rain_level = 0.0
	Ocean.clear_events()
	_cierre()
	get_tree().quit(0)


## Un frame, con la camara re-anclada al barco. Se re-ancla CADA frame a
## proposito: es la carga real (la malla del mar hace snapping a la rejilla cada
## vez que la camara se mueve) y una camara clavada en el mundo mediria un caso
## mas barato del que se juega.
func _frame(cam: Camera3D, barco: Node3D) -> void:
	if barco != null:
		cam.global_position = barco.to_global(Vector3(0.0, 2.0, -1.2))
		cam.look_at(barco.to_global(Vector3(0.0, 2.0, -60.0)), Vector3.UP)
	await get_tree().process_frame


# =============================================================================
#  Informe
# =============================================================================

func _linea(texto: String) -> void:
	_lineas.append(texto)
	print(texto)


func _cabecera(superficie: OceanSurface3D) -> void:
	var tam := DisplayServer.window_get_size()
	_linea("")
	_linea("=== Frame time en tormenta (criterio duro de F2) ===")
	_linea("")
	_linea("  GPU:      %s (%s)" % [
		RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor()])
	_linea("  CPU:      %s" % OS.get_processor_name())
	_linea("  Godot:    %s, build %s, %s" % [
		String(Engine.get_version_info()["string"]),
		"debug" if OS.has_feature("debug") else "release",
		String(ProjectSettings.get_setting("rendering/renderer/rendering_method", "forward_plus"))])
	_linea("  Ventana:  %d x %d, MSAA %d, vsync DESACTIVADO, max_fps 0, fisica %d Hz" % [
		tam.x, tam.y,
		int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d", 0)),
		Engine.physics_ticks_per_second])
	if superficie != null:
		# La linea base del clipmap: estos son los numeros que va a cambiar.
		var lado: int = superficie.subdivisions + 2
		_linea("  Mar:      plano de %.0f m, %d subdivisiones, celda %.2f m -> %d vertices, %d triangulos" % [
			superficie.size, superficie.subdivisions, superficie.cell_size(),
			lado * lado, 2 * (superficie.subdivisions + 1) * (superficie.subdivisions + 1)])
	_linea("")
	_linea("  El criterio de F2 se enuncia contra una GTX 1060 (el minimo de F0). Si la GPU de")
	_linea("  arriba no es esa, esta tabla es informativa: hay que repetirla en la maquina objetivo.")
	_linea("")
	_linea("  %-30s %8s %8s %8s %8s %8s %8s %8s %8s" % [
		"segmento", "p50", "p95", "p99", "peor", ">16.7", ">33.3", "gpu p50", "gpu p99"])
	_linea("  %-30s %8s %8s %8s %8s %8s %8s %8s %8s" % [
		"", "ms", "ms", "ms", "ms", "%", "%", "ms", "ms"])


func _fila(etiqueta: String, pared: PackedFloat32Array, gpu: PackedFloat32Array,
		pasos: PackedInt32Array) -> void:
	# El desglose por numero de pasos necesita los arrays EN ORDEN (el frame i
	# de `pared` con el frame i de `pasos`), asi que los percentiles salen de
	# copias ordenadas y los originales no se tocan.
	var pared_ord := PackedFloat32Array(pared)
	var gpu_ord := PackedFloat32Array(gpu)
	pared_ord.sort()
	gpu_ord.sort()

	_linea("  %-30s %8.2f %8.2f %8.2f %8.2f %8.1f %8.1f %8.2f %8.2f" % [
		etiqueta,
		_percentil(pared_ord, 0.50) / 1000.0,
		_percentil(pared_ord, 0.95) / 1000.0,
		_percentil(pared_ord, 0.99) / 1000.0,
		pared_ord[pared_ord.size() - 1] / 1000.0,
		100.0 * float(_por_encima(pared_ord, FRAME_60_USEC)) / float(pared_ord.size()),
		100.0 * float(_por_encima(pared_ord, FRAME_30_USEC)) / float(pared_ord.size()),
		_percentil(gpu_ord, 0.50),
		_percentil(gpu_ord, 0.99)])
	_veredicto(etiqueta, pared_ord, gpu_ord)
	_desglose_por_pasos(etiqueta, pared, pasos)


func _veredicto(etiqueta: String, pared: PackedFloat32Array, gpu: PackedFloat32Array) -> void:
	var p50: float = _percentil(pared, 0.50)
	var p99: float = _percentil(pared, 0.99)
	var ratio: float = p99 / maxf(p50, 1.0)
	var juicio := "estable"
	if ratio > RATIO_ESTABLE:
		juicio = "cola larga"
	elif p99 >= FRAME_60_USEC:
		juicio = "estable pero por debajo de 60 fps"
	# Quien manda en el frame: si el tiempo de GPU esta muy por debajo del de
	# pared, la geometria del mar no es el cuello de botella, y entonces
	# optimizar el clipmap no movera esta tabla ni un milimetro.
	var cuello := "CPU"
	if _percentil(gpu, 0.50) * 1000.0 >= FRACCION_GPU_MANDA * p50:
		cuello = "GPU"
	_veredictos.append("  %-30s %5.0f fps de mediana, cola p99/p50 = %.2f, manda la %s  ->  %s" % [
		etiqueta, 1e6 / maxf(p50, 1.0), ratio, cuello, juicio])


## De donde sale la cola. Separa los frames que se comieron un paso de fisica de
## los que se comieron dos: si el salto entre las dos poblaciones es del tamaño
## de una pasada de flotabilidad (la que mide `tests/perf_tests`), la cola no es
## del renderizado y el clipmap no la va a tocar.
func _desglose_por_pasos(etiqueta: String, pared: PackedFloat32Array,
		pasos: PackedInt32Array) -> void:
	var por_pasos: Dictionary = {}
	var total: int = 0
	for i in pared.size():
		var n: int = pasos[i]
		total += n
		var lista: PackedFloat32Array = por_pasos.get(n, PackedFloat32Array())
		lista.append(pared[i])
		por_pasos[n] = lista

	var claves: Array = por_pasos.keys()
	claves.sort()
	var trozos := PackedStringArray()
	for n: int in claves:
		var lista: PackedFloat32Array = por_pasos[n]
		if lista.size() < 10:
			continue # muestra demasiado pequeña para decir nada de ella
		lista.sort()
		trozos.append("%d paso%s: p50 %.2f ms (%d %% de los frames)" % [
			n, "" if n == 1 else "s", _percentil(lista, 0.50) / 1000.0,
			int(round(100.0 * float(lista.size()) / float(pared.size())))])
	_desgloses.append("  %-30s %.2f pasos/frame  |  %s" % [
		etiqueta, float(total) / float(pared.size()), "   ".join(trozos)])


func _cierre() -> void:
	_linea("")
	_linea("  Lectura: \"estable\" = p99 por debajo de 16,7 ms (60 fps) Y cola p99/p50 <= %.1f." % RATIO_ESTABLE)
	for v in _veredictos:
		_linea(v)
	_linea("")
	_linea("  De donde sale la cola. La fisica va a %d Hz y los frames no van a ese ritmo, asi" % Engine.physics_ticks_per_second)
	_linea("  que un frame se traga a veces un paso y a veces dos, y cada paso arrastra una")
	_linea("  pasada entera de flotabilidad:")
	for d in _desgloses:
		_linea(d)
	_linea("")
	_linea("  Si el salto entre 1 paso y 2 pasos se parece al coste de flotabilidad que mide")
	_linea("  tests/perf_tests, la cola NO es del mar: es la CPU, y el clipmap no la toca.")
	_linea("")
	_linea("  Aviso sobre el vsync: aqui va DESACTIVADO porque si no todos los frames durarian")
	_linea("  un refresco y no se mediria nada. Jugando con vsync a 60 Hz y la fisica a %d Hz," % Engine.physics_ticks_per_second)
	_linea("  TODOS los frames se comen %d pasos: el caso caro de esta tabla, en todos." % [
		maxi(Engine.physics_ticks_per_second / 60, 1)])
	_linea("")
	_linea("  Esta tabla es la LINEA BASE previa al clipmap. Guardala y repite el comando")
	_linea("  despues de meter los anillos concentricos: la comparacion es el criterio.")
	_linea("")

	if _salida != "":
		var f := FileAccess.open(_salida, FileAccess.WRITE)
		if f == null:
			push_error("No se pudo escribir el informe en %s (error %d)" % [
				_salida, FileAccess.get_open_error()])
		else:
			f.store_string("\n".join(_lineas) + "\n")
			f.close()
			print("informe guardado en: ", ProjectSettings.globalize_path(_salida))


func _por_encima(ordenadas: PackedFloat32Array, umbral: float) -> int:
	var n: int = 0
	for v in ordenadas:
		if v > umbral:
			n += 1
	return n


## Percentil por rango mas cercano sobre una muestra YA ordenada. Sin
## interpolar: el valor devuelto es siempre un frame que ocurrio de verdad.
func _percentil(ordenadas: PackedFloat32Array, q: float) -> float:
	if ordenadas.is_empty():
		return 0.0
	var idx: int = clampi(int(ceil(q * float(ordenadas.size()))) - 1, 0, ordenadas.size() - 1)
	return ordenadas[idx]
