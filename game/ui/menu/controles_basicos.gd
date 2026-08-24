class_name ControlesBasicos
extends RefCounted

## Los controles básicos tal y como los enseña el menú de opciones.
##
## [b]No hay ni una tecla escrita a mano.[/b] Cada fila nombra ACCIONES del
## InputMap y las teclas se leen de ahí, por dos motivos:
##
## 1. Regla 8 del repo — el feedback jamás miente. Una lista escrita a mano
##    envejece en silencio: se cambia el salto en `project.godot`, la ayuda
##    sigue diciendo «Espacio» y el jugador cree que el juego está roto.
## 2. Los teclados no son todos QWERTY. Las acciones de andar están grabadas por
##    código FÍSICO (la tecla de arriba a la izquierda del racimo), así que en un
##    AZERTY hay que enseñar `Z`, no `W`. Eso lo sabe el sistema operativo, no
##    nosotros.
##
## Es «básicos» a propósito: lo que hace falta para levantarse, moverse y coger
## algo. La pesca y la bomba se aprenden a bordo, con sus propios prompts.

## Nombres humanos y en español para las teclas que Godot llama en inglés. Solo
## las que salen en esta pantalla: una tabla completa sería otra lista que
## envejece sola.
const NOMBRES_TECLA := {
	KEY_ESCAPE: "Esc",
	KEY_SPACE: "Espacio",
	KEY_SHIFT: "Mayús",
	KEY_CTRL: "Ctrl",
	KEY_ALT: "Alt",
	KEY_ENTER: "Intro",
	KEY_TAB: "Tab",
}

## Botones del ratón. Abreviado porque va en una columna estrecha al lado de las
## teclas, no en un párrafo.
const NOMBRES_RATON := {
	MOUSE_BUTTON_LEFT: "Clic izq.",
	MOUSE_BUTTON_RIGHT: "Clic der.",
	MOUSE_BUTTON_MIDDLE: "Clic central",
	MOUSE_BUTTON_WHEEL_UP: "Rueda arriba",
	MOUSE_BUTTON_WHEEL_DOWN: "Rueda abajo",
}

## Une varias teclas de la misma fila. Punto medio, cubierto por las fuentes
## vendorizadas (`docs/TIPOGRAFIA.md`); una flecha o un guion largo no lo están
## en las tres a la vez.
const SEPARADOR := " · "

## Las filas de la tabla, en el orden en que se aprenden a bordo: primero
## sostenerse, después las manos, y al final la tecla que devuelve el ratón.
##
## `acciones` son nombres del InputMap y `fijo` es para lo que NO es una acción
## (el ratón de mirar no pasa por el InputMap: lo lee `player.gd` como
## `InputEventMouseMotion` crudo, así que aquí no hay nada que consultar).
const FILAS: Array[Dictionary] = [
	{"etiqueta": "Andar", "acciones": ["move_forward", "move_left", "move_back", "move_right"], "fijo": ""},
	{"etiqueta": "Mirar", "acciones": [], "fijo": "Ratón"},
	{"etiqueta": "Saltar", "acciones": ["jump"], "fijo": ""},
	{"etiqueta": "Agarrar y lanzar", "acciones": ["grab"], "fijo": ""},
	{"etiqueta": "Interactuar", "acciones": ["interact"], "fijo": ""},
	{"etiqueta": "Cinturón", "acciones": ["belt"], "fijo": ""},
	{"etiqueta": "Soltar el ratón", "acciones": ["toggle_mouse"], "fijo": ""},
]


## La tabla lista para pintar: `[{etiqueta, teclas}]`.
static func filas() -> Array[Dictionary]:
	var salida: Array[Dictionary] = []
	for fila in FILAS:
		salida.append({
			"etiqueta": String(fila["etiqueta"]),
			"teclas": _teclas_de_fila(fila),
		})
	return salida


static func _teclas_de_fila(fila: Dictionary) -> String:
	var trozos := PackedStringArray()
	for accion in fila["acciones"]:
		var texto := teclas_de(StringName(accion))
		if not texto.is_empty():
			trozos.append(texto)
	var fijo := String(fila.get("fijo", ""))
	if not fijo.is_empty():
		trozos.append(fijo)
	return SEPARADOR.join(trozos)


## Las teclas de una acción, ya legibles. Cadena vacía si la acción no existe:
## el menú enseña la fila con el hueco en blanco en vez de romperse, y
## `tests/menu_tests.tscn` es quien avisa de que alguien renombró una acción.
static func teclas_de(accion: StringName) -> String:
	if not InputMap.has_action(accion):
		return ""
	var trozos := PackedStringArray()
	for evento in InputMap.action_get_events(accion):
		var texto := nombre_de_evento(evento)
		if not texto.is_empty() and not trozos.has(texto):
			trozos.append(texto)
	return SEPARADOR.join(trozos)


## El nombre de un evento de entrada, en español y sin el «(Physical)» que Godot
## le pega a `as_text()`. Los mandos se ignoran: esta pantalla es de teclado y
## ratón, y un «Botón 0 del joypad» al lado de «W» no ayuda a nadie.
static func nombre_de_evento(evento: InputEvent) -> String:
	var tecla := evento as InputEventKey
	if tecla != null:
		return nombre_de_tecla(_keycode_de(tecla))
	var raton := evento as InputEventMouseButton
	if raton != null:
		return String(NOMBRES_RATON.get(raton.button_index, "Ratón"))
	return ""


## De un evento de teclado al código que hay que ENSEÑAR. Si está grabado por
## código físico se traduce a la distribución del jugador (QWERTY, AZERTY,
## QWERTZ...); si esa traducción no está disponible —headless no tiene teclado—
## se enseña el físico tal cual, que en QWERTY es el mismo.
static func _keycode_de(tecla: InputEventKey) -> int:
	if tecla.keycode != KEY_NONE:
		return tecla.keycode
	if tecla.physical_keycode == KEY_NONE:
		return KEY_NONE
	# El servidor de pantalla de `--headless` no sabe de teclados y protesta por
	# consola en cada tecla. Se pregunta antes: los arneses no pueden llenar la
	# salida de errores que no son fallos.
	if DisplayServer.get_name() == "headless":
		return tecla.physical_keycode
	var local := DisplayServer.keyboard_get_keycode_from_physical(tecla.physical_keycode)
	return local if local != KEY_NONE else tecla.physical_keycode


static func nombre_de_tecla(keycode: int) -> String:
	if keycode == KEY_NONE:
		return ""
	if NOMBRES_TECLA.has(keycode):
		return String(NOMBRES_TECLA[keycode])
	return OS.get_keycode_string(keycode)


## Todas las acciones que esta pantalla promete enseñar. Para el arnés: si una
## deja de existir en `project.godot`, la ayuda mentiría en silencio.
static func acciones() -> PackedStringArray:
	var salida := PackedStringArray()
	for fila in FILAS:
		for accion in fila["acciones"]:
			salida.append(String(accion))
	return salida
