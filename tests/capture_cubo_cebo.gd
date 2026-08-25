extends Node3D

## Capturas del balde de cebo. No es un test: es la revision visual de la pieza
## que `tools/build_bait_bucket.py` genera y que `cubo_cebo.gd` anima.
##
##   <godot> --path . tests/capture_cubo_cebo.tscn -- --shots-dir=<carpeta>
##
## Necesita ventana y GPU (el tinte del cebo y el color por vertice no existen
## en headless), asi que NO se corre con --headless.
##
## Lo que hay que mirar en las fotos, por orden de importancia:
##
## 1. **La lectura del nivel desde los ojos** (`ojos_*`): el jugador mira el
##    balde de pie, desde arriba y de lado. Si a 6 cargas no se ve que queda
##    poco, el contador ha dejado de contar y da igual lo bonita que sea la
##    malla — es la promesa de PESCA.md §5.
## 2. **Que el cebo parezca cebo**: sardinas y gusanos deben distinguirse de
##    las pellas de masa. Si todo se funde en un domo liso, hay que subir el
##    contraste del color por vertice, no la geometria.
## 3. **Que el asa no tape la boca** y que ni la masa ni el copete asomen por
##    la duela a ningun nivel (eso ademas lo vigila `fishing_tests`).

const NIVELES: Array[int] = [24, 12, 6, 1]

var _dir: String = "user://cubo_cebo_shots"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots-dir="):
			_dir = arg.substr("--shots-dir=".length())
	DirAccess.make_dir_recursive_absolute(_dir)

	var camera := $Camera3D as Camera3D
	camera.current = true

	var cubo: CuboCebo = load("res://game/props/cubo_cebo.tscn").instantiate()
	add_child(cubo)

	var cebos: Array[String] = [
		"res://resources/cebos/cebo_comun.tres",
		"res://resources/cebos/cebo_vivo.tres",
	]
	for ruta in cebos:
		var tipo := load(ruta) as TipoCebo
		cubo.tipo = tipo
		var etiqueta: String = ruta.get_file().get_basename()
		for cargas in NIVELES:
			cubo.cargas = cargas
			cubo._refrescar()
			# La foto de trabajo: de pie junto al balde, mirandolo de reojo.
			await _capture(
				camera, "%s_ojos_%02d" % [etiqueta, cargas],
				Vector3(0.30, 0.62, 0.46), Vector3(0.0, 0.20, 0.0), 52.0)
			# Y LA QUE MANDA: la altura real de los ojos de un pescador de pie
			# a un paso del balde. Si el nivel no se lee AQUI, no se lee.
			await _capture(
				camera, "%s_pov_%02d" % [etiqueta, cargas],
				Vector3(0.0, 1.62, 0.86), Vector3(0.0, 0.18, 0.0), 70.0)
		cubo.cargas = NIVELES[0]
		cubo._refrescar()
		# Y la ficha del asset: silueta entera, para juzgar duelas y herrajes.
		await _capture(
			camera, "%s_pieza" % etiqueta,
			Vector3(0.62, 0.40, 0.62), Vector3(0.0, 0.15, 0.0), 46.0)

	print("capturas del balde en: ", ProjectSettings.globalize_path(_dir))
	get_tree().quit(0)


func _capture(
	camera: Camera3D, etiqueta: String, posicion: Vector3, objetivo: Vector3, fov: float
) -> void:
	camera.fov = fov
	camera.global_position = posicion
	camera.look_at(objetivo, Vector3.UP)
	for _frame in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png("%s/%s.png" % [_dir, etiqueta])
	print("%s  %s" % ["OK  " if error == OK else "FALLO", etiqueta])
