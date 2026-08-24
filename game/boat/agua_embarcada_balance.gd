class_name AguaEmbarcadaBalance
extends Resource

## El balance del agua embarcada: se edita desde el editor sin tocar codigo.
##
## Los numeros vienen de docs/CLIMA.md §6.4 (el bucle de achique), salvo los dos
## umbrales, que ahi estaban puestos a ojo y aqui salen de una cuenta —ver
## [member umbral_alarma]—. Ninguno de estos valores puede estar ademas escrito
## en un .gd: el dial de dificultad se cuadra editando ESTE recurso, y un numero
## repetido en dos sitios es un dial que miente.

@export_group("Olas sobre la borda")

## Metros que el agua tiene que superar la borda para que cuente como embarque.
## Sin margen, cada rizo que roza la regala contaria como una ola y el barco se
## llenaria por goteo constante en vez de por golpes que se ven venir.
@export var margen_borda: float = 0.30

## Rebase (en metros sobre la borda) que ya mete toda el agua que cabe. Por
## encima, mas altura no embarca mas: la cresta pasa igual de rapido.
@export var rebase_pleno: float = 1.50

## Cuanto sube el nivel MEDIO una ola floja y una ola plena. Los de CLIMA §6.4.
@export var aporte_ola_min: float = 0.03
@export var aporte_ola_max: float = 0.08

## Segundos que un punto de borda ignora nuevas olas despues de contar una. Es
## el antirebote: una sola cresta tarda cerca de un segundo en pasar y sin esto
## se contaria una vez por tick.
@export var enfriamiento_punto: float = 1.20

@export_group("Mar gruesa")

## Furia por debajo de la cual el mar no mete NADA de agua a bordo. Faena
## tranquila: se pesca sin vigilar la sentina.
@export var furia_umbral_embarque: float = 5.0

## Cuanta agua embarca el mar por segundo con la furia al maximo (rociones,
## salpicaduras y crestazos contra la amura, ver
## `AguaEmbarcadaModel.embarque_por_mar`).
##
## El valor sale de cuadrar el dial, no de la intuicion: con la curva cuadratica,
## la furia 8 se lleva el 36% de este maximo, asi que 0,055 deja la tormenta
## entrando a ~0,020/s — exactamente el caudal de la bomba. Dos personas
## achicando EMPATAN con el mar y cualquier ola de mas los desborda, que es el
## punto de equilibrio que pide docs/CLIMA.md §6.4; una sola persona (medio
## caudal) pierde despacio. Con 0,045 la bomba ganaba tan holgada que el nivel
## no llegaba a subir del cero y la tormenta no se sentia.
##
## A cero, el barco solo embarca por tsunami y lluvia.
@export var embarque_mar_max: float = 0.055

@export_group("Otras entradas")

## Subida del nivel medio por segundo con la lluvia al maximo. A este ritmo, un
## diluvio sostenido tarda unos 11 minutos en llegar a la alarma sin que nadie
## achique: la lluvia tiene que COSTAR algo (la leccion de Sea of Thieves, en
## CLIMA §1), no matarte sola.
@export var goteo_lluvia_max: float = 0.0008

## Subida por segundo de una celda cuya cubierta esta bajo el agua. Alto y
## capado: enterrarse es un trago de verdad, y si el barco ya venia inundado es
## la cascada que acaba en naufragio.
@export var ritmo_entierro: float = 0.15

@export_group("Umbrales")

## Nivel al que suena la alarma.
##
## CLIMA §6.4 proponia 0,75, pero la cuenta en frio lo desmiente: con la
## geometria del pesquero la cubierta queda al ras del agua con el nivel medio
## en ~0,69 (ver `AguaEmbarcadaModel.flooding_neutro`), o sea que una alarma a
## 0,75 sonaria DESPUES del punto sin retorno. La regla 8 del repo dice que todo
## fallo se telegrafia ANTES de castigar, asi que la alarma baja a 0,55: deja
## unos 0,14 de margen, que al ritmo de ingreso tipico son entre 7 y 15 segundos
## de aviso, mas lo que la bomba estire.
@export var umbral_alarma: float = 0.55

## Banda muerta para que la alarma no parpadee cuando el nivel oscila justo en
## el umbral.
@export var histeresis_alarma: float = 0.05

## Nivel a partir del cual se declara el naufragio.
##
## Va por encima del techo de flotacion (~0,83 con la reserva actual, ver
## `AguaEmbarcadaModel.techo_flotacion`): cuando esto salta, la fisica YA decidio
## que el barco no puede flotar. La señal confirma lo que se esta viendo, no lo
## provoca.
@export var umbral_naufragio: float = 0.85

## Segundos que hay que estar por encima del umbral para que sea naufragio. Una
## ola que llena la cubierta y se va no hunde el barco.
@export var sostenido_naufragio: float = 3.0

@export_group("Salidas")

## Cuanto BAJA el nivel medio por segundo con la bomba a pleno rendimiento
## (CLIMA §6.4: -0,02/s con alguien accionandola).
##
## Vive aqui, en el balance del AGUA, y no en el de la bomba, aunque sea la bomba
## quien lo aplica: entrada y salida son los dos lados de la misma balanza, y el
## punto de equilibrio ES el dial de dificultad del juego (CLIMA §6.4: "con furia
## 8+, 2 jugadores achicando deben empatar con el mar"). Separarlos en dos
## recursos permitiria que alguien afinara uno sin ver el otro, que es
## exactamente como se descuadra un dial.
@export var caudal_bomba: float = 0.02
