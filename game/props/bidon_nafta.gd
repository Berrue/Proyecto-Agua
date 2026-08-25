class_name BidonNafta
extends Portable3D

## Un bidón de nafta: la reserva del pesquero, y la única forma de volver si el
## tanque se seca en la mar.
##
## [b]Por que es un objeto y no un numero[/b] (docs/TIMON.md §0): estibado en la
## bodega compite por sitio con el pescado, asi que llevar autonomia CUESTA
## captura — y esa es la decision de cada salida. Y repostar es PORTEO: cruzar la
## cubierta a dos manos con veinte kilos largos mientras el barco cabecea es la
## escena, no un menu.
##
## [b]FLOTA, y a proposito.[/b] La nafta es menos densa que el agua y un bidon
## cerrado es una boya, asi que la fisica ya lo pedia. Ademas el drama de perder
## algo al agua ya lo cubre la LLAVE, que si se hunde (`DISENO.md` §2): un bidon
## que se fuera al fondo al primer resbalon seria el mismo castigo dos veces, y
## la segunda sin aviso.
##
## Cuanto trae lleno NO se escribe aqui: sale de [member MotorNaftaBalance.bidon_l],
## que es el mismo numero contra el que se cuadra el tanque. Un bidon y un tanque
## afinados por separado son un dial que miente.

## Densidad de la nafta, kg por litro. Menor que la del agua — de ahi que flote.
const DENSIDAD_NAFTA := 0.84

@export var balance: MotorNaftaBalance

## Lo que pesa el bidon VACIO. La chapa y el asa.
@export var tara_kg: float = 3.0

## Lo que lleva dentro. Nace lleno; `-1` significa "lo que diga el balance".
@export var litros: float = -1.0


func _ready() -> void:
	super()
	if litros < 0.0:
		litros = capacidad()
	_sincronizar_masa()


## Cuanto cabe. Del balance, para que el bidon y el tanque se afinen juntos.
func capacidad() -> float:
	return balance.bidon_l if balance != null else 0.0


func vacio() -> bool:
	return litros <= 0.0


## Saca hasta `pedidos` litros y devuelve los que habia de verdad.
##
## Devolver lo REALMENTE sacado —y no lo pedido— es lo que hace que la nafta se
## conserve: quien llama le suma exactamente esto al tanque, asi que no se puede
## fabricar combustible ni perderlo por el camino.
func sacar(pedidos: float) -> float:
	var dan := clampf(pedidos, 0.0, maxf(litros, 0.0))
	litros -= dan
	_sincronizar_masa()
	return dan


## Lo que se lee en el prompt. Dice los litros porque el bidon es una DECISION
## (¿lo vuelco entero ahora o dejo para despues?) y decidir pide el dato.
func resumen() -> String:
	if vacio():
		return "bidón vacío"
	return "bidón · %.0f l" % litros


## El bidon pesa lo que lleva dentro.
##
## No es adorno: `Portador.factor_lentitud` lee este peso, asi que uno lleno
## frena de verdad al cruzar la cubierta y uno vacio casi no se nota. La
## diferencia entre ir a por nafta y volver con el bidon seco se SIENTE.
func _sincronizar_masa() -> void:
	mass = maxf(tara_kg + maxf(litros, 0.0) * DENSIDAD_NAFTA, 0.1)
