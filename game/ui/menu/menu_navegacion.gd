class_name MenuNavegacion
extends RefCounted

## La navegación del menú principal, SIN un solo nodo: qué panel se ve y cómo
## se vuelve atrás.
##
## Vive aparte —y es pura— por el mismo motivo que `FightModel` o `NetPorteo`:
## en este repo, lo que DECIDE algo se puede probar en headless. Un menú es una
## máquina de estados diminuta, pero es justo donde se cuelan los fallos que no
## se ven en una captura: apilar dos veces el mismo panel y necesitar dos
## «Atrás» para salir de él, o volver desde la raíz a ninguna parte.

## Los paneles, en el orden en que se abren. `UNIRSE` cuelga de `MULTIJUGADOR`
## y no es un modo aparte: escribir la dirección es un PASO de «conectarse», no
## una tercera decisión.
enum Pantalla { RAIZ, JUGAR, MULTIJUGADOR, UNIRSE, OPCIONES }

## Cómo se llama cada panel en la miga de pan. La raíz no se nombra: encima
## está el título del juego, que ya dice dónde estás.
const NOMBRES := {
	Pantalla.RAIZ: "",
	Pantalla.JUGAR: "Jugar",
	Pantalla.MULTIJUGADOR: "Multijugador",
	Pantalla.UNIRSE: "Conectarse",
	Pantalla.OPCIONES: "Opciones",
}

## Separador de la miga de pan. Es el punto medio y no una flecha o un triángulo
## a propósito: `docs/TIPOGRAFIA.md` garantiza cobertura del punto medio en las
## fuentes vendorizadas, y un glifo que no exista se pinta como un cuadrado en
## la única línea que dice dónde está el jugador.
const SEPARADOR := " · "

## La pila de paneles abiertos. Siempre tiene al menos la raíz: un menú sin
## panel visible no es un estado válido, es un fotograma en negro.
var _pila: Array[int] = [Pantalla.RAIZ]


## El panel que se ve ahora.
func actual() -> int:
	return _pila[_pila.size() - 1]


## Abre un panel encima del actual. Abrir el que ya está abierto NO lo apila:
## si lo hiciera, un doble clic dejaría que hiciera falta pulsar «Atrás» dos
## veces para salir de una pantalla en la que solo se entró una.
func abrir(panel: int) -> void:
	if panel == actual():
		return
	_pila.append(panel)


## Vuelve un paso. Devuelve `false` si ya estaba en la raíz — quien llama decide
## qué significa eso (en el menú principal: nada; en la pausa: cerrar).
func atras() -> bool:
	if _pila.size() <= 1:
		return false
	_pila.resize(_pila.size() - 1)
	return true


func en_raiz() -> bool:
	return _pila.size() == 1


## Cuántos paneles hay abiertos contando la raíz. Para tests y para saber si
## «Atrás» tiene algo que hacer.
func profundidad() -> int:
	return _pila.size()


## Cierra todo y vuelve a la portada de un salto.
func a_la_raiz() -> void:
	_pila.resize(1)


## La miga de pan: «Jugar · Multijugador». Vacía en la raíz.
func ruta() -> String:
	var trozos := PackedStringArray()
	for panel: int in _pila:
		var nombre: String = NOMBRES.get(panel, "")
		if not nombre.is_empty():
			trozos.append(nombre)
	return SEPARADOR.join(trozos)
