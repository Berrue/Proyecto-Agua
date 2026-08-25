class_name GoldenOceano
extends Resource

## La tabla GOLDEN: lo que la GPU contesto, guardado para que la CPU se compare.
##
## [b]El problema que resuelve.[/b] El oleaje esta escrito DOS veces —
## `wave_proxy.gd` para la fisica y `ocean_waves.gdshaderinc` para lo que se ve—
## y tienen que ser espejos exactos (regla 3 del repo). Si divergen, el barco
## flota a una altura y la pantalla dibuja otra, y el fallo es COMPLETAMENTE
## SILENCIOSO: cada pantalla se ve perfecta por separado. Hasta hoy la unica
## defensa era mirar unas esferas a ojo.
##
## [b]Por que hay que partirlo en dos.[/b] En headless Godot no tiene
## `RenderingDevice`, asi que el shader no se puede ejecutar en CI (verificado;
## ver docs/PLAN.md §Verificacion). De ahi el reparto:
##   1. `addons/ocean/debug/golden_gen.tscn` corre CON ventana y GPU, pregunta
##      al shader y guarda esta tabla. Se commitea.
##   2. `tests/parity_tests.tscn` corre HEADLESS, evalua la CPU y compara.
##      Falla si algo se aparta mas de [constant TOLERANCIA].
##
## [b]Regenerarla es OBLIGATORIO[/b] en cualquier commit que toque una formula
## del agua. Si no, el test compara la CPU nueva contra una GPU vieja y falla —
## que es molesto pero es el lado correcto en el que fallar.

## Cuanto puede apartarse la CPU de la GPU, en metros. Un milimetro: por debajo
## empiezan a contar las diferencias de orden de operaciones y de precision
## entre una GPU y la FPU, que no son bugs.
const TOLERANCIA := 1e-3

## Muestras por lado del cuadro. 32x32 = 1024 puntos por combinacion, que es lo
## que pide docs/PLAN.md.
const LADO := 32
## Rango simetrico del empaquetado. Tiene que coincidir con el uniform `rango`
## de `golden_probe.gdshader`.
const RANGO := 64.0
## dx, altura, dz, jacobiano.
const COMPONENTES := 4

@export var semillas: PackedInt32Array = PackedInt32Array()
@export var furias: PackedFloat32Array = PackedFloat32Array()
@export var tiempos: PackedFloat32Array = PackedFloat32Array()
## Aplanado, en este orden: semilla, furia, tiempo, componente, fila, columna.
@export var valores: PackedFloat32Array = PackedFloat32Array()
## Cuando se genero y con que, para que un fallo se pueda fechar.
@export var generado: String = ""


## Posicion de reposo de la muestra (i, j).
##
## ⚠️ DUPLICADA a proposito en `golden_probe.gdshader`. Las dos caras del test
## tienen que poder calcular el punto por su cuenta —si una se lo preguntara a
## la otra, el test comprobaria que dos copias del mismo dato son iguales, que
## es siempre cierto. Si tocas una, toca la otra.
##
## Primos en los pasos y en los modulos para que la rejilla no se alinee con
## ninguna longitud de onda del banco: una rejilla regular puede caer entera en
## los nodos de una ola y dar cero error con la formula rota.
static func punto(i: int, j: int) -> Vector2:
	return Vector2(
		float((i * 37) % 977) - 488.0,
		float((j * 53) % 991) - 495.0)


func indice(s: int, f: int, t: int, comp: int, j: int, i: int) -> int:
	return ((((s * furias.size() + f) * tiempos.size() + t) * COMPONENTES + comp) \
		* LADO + j) * LADO + i


func total_muestras() -> int:
	return semillas.size() * furias.size() * tiempos.size() * COMPONENTES * LADO * LADO


func esta_vacia() -> bool:
	return valores.size() != total_muestras() or valores.is_empty()


## Un float en [0,1] repartido en cuatro canales de 8 bits, deshecho.
## Espejo exacto de `empaquetar()` en `golden_probe.gdshader`.
##
## Toma BYTES y no un `Color` a proposito: pedir colores al `Image` mete una
## conversion de espacio (medido: se codificaba 0.612 y se leia 0.303, que es
## sRGB->lineal) y envenenaba la tabla entera con ~39 m de error.
static func desempaquetar_bytes(r: int, g: int, b: int) -> float:
	var v: float = (float(r) + float(g) / 255.0 + float(b) / 65025.0) / 255.0
	return (v * 2.0 - 1.0) * RANGO
