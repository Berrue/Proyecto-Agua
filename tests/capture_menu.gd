extends Node

## Capturas del MENU PRINCIPAL, panel por panel, para revisar el look.
##
## No es un test: el arnes de verdad es `tests/menu_tests.tscn`. Esto pinta lo
## que el jugador ve —el mar de dia detras de los botones— y por eso necesita
## ventana y GPU, o sea que NO se corre con `--headless`:
##
##   <godot 4.7.2> --path . tests/capture_menu.tscn -- --shots-dir=<carpeta>

const RUTA_MENU := "res://game/ui/menu/menu_principal.tscn"

var _dir: String = "user://menu-shots"
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

	var escena := (load(RUTA_MENU) as PackedScene).instantiate() as Node3D
	add_child(escena)
	var menu := escena.get_node("MenuPrincipal") as MenuPrincipal
	# Unos segundos de mar antes de la primera foto: la malla del oceano se
	# reconstruye al seguir a la camara y el primer fotograma sale plano.
	for _i in 90:
		await get_tree().process_frame

	await _foto("menu_1_portada")
	menu._abrir(MenuNavegacion.Pantalla.JUGAR)
	await _foto("menu_2_jugar")
	menu._abrir(MenuNavegacion.Pantalla.MULTIJUGADOR)
	await _foto("menu_3_multijugador")
	menu._abrir(MenuNavegacion.Pantalla.UNIRSE)
	await _foto("menu_4_conectarse")
	menu._nav.a_la_raiz()
	menu._abrir(MenuNavegacion.Pantalla.OPCIONES)
	await _foto("menu_5_opciones")

	if _fallo:
		push_error("Alguna captura del menu no se pudo guardar")
		get_tree().quit(1)
	else:
		print("capturas del menu en: ", absoluta)
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
