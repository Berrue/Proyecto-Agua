class_name TimonModel
extends RefCounted

## La matematica del GOBIERNO, separada del nodo para poder testearla sin
## simular inputs ni levantar un mar. Mismo patron que `FightModel` y
## `BombaModel`, y por el mismo motivo: aqui vive TODO lo que decide algo. Un
## nodo hijo de un `RigidBody3D` no se puede correr en headless y un RPC tampoco
## (`Net` es un autoload singleton), asi que una regla escrita dentro del nodo
## seria una regla sin prueba.
##
## [b]La tesis, en una frase: el timon no rota el barco.[/b] Es una superficie
## sustentadora sumergida, y de esa frase sale gratis todo lo que hace que
## gobernar se sienta como gobernar un barco:
##
##   1. La autoridad va con el CUADRADO del flujo: sin arrancada no hay timon, y
##      gestionar la velocidad se vuelve juego.
##   2. El angulo que manda es el EFECTIVO (pala menos deriva): la virada se
##      auto-limita —fase de ataque y fase de asiento— sin amortiguacion
##      inventada.
##   3. Pasados 45 grados la placa entra en PERDIDA sola: el tope de 35 de los
##      barcos reales EMERGE, no se decide.
##   4. El flujo es RELATIVO AL AGUA: en mar de popa, cuando el casco surfea la
##      cara de la ola a la velocidad de la ola, la pala se queda sin flujo y el
##      barco deja de obedecer. Eso es el BROACHING, y es una resta (ver
##      [method velocidad_relativa]), no un sistema que haya que escribir.
##
## Una sola matematica, TRES instancias (la descomposicion MMG de la
## arquitectura naval): el PLANO DE DERIVA del casco (delta = 0, a popa del
## centro de masas, el que impide patinar), la HELICE y la PALA. Ver
## `docs/TIMON.md`.

## La densidad se LEE de la flotabilidad en vez de copiarse: el mismo numero en
## dos sitios es un numero que un dia va a discrepar sin que nadie se entere.
const DENSIDAD_AGUA := FloatingBody3D.WATER_DENSITY

## Por debajo de este flujo la superficie no produce nada. No es un knob de
## feel: es la guarda contra dividir por un modulo casi cero al normalizar, y a
## 5 cm/s la fuerza real ya es despreciable (va con el cuadrado).
const FLUJO_MINIMO := 0.05


# =============================================================================
#  EL SIGNO — leer esto antes de tocar una linea
# =============================================================================
#
# Aqui se cruzan TRES convenciones de angulo, y confundirlas es exactamente el
# bug que la investigacion predijo ("si el barco cae a la banda contraria, hay
# que invertir"). Las tres, escritas:
#
#  1. EL MANDO (`mando`, `rueda`, y la `pala` normalizada): -1 = babor,
#     +1 = estribor. Es lo que devuelve
#     `Input.get_axis(&"timon_babor", &"timon_estribor")`, es lo que agarra el
#     jugador y es lo UNICO que viaja por el cable (F8 replica el eje crudo).
#
#  2. EL ANGULO HIDRODINAMICO (`pala_rad`, `alfa`): positivo hacia ESTRIBOR,
#     porque se mide en el mismo sentido que la deriva del flujo
#     —`atan2(flujo.x, -flujo.z)`—, y sin compartir sentido la resta de
#     [method angulo_ataque] no significaria nada. Con la proa en -Z, girar "de
#     proa hacia +X" es una rotacion NEGATIVA sobre +Y: de ahi el signo menos de
#     [method pala_rad_desde_mando], que no es un parche sino la traduccion.
#
#  3. LA ROTACION VISUAL del nodo de la pala (`rotation.y`, la de Godot): es la
#     del punto 2 cambiada de signo. Ver [method yaw_visual].
#
# Y el resultado que las ata, que es el que hay que comprobar:
#
#     mando a estribor + arrancada avante  =>  la proa cae a ESTRIBOR
#
# La cadena entera: mando +1 -> `pala_rad` NEGATIVO (la nariz de la pala a
# babor, o sea la cola a estribor: el "timon a estribor" del marino) -> `alfa`
# negativo -> `cl` negativo -> fuerza lateral a BABOR sobre una pala que esta a
# POPA -> la popa se va a babor y la proa cae a estribor. Es la unica
# combinacion que da marineria correcta, y `gobierno_tests` la clava con el par
# de guiñada calculado a mano.
#
# El arbitro FINAL sigue siendo el circulo de evolucion de F2 con el barco de
# verdad. Si alli cae a la banda contraria, se invierte AQUI —en
# [method pala_rad_desde_mando]— y en ningun otro sitio.


# =============================================================================
#  La superficie sustentadora
# =============================================================================

## Coeficiente de sustentacion de una placa plana.
##
## Entra en PERDIDA sola a 45 grados y se anula a 90: el tope de pala de 35 que
## usan los barcos reales SALE de aqui, no hay que decidirlo. Pasado el pico, la
## pala deja de girar el barco y solo frena.
static func cl(alfa: float) -> float:
	return sin(2.0 * alfa)


## Coeficiente de resistencia de una placa plana. Maximo a 90 grados, donde la
## pala ya es solo un freno de mano.
static func cd(alfa: float) -> float:
	var s := sin(alfa)
	return 2.0 * s * s


## Angulo de ataque EFECTIVO: lo que pide el jugador MENOS el angulo de deriva
## del flujo.
##
## Es el mecanismo que hace que la primera mitad de una virada tire mas que la
## segunda: segun el barco empieza a derrapar, la deriva se come angulo de pala
## y el giro se asienta solo. No hay ninguna curva de amortiguacion detras.
##
## ⚠️ `flujo_local` va en ejes del CASCO (a diferencia de
## [method fuerza_superficie], que trabaja en mundo). El barco mira a -Z
## —verificado: `RailBow` esta en z = -6.2—, asi que el avance es -z y la deriva
## a estribor es +x.
static func angulo_ataque(pala_rad: float, flujo_local: Vector3) -> float:
	var avance := -flujo_local.z
	var deriva := flujo_local.x
	# Sin flujo no hay angulo que medir: `atan2(0, 0)` es cero pero no significa
	# nada, y devolver `pala_rad` fingiria un ataque que no existe.
	if absf(avance) < 0.01 and absf(deriva) < 0.01:
		return 0.0
	return wrapf(pala_rad - atan2(deriva, avance), -PI, PI)


## Fuerza de una superficie sustentadora, en ejes de MUNDO.
##
## `v_rel` es la velocidad de la superficie RESPECTO AL AGUA: la orbital ya
## viene restada (ver [method velocidad_relativa]). `eje_mecha` es el eje de
## giro de la pala, o sea el "arriba" del casco — la sustentacion es
## perpendicular al flujo Y a ese eje.
##
## Vale igual para las tres instancias: plano de deriva (alfa = deriva pura),
## pala (alfa = pedido menos deriva) y cualquier apendice que se añada. Y
## funciona marcha atras sin un solo `if`, porque el seno lleva signo.
static func fuerza_superficie(v_rel: Vector3, alfa: float, area: float,
		eje_mecha: Vector3) -> Vector3:
	var u := v_rel.length()
	if u < FLUJO_MINIMO or area <= 0.0:
		return Vector3.ZERO

	# El flujo INCIDENTE es opuesto al movimiento de la superficie.
	var incidente := -v_rel / u
	var sust := eje_mecha.cross(incidente)
	if sust.length_squared() < 1e-6:
		return Vector3.ZERO # flujo paralelo a la mecha: no hay plano donde sustentar
	sust = sust.normalized()

	# La presion dinamica por el area. Aqui es donde vive el CUADRADO del que
	# sale el factor ~32 de autoridad entre mar de proa y surf-riding.
	var q := 0.5 * DENSIDAD_AGUA * area * u * u
	return sust * (q * cl(alfa)) + incidente * (q * cd(alfa))


## La velocidad de un punto del casco RESPECTO AL AGUA. La linea que lo cambia
## todo.
##
## Dos restas, y cada una paga algo:
##
##   1. La velocidad del PUNTO, no la del centro de masas: si el barco ya esta
##      guiñando, la pala se mueve de lado aunque el casco avance recto. Sin
##      esto la virada no se amortigua sola.
##   2. Menos la orbital del agua. Esta resta ES el broaching entero: cuando la
##      ola alcanza al barco por la aleta y lo lleva a su velocidad, `v_rel` cae
##      a casi cero, la pala se queda sin flujo y el timon deja de existir.
##
## `factor_orbital` existe por una razon fisica concreta:
## `Ocean.get_surface_velocity()` devuelve la orbital EN LA SUPERFICIE y la pala
## esta a casi un metro, donde la orbita ya decayo. De paso es la perilla de
## cuanto gobierno quieres que el mar te robe (0 = ninguno, 1 = broaching
## constante).
static func velocidad_relativa(v_lineal: Vector3, v_angular: Vector3,
		punto: Vector3, centro_masas: Vector3, orbital: Vector3,
		factor_orbital: float) -> Vector3:
	var v_punto := v_lineal + v_angular.cross(punto - centro_masas)
	return v_punto - orbital * factor_orbital


# =============================================================================
#  La traduccion mando -> pala -> nodo visible
# =============================================================================

## Del mando del jugador (-1 babor, +1 estribor) al angulo hidrodinamico.
##
## El signo menos es la traduccion entre las convenciones 1 y 2 del bloque de
## arriba, y es LA linea que hay que invertir si el circulo de evolucion de F2
## dice que el barco cae a la banda contraria. En ninguna otra.
static func pala_rad_desde_mando(mando: float, pala_max_deg: float) -> float:
	return -clampf(mando, -1.0, 1.0) * deg_to_rad(pala_max_deg)


## Del angulo hidrodinamico a la rotacion del nodo de la pala (y del aro del
## timon, y de la aguja del axiometro si algun dia la hay).
##
## Existe para que ningun `.gd` de presentacion tenga que acordarse del signo:
## si la pala VISIBLE mira al lado contrario que la fuerza, el feedback miente
## (regla 8) y encima nadie sabria cual de las dos esta mal.
static func yaw_visual(pala_rad: float) -> float:
	return -pala_rad


# =============================================================================
#  El mando: rate-limit de dos etapas
# =============================================================================
#
# Entre el pulgar del jugador y el rumbo hay TRES retardos apilados, y
# confundirlos es la causa numero uno de barcos que se sienten rotos en vez de
# pesados:
#
#   - Suavizado de input: 0 ms. SIEMPRE. Suavizar el input es un mando roto; lo
#     que se suaviza es la rueda.
#   - Mano -> rueda: 4-6 s tope a tope. El peso mecanico, y la perilla principal
#     de caracter.
#   - Rueda -> pala: el servo hidraulico. La segunda etapa es lo que lo hace
#     MECANICO en vez de pesado a secas.
#
# ⚠️ Las dos etapas son `move_toward` y NO `lerp`: lerp es exponencial y su
# resultado depende del tick rate, asi que el mismo gesto daria angulos
# distintos en dos maquinas —y en red, entre host y cliente—. `move_toward` es
# rate-limit puro. Y el `delta` de aqui no viola la regla 5 del repo: esa regla
# prohibe multiplicar FUERZAS por delta; aqui se integra una velocidad angular
# cinematica, que es exactamente donde delta corresponde.
#
# Es tambien el bug documentado de Sailwind (la rueda giraba a velocidad
# dependiente del framerate). Con `_physics_process` + `move_toward` no puede
# pasar; si alguien mueve esto a `_process` "porque es visual", vuelve.

## La rueda persiguiendo lo que pide la mano. `vuelta_completa_s` son los
## segundos de TOPE A TOPE, y el recorrido -1..1 son dos unidades.
static func avanzar_rueda(rueda: float, pedido: float, dt: float,
		vuelta_completa_s: float) -> float:
	var destino := clampf(pedido, -1.0, 1.0)
	if vuelta_completa_s <= 0.0:
		return destino
	return move_toward(rueda, destino, (2.0 / vuelta_completa_s) * maxf(dt, 0.0))


## La pala persiguiendo a la rueda: el servo.
##
## `pala_rate_deg` esta en grados de PALA por segundo y la pala se lleva
## normalizada, asi que el cociente con `pala_max_deg` es la conversion (los
## `deg_to_rad` de las dos se cancelan, por eso no aparecen).
static func avanzar_pala(pala: float, rueda: float, dt: float,
		pala_rate_deg: float, pala_max_deg: float) -> float:
	var destino := clampf(rueda, -1.0, 1.0)
	if pala_max_deg <= 0.0:
		return 0.0
	if pala_rate_deg <= 0.0:
		return destino
	return move_toward(pala, destino, (pala_rate_deg / pala_max_deg) * maxf(dt, 0.0))


## Zona muerta del eje, con reescalado.
##
## ⚠️ La deadzone por defecto del InputMap de Godot es 0,5, pensada para mover un
## personaje. Un timon INTEGRA el eje: con 0,5 se pierde todo el control fino y
## con 0 el drift del stick hace derivar la rueda sola con el mando quieto. Por
## eso las acciones del timon van a 0,10-0,15 y por eso esto no es solo un snap
## a cero: reescalar [zona..1] a [0..1] devuelve el control fino que la zona
## muerta acababa de comerse, que era justamente el motivo de bajarla.
static func aplicar_zona_muerta(eje: float, zona: float) -> float:
	var z := clampf(zona, 0.0, 0.99)
	var m := absf(eje)
	if m <= z:
		return 0.0
	return signf(eje) * ((m - z) / (1.0 - z))
