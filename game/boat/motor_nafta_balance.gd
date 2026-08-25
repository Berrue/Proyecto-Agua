class_name MotorNaftaBalance
extends Resource

## El balance del MOTOR y la NAFTA. Los dos en el MISMO recurso a proposito, por
## la misma razon que la entrada y la salida del agua embarcada comparten el
## suyo: cuanto empuja y cuanto bebe son los dos lados de la misma balanza, y el
## punto donde se cruzan ES el dial. Separarlos permitiria que alguien afinara la
## velocidad punta sin ver que acaba de dejar el barco sin autonomia.
##
## Posiciones en ejes del casco, proa a -Z, medidas contra `fishing_boat.tscn`.
## Ver `docs/TIMON.md` §5 y §8.

@export_group("Motor")

## Empuje de la helice a avante toda, en newtons. Manda la velocidad punta, y se
## calibra CONTRA el arrastre que ya aplican las ocho sondas: no hay una
## velocidad objetivo escrita en ningun sitio, sale del equilibrio.
##
## MEDIDO en `gobierno_tests`, que es el unico sitio donde este numero significa
## algo: 60 000 N dan **3,94 m/s (7,7 nudos)**, velocidad de pesquero. Los 26 000
## de la investigacion se quedaban en ~2,6 m/s (5 nudos), lento para las
## travesias del ciclo de marea.
##
## Es del orden de un motor real de este barco (20-40 kN) y algo generoso, y esa
## holgura tiene causa: el arrastre de la flotabilidad es ISOTROPO
## (`floating_body.gd` frena con `rel_vel.length()`), asi que frena el avance con
## el mismo coeficiente con el que amortigua el balanceo. Cuando F2b baje
## `drag_coefficient` —ya se puede, porque el plano de deriva da ahora la
## resistencia lateral que ese arrastre daba a lo bruto— la velocidad subira sola
## con este mismo empuje, y entonces este numero BAJA.
@export var empuje_max: float = 60000.0

## Segundos de STOP a AVANTE TODA.
##
## Es lo que impide que el barco arranque como un coche, y es la via honesta de
## vender inercia longitudinal sin implementar masa añadida traslacional (que se
## investigo y se descarto: cerca de la mitad de la masa el lazo oscila y
## diverge). Baja, el pesquero se siente ligero por muchas toneladas que pese.
@export var rampa_s: float = 2.5

## Velocidad que la helice inyecta sobre la pala a empuje pleno, en m/s.
##
## Es el GOLPE DE MAQUINA: timon a la banda mas una rafaga de motor y el barco
## gira casi sin arrancada. A cero no se puede maniobrar parado — y se pierde la
## unica respuesta que el broaching tiene.
@export var estela_ms: float = 4.5

## Donde empuja la helice. Justo por delante de la pala y bajo el casco; si sale
## del agua (`Ocean.get_submersion`), no empuja: en mar gruesa la popa se
## levanta y el motor se embala en vacio.
@export var pos_helice: Vector3 = Vector3(0.0, -1.0, 5.4)

@export_group("Nafta")

## Capacidad del tanque, en litros.
##
## HOLGADO, pero no infinito (docs/TIMON.md §0). Es el numero que decide si la
## nafta EXISTE, y esta cuadrado contra la salida tipo: unos 15 min navegando a
## media y otros 20 al ralenti pescando son ~20 litros, o sea el 45 % del
## tanque. Con eso, en una salida normal nadie piensa en la nafta —que es lo que
## pedia la decision—, pero estirar la marea o ir siempre a avante toda si vacia
## (15 min seguidos a toda son los 45 litros enteros). Un tanque chico devolveria
## el tedio que DREDGE corto; uno de 120 haria que la nafta no existiera.
@export var tanque_l: float = 45.0

## Litros por minuto de cada muesca del telegrafo. El indice es la muesca
## (`MotorModel.Muesca`): atras toda, atras, stop, poca, media, avante toda.
##
## La tabla no es proporcional al empuje y ese es el punto: correr sale
## desproporcionadamente caro. Avante toda bebe 2,5 veces lo de media para mover
## un 50 % mas de empuje, asi que la ruta rapida con mar de popa se paga en
## litros — que es justo la quinta decision del ciclo de marea (`DISENO.md` §1).
## El ralenti bebe poquisimo pero NO cero: apagar el motor mientras se cala
## tiene que ahorrar algo.
##
## ⚠️ Tiene que tener exactamente tantas entradas como muescas. Una tabla corta
## dejaria al motor bebiendo cero en las muescas altas sin un solo error en
## consola; `gobierno_tests` comprueba el tamaño por eso.
@export var consumos_l_min: PackedFloat32Array = PackedFloat32Array([3.0, 1.2,
	0.1, 0.6, 1.2, 3.0])

## Litros a partir de los cuales el motor empieza a TOSER.
##
## La segunda telegrafia, despues de la aguja (regla 8: todo fallo se avisa antes
## de castigar). A consumo de media son cinco minutos de aviso: tiempo de sobra
## para virar a puerto o mandar a alguien a por el bidon. A cero, el motor
## moriria de golpe y en silencio, que es el "me robo" que la regla prohibe.
@export var umbral_tos_l: float = 6.0

@export_group("El bidón")

## Litros de un bidon lleno. Poco mas de medio tanque: volcarlo entero es un
## rescate de verdad —te devuelve la salida— sin ser un tanque nuevo, y cabe en
## el hueco que deja cualquier tanque ya mordido, asi que no queda nafta muerta
## en cubierta.
@export var bidon_l: float = 25.0

## Litros por segundo que pasan del bidon al tanque. A ritmo VISIBLE y no de
## golpe: volcar un bidon en la boca de llenado con el barco escorando es
## porteo, y el porteo ya es contenido.
@export var ritmo_repostaje_l_s: float = 5.0
