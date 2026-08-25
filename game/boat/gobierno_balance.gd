class_name GobiernoBalance
extends Resource

## El balance del GOBIERNO: se edita desde el editor sin tocar codigo.
##
## Todo lo de aqui son PUNTOS DE PARTIDA para iterar, no constantes fisicas —lo
## que si es invariante (la perdida a 45 grados, el cuadrado del flujo) vive
## dentro de `TimonModel` porque no se negocia—. El criterio de reparto es el de
## `CLAUDE.md`: invariante -> `const` en el archivo que lo usa; balance que edita
## diseño -> este recurso.
##
## Las posiciones van en ejes del CASCO, con la proa en -Z. Referencias medidas
## en `fishing_boat.tscn`, no estimadas: `RailBow` en z = -6.2, `RailStern` en
## z = +6.4, las ocho celdas de flotacion en y = -0.7 y el centro de masas
## forzado a (0, -0.45, 0).
##
## Ver `docs/TIMON.md` §8 (la tabla de perillas y que se rompe si cada una esta
## mal).

@export_group("Plano de deriva (el casco)")

## Area de la superficie que representa el costado sumergido del casco.
##
## Es lo que impide que el barco patine de lado como un cubito de hielo, y NO se
## resuelve con un segundo sistema de arrastre: eso duplicaria el que ya aplican
## las ocho sondas y serian dos numeros peleando por el mismo efecto. Baja:
## hielo. Alta: el barco no vira.
@export var area_plano_deriva: float = 9.0

## Donde vive esa superficie. La Z tiene que quedar POR DETRAS del centro de
## masas (que esta en z = 0): ahi esta la estabilidad direccional entera — el
## casco se orienta solo con el flujo y vuelve al rumbo. Delante del centro de
## masas el barco se vuelve inestable y no vuelve nunca.
@export var pos_plano_deriva: Vector3 = Vector3(0.0, -0.7, 1.25)

@export_group("Pala")

## Area de la pala del timon. Es la autoridad de gobierno: se ajusta hasta que
## el circulo de evolucion caiga entre 3 y 5 esloras (F2).
@export var area_pala: float = 1.1

## Donde cuelga la pala. A popa del todo —justo por dentro de `RailStern`— y mas
## abajo que las celdas: la pala vive bajo el casco, no a su altura.
@export var pos_pala: Vector3 = Vector3(0.0, -1.0, 6.0)

## Tope de angulo de pala. Pasados ~45 grados la placa entra en PERDIDA sola
## (`TimonModel.cl`), asi que mas de 40 aqui no gira mas: solo frena. Los 35 son
## los de los barcos reales, y salen de la misma cuenta.
@export var pala_max_deg: float = 35.0

@export_group("El agua")

## Cuanta orbital del mar se le resta al flujo sobre la pala.
##
## `Ocean.get_surface_velocity()` devuelve la orbital EN LA SUPERFICIE y la pala
## esta casi un metro mas abajo, donde la orbita ya decayo — de ahi que no sea 1.
## Y de paso es la perilla de cuanto gobierno te roba el mar: a 1,0 el broaching
## es constante; a 0 no existe y el mar de popa deja de dar miedo.
@export var factor_orbital: float = 0.7

@export_group("La rueda")

## Segundos de TOPE A TOPE de la rueda. La perilla principal de caracter: es el
## peso mecanico que separa "pesado" de "roto". Alto sin animacion visible que lo
## acompañe, se lee como lag.
@export var vuelta_completa_s: float = 5.0

## Grados de PALA por segundo del servo hidraulico: la segunda etapa, la que hace
## que el mando se sienta mecanico y no solo lento.
##
## ⚠️ 10 y no los 2,5 de la investigacion, a proposito. Los 2,5 grados/s son el
## minimo que SOLAS le exige a un buque (35 a 35 en 28 segundos) y este barco
## mide 12,6 m: con la rueda a 5 s tope a tope, la pala habria tardado 14 s en
## llegar al tope desde el centro y se habria quedado ONCE SEGUNDOS por detras de
## la rueda. La segunda etapa habria dejado de ser un matiz para ser el sistema
## entero, y el timonel estaria mirando una rueda que ya no significa nada. A 10
## la pala va ~1 s por detras: se ve, se siente, y no manda.
@export var pala_rate_deg: float = 10.0

## Zona muerta del eje del timon, con reescalado (`TimonModel.aplicar_zona_muerta`).
##
## ⚠️ El default del InputMap de Godot es 0,5, pensado para mover un personaje.
## Un timon INTEGRA el eje: con 0,5 se pierde el control fino entero y con 0 el
## drift del stick hace derivar la rueda sola con el mando quieto en la mesa.
@export var zona_muerta: float = 0.12

@export_group("Cabo de trinca")

## Segundos que el cabo de trinca mantiene el rumbo con la rueda sin nadie
## (`DISENO.md` §2). Es lo que permite que el timonel suelte y vaya a ayudar, y
## el reloj que convierte "voy un momento" en una apuesta.
@export var trinca_s: float = 12.0

## Lo mismo, pero con mar hecha: el cabo aguanta la mitad.
@export var trinca_s_temporal: float = 6.0

## Altura de ola significativa a partir de la cual se aplica el recorte de
## arriba.
@export var trinca_hs_temporal: float = 6.0
