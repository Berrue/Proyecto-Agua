extends Node

## Cuanto cuesta la manguera de la bomba, medido y no estimado.
##
##   <godot 4.7.2> --headless --path . tests/capture_manguera_perf.tscn
##
## No es un test de correccion sino de COSTE, como `perf_tests`: nace de una
## caida a 7 fps al agarrar el colador en juego, con 14,65 ms de fisica. Mide el
## paso completo de `StretchHose` en tres estados —guardada, tomada quieta y
## tomada moviendose— porque la sospecha es que simula y reconstruye su malla a
## 120 Hz aunque no se mueva nada.
##
## Imprime el reparto para poder decidir DONDE cortar en vez de adivinar.

const RUTA_BOMBA := "res://game/boat/equipment/manual_bilge_pump.tscn"

## Cuantos pasos se cronometran por escenario. A 120 Hz son ~8 segundos de juego.
const PASOS := 1000


func _ready() -> void:
	print_rich("[b]--- Coste de la manguera (%d pasos por escenario) ---[/b]" % PASOS)
	var hz: int = maxi(Engine.physics_ticks_per_second, 1)
	var dt: float = 1.0 / float(hz)
	print("  fisica del proyecto: %d Hz  (presupuesto por tick: %.2f ms)" % [hz, 1000.0 / float(hz)])
	print("")

	var bomba: Node3D = (load(RUTA_BOMBA) as PackedScene).instantiate()
	add_child(bomba)
	await get_tree().physics_frame
	var hose: Node = bomba.call(&"get_hose")
	if hose == null:
		print("  no encontre la manguera")
		get_tree().quit(1)
		return

	# Sin tocar nada: recogida en su carrete.
	var guardada := await _medir(hose, dt, null)
	_linea("guardada, nadie la toca", guardada, dt)

	# Tomada y quieta: una mano que no se mueve.
	var mano := Marker3D.new()
	bomba.add_child(mano)
	mano.global_position = bomba.global_position + Vector3(0.0, 0.2, -1.2)
	bomba.call(&"tomar_manguera", mano)
	await get_tree().physics_frame
	var quieta := await _medir(hose, dt, null)
	_linea("tomada, la mano quieta", quieta, dt)

	# Tomada y moviendose: el caso de juego, alguien caminando con el colador.
	var movida := await _medir(hose, dt, mano)
	_linea("tomada, la mano moviendose", movida, dt)

	# El reparto: cuanto es resolver la cuerda y cuanto es DIBUJARLA. Importa,
	# porque la forma exacta es presentacion y se puede recortar sin que el juego
	# se entere; el solver no tanto.
	print("")
	var presentacion := await _medir_presentacion(hose)
	print("  de eso, solo `_actualizar_presentacion`: %7.3f ms/tick  (%.0f %% del paso)" % [
		presentacion, presentacion / maxf(movida, 0.0001) * 100.0])
	print("  o sea que el solver de la cuerda es:      %7.3f ms/tick" % [
		maxf(movida - presentacion, 0.0)])

	print("")
	var peor: float = maxf(maxf(guardada, quieta), movida)
	print_rich("[b]peor caso: %.3f ms por tick  ->  %.1f ms por segundo de juego[/b]" % [
		peor, peor * float(hz)])
	if peor * float(hz) > 8.0:
		print_rich("[color=#ffb020]La manguera sola se come mas de 8 ms de cada segundo.[/color]")
	get_tree().quit(0)


## Cronometra `PASOS` llamadas al paso de simulacion. Si `mover` no es null, la
## mano se pasea: es el caso que de verdad hace trabajar al solver.
func _medir(hose: Node, dt: float, mover: Node3D) -> float:
	var t0: int = Time.get_ticks_usec()
	var base: Vector3 = mover.position if mover != null else Vector3.ZERO
	for i in PASOS:
		if mover != null:
			var f: float = float(i) * 0.01
			mover.position = base + Vector3(sin(f) * 1.5, 0.0, cos(f) * 1.5)
		hose.call(&"_simular_paso", dt)
	return float(Time.get_ticks_usec() - t0) / 1000.0 / float(PASOS)


## Solo el dibujado, sin resolver la cuerda.
func _medir_presentacion(hose: Node) -> float:
	var t0: int = Time.get_ticks_usec()
	for _i in PASOS:
		hose.call(&"_actualizar_presentacion")
	return float(Time.get_ticks_usec() - t0) / 1000.0 / float(PASOS)


func _linea(que: String, ms: float, dt: float) -> void:
	var porcentaje: float = ms / (dt * 1000.0) * 100.0
	print("  %-28s %7.3f ms/tick   (%.0f %% del presupuesto de un tick)" % [
		que, ms, porcentaje])
