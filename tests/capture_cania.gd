extends Node

## Capturas del DOBLEZ de la caña: la misma caña, desde la misma cámara, con el
## doblez clavado a mano en cinco niveles.
##
## No es un test: es la regla para mirar la curva. El doblez real lo empuja un
## muelle que responde a la tensión, así que en una partida normal nunca ves el
## máximo el tiempo suficiente para juzgarlo — y juzgarlo es justo lo que hay
## que hacer cada vez que se toca el rig o el reparto muñeca/cuerpo.
##
##   godot --path . tests/capture_cania.tscn -- --shots-dir=<carpeta>

## Los cinco niveles, en radianes de `FishingRod._bend`. El negativo es la caña
## cargando el lanzamiento (ahí el cuerpo se arquea al REVÉS); 1.05 es el techo
## que da la lucha con un pez pesado y la tensión al máximo.
const NIVELES: Array[float] = [0.0, -0.35, 0.35, 0.7, 1.05]

var _dir: String = "user://shots"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots-dir="):
			_dir = arg.substr("--shots-dir=".length())
	DirAccess.make_dir_recursive_absolute(_dir)

	var scene: Node3D = load("res://game/world/toybox.tscn").instantiate()
	add_child(scene)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var player := scene.get_node(^"Player") as Player
	var rod := player.get_node(^"Camera3D/FishingRod") as FishingRod
	var hud := scene.get_node_or_null(^"OceanDebugHUD") as CanvasItem

	# Mar en calma: aquí el asunto es la caña, no el agua.
	Ocean.set_fury_immediate(0.5)
	for _i in 120:
		await get_tree().process_frame

	# La partida arranca con la caña clavada en el barco y para estas láminas
	# hace falta en la mano, que es donde se juzga el doblez. Va DESPUÉS de la
	# espera a propósito: clavarla es diferido (`_clavar_al_arrancar`), así que
	# retomarla en el mismo frame en que nace el mundo no retomaría nada.
	rod.retomar()
	if hud != null:
		hud.visible = false

	# El muelle del doblez tiraría de vuelta a cero en dos frames: se apaga el
	# proceso de la caña y se le dicta la pose a mano.
	rod.set_physics_process(false)
	for nivel: float in NIVELES:
		rod._bend = nivel
		rod._aplicar_doblez(nivel)
		# El aparejo cuelga de la punta con un muelle, asi que con el proceso
		# apagado se quedaria donde estaba y el sedal saldria estirado: se le
		# dejan los pasos que tarda el pendulo en asentarse en la punta NUEVA.
		for _p in 90:
			rod._mover_aparejo(1.0 / 60.0)
		rod._draw_line()
		for _i in 3:
			await get_tree().process_frame
		await _shoot("doblez_%+.2f" % nivel)

	print("capturas en: ", ProjectSettings.globalize_path(_dir))
	get_tree().quit(0)


func _shoot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png("%s/%s.png" % [_dir, label])
	print("%s  %s" % ["OK  " if err == OK else "FALLO", label])
