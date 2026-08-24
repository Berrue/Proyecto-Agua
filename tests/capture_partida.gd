extends Node

## Capturas del MENU DE ESC y de la LISTA DE TRIPULACION sobre el mundo real.
##
## No es un test —ese es `tests/partida_tests.tscn`—: esto es para mirar si se
## leen sobre el mar y si tapan lo que no deben (el HUD de debug vive en la
## columna izquierda y tiene que seguir alcanzable). Necesita ventana y GPU:
##
##   <godot 4.7.2> --path . tests/capture_partida.tscn -- --shots-dir=<carpeta>

const RUTA_MUNDO := "res://game/world/toybox.tscn"

var _dir: String = "user://partida-shots"
var _fallo := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots-dir="):
			_dir = arg.substr("--shots-dir=".length())
	var absoluta := ProjectSettings.globalize_path(_dir)
	if DirAccess.make_dir_recursive_absolute(absoluta) != OK:
		push_error("No se pudo crear la carpeta de capturas: %s" % absoluta)
		get_tree().quit(1)
		return

	var arbol := get_tree()
	await arbol.process_frame
	var mundo := (load(RUTA_MUNDO) as PackedScene).instantiate()
	arbol.root.add_child(mundo)
	arbol.current_scene = mundo
	for _i in 120:
		await arbol.process_frame

	Partida.mostrar_menu(true)
	await _foto("partida_1_menu_esc")
	Partida.mostrar_menu(false)

	# Una tripulacion de mentira: en un proceso no se pueden levantar host y
	# cliente (docs/RED.md), y lo que hay que mirar es como se LEE la lista.
	Partida._mostrar_lista(true)
	Partida._pintar_lista(NetTripulacion.ordenar([
		NetTripulacion.fila(NetTripulacion.HOST, "Nadia", NetTripulacion.MS_DESCONOCIDO, false),
		NetTripulacion.fila(7, "Berrue", 38, true),
		NetTripulacion.fila(9, "Ana", 126, false),
		NetTripulacion.fila(11, "Marcos", 310, false),
	]))
	await _foto("partida_2_tripulacion")
	Partida._mostrar_lista(false)

	if _fallo:
		push_error("Alguna captura de la partida no se pudo guardar")
		get_tree().quit(1)
	else:
		print("capturas de la partida en: ", absoluta)
		get_tree().quit(0)


func _foto(nombre: String) -> void:
	for _i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var imagen := get_viewport().get_texture().get_image()
	var error := imagen.save_png("%s/%s.png" % [_dir, nombre])
	if error == OK:
		print("OK  ", nombre)
	else:
		_fallo = true
		push_error("FALLO  %s (error %d)" % [nombre, error])
