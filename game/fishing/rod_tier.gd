class_name RodTier
extends Resource

## Un escalon de caña. Se edita como recurso desde el editor, igual que los
## tiers de tsunami (los .tres viven en resources/rod_tiers/).
##
## [b]Puerta blanda, jamas candado.[/b] Ninguna caña "desbloquea" peces: una
## caña floja PUEDE clavar un atun. La fisica (su tiron contra la capacidad
## real de este sedal) hara la captura casi imposible, pero el intento es
## legitimo, el sedal avisa como siempre (chirrido, ambar, rojo — normalizado
## contra SU limite real) y perderlo es una anecdota que pide mejor aparejo,
## no un cartel de "necesitas nivel 3". Es la regla 8 aplicada a la tienda.
##
## Y la regla del arbol de mejoras (DISENO §3, "prohibido +5% de X"): cada
## tier es una PIEZA que se ve — la empuñadura cambia de color hoy, un modelo
## propio mañana — y que se siente en tres sitios concretos: cuanta tension
## aguanta el sedal, cuanto recoge cada vuelta de carrete, y cuanta gracia
## extra da antes de partirse.

## Nombre corto: el HUD de debug hoy, la lonja mañana.
@export var tier_name: String = "Caña de iniciación"

@export_group("Sedal y carrete")
## Multiplica la tension que aguanta el sedal antes de la zona de rotura.
## Es LA cifra del tier: decide contra que banda peleas con dignidad.
@export var line_strength: float = 1.0
## Multiplica la velocidad de recogida (pausa y tiron por igual): mas
## carrete = capturas mas rapidas, la promesa central de la mejora.
@export var reel_factor: float = 1.0
## Segundos EXTRA de sobrecarga sostenida antes del snap. Se SUMAN a la
## ventana de reaccion del tier del pez (FightModel.SNAP_HOLD_BY_TIER):
## una caña mejor tambien perdona mas.
@export var snap_hold_bonus: float = 0.0

@export_group("Lanzamiento y pinta")
## Multiplica el alcance maximo del lanzamiento (llegar a bancos lejanos).
@export var cast_factor: float = 1.0
## El color de la empuñadura: la mejora se VE en tus manos y desde la borda
## de al lado. (Cuando haya arte propio, cada tier tendra su modelo.)
@export var accent_color: Color = Color(0.15, 0.13, 0.11)
