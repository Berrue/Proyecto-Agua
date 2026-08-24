extends Node

## Arnés de la PARTIDA como sesión: el menú de `Esc` y la lista de `TAB`.
##
##   <godot 4.7.2> --headless --path . tests/partida_tests.tscn
##
## Lo que se prueba aquí es lo que falla en silencio: la aritmética de la lista
## de tripulación (nombres que llegan por la red, orden, pings, códec), que las
## dos teclas existan en el InputMap, y que el autoload sepa distinguir una
## partida de una portada — si esa cuenta se equivoca, `Esc` deja de abrir el
## menú o lo abre encima del menú principal, y ninguna de las dos cosas da error.
##
## Los RPC no se pueden probar: `Net` es un autoload SINGLETON y no se pueden
## levantar host y cliente en un proceso (docs/RED.md). Por eso la lista se
## pinta desde una tripulación de mentira.

const RUTA_MUNDO := "res://game/world/toybox.tscn"

var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0


func _ready() -> void:
	print_rich("[b]--- Pruebas de la partida (menu de Esc y lista de TAB) ---[/b]")
	_test_nombres()
	_test_orden()
	_test_pings()
	_test_codec()
	_test_teclas()
	_test_net_sin_red()
	await _test_autoload()
	_report()


func _check(condition: bool, label: String, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("  ok    %s" % label)
	else:
		print("  FALLO %s%s" % [label, ("  ->  " + detail) if detail != "" else ""])
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


# =============================================================================
#  Los nombres vienen de OTRA maquina
# =============================================================================

func _test_nombres() -> void:
	_check(NetTripulacion.limpiar_nombre("  Ana  ") == "Ana",
		"un nombre se guarda sin bordes")
	_check(NetTripulacion.limpiar_nombre("") == NetTripulacion.NOMBRE_POR_DEFECTO,
		"vacio no deja una fila sin nombre: cae a Marinero")
	_check(NetTripulacion.limpiar_nombre("   ") == NetTripulacion.NOMBRE_POR_DEFECTO,
		"y solo espacios, tambien")
	# Llega por la red desde otra maquina: un salto de linea parte la fila en
	# dos y un nombre de 4 kB empuja el ping fuera de la pantalla.
	_check(not NetTripulacion.limpiar_nombre("Ana\nB").contains("\n"),
		"un salto de linea no puede partir la lista en dos")
	_check(NetTripulacion.limpiar_nombre("Ana     B") == "Ana B",
		"los espacios de relleno se colapsan")
	var largo := NetTripulacion.limpiar_nombre("A".repeat(200))
	_check(largo.length() == NetTripulacion.NOMBRE_MAX,
		"y el nombre se corta al tope", "%d" % largo.length())

	var mia := NetTripulacion.fila(NetTripulacion.HOST, " Ana ", 40, true)
	_check(bool(mia["es_host"]), "el peer 1 es SIEMPRE el patron")
	_check(String(mia["nombre"]) == "Ana", "y la fila guarda el nombre ya limpio")
	_check(not bool(NetTripulacion.fila(7, "Ana", 40, false)["es_host"]),
		"y ningun otro peer lo es")


# =============================================================================
#  El orden tiene que ser estable
# =============================================================================

func _test_orden() -> void:
	var filas := [
		NetTripulacion.fila(9, "zoe", 20, false),
		NetTripulacion.fila(4, "Ana", 20, false),
		NetTripulacion.fila(NetTripulacion.HOST, "Nadia", 0, true),
	]
	var puestas := NetTripulacion.ordenar(filas)
	_check(bool(puestas[0]["es_host"]), "el patron va primero")
	_check(String(puestas[1]["nombre"]) == "Ana" and String(puestas[2]["nombre"]) == "zoe",
		"y el resto por nombre sin mirar mayusculas")

	# Dos ventanas en la misma maquina es EL ciclo de trabajo del repo: los dos
	# tripulantes se llaman igual y la lista no puede bailar entre refrescos.
	var iguales := NetTripulacion.ordenar([
		NetTripulacion.fila(8, "Berrue", 30, false),
		NetTripulacion.fila(3, "Berrue", 30, false),
	])
	_check(int(iguales[0]["peer"]) == 3,
		"con nombres repetidos desempata el peer, y el orden no cambia solo")


# =============================================================================
#  El retardo
# =============================================================================

func _test_pings() -> void:
	_check(NetTripulacion.texto_ms(NetTripulacion.MS_DESCONOCIDO) == "—",
		"un ping que no se sabe se dice, no se inventa un cero")
	_check(NetTripulacion.texto_ms(42) == "42 ms", "y el que se sabe lleva unidad")
	_check(NetTripulacion.calidad(NetTripulacion.MS_DESCONOCIDO)
			== NetTripulacion.Calidad.DESCONOCIDA,
		"sin dato no hay color")
	_check(NetTripulacion.calidad(0) == NetTripulacion.Calidad.BUENA,
		"cero es un ping buenisimo, no una ausencia")
	_check(NetTripulacion.calidad(NetTripulacion.MS_BUENO) == NetTripulacion.Calidad.BUENA,
		"el umbral bueno entra en bueno")
	_check(NetTripulacion.calidad(NetTripulacion.MS_BUENO + 1)
			== NetTripulacion.Calidad.REGULAR,
		"y un ms mas ya es regular")
	_check(NetTripulacion.calidad(NetTripulacion.MS_REGULAR + 1)
			== NetTripulacion.Calidad.MALA,
		"pasado el segundo umbral, malo")


# =============================================================================
#  El paquete viene de la red: puede llegar roto
# =============================================================================

func _test_codec() -> void:
	var filas := NetTripulacion.ordenar([
		NetTripulacion.fila(NetTripulacion.HOST, "Nadia", 0, false),
		NetTripulacion.fila(7, "Berrue", 84, true),
	])
	var vuelta := NetTripulacion.desempaquetar(NetTripulacion.empaquetar(filas), 7)
	_check(vuelta.size() == 2, "el paquete lleva a los dos", "%d" % vuelta.size())
	_check(String(vuelta[0]["nombre"]) == "Nadia" and int(vuelta[0]["peer"]) == 1,
		"con su nombre y su peer")
	_check(int(vuelta[1]["ms"]) == 84, "y su retardo", "%d" % int(vuelta[1]["ms"]))
	_check(bool(vuelta[1]["soy_yo"]) and not bool(vuelta[0]["soy_yo"]),
		"quien desempaqueta se reconoce a si mismo por su peer")

	# Un paquete truncado no puede tirar el HUD: viene de fuera.
	var roto := NetTripulacion.empaquetar(filas)
	roto.resize(4)
	_check(NetTripulacion.desempaquetar(roto, 7).size() == 1,
		"un paquete cortado por la mitad deja lo que se entiende")
	_check(NetTripulacion.desempaquetar(["basura", {}, []], 7).is_empty(),
		"y uno con basura no deja nada, pero tampoco revienta")
	_check(NetTripulacion.desempaquetar([], 7).is_empty(), "vacio, vacio")


# =============================================================================
#  Las dos teclas existen
# =============================================================================

func _test_teclas() -> void:
	# Si alguien borra la accion, TAB deja de abrir la lista y no salta ni un
	# error: el `_input` simplemente no encuentra nada que comparar.
	_check(InputMap.has_action(&"crew"),
		"la accion 'crew' (TAB) existe en el InputMap")
	_check(InputMap.has_action(&"toggle_mouse"),
		"y 'toggle_mouse' (Esc), que es la que abre el menu")
	_check(ControlesBasicos.teclas_de(&"crew") == "Tab",
		"y la ayuda del menu ensena la tecla de verdad",
		ControlesBasicos.teclas_de(&"crew"))


# =============================================================================
#  Net sin red
# =============================================================================

func _test_net_sin_red() -> void:
	_check(not Net.nombre_local.is_empty(),
		"siempre hay un nombre: sin ajustes, el de la sesion del sistema")
	_check(Net.nombre_local == NetTripulacion.limpiar_nombre(Net.nombre_local),
		"y ya viene saneado")

	var solo := Net.tripulacion()
	_check(solo.size() == 1, "en solitario la tripulacion es uno", "%d" % solo.size())
	_check(bool(solo[0]["soy_yo"]) and not bool(solo[0]["es_host"]),
		"eres tu, y no eres el patron de nadie")
	_check(int(solo[0]["ms"]) == NetTripulacion.MS_DESCONOCIDO,
		"sin red no hay ping que ensenar")

	# Preguntar por un peer que no existe no puede llenar la consola de errores
	# ni devolver un cero que se lea como «va perfecto».
	_check(Net.ping_de(NetTripulacion.HOST) == NetTripulacion.MS_DESCONOCIDO,
		"el ping de un peer que no esta se dice desconocido")
	Net.desconectar()
	_check(Net.rol == Net.Rol.OFFLINE,
		"desconectar sin estar conectado no hace nada y no rompe nada")


# =============================================================================
#  El autoload
# =============================================================================

func _test_autoload() -> void:
	_check(Partida != null, "el autoload Partida existe")
	_check(ResourceLoader.exists(Partida.RUTA_MENU),
		"y sabe volver a una portada que existe", Partida.RUTA_MENU)
	_check(not Partida.menu_visible(), "el menu de Esc arranca cerrado")
	_check(not Partida.en_partida(),
		"y en una escena sin jugador (esta) ni Esc ni TAB hacen nada")

	Partida.mostrar_menu(true)
	_check(Partida.menu_visible(), "se abre cuando se le pide")
	_check(Partida._botones.size() == 3,
		"con sus tres salidas: seguir, volver al menu y salir del juego",
		"%d" % Partida._botones.size())
	var display := GameTypography.display_hud()
	var con_voz := true
	for boton: Button in Partida._botones:
		if boton.get_theme_font(&"font") != display:
			con_voz = false
	_check(con_voz, "y con la misma voz que la portada (regla 11)")
	Partida.mostrar_menu(false)
	_check(not Partida.menu_visible(), "y se cierra")

	# La lista se pinta con lo que le den: asi se puede probar una tripulacion
	# de seis sin levantar una red, que en un proceso no se puede.
	Partida._pintar_lista(NetTripulacion.ordenar([
		NetTripulacion.fila(NetTripulacion.HOST, "Nadia", NetTripulacion.MS_DESCONOCIDO, false),
		NetTripulacion.fila(7, "Berrue", 84, true),
		NetTripulacion.fila(9, "Ana", 320, false),
	]))
	_check(Partida._filas.get_child_count() == 3,
		"tres tripulantes, tres filas", "%d" % Partida._filas.get_child_count())
	var textos := _textos_de_lista()
	_check(textos.contains("Nadia") and textos.contains("patrón"),
		"el patron sale marcado", textos)
	_check(textos.contains("84 ms") and textos.contains("—"),
		"cada uno con su retardo, y el que no se sabe dicho por su nombre", textos)
	_check(textos.contains("(tú)"), "y uno mismo se encuentra de un vistazo")

	# Y con el mundo delante, las dos teclas SI tienen sentido. Esto es lo que
	# caza que alguien renombre el nodo `Player` de la escena jugable: `Net`
	# hace la misma cuenta para saber quien eres.
	var arbol := get_tree()
	# Un frame antes de tocar la raiz: seguimos dentro del `_ready` del arnes y
	# ahi la raiz esta ocupada montando a sus hijos.
	await arbol.process_frame
	var mundo := (load(RUTA_MUNDO) as PackedScene).instantiate()
	arbol.root.add_child(mundo)
	arbol.current_scene = mundo
	for _i in 4:
		await arbol.process_frame
	_check(Partida.en_partida(),
		"con el mundo cargado, Esc y TAB vuelven a significar algo")

	# Y con las TECLAS de verdad, no llamando a la API: `_input` es cableado, y
	# el cableado es justo lo que se rompe en silencio (una accion renombrada,
	# otro nodo que se come el evento antes).
	await _pulsar(KEY_ESCAPE)
	_check(Partida.menu_visible(), "Esc abre el menu de sesion")
	await _pulsar(KEY_ESCAPE)
	_check(not Partida.menu_visible(), "y Esc otra vez lo cierra")

	await _tecla(KEY_TAB, true)
	_check(Partida._lista.visible, "TAB ensena la tripulacion...")
	await _tecla(KEY_TAB, false)
	_check(not Partida._lista.visible, "...solo mientras se tiene apretado")

	# La puerta de salida, de punta a punta: es LO que pidio el usuario y lo
	# unico que no se puede comprobar por partes.
	Partida.volver_al_menu()
	for _i in 8:
		await arbol.process_frame
	var actual := arbol.current_scene
	_check(actual != null and actual.scene_file_path == Partida.RUTA_MENU,
		"«Volver al menu» abre la portada",
		"" if actual == null else str(actual.scene_file_path))
	_check(Net.rol == Net.Rol.OFFLINE, "y suelta la red al salir")
	_check(not Partida.en_partida(),
		"y en la portada la cuenta se rehace: ahi ni Esc ni TAB significan nada")


## Una tecla apretada y soltada, por el camino real del sistema de entrada.
func _pulsar(codigo: Key) -> void:
	await _tecla(codigo, true)
	await _tecla(codigo, false)


func _tecla(codigo: Key, apretada: bool) -> void:
	var evento := InputEventKey.new()
	evento.keycode = codigo
	evento.pressed = apretada
	Input.parse_input_event(evento)
	Input.flush_buffered_events()
	await get_tree().process_frame
	await get_tree().process_frame


func _textos_de_lista() -> String:
	var partes := PackedStringArray()
	for fila in Partida._filas.get_children():
		for hijo in fila.get_children():
			var etiqueta := hijo as Label
			if etiqueta != null:
				partes.append(etiqueta.text)
	return " | ".join(partes)
