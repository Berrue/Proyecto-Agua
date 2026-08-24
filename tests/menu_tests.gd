extends Node

## Arnés del MENÚ PRINCIPAL: la navegación, la ayuda de controles, los ajustes
## que se recuerdan y el cableado de la escena.
##
##   <godot 4.7.2> --headless --path . tests/menu_tests.tscn
##
## Un menú parece lo último que merece un test, y es justo al revés: es la única
## pantalla que TODO el mundo ve, y falla en silencio de tres formas que no se
## notan mirando una captura —una acción del InputMap renombrada y la ayuda
## enseñando teclas que ya no hacen nada; el fondo amaneciendo a otra hora
## porque alguien tocó el ciclo; el mar de la partida saliendo distinto porque
## la portada le escribió algo—. Las tres se comprueban aquí.

const RUTA_MENU := "res://game/ui/menu/menu_principal.tscn"
const RUTA_AJUSTES := "user://test_menu_ajustes.cfg"

var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0


func _ready() -> void:
	print_rich("[b]--- Pruebas del menu principal ---[/b]")
	_test_navegacion()
	_test_controles()
	_test_ajustes()
	await _test_escena()
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
#  La navegación, sin un solo nodo
# =============================================================================

func _test_navegacion() -> void:
	var nav := MenuNavegacion.new()
	_check(nav.actual() == MenuNavegacion.Pantalla.RAIZ,
		"el menu abre en la portada")
	_check(nav.en_raiz() and nav.ruta().is_empty(),
		"en la portada no hay miga de pan: el titulo ya dice donde estas")
	_check(not nav.atras(),
		"volver desde la portada no hace nada (y lo dice devolviendo false)")

	nav.abrir(MenuNavegacion.Pantalla.JUGAR)
	nav.abrir(MenuNavegacion.Pantalla.MULTIJUGADOR)
	_check(nav.ruta() == "Jugar" + MenuNavegacion.SEPARADOR + "Multijugador",
		"la miga de pan cuenta el camino entero", nav.ruta())
	_check(nav.profundidad() == 3, "tres paneles abiertos contando la portada")

	# El caso que se cuela siempre: doble clic en el mismo boton. Si se apilara,
	# haria falta pulsar «Atras» dos veces para salir de una pantalla en la que
	# solo se entro una — y eso se lee como un menu atascado.
	nav.abrir(MenuNavegacion.Pantalla.MULTIJUGADOR)
	_check(nav.profundidad() == 3, "abrir dos veces el mismo panel no lo apila")

	nav.abrir(MenuNavegacion.Pantalla.UNIRSE)
	_check(nav.atras() and nav.actual() == MenuNavegacion.Pantalla.MULTIJUGADOR,
		"escribir la direccion es un paso de multijugador, no un modo aparte")

	nav.a_la_raiz()
	_check(nav.en_raiz(), "se puede volver a la portada de un salto")

	# El separador va en la unica linea que dice donde esta el jugador: si la
	# fuente no lo tuviera, saldria un cuadrado (docs/TIPOGRAFIA.md).
	var punto := MenuNavegacion.SEPARADOR.strip_edges().unicode_at(0)
	_check(GameTypography.ui_bold().has_char(punto),
		"la fuente de la miga de pan tiene el punto medio")
	_check(GameTypography.ui_regular().has_char(
		ControlesBasicos.SEPARADOR.strip_edges().unicode_at(0)),
		"y la de la tabla de controles tambien")


# =============================================================================
#  La ayuda de controles no puede mentir
# =============================================================================

func _test_controles() -> void:
	# EL test de esta pantalla. Renombrar una accion en project.godot deja la
	# ayuda enseñando una tecla que ya no hace nada, y eso no da ni un error.
	for accion in ControlesBasicos.acciones():
		_check(InputMap.has_action(accion),
			"la accion '%s' que promete el menu existe en el InputMap" % accion)

	var filas := ControlesBasicos.filas()
	_check(filas.size() == ControlesBasicos.FILAS.size(),
		"la tabla sale entera")
	for fila in filas:
		_check(not String(fila["teclas"]).is_empty(),
			"la fila '%s' tiene teclas que enseñar" % fila["etiqueta"])

	_check(ControlesBasicos.nombre_de_tecla(KEY_SPACE) == "Espacio",
		"las teclas se dicen en español, no en el ingles de Godot",
		ControlesBasicos.nombre_de_tecla(KEY_SPACE))
	_check(ControlesBasicos.nombre_de_tecla(KEY_ESCAPE) == "Esc",
		"y abreviadas donde toca")
	_check(ControlesBasicos.teclas_de(&"grab").begins_with("Clic"),
		"agarrar sale como boton del raton, no como tecla",
		ControlesBasicos.teclas_de(&"grab"))
	_check(ControlesBasicos.teclas_de(&"no_existe_esta_accion").is_empty(),
		"una accion inventada deja el hueco en blanco en vez de reventar")

	# Andar son cuatro acciones en una sola fila: el jugador lee «W · A · S · D»
	# y no cuatro renglones.
	var andar := ControlesBasicos.teclas_de(&"move_forward") \
		+ ControlesBasicos.SEPARADOR + ControlesBasicos.teclas_de(&"move_left")
	_check(String(filas[0]["teclas"]).begins_with(andar),
		"andar junta sus cuatro teclas en una fila", String(filas[0]["teclas"]))


# =============================================================================
#  Lo que el menú recuerda
# =============================================================================

func _test_ajustes() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RUTA_AJUSTES))

	var vacio := MenuAjustes.cargar(RUTA_AJUSTES)
	_check(String(vacio[MenuAjustes.CLAVE_DISPOSITIVO]) == MicrofonoModel.POR_DEFECTO,
		"sin archivo se escucha por el aparato del sistema")
	_check(is_equal_approx(float(vacio[MenuAjustes.CLAVE_VOLUMEN]), 100.0),
		"y con la señal tal cual entra: 100 %")

	_check(MenuAjustes.guardar("Cascos USB", 160.0, RUTA_AJUSTES) == OK,
		"los ajustes se guardan")
	var leido := MenuAjustes.cargar(RUTA_AJUSTES)
	_check(String(leido[MenuAjustes.CLAVE_DISPOSITIVO]) == "Cascos USB",
		"el aparato elegido sobrevive al cierre del juego")
	_check(is_equal_approx(float(leido[MenuAjustes.CLAVE_VOLUMEN]), 160.0),
		"y la ganancia tambien")

	# Un .cfg editado a mano no puede acabar en la ganancia del bus.
	MenuAjustes.guardar("Cascos USB", 9000.0, RUTA_AJUSTES)
	_check(is_equal_approx(float(MenuAjustes.cargar(RUTA_AJUSTES)[MenuAjustes.CLAVE_VOLUMEN]),
			MicrofonoModel.PCT_MAX),
		"el volumen se acota al escribir, no solo al leer")

	var roto := FileAccess.open(RUTA_AJUSTES, FileAccess.WRITE)
	roto.store_string("esto no es un ini { ][ ")
	roto.close()
	var recuperado := MenuAjustes.cargar(RUTA_AJUSTES)
	_check(String(recuperado[MenuAjustes.CLAVE_DISPOSITIVO]) == MicrofonoModel.POR_DEFECTO,
		"un archivo roto devuelve los ajustes de fabrica, no deja el menu sin abrir")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(RUTA_AJUSTES))


# =============================================================================
#  El cableado de la escena
# =============================================================================

func _test_escena() -> void:
	var semilla := Ocean.ocean_seed
	var furia := Ocean.fury
	var lluvia := Ocean.rain_level

	var escena := (load(RUTA_MENU) as PackedScene).instantiate() as Node3D
	add_child(escena)
	for _i in 6:
		await get_tree().process_frame

	# --- El mar es un fondo, no una partida --------------------------------
	_check(is_equal_approx(Ocean.fury, MenuPrincipal.FURIA_PORTADA),
		"la portada pone su propia marejadilla: con la furia de arranque el cielo se encapota",
		"furia %.2f" % Ocean.fury)
	_check(Ocean.ocean_seed == semilla and is_equal_approx(Ocean.rain_level, lluvia),
		"y de lo demas no toca nada: ni semilla ni lluvia")

	var superficie := escena.get_node_or_null("OceanSurface")
	_check(superficie is OceanSurface3D, "el fondo es el oceano de verdad")
	var camara := escena.get_node_or_null("CamaraMenu") as CamaraMenu
	_check(camara != null and camara.current, "y hay una camara mirandolo")
	_check(is_equal_approx(camara.rotation.z, 0.0),
		"la camara del menu no rueda: el horizonte torcido delata el truco (regla 7)")

	var ciclo := escena.get_node_or_null("DayNightCycle") as DayNightCycle
	_check(ciclo != null and ciclo.profile != null, "el cielo tiene su ciclo y su perfil")
	_check(ciclo.hora_congelada, "con la hora congelada")
	var energia := ciclo.profile.sample_energy(
		ciclo.profile.sun_energy, ciclo.time_of_day(), ciclo.profile.sun_energy_max)
	_check(energia > 1.0 and not ciclo.is_night(),
		"y es de DIA: el fondo pedido es el mar de dia", "energia solar %.2f" % energia)
	var hora_antes := ciclo.hour()
	Ocean.sim_time += 900.0
	_check(is_equal_approx(hora_antes, ciclo.hour()),
		"quince minutos mirando el menu no anochecen la portada",
		"%.2f -> %.2f" % [hora_antes, ciclo.hour()])

	# --- La interfaz --------------------------------------------------------
	var menu := escena.get_node_or_null("MenuPrincipal") as MenuPrincipal
	_check(menu != null, "la escena trae su CanvasLayer de menu")
	if menu == null:
		escena.queue_free()
		return

	# Lo que hace al abrir la partida: el mar vuelve a ser el que era. Sin esto,
	# TODAS las partidas empezarian con la marejadilla de la portada.
	menu._devolver_el_mar()
	_check(is_equal_approx(Ocean.fury, furia),
		"y al abrir la partida devuelve el mar exactamente como lo encontro",
		"%.2f -> %.2f" % [furia, Ocean.fury])

	_check(menu._paneles.size() == MenuNavegacion.Pantalla.size(),
		"estan los cinco paneles: portada, jugar, multijugador, conectarse y opciones",
		"%d" % menu._paneles.size())
	_check(_visibles(menu) == 1, "solo se ve uno a la vez", "%d visibles" % _visibles(menu))
	_check((menu._paneles[MenuNavegacion.Pantalla.RAIZ] as Control).visible,
		"y el que se ve al arrancar es la portada")
	for panel: int in menu._paneles:
		_check(menu._foco_inicial.has(panel),
			"el panel %d dice quien coge el foco (el teclado tambien navega)" % panel)

	_check(ResourceLoader.exists(MenuPrincipal.RUTA_PARTIDA),
		"el mundo que abre «Jugar» existe", MenuPrincipal.RUTA_PARTIDA)

	# Regla 11: ni una fuente fijada a mano. Si un boton se queda con la fuente
	# por defecto de Godot, el menu deja de ser del mismo juego que el HUD.
	var display := GameTypography.display_hud()
	var todos_con_voz := true
	for boton in menu._botones:
		if boton.get_theme_font(&"font") != display:
			todos_con_voz = false
	_check(todos_con_voz and menu._botones.size() >= 8,
		"todos los botones piden su fuente a GameTypography",
		"%d botones" % menu._botones.size())

	menu._abrir(MenuNavegacion.Pantalla.MULTIJUGADOR)
	_check((menu._paneles[MenuNavegacion.Pantalla.MULTIJUGADOR] as Control).visible
			and _visibles(menu) == 1,
		"navegar cambia el panel visible")
	_check(menu._ruta.visible and not menu._ruta.text.is_empty(),
		"y fuera de la portada aparece la miga de pan")
	menu._atras()
	menu._atras()
	_check((menu._paneles[MenuNavegacion.Pantalla.RAIZ] as Control).visible,
		"y se vuelve")

	# El estado se pinta por LabelSettings: un `add_theme_color_override` no
	# haria nada y los errores saldrian del color de siempre, sin avisar de nada.
	menu._decir("prueba", MenuPrincipal.CORAL)
	_check(menu._estado.visible and menu._estado.label_settings.font_color == MenuPrincipal.CORAL,
		"los avisos del menu se ven y se tiñen")
	menu._decir("", MenuPrincipal.CREMA)
	_check(not menu._estado.visible, "y desaparecen cuando no hay nada que decir")

	# --- El micrófono -------------------------------------------------------
	_check(menu._mic_lista.item_count >= 1, "la lista de microfonos esta poblada")
	_check(String(menu._mic_lista.get_item_metadata(0)) == MicrofonoModel.POR_DEFECTO,
		"y la primera opcion es el del sistema, la unica que se puede prometer")
	_check(is_equal_approx(menu._mic_volumen.value, Microfono.volumen_pct),
		"el mando de ganancia arranca donde esta el bus, no en un numero inventado")
	_check(is_equal_approx(menu._mic_volumen.max_value, MicrofonoModel.PCT_MAX),
		"y llega hasta el mismo tope que el autoload (200 %)")
	_check(menu._mic_nivel != null and is_equal_approx(menu._mic_nivel.max_value, 1.0),
		"hay medidor de entrada: elegir microfono sin verlo saltar es adivinar")

	escena.queue_free()


func _visibles(menu: MenuPrincipal) -> int:
	var cuenta := 0
	for panel: int in menu._paneles:
		if (menu._paneles[panel] as Control).visible:
			cuenta += 1
	return cuenta
