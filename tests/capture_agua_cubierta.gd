extends Node

## Los tres momentos que el jugador tiene que leer de un vistazo, en imagen.
##
##   godot --path . tests/capture_agua_cubierta.tscn -- --shots-dir=<carpeta>
##
## No es un test: es la comprobacion VISUAL de la calibracion. `agua_tests`
## garantiza que los numeros salen, pero que un charco se lea como charco y que
## el agua por la cintura de miedo solo se puede mirar. Necesita ventana y GPU,
## asi que NO se corre con `--headless`.

const RUTA_BARCO := "res://game/boat/fishing_boat.tscn"

## Los tres momentos, con su nombre. Son los que decide `agua_embarcada.tres`.
const MOMENTOS: Array = [
	[0.00, "seco"],
	[0.05, "charco"],
	[0.55, "alarma_rodilla"],
	[0.85, "naufragio_cintura"],
]

var _dir: String = "res://docs/images/agua_cubierta"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots-dir="):
			_dir = arg.substr("--shots-dir=".length())
	_dir = ProjectSettings.globalize_path(_dir)
	DirAccess.make_dir_recursive_absolute(_dir)

	Ocean.clear_events()
	Ocean.set_fury_immediate(0.0)

	var barco: FloatingBody3D = (load(RUTA_BARCO) as PackedScene).instantiate()
	add_child(barco)
	barco.global_position = Vector3.ZERO
	barco.freeze = true # quieto: lo que se mira es el agua, no el oleaje

	var luz := DirectionalLight3D.new()
	luz.rotation_degrees = Vector3(-52.0, 38.0, 0.0)
	luz.light_energy = 1.15
	add_child(luz)

	var camara := Camera3D.new()
	add_child(camara)
	# A la altura de los ojos de un tripulante y mirando la cubierta: es EL punto
	# de vista desde el que hay que entender cuanta agua hay.
	camara.global_position = Vector3(2.6, 3.1, -6.2)
	camara.look_at(Vector3(0.0, 0.9, 0.5), Vector3.UP)
	camara.current = true

	await get_tree().process_frame
	await get_tree().process_frame

	for momento: Array in MOMENTOS:
		var nivel: float = float(momento[0])
		var nombre: String = String(momento[1])
		barco.bail_out(1.0)
		if nivel > 0.0:
			for i in barco.probe_count():
				barco.flood_probe(i, nivel)
		# Unos frames para que el nivel llegue al plano y el chapoteo se asiente.
		for _i in 12:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw

		var img := get_viewport().get_texture().get_image()
		var ruta := "%s/%s.png" % [_dir, nombre]
		img.save_png(ruta)
		var piscina := barco.get_node_or_null(^"AguaCubierta") as AguaCubierta
		var prof: float = piscina.profundidad_maxima() if piscina != null else 0.0
		print("  %-20s nivel %.2f  ->  %.2f m de agua  ->  %s" % [
			nombre, nivel, prof, ruta])

	print("")
	print("Miralas seguidas: si no se distingue de un vistazo el charco de la")
	print("alarma, y la alarma del naufragio, la calibracion no sirve por muy")
	print("verdes que salgan los tests.")
	get_tree().quit(0)
