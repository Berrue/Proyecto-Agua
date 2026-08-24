class_name AdrizamientoModel
extends RefCounted

## La matematica del ADRIZAMIENTO: el par que devuelve un cuerpo a su vertical
## y el estado VOLCADO. PURO: cero nodos, cero Ocean, cero fisica — el mismo
## contrato que declaran `AguaEmbarcadaModel`, `NetPorteo` y `FightModel`.
##
## La pureza aca no es elegancia: probar de verdad esto pide levantar el barco
## sobre el oceano y esperar minutos de simulacion (lo hace
## `tests/volcado_tests.tscn`, y tarda). La curva, el eje, el desempate y la
## histeresis se prueban aqui con aritmetica, en milisegundos y sin escena.
##
## [b]Por que hace falta un par aparte y no sale de las sondas.[/b] Las ocho
## celdas del pesquero estan TODAS en el mismo plano horizontal (y = -0,7), asi
## que el empuje que reparten es simetrico respecto a ese plano: el casco flota
## igual de bien del derecho que del reves. Medido con el barco de hoy en mar
## plana: soltandolo a 80 grados de escora —ni siquiera volcado— terminaba a 180
## y se quedaba ahi PARA SIEMPRE. Con el LEVIATAN pasaba en 1 de cada 3 intentos.
##
## Lo que al modelo de celdas le falta es la SUPERESTRUCTURA. En un barco de
## verdad la cabina estanca no toca el agua mientras navegas —no aporta nada—,
## pero al escorar se hunde y empuja hacia arriba desde muy alto y muy afuera;
## es exactamente lo que hace autoadrizante a un bote salvavidas. Aqui se aplica
## como lo que un arquitecto naval llamaria su curva de brazo adrizante GZ:
##
##   [b]cero mientras la cabina esta seca[/b] (por debajo de `inicio` el barco se
##   comporta EXACTAMENTE igual que antes de existir este archivo),
##   creciente mientras entra en el agua, y plena cuando esta sumergida.
##
## [b]El numero con el que se elige el brazo.[/b] Medida la curva del casco
## desnudo (giro bloqueado, bodega seca, en su calado de equilibrio): adriza
## hasta unos 78 grados y a partir de ahi empuja HACIA el vuelco, con su peor
## momento en -48 kN*m a 150 grados. El brazo tiene que superar eso, y como el
## par es peso x brazo, el pesquero (4 t) necesita mas de 1,22 m para volver
## estando seco. Lleva 3,5 m, que es lo que le deja volver hasta con la bodega
## al 65 % — y ese margen es justo lo que fija cuando el agua gana.
##
## Y va multiplicado por la reserva intacta (1 - inundacion): una bodega llena se
## lleva por delante el adrizamiento igual que se lleva la flotacion. Volcar no
## se castiga con un estado sin salida —el mar te devuelve—; lo que se paga es
## el agua que entro mientras estabas del reves.

## Modulo minimo de `arriba x UP` para fiarse de ese eje. Por debajo el cuerpo
## esta o en pie (y entonces la curva vale 0 y no se aplica par) o EXACTAMENTE
## del reves, que es un equilibrio inestable sin lado preferido: ahi el eje sale
## de un desempate fijo. No es un detalle de precision, es determinismo (regla
## 4): dejar que lo decida el ruido de la fisica es dejar que cada maquina
## adrice el barco hacia un lado distinto.
const EPS_EJE := 0.001

## Fraccion sumergida a partir de la cual el adrizamiento actua entero. El
## pesquero en reposo va al 0,17, asi que el umbral tiene que quedar MUY por
## debajo o el barco no se adrizaria nunca flotando normal; lo que corta de
## verdad es el caso "el cuerpo salio volando de la cresta": el mar no puede
## adrizar lo que no esta tocando.
const INMERSION_PLENA := 0.10


## Radianes entre el "arriba" del cuerpo y la vertical del mundo.
## 0 = en pie, PI = del reves.
static func inclinacion(arriba: Vector3) -> float:
	return arriba.angle_to(Vector3.UP)


## Eje unitario sobre el que hay que girar para devolver el cuerpo a la vertical.
##
## `desempate` es el eje que se usa cuando el cuerpo esta exactamente del reves.
## Para un barco tiene que ser su ESLORA (la proa): asi el desempate lo hace
## RODAR sobre el costado, que es como vuelve un barco de verdad, en vez de dar
## la voltereta sobre la proa.
static func eje(arriba: Vector3, desempate: Vector3) -> Vector3:
	var e := arriba.cross(Vector3.UP)
	if e.length_squared() > EPS_EJE * EPS_EJE:
		return e.normalized()
	var d := desempate.normalized()
	if d.is_zero_approx():
		return Vector3.RIGHT # cualquiera vale: lo que importa es que sea SIEMPRE el mismo
	return d


## Curva del brazo adrizante, 0..1, en funcion de la inclinacion (radianes).
##
## Es una rampa suave y no un escalon porque el escalon se nota: el par
## apareceria de golpe en mitad de un balanceo y el barco daria un tiron que el
## jugador no puede explicar (regla 8, el feedback no miente).
static func curva(inclinacion_rad: float, inicio_rad: float, pleno_rad: float) -> float:
	if inclinacion_rad <= inicio_rad:
		return 0.0
	if pleno_rad <= inicio_rad:
		return 1.0
	return smoothstep(inicio_rad, pleno_rad, inclinacion_rad)


## Cuanto cuenta estar mojado, 0..1. Ver [constant INMERSION_PLENA].
static func mojado(fraccion_sumergida: float) -> float:
	return clampf(fraccion_sumergida / INMERSION_PLENA, 0.0, 1.0)


## Ganancia total del par, 0..1: la curva por la reserva intacta por el mojado.
static func ganancia(curva_gz: float, reserva: float, fraccion_sumergida: float) -> float:
	return clampf(curva_gz, 0.0, 1.0) * clampf(reserva, 0.0, 1.0) * mojado(fraccion_sumergida)


## El par de adrizamiento, en N*m, listo para sumar al torque del cuerpo.
##
## `par_maximo` es peso x brazo adrizante: para un cuerpo que FLOTA, el peso es
## exactamente el empuje que lo sostiene, asi que peso x brazo es la formula
## naval del momento adrizante sin inventarse nada.
##
## `giro_axial` es la velocidad angular ya proyectada sobre el eje y
## `giro_objetivo` la velocidad a la que se quiere adrizar (rad/s). El cociente
## convierte esto en un controlador proporcional sobre la VELOCIDAD, no una
## patada: mientras el barco gira mas despacio de lo pedido empuja, y en cuanto
## se pasa frena. Sin ese freno el barco vuelve de 180 grados con tanta inercia
## que se pasa de largo y vuelca hacia el otro lado — un pendulo, no un rescate.
##
## El freno esta acotado a [-1, 1] a proposito: frenar puede costar como mucho
## lo mismo que adrizar. Sin el tope, un cuerpo que llega girando muy rapido
## (una ola que lo revuelca) recibiria un frenazo de varias veces el par maximo,
## que es la misma clase de fuerza desbocada que el "barril cohete" (regla 3).
static func par(eje_unitario: Vector3, par_maximo: float, ganancia_total: float,
		giro_axial: float, giro_objetivo: float) -> Vector3:
	if par_maximo <= 0.0 or ganancia_total <= 0.0:
		return Vector3.ZERO
	var freno: float = 1.0
	if giro_objetivo > 0.0:
		freno = clampf(1.0 - giro_axial / giro_objetivo, -1.0, 1.0)
	return eje_unitario * (par_maximo * ganancia_total * freno)


## Estado VOLCADO con histeresis: enciende en `umbral` y no se apaga hasta bajar
## de la banda.
##
## La banda no es un lujo: en el muro de un tsunami el barco cabecea decenas de
## grados en un segundo, y sin histeresis el estado parpadearia varias veces por
## segundo llevandose por delante todo lo que cuelgue de el (aviso, sonido, la
## maquina de estados del jugador de F4).
static func volcado(inclinacion_rad: float, umbral_rad: float, banda_rad: float,
		volcado_antes: bool) -> bool:
	if volcado_antes:
		return inclinacion_rad > umbral_rad - banda_rad
	return inclinacion_rad > umbral_rad
