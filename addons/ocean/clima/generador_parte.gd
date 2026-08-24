class_name GeneradorParte
extends RefCounted

## Quien REDACTA el parte (docs/CLIMA.md §8 item 14, docs/DECISIONES.md
## 2026-08-24). Convierte una semilla en el clima entero de una salida.
##
## [b]La regla que ordena todo[/b], en palabras del diseñador:
##
##   «Si sube la furia NO tiene por que llover. Si sube la lluvia SI tiene que
##    subir la furia.»
##
## Es la causalidad real del mar. El mar VIAJA y la lluvia no: una tormenta a
## 300 km te manda su mar de fondo pero no su agua, y por eso furia 8 con cielo
## seco es un estado legitimo — ese mar es de OTRO lado. Pero la celda
## convectiva que descarga agua descarga viento, asi que el diluvio sobre mar
## planchado no existe.
##
## Formalmente: la lluvia impone un [b]piso[/b] a la furia,
## `furia(t) >= piso_furia(lluvia(t))`, y nunca al reves. No es un acoplamiento
## —la lluvia no empuja la furia— sino una restriccion sobre lo que este
## generador tiene permitido escribir.
##
## [b]Por eso el orden importa[/b]: se escribe PRIMERO la furia (la sierra por
## actos, el techo del caladero, la cota de pendiente) y DESPUES se encaja la
## lluvia dentro de las jorobas que le dan piso suficiente. El invariante queda
## cumplido por CONSTRUCCION — el mismo principio que el techo fotosensible de
## los rayos — y se verifica con [method violaciones_del_piso].
##
## Y lo que compra es legibilidad: el jugador razona como un pescador. Empieza
## a llover, el mar viene detras, garantizado. Mar enorme con cielo abierto, la
## tormenta esta en otra parte o ya paso.
##
## [b]Azar si, `randf()` no.[/b] Todo sale de la semilla, porque `DISENO.md`
## promete semilla diaria: «todos los grupos del mundo pescan el mismo mar ese
## dia». Con dados en vivo eso es imposible.

# =============================================================================
#  La regla
# =============================================================================

## Cuanta furia exige cada punto de lluvia. Llovizna (0.3) pide furia 2; lluvia
## franca (0.6) pide 4; diluvio (1.0) pide 6 — que es justo donde el cruce a
## «tormenta encima» de los rayos ya esta activo, asi que el diluvio trae rayos
## sin tocar esa formula.
const FURIA_POR_LLUVIA := 6.0

## Debajo de esto la lluvia no se lee en pantalla y solo ensucia el audio: si
## el piso no da para tanto, este acto sale seco y ya.
const LLUVIA_MINIMA := 0.15

## Cuanto puede crecer la altura significativa, en m/s. Sale de la
## investigacion (docs/CLIMA.md §4.4): por encima, modular `Q_i*A_i` produce un
## patinaje lateral visible en las crestas.
##
## [b]La cota va en Hs y NO en furia[/b], que es toda la diferencia: el
## `FURY_RATE_LIMIT` de 0.4 furia/s equivale a 2.8 m/s en el peor tramo del
## dial (de furia 9 a 10 hay 7 m de Hs), o sea 9 veces esto.
const COTA_HS := 0.3

## Un tramo con pendiente 0 en los dos extremos es exactamente un smoothstep, y
## un smoothstep alcanza 1.5x la pendiente media en su punto medio. Acotar la
## media dejaria pasar picos un 50% por encima de la cota.
const PICO_SOBRE_MEDIA := 1.5


## La furia MINIMA que exige esta lluvia.
static func piso_furia(lluvia: float) -> float:
	return clampf(lluvia, 0.0, 1.0) * FURIA_POR_LLUVIA


## La lluvia MAXIMA que esta furia permite. La inversa de [method piso_furia]:
## es lo que el generador usa para recortar el chubasco al mar disponible.
static func lluvia_maxima(furia: float) -> float:
	return clampf(furia / FURIA_POR_LLUVIA, 0.0, 1.0)


# =============================================================================
#  Redaccion
# =============================================================================

## Duracion de un acto. La sierra de Left 4 Dead que cita DISENO: gancho,
## escalada, pico, valle — y vuelta a empezar, cada vez mas arriba.
const ACTO_MIN := 180.0
const ACTO_MAX := 360.0

## [b]La salida es FINITA y tiene final[/b] (decision de diseño 2026-08-24): el
## parte se acaba, y que se acabe ES «se acabo la marea». Cuanto dura lo sortea
## la SEMILLA entre estos dos, no una constante fija: dos salidas seguidas en el
## mismo caladero no duran lo mismo, y aun asi las seis maquinas coinciden.
##
## 10-25 minutos casa con los 25-35 min por salida de DISENO dejando sitio al
## viaje de ida y vuelta al caladero.
const DURACION_MIN := 600.0
const DURACION_MAX := 1500.0


## Escribe el parte entero de una salida.
##
## [param techo_furia] es la promesa del caladero (BAHIA 3, BANCO 5, FOSA 7,
## AGUAS NEGRAS 9). Nada de lo que se escriba aqui la pasa: «la furia prometida
## es la furia entregada», y ahora eso incluye el cielo.
##
## [param duracion] en segundos, o -1 para que la sortee la semilla entre
## [constant DURACION_MIN] y [constant DURACION_MAX]. Es un TOPE de verdad: si
## los actos no caben, se generan menos actos hasta que quepan.
static func generar(semilla: int, techo_furia: float, duracion: float = -1.0,
		furia_inicial: float = 1.0, t0: float = 0.0) -> ParteMeteorologico:
	techo_furia = clampf(techo_furia, 0.0, 10.0)

	var objetivo: float = duracion
	if objetivo <= 0.0:
		# RNG aparte para la duracion: asi cambiar como se reparten los actos no
		# cambia cuanto dura la salida, ni al reves.
		var rng_dur := RandomNumberGenerator.new()
		rng_dur.seed = semilla ^ 0x44555241 # "DURA"
		objetivo = rng_dur.randf_range(DURACION_MIN, DURACION_MAX)
	objetivo = maxf(objetivo, ACTO_MIN)

	# LA DURACION ES UN TOPE, NO UN PISO. Antes esta cifra solo elegia CUANTOS
	# actos habia y cada acto duraba lo que le saliera: pedir 1500 s devolvia
	# entre 1733 y 2194 (medido), o sea hasta un 46 % de mas. Ahora se prueban
	# repartos de menos a menos actos hasta que uno cabe. Generar cuesta
	# microsegundos y cada intento re-siembra, asi que sigue siendo funcion pura
	# de la semilla.
	var parte := ParteMeteorologico.new()
	var jorobas: Array = []
	var rng := RandomNumberGenerator.new()
	var n_max: int = maxi(1, int(round(objetivo / ((ACTO_MIN + ACTO_MAX) * 0.5))))
	for n in range(n_max, 0, -1):
		rng.seed = semilla ^ 0x50415254 # "PART"
		parte = ParteMeteorologico.new()
		jorobas = _escribir_furia(parte, rng, techo_furia, n, furia_inicial, t0)
		if parte.duracion() - t0 <= objetivo:
			break
		# Si ni con UN acto cabe, gana la cota de pendiente de Hs y la salida
		# dura lo que la fisica permita: un mar que gana energia mas rapido de
		# lo que puede se ve, y ningun tope de reloj justifica eso.

	# Quitar actos deja la salida CORTA (un acto son ~10 min: la granularidad
	# es enorme), asi que el resto se recupera ESTIRANDO el guion hasta el
	# objetivo. Estirar es siempre legal: alarga los tramos, o sea que la
	# pendiente de Hs solo puede BAJAR — la cota se respeta por construccion.
	# Comprimir seria lo prohibido, y por eso el bucle de arriba nunca acepta
	# un guion mas largo que el objetivo (salvo que la fisica mande).
	var bruto: float = parte.duracion() - t0
	if bruto > 0.0 and bruto < objetivo:
		var factor: float = objetivo / bruto
		var estirado := ParteMeteorologico.new()
		for kf in parte.keyframes(ParteMeteorologico.FURIA):
			estirado.comprometer(ParteMeteorologico.FURIA,
				t0 + (kf.x - t0) * factor, kf.y, kf.z / factor)
		parte = estirado
		for joroba: Dictionary in jorobas:
			for campo: StringName in [&"t_pie", &"t_cima", &"t_meseta", &"t_fin"]:
				joroba[campo] = t0 + (float(joroba[campo]) - t0) * factor

	_escribir_lluvia(parte, rng, jorobas)
	_escribir_rumbo(parte, rng, jorobas, t0)
	return parte


## Primero la furia. Devuelve las jorobas escritas, que es lo que la lluvia
## necesita para saber donde tiene permiso de llover.
##
## Cada joroba es un diccionario: t_pie, t_cima, t_fin, furia_cima.
static func _escribir_furia(parte: ParteMeteorologico, rng: RandomNumberGenerator,
		techo: float, n_actos: int, furia_inicial: float, t0: float) -> Array:
	var jorobas: Array = []
	var t: float = t0
	parte.comprometer(ParteMeteorologico.FURIA, t, clampf(furia_inicial, 0.0, techo))

	n_actos = maxi(1, n_actos)
	var furia_previa: float = clampf(furia_inicial, 0.0, techo)

	for i in n_actos:
		# ESCALADA: cada acto apunta mas alto que el anterior. El ultimo llega
		# al techo del caladero, que es la promesa que el jugador compro al
		# elegir donde pescar.
		var avance: float = float(i) / maxf(float(n_actos - 1), 1.0)
		var cima: float = lerpf(techo * 0.45, techo, avance)
		cima = clampf(cima + rng.randf_range(-0.08, 0.08) * techo, 0.0, techo)
		var valle: float = clampf(cima * rng.randf_range(0.30, 0.52), 0.0, techo)

		var t_pie: float = t
		# SUBIDA. La cota manda sobre el guion: si el salto de Hs no cabe en el
		# tiempo que el acto queria, el acto se estira. Un mar que gana energia
		# mas rapido de lo que la fisica permite se VE, y no hay tuning que lo
		# tape.
		var subida: float = maxf(rng.randf_range(0.30, 0.45) * ACTO_MAX,
			_tiempo_minimo(furia_previa, cima))
		var t_cima: float = t_pie + subida
		parte.comprometer(ParteMeteorologico.FURIA, t_cima, cima)

		# MESETA: el mar se queda arriba un rato. Sin esto la cima es un pico y
		# no da tiempo a jugar la tormenta.
		var meseta: float = rng.randf_range(40.0, 110.0)
		var t_meseta: float = t_cima + meseta
		parte.comprometer(ParteMeteorologico.FURIA, t_meseta, cima)

		# BAJADA. Tambien acotada: el mar tampoco se desinfla de golpe.
		var bajada: float = maxf(rng.randf_range(0.25, 0.40) * ACTO_MAX,
			_tiempo_minimo(cima, valle))
		var t_fin: float = t_meseta + bajada
		parte.comprometer(ParteMeteorologico.FURIA, t_fin, valle)

		jorobas.append({
			&"t_pie": t_pie,
			&"t_cima": t_cima,
			&"t_meseta": t_meseta,
			&"t_fin": t_fin,
			&"furia_cima": cima,
		})
		furia_previa = valle
		t = t_fin

	return jorobas


## Segundos MINIMOS para ir de una furia a otra sin pasarse de [constant
## COTA_HS]. Se mide en metros de Hs, no en puntos de dial, porque el dial no
## es lineal: de 0 a 1 hay 10 cm y de 9 a 10 hay 7 metros.
static func _tiempo_minimo(furia_a: float, furia_b: float) -> float:
	# Con la pendiente MEDIA del tramo no alcanza, y por partida doble:
	#   1. el smoothstep pica un 50% por encima de su media (PICO_SOBRE_MEDIA);
	#   2. dHs/dfuria no es constante DENTRO del tramo — de 8 a 9 hay 4 m y de
	#      9 a 10 hay 7, asi que un tramo 8->10 acelera justo al final.
	# El pico real es max(dHs/dfuria) * max(dfuria/dt), y hay que acotar ESE.
	var salto_dial: float = absf(furia_b - furia_a)
	if salto_dial < 0.0001:
		return 0.0
	var pendiente: float = _pendiente_hs_maxima(minf(furia_a, furia_b), maxf(furia_a, furia_b))
	return PICO_SOBRE_MEDIA * salto_dial * pendiente / COTA_HS


## El mayor dHs/dfuria de la tabla Douglas dentro del rango, en m por punto.
static func _pendiente_hs_maxima(f_lo: float, f_hi: float) -> float:
	var tabla: Array[float] = Ocean.DOUGLAS_HS
	var peor: float = 0.0
	for i in tabla.size() - 1:
		# Solo los tramos de la tabla que el salto atraviesa de verdad.
		if float(i + 1) <= f_lo or float(i) >= f_hi:
			continue
		peor = maxf(peor, tabla[i + 1] - tabla[i])
	return maxf(peor, 0.0001)


## Y despues la lluvia, encajada DENTRO de las jorobas.
##
## La envolvente es ASIMETRICA a proposito: entra tarde y sale temprano
## respecto de su joroba de furia. El mar de fondo la precede (§3.3) y le
## sobrevive — cubierta mojada, cielo abriendo, mar todavia grande. El beat de
## «ya paso» sale gratis de la regla, sin scriptear nada.
static func _escribir_lluvia(parte: ParteMeteorologico, rng: RandomNumberGenerator,
		jorobas: Array) -> void:
	if jorobas.is_empty():
		return
	# Arranca seco. Si el primer chubasco no pone su propio cero delante, la
	# lluvia empezaria en el valor del primer keyframe desde el minuto cero.
	parte.comprometer(ParteMeteorologico.LLUVIA, float(jorobas[0][&"t_pie"]), 0.0)

	for joroba: Dictionary in jorobas:
		var llueve: bool = rng.randf() < 0.55
		if not llueve:
			continue

		var t_cima: float = joroba[&"t_cima"]
		var t_meseta: float = joroba[&"t_meseta"]
		var t_fin: float = joroba[&"t_fin"]

		# Entra ya empezada la meseta y sale antes de que el mar baje del todo.
		var rampa: float = rng.randf_range(25.0, 55.0)
		var t_in: float = lerpf(t_cima, t_meseta, rng.randf_range(0.15, 0.45))
		var t_out: float = lerpf(t_meseta, t_fin, rng.randf_range(0.20, 0.50))
		if t_out - t_in < 30.0:
			continue

		# El recorte por el piso. Se mide sobre la ventana ENTERA incluidas las
		# rampas, no solo sobre la meseta de lluvia: durante la rampa de subida
		# la furia todavia es menor, y es ahi donde el invariante se romperia.
		# Ser conservador aqui es justo lo que empuja al chubasco hacia el
		# centro de la joroba.
		var f_min: float = parte.extremos_en(
			ParteMeteorologico.FURIA, t_in - rampa, t_out + rampa).x
		var tope: float = lluvia_maxima(f_min)
		if tope < LLUVIA_MINIMA:
			# Este mar nunca fue lo bastante grande para justificar agua. En
			# BAHIA (techo 3) esto es lo normal, y es correcto: el caladero
			# promete tambien el cielo.
			continue
		var intensidad: float = clampf(
			tope * rng.randf_range(0.55, 1.0), LLUVIA_MINIMA, tope)

		parte.comprometer(ParteMeteorologico.LLUVIA, t_in - rampa, 0.0)
		parte.comprometer(ParteMeteorologico.LLUVIA, t_in, intensidad)
		parte.comprometer(ParteMeteorologico.LLUVIA, t_out, intensidad)
		parte.comprometer(ParteMeteorologico.LLUVIA, t_out + rampa, 0.0)


## De donde viene el frente. Alimenta `front_dir` del cielo, que esta
## implementado y a cero justo porque le faltaba esto.
static func _escribir_rumbo(parte: ParteMeteorologico, rng: RandomNumberGenerator,
		jorobas: Array, t0: float) -> void:
	# Arranca en la direccion del VIENTO, no en un rumbo suelto. Con
	# `rng.randf() * 360` el cielo dibujaba la pared de nubes en un lado
	# cualquiera mientras el espectro JONSWAP, las manchas de racha, las estrias
	# y la deriva del agua seguian apuntando a `wind_direction_deg`: la tormenta
	# se veia venir por babor y el mar llegaba por proa.
	var rumbo: float = Ocean.wind_direction_deg + rng.randf_range(-40.0, 40.0)
	parte.comprometer(ParteMeteorologico.RUMBO, t0, rumbo)
	for joroba: Dictionary in jorobas:
		# El frente rola despacio entre actos, como un sistema real pasando.
		rumbo += rng.randf_range(-55.0, 55.0)
		parte.comprometer(ParteMeteorologico.RUMBO, float(joroba[&"t_cima"]), rumbo)


# =============================================================================
#  Verificacion
# =============================================================================

## Devuelve los instantes donde el parte rompe el invariante. Vacio = correcto.
##
## No muestrea: recorre la rejilla UNION de los nudos de los dos canales y en
## cada celda compara la furia MINIMA contra la lluvia MAXIMA, las dos exactas
## (los extremos de un cubico salen de las raices de su derivada). Es una cota
## conservadora, asi que si esto sale limpio el invariante se cumple de verdad
## en todo instante, no solo en los puntos mirados.
static func violaciones_del_piso(parte: ParteMeteorologico) -> Array:
	var out: Array = []
	if not parte.tiene(ParteMeteorologico.LLUVIA):
		return out

	var cortes := PackedFloat32Array()
	for canal in [ParteMeteorologico.FURIA, ParteMeteorologico.LLUVIA]:
		for kf in parte.keyframes(canal):
			cortes.append(kf.x)
	cortes.sort()
	if cortes.size() < 2:
		return out

	for i in cortes.size() - 1:
		var a: float = cortes[i]
		var b: float = cortes[i + 1]
		if b - a < 0.0001:
			continue
		var furia_min: float = parte.extremos_en(ParteMeteorologico.FURIA, a, b).x
		var lluvia_max: float = parte.extremos_en(ParteMeteorologico.LLUVIA, a, b).y
		var exigida: float = piso_furia(lluvia_max)
		if furia_min < exigida - 0.001:
			out.append({
				&"desde": a,
				&"hasta": b,
				&"furia": furia_min,
				&"lluvia": lluvia_max,
				&"exigida": exigida,
			})
	return out
