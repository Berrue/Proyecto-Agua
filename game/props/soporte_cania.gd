class_name SoporteCania
extends Marker3D

## El soporte de borda de la caña (DISENO §1, paso 3): clavarla libera las
## manos SIN dejar de pescar. La caña clavada sigue su maquina entera —
## espera, toques falsos, mordisco — y desde el 24-ago-2026 el soporte ya no
## tiene "su" caña: la caña de verdad SE MUDA aqui.
##
## Antes habia dos: el viewmodel escondido y un palo gris de primitivas que se
## encendia en la borda. Dos cañas siempre acaban contando cosas distintas —
## la gris no tenia ni sedal enhebrado ni aparejo ni tier, o sea que la caña
## clavada parecia otra— y ademas obligaba a que el doblez viajara a mano
## (`set_doblado`) en vez de salir del muelle real. Ahora `FishingRod` muda su
## pivote a `Cuna` y se lleva todo consigo: modelo, hilo, anzuelo con su cebo,
## el carrete que gira y los altavoces del freno. El doblez se ve porque es EL
## doblez (regla 8: la señal de estacion sale de la misma fisica que doblaria
## tus manos).
##
## El precio sigue siendo la ventana: la picada dura lo que dura, y retomar la
## caña (E) consume parte. Clavarla y alejarse es una APUESTA — oir el chomp,
## cruzar la cubierta y llegar a tiempo es contenido, no friccion.

## Inclinacion de reposo, apuntando fuera de la borda (-Z local). Vive tambien
## en la transformada de `Cuna`: este numero es el que la explica.
const BASE_RAD := -0.55

var ocupado: bool = false


func libre() -> bool:
	return not ocupado


func ocupar() -> void:
	ocupado = true


func liberar() -> void:
	ocupado = false


## Donde se planta el pivote de la caña al clavarla. Si faltara el nodo, la
## caña se clava en el soporte mismo: torcida, pero jugable.
func cuna() -> Node3D:
	var n := get_node_or_null(^"Cuna") as Node3D
	return n if n != null else self
