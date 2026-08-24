class_name AguaEmbarcadaModel
extends RefCounted

## La matematica del agua que entra en el barco. PURO: cero nodos, cero Ocean,
## cero red — el mismo contrato que declaran `NetPorteo` y `FightModel`.
##
## La pureza aca no es elegancia: la simulacion del agua corre SOLO en el host,
## dentro de un nodo que cuelga del barco, y `Net` es un autoload singleton que
## no se puede levantar dos veces en un test headless. Si las reglas se quedan
## dentro del `_physics_process` del nodo, no hay forma de probarlas; aca abajo
## se prueban con aritmetica y sin escena.
##
## [b]El modelo, en una frase.[/b] El agua embarcada NO se simula como fluido ni
## se convierte en masa: baja el empuje de la celda donde entro
## ([member BuoyancyProbe3D.flooding]). Eso da gratis las tres cosas que el
## diseño pide —la escora hacia el lado anegado, el calado que crece, y la
## respuesta pastosa— sin una sola linea de HUD, y ademas hace que el punto sin
## retorno se pueda CALCULAR en vez de afinarlo a ojo (ver
## [method flooding_neutro] y [method techo_flotacion]).

const DENSIDAD_AGUA := 1000.0

## Fraccion del ritmo de entierro que sigue entrando con el barco DEL REVES.
##
## No es cero a proposito: una cubierta invertida atrapa aire, pero no es
## estanca — por las escotillas, la puerta de la cabina y los imbornales se va
## escapando. Sin este resto, un barco que vuelca ya inundado se queda tumbado a
## 90 grados PARA SIEMPRE: ni se adriza (le falta reserva) ni llega nunca al
## umbral de naufragio, que es exactamente el estado sin salida que el volcado
## venia a quitar. Con el, ese barco se hunde despacio y el final se puede leer.
const FILTRACION_VOLCADO := 0.10


# =============================================================================
#  Las olas sobre la borda
# =============================================================================

## Metros de agua por encima de la borda en un punto. <= 0 significa que la ola
## no embarco: paso por el costado, que es lo normal.
##
## El margen existe porque la superficie roza la borda continuamente con mar
## gruesa; sin el, cada rizo contaria como un embarque y el barco se llenaria
## por goteo constante en vez de por golpes que se ven venir.
static func rebase(altura_agua: float, altura_borda: float, margen: float) -> float:
	return altura_agua - altura_borda - margen


## 0..1 a partir del rebase. `rebase_pleno` es el metraje que satura la ola: por
## encima, mas altura no mete mas agua (la borda solo deja pasar lo que cabe por
## encima de ella en el tiempo que dura la cresta).
static func intensidad_ola(rebase_m: float, rebase_pleno: float) -> float:
	if rebase_m <= 0.0:
		return 0.0
	return clampf(rebase_m / maxf(rebase_pleno, 0.01), 0.0, 1.0)


## Cuanto sube el nivel MEDIO del barco una ola de esta intensidad.
## Los extremos son balance (docs/CLIMA.md §6.4: +0,03 a +0,08 por ola).
static func aporte_ola(intensidad: float, aporte_min: float, aporte_max: float) -> float:
	if intensidad <= 0.0:
		return 0.0
	return lerpf(aporte_min, aporte_max, clampf(intensidad, 0.0, 1.0))


## Convierte un aporte expresado sobre la MEDIA del barco en el aporte que hay
## que sumarle a cada una de las celdas afectadas.
##
## `flooding_level()` es la media de las n celdas, asi que subir la media en `a`
## tocando solo k celdas exige repartir `a * n / k` entre ellas. Sin esta
## conversion, mojar dos celdas de ocho subiria la media una cuarta parte de lo
## que dice el balance, y el dial de dificultad mentiria por un factor 4.
static func aporte_por_celda(aporte_agregado: float, n_celdas: int, n_afectadas: int) -> float:
	if n_afectadas <= 0 or n_celdas <= 0:
		return 0.0
	return aporte_agregado * float(n_celdas) / float(n_afectadas)


## Agua que embarca por MAR GRUESA, por segundo y sobre la media: rociones,
## salpicaduras y crestas que revientan contra la amura.
##
## [b]Por que existe esta fuente aparte de las olas sobre la borda.[/b] Medido en
## este proyecto: con el mar Gerstner actual, a las olas les falta MAS DE UN
## METRO para rebasar la regala, incluso a furia 9 con Hs de 18 m — y no hay ni
## un pantocazo. No es un fallo del modelo: las olas del espectro son largas
## (lambda de decenas a cientos de metros) y un pesquero de 13 m las cabalga
## siguiendo la superficie casi perfectamente. El agua verde por encima de la
## borda solo llega con el tsunami, que si entierra el barco.
##
## Pero un pesquero en temporal EMBARCA AGUA, y el juego la necesita: es lo que
## pone a alguien en la bomba mientras los demas pescan. Esa agua, en un barco
## real, no entra por encima de la regala: entra pulverizada por el viento y a
## crestazos contra el costado. Eso es lo que modela esta funcion.
##
## Crece con el CUADRADO de la furia por encima del umbral, no lineal: entre mar
## rizada y mar gruesa apenas cambia nada, y a partir de ahi se dispara. Asi la
## tormenta se siente como un salto de estado y no como una pendiente.
static func embarque_por_mar(furia: float, furia_umbral: float, maximo: float) -> float:
	if furia <= furia_umbral:
		return 0.0
	var t: float = clampf((furia - furia_umbral) / maxf(10.0 - furia_umbral, 0.01), 0.0, 1.0)
	return maximo * t * t


## Si la cubierta todavia mira hacia arriba. Pasado el horizontal ya no hay
## "sobre la borda" que valga: no queda cubierta donde embarcar, y lo que entre
## lo decide el aire atrapado (ver [method factor_entierro]).
##
## Es un corte duro y no una curva A PROPOSITO: por debajo de 90 grados no toca
## ni uno de los numeros que el balance afina, y por encima quita una fuente que
## ahi no significa nada. Sin el, un barco volcado se cobra un embarque cada vez
## que una regala cruza la superficie mientras se revuelca —medido: de 0 a 0,76
## en veinte segundos, mas rapido que ninguna tormenta— y el vuelco pasa a ser
## naufragio seguro por una via que nadie diseño.
static func cubierta_mira_arriba(arriba: Vector3) -> bool:
	return arriba.dot(Vector3.UP) > 0.0


## Cuanta agua entra por una celda ENTERRADA, 0..1, segun lo tumbado que este el
## casco. `arriba` es el eje Y del cuerpo.
##
## Con la cubierta mirando al cielo entra todo, y del reves casi nada: bajo una
## cubierta invertida queda AIRE ATRAPADO, y ese aire es justo lo que mantiene a
## flote a un barco volcado — es la razon de que un barco que vuelca se quede
## boca abajo en la superficie en vez de irse al fondo.
##
## Sin este factor, el vuelco es siempre naufragio y ningun adrizamiento llega a
## tiempo: medido, un barco del reves se llena a `ritmo_entierro` por celda (0,15
## /s) y toca el 100% en unos siete segundos, mientras que volver de 180 grados
## cuesta ocho. El agua tiene que seguir siendo lo que mata, pero por la puerta
## por la que entra de verdad.
##
## [b]La transicion va pegada al horizontal a proposito.[/b] Por debajo de ~84
## grados de escora esto vale 1 EXACTO, asi que no toca ni uno de los numeros que
## el balance de dificultad afina; por encima de ~96 solo queda la filtracion. La
## primera version repartia un coseno por todo el rango y le quitaba un 13 % del
## ingreso a una escora de 30 grados —que es mar de trabajo, no un vuelco—: eso
## es mover el dial de otro sistema de tapadillo. Y la banda es una rampa y no un
## escalon porque el salto se daria justo en el instante que mas se mira.
static func factor_entierro(arriba: Vector3) -> float:
	return lerpf(FILTRACION_VOLCADO, 1.0, smoothstep(-0.1, 0.1, arriba.dot(Vector3.UP)))


## Goteo de lluvia por segundo, sobre la media. Lineal con `rain01` porque la
## lluvia es INDEPENDIENTE de la furia por decision de diseño (ver `Ocean`): un
## dia calmo y diluviando tiene que costar algo, y una tormenta seca no.
static func goteo_lluvia(rain01: float, goteo_max: float) -> float:
	return clampf(rain01, 0.0, 1.0) * goteo_max


# =============================================================================
#  La geometria del hundimiento (la cuenta que fija los umbrales)
# =============================================================================

## Inundacion media a la que la cubierta queda al ras del agua en calma: el
## PUNTO SIN RETORNO practico, porque a partir de ahi cada celda queda enterrada
## y embarca sola.
##
## El calado de equilibrio con inundacion `f` es `d(f) = d0 / (1 - f)`, con
## `d0 = masa / (densidad * area)`. Igualando `d(f)` al francobordo sale esto.
## No depende de la gravedad ni del volumen: solo del area de flotacion y de lo
## alta que este la cubierta sobre las sondas.
static func flooding_neutro(masa: float, area_flotacion: float,
		calado_cubierta: float, densidad: float = DENSIDAD_AGUA) -> float:
	if area_flotacion <= 0.0 or calado_cubierta <= 0.0 or densidad <= 0.0:
		return 0.0
	var d0: float = masa / (densidad * area_flotacion)
	return clampf(1.0 - d0 / calado_cubierta, 0.0, 1.0)


## Inundacion media por encima de la cual el barco NO flota ni completamente
## sumergido: `1 - peso / empuje_maximo`. La gravedad se cancela en la division,
## asi que es geometria pura.
##
## Tiene que quedar POR ENCIMA de [method flooding_neutro] o el barco se hunde
## antes de que se vea entrar el agua, y no hay forma honesta de avisar (regla 8).
static func techo_flotacion(masa: float, volumen_total: float,
		densidad: float = DENSIDAD_AGUA) -> float:
	if volumen_total <= 0.0 or densidad <= 0.0:
		return 0.0
	return clampf(1.0 - masa / (densidad * volumen_total), 0.0, 1.0)


# =============================================================================
#  Alarma y naufragio
# =============================================================================

## Alarma con histeresis: enciende en `umbral` y no se apaga hasta bajar de
## `umbral - histeresis`. Sin la banda parpadea justo en el peor momento, que es
## cuando el nivel oscila alrededor del umbral.
static func estado_alarma(nivel: float, umbral: float, histeresis: float,
		estaba_encendida: bool) -> bool:
	if estaba_encendida:
		return nivel > umbral - maxf(histeresis, 0.0)
	return nivel >= umbral


## Acumulador del naufragio: devuelve los segundos que el nivel lleva SEGUIDOS
## por encima del umbral (0 en cuanto baja). Se declara naufragio cuando esto
## alcanza el sostenido del balance.
##
## Es sostenido y no instantaneo porque una ola grande puede cruzar el umbral
## un instante y drenarse sola: declarar el naufragio ahi seria castigar sin
## haber perdido el barco.
static func acumular_naufragio(nivel: float, umbral: float,
		acumulado_s: float, dt: float) -> float:
	if nivel < umbral:
		return 0.0
	return acumulado_s + maxf(dt, 0.0)


# =============================================================================
#  Geometria de celdas
# =============================================================================

## Indice de la celda mas cercana a un punto, comparando solo en el plano de
## cubierta (XZ local). La altura se ignora a proposito: el cabezal de la
## manguera cuelga y se balancea, y lo que decide de que compartimento aspira es
## DONDE esta sobre la cubierta, no a que altura quedo colgando ese tick.
static func celda_mas_cercana(celdas_xz: PackedVector2Array, punto_xz: Vector2) -> int:
	if celdas_xz.is_empty():
		return -1
	var mejor: int = 0
	var mejor_dist: float = INF
	for i in celdas_xz.size():
		var d: float = celdas_xz[i].distance_squared_to(punto_xz)
		if d < mejor_dist:
			mejor_dist = d
			mejor = i
	return mejor


## Las dos celdas mas cercanas y su reparto, para que una ola que entra por un
## punto de la borda moje a las dos de ese costado en vez de crear un pozo en
## una sola. Devuelve `[indice_a, indice_b, peso_a]`; `peso_b` es `1 - peso_a`.
##
## Con una sola celda la escora saldria a tirones (un compartimento entero se
## anega mientras el de al lado sigue seco); con el reparto por distancia el
## barco se tumba hacia el costado mojado, que es lo que se quiere leer.
static func reparto_dos_celdas(celdas_xz: PackedVector2Array, punto_xz: Vector2,
		sesgo: float = 0.6) -> Array:
	if celdas_xz.is_empty():
		return [-1, -1, 0.0]
	if celdas_xz.size() == 1:
		return [0, 0, 1.0]
	var a: int = -1
	var b: int = -1
	var da: float = INF
	var db: float = INF
	for i in celdas_xz.size():
		var d: float = celdas_xz[i].distance_squared_to(punto_xz)
		if d < da:
			b = a
			db = da
			a = i
			da = d
		elif d < db:
			b = i
			db = d
	return [a, b, clampf(sesgo, 0.5, 1.0)]
