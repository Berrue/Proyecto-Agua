extends Node

## Arnes del VOLCADO: que el barco vuelva solo del reves, y que siga siendo el
## agua —y solo el agua— lo que se lo impida.
##
##   <godot 4.7.2> --headless --path . tests/volcado_tests.tscn
##
## [b]El fallo que protege.[/b] Las ocho celdas del pesquero estan todas en un
## plano horizontal, asi que el empuje que reparten es simetrico: medido, el
## casco desnudo flota igual de bien del derecho que del reves y su estabilidad
## se anula pasados unos 78 grados de escora. Con el LEVIATAN volcaba 1 de cada
## 3 veces y se quedaba boca abajo PARA SIEMPRE — un estado sin salida, sin
## aviso y sin causa legible, que es justo lo que el diseño no permite.
##
## La decision (docs/DECISIONES.md) es que el pesquero sea AUTOADRIZANTE
## mientras conserve reserva: el mar te devuelve, y lo que pagas es el agua que
## entro mientras estabas del reves. Aqui se protegen las dos mitades:
##
##   1. que vuelva SIEMPRE con la bodega seca, desde cualquier angulo;
##   2. que NO vuelva con la bodega llena, porque si volviera siempre el agua
##      dejaria de matar y el naufragio dejaria de existir.
##
## Y la cadena de umbrales que las une, que es lo que hace honesto el aviso: la
## alarma de sentina suena ANTES de que el barco pierda el adrizamiento, y este
## se pierde antes de que se declare el naufragio.

const RUTA_BARCO := "res://game/boat/fishing_boat.tscn"
const RUTA_LEVIATAN := "res://resources/tsunami_tiers/tier_3_leviatan.tres"
const RUTA_BALANCE := "res://resources/agua/agua_embarcada.tres"

## Escora (grados) por debajo de la cual se considera que el barco ya volvio.
## No es cero: el barco sigue balanceandose con el mar, y exigir la vertical
## exacta seria exigir que el oleaje pare.
const ADRIZADO := 20.0

## Segundos que se le conceden para volver. El mar devuelve, no teletransporta:
## medido, el peor caso (180 grados, mar de furia 7) tarda unos 7 s.
const PLAZO_VUELTA := 12.0

## Angulos a los que se mide la curva de par. Cubren el rango en el que el casco
## desnudo empuja HACIA el vuelco (medido: negativo desde ~78 grados, con su
## peor momento en 150).
const ANGULOS_MEDIDOS: Array[float] = [90.0, 130.0, 150.0]

var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0


func _ready() -> void:
	print_rich("[b]--- Pruebas de volcado ---[/b]")
	_test_modelo_puro()
	_test_modelo_del_agua()
	await _test_curva_de_par()
	await _test_vuelve_desde_cualquier_angulo()
	await _test_con_la_bodega_llena_no_vuelve()
	await _test_navegar_no_toca_el_adrizamiento()
	await _test_el_leviatan_ya_no_lo_deja_boca_abajo()
	_report()


func _check(condition: bool, label: String, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("  ok    %s" % label)
	else:
		var line := "  FALLO %s%s" % [label, ("  ->  " + detail) if detail != "" else ""]
		print(line)
		_failures.append(label + (" :: " + detail if detail != "" else ""))


func _report() -> void:
	print("")
	if _failures.is_empty():
		print_rich("[color=green][b]%d/%d comprobaciones OK[/b][/color]" % [_checks, _checks])
		get_tree().quit(0)
	else:
		print_rich("[color=red][b]%d de %d comprobaciones han fallado:[/b][/color]" % [
			_failures.size(), _checks])
		for f in _failures:
			print("   - " + f)
		get_tree().quit(1)


# =============================================================================
#  Los modelos puros: aritmetica, sin escena y sin esperar un solo frame
# =============================================================================


func _test_modelo_puro() -> void:
	_check(is_zero_approx(AdrizamientoModel.inclinacion(Vector3.UP)), "en pie son 0 grados")
	_check(is_equal_approx(AdrizamientoModel.inclinacion(Vector3.DOWN), PI), "del reves son 180")
	_check(is_equal_approx(AdrizamientoModel.inclinacion(Vector3.RIGHT), PI * 0.5), "de costado, 90")

	# La curva: cero mientras la superestructura esta seca. Es lo que garantiza
	# que navegar normal se comporte EXACTAMENTE igual que sin este sistema.
	var inicio := deg_to_rad(45.0)
	var pleno := deg_to_rad(100.0)
	_check(is_zero_approx(AdrizamientoModel.curva(deg_to_rad(30.0), inicio, pleno)),
		"escorado 30 grados el brazo no existe todavia")
	_check(is_zero_approx(AdrizamientoModel.curva(inicio, inicio, pleno)), "y en el umbral tampoco")
	_check(is_equal_approx(AdrizamientoModel.curva(deg_to_rad(120.0), inicio, pleno), 1.0),
		"pasado el pleno el brazo es entero")
	_check(is_equal_approx(AdrizamientoModel.curva(PI, inicio, pleno), 1.0),
		"y del reves tambien: es donde mas falta hace")
	var media := AdrizamientoModel.curva(deg_to_rad(70.0), inicio, pleno)
	_check(media > 0.0 and media < 1.0, "entre medias sube suave, sin escalon",
		"%.3f" % media)

	# El eje. Girar un poquito sobre el tiene que ACERCAR el cuerpo a la
	# vertical: si el signo se invierte, el sistema tumba en vez de adrizar.
	var tumbado := Basis(Vector3.FORWARD, deg_to_rad(50.0)).y
	var eje := AdrizamientoModel.eje(tumbado, Vector3.FORWARD)
	_check(is_equal_approx(eje.length(), 1.0), "el eje sale unitario")
	var despues := Basis(eje, 0.02) * tumbado
	_check(AdrizamientoModel.inclinacion(despues) < AdrizamientoModel.inclinacion(tumbado),
		"girar sobre el eje acerca el cuerpo a la vertical, no lo tumba",
		"%.2f -> %.2f grados" % [
			rad_to_deg(AdrizamientoModel.inclinacion(tumbado)),
			rad_to_deg(AdrizamientoModel.inclinacion(despues))])

	# El desempate: EXACTAMENTE del reves no hay lado preferido. Que lo decida el
	# ruido de la fisica seria que cada maquina adrizara hacia un lado (regla 4).
	_check(AdrizamientoModel.eje(Vector3.DOWN, Vector3.FORWARD).is_equal_approx(Vector3.FORWARD),
		"del reves exacto manda el desempate, y es determinista")
	_check(AdrizamientoModel.eje(Vector3.DOWN, Vector3.ZERO).is_equal_approx(Vector3.RIGHT),
		"sin desempate valido sigue saliendo un eje fijo, no un NaN")

	# Mojado: el mar no adriza lo que no esta tocando.
	_check(is_zero_approx(AdrizamientoModel.mojado(0.0)), "en el aire no hay adrizamiento")
	_check(is_equal_approx(AdrizamientoModel.mojado(AdrizamientoModel.INMERSION_PLENA), 1.0),
		"con el cuerpo dentro del agua, entero")

	_check(is_zero_approx(AdrizamientoModel.ganancia(1.0, 0.0, 1.0)),
		"sin reserva no hay par: la bodega llena se lo lleva")
	_check(is_equal_approx(AdrizamientoModel.ganancia(1.0, 1.0, 1.0), 1.0), "seco y mojado, par pleno")

	# El par y su freno.
	var par_max := 100000.0
	var objetivo := deg_to_rad(35.0)
	var quieto := AdrizamientoModel.par(Vector3.RIGHT, par_max, 1.0, 0.0, objetivo)
	_check(quieto.is_equal_approx(Vector3.RIGHT * par_max),
		"parado empuja con todo el brazo")
	var al_ritmo := AdrizamientoModel.par(Vector3.RIGHT, par_max, 1.0, objetivo, objetivo)
	_check(al_ritmo.length() < par_max * 0.01,
		"al ritmo pedido deja de empujar: es un controlador, no una patada",
		"%.0f N*m" % al_ritmo.length())
	var pasado := AdrizamientoModel.par(Vector3.RIGHT, par_max, 1.0, objetivo * 8.0, objetivo)
	_check(pasado.dot(Vector3.RIGHT) < 0.0, "si se pasa de vueltas, frena")
	_check(pasado.length() <= par_max + 1.0,
		"y el freno esta acotado: nunca pega mas fuerte que el propio brazo",
		"%.0f N*m" % pasado.length())
	_check(AdrizamientoModel.par(Vector3.RIGHT, par_max, 0.0, 0.0, objetivo).is_zero_approx(),
		"sin ganancia no se aplica nada")

	# El estado VOLCADO y su banda.
	var umbral := deg_to_rad(100.0)
	var banda := deg_to_rad(25.0)
	_check(not AdrizamientoModel.volcado(deg_to_rad(95.0), umbral, banda, false),
		"el aviso no se adelanta")
	_check(AdrizamientoModel.volcado(deg_to_rad(105.0), umbral, banda, false), "salta en su umbral")
	_check(AdrizamientoModel.volcado(deg_to_rad(90.0), umbral, banda, true),
		"y no parpadea mientras el barco cabecea")
	_check(not AdrizamientoModel.volcado(deg_to_rad(70.0), umbral, banda, true),
		"pero se apaga al volver de verdad")


## Las dos puertas del agua que el volcado toca. Viven en `AguaEmbarcadaModel`
## porque son agua, no adrizamiento, pero es el volcado quien las necesita: sin
## ellas el barco del reves se llena mas rapido de lo que tarda en volver, y
## entonces da igual lo bueno que sea el par adrizante.
func _test_modelo_del_agua() -> void:
	_check(AguaEmbarcadaModel.cubierta_mira_arriba(Vector3.UP), "en pie hay cubierta donde embarcar")
	_check(not AguaEmbarcadaModel.cubierta_mira_arriba(Vector3.DOWN),
		"del reves no: no hay 'sobre la borda' que valga")
	_check(is_equal_approx(AguaEmbarcadaModel.factor_entierro(Vector3.UP), 1.0),
		"con la cubierta al cielo el entierro entra entero")
	_check(is_equal_approx(AguaEmbarcadaModel.factor_entierro(Vector3.DOWN),
			AguaEmbarcadaModel.FILTRACION_VOLCADO),
		"del reves solo se filtra: el aire atrapado es lo que lo mantiene a flote")
	_check(AguaEmbarcadaModel.FILTRACION_VOLCADO > 0.0,
		"pero se filtra ALGO: un barco volcado no puede quedarse asi para siempre")
	# Lo que este factor NO puede hacer es tocar el dial de otro sistema: con mar
	# de trabajo (escoras de 20-45 grados) tiene que valer 1 exacto, o le estaria
	# quitando agua a la tormenta que `agua_tests` afina.
	_check(is_equal_approx(
			AguaEmbarcadaModel.factor_entierro(Vector3(0.0, 0.7, 0.7).normalized()), 1.0),
		"escorado 45 grados entra IGUAL: por debajo del horizontal no se toca el balance")
	_check(AguaEmbarcadaModel.factor_entierro(Vector3(0.0, -0.2, 1.0).normalized()) < 0.5,
		"y pasado el horizontal se corta, que es lo que da tiempo a volver")


# =============================================================================
#  La curva de par, medida sobre el barco de verdad
# =============================================================================


## Mide el par de balance a escoras fijas y comprueba las dos cosas que importan:
## que el barco SECO vuelve desde cualquier angulo, y a partir de cuanta agua
## deja de volver.
##
## Se mide con el giro bloqueado y `AguaEmbarcada` apagada porque lo que se busca
## es la curva del CASCO, no una simulacion: si el barco se inunda mientras se
## mide, cada punto sale de un barco distinto y la curva no dice nada.
func _test_curva_de_par() -> void:
	var barco := _instanciar_barco()
	var brazo: float = barco.brazo_adrizante
	var peso: float = barco.mass * 9.81
	var inicio: float = deg_to_rad(barco.adrizamiento_inicio_deg)
	var pleno: float = deg_to_rad(barco.adrizamiento_pleno_deg)
	barco.queue_free()
	await get_tree().physics_frame

	_check(brazo > 0.0, "el pesquero lleva brazo adrizante", "%.2f m" % brazo)

	var peor_casco: float = 0.0
	var casco_ultimo: float = 0.0
	var todos_positivos := true
	var detalle := ""
	for grados in ANGULOS_MEDIDOS:
		var casco := await _par_a(grados, 0.0)
		casco_ultimo = casco
		var total := casco + peso * brazo * AdrizamientoModel.curva(
			deg_to_rad(grados), inicio, pleno)
		peor_casco = minf(peor_casco, casco)
		if total <= 0.0:
			todos_positivos = false
		detalle += "%.0f: casco %+.0f, total %+.0f  " % [grados, casco, total]

	_check(todos_positivos,
		"seco, el par adrizante es positivo a TODA escora: el barco siempre vuelve",
		detalle)
	_check(peor_casco < 0.0,
		"y sigue haciendo falta: el casco desnudo empuja hacia el vuelco",
		"peor %.0f N*m" % peor_casco)

	# El cableado: que el par que sale del cuerpo sea el que dice el modelo. Un
	# signo del reves o un eje mal elegido pasarian todos los tests puros.
	# El del casco es el ultimo del barrido de arriba (mismo angulo), y la curva
	# ahi vale 1: medirlo otra vez seria pagar doce segundos de simulacion por un
	# numero que ya esta.
	var medido := await _par_a(ANGULOS_MEDIDOS[-1], brazo)
	var esperado: float = casco_ultimo + peso * brazo
	_check(absf(medido - esperado) < absf(esperado) * 0.15,
		"el par que aplica el cuerpo es el que dice el modelo",
		"medido %.0f vs esperado %.0f N*m" % [medido, esperado])

	# La cadena de umbrales. Es lo mismo que protege `agua_tests` para el
	# naufragio, con un eslabon mas: el punto en el que el barco deja de saber
	# volver tiene que caer DESPUES de que la alarma lleve rato sonando (regla 8,
	# el fallo se telegrafia antes de castigar) y ANTES del naufragio, o habria
	# barcos declarados perdidos que todavia se adrizan solos.
	var balance := load(RUTA_BALANCE) as AguaEmbarcadaBalance
	if balance == null:
		_check(false, "el balance del agua carga", RUTA_BALANCE)
		return
	var limite: float = 1.0 - absf(peor_casco) / (peso * brazo)
	_check(limite > balance.umbral_alarma,
		"la alarma de sentina suena ANTES de que el barco pierda el adrizamiento",
		"alarma %.2f vs limite %.3f" % [balance.umbral_alarma, limite])
	_check(limite < balance.umbral_naufragio,
		"y el barco deja de volver antes de que se declare el naufragio",
		"limite %.3f vs naufragio %.2f" % [limite, balance.umbral_naufragio])


## Par de balance (N*m) con el barco sujeto a `grados` de escora. Positivo =
## devuelve a la vertical.
func _par_a(grados: float, brazo: float) -> float:
	var barco := _instanciar_barco()
	var agua := barco.get_node_or_null(^"AguaEmbarcada")
	if agua != null:
		agua.set_physics_process(false)
	barco.brazo_adrizante = brazo
	barco.axis_lock_angular_x = true
	barco.axis_lock_angular_y = true
	barco.axis_lock_angular_z = true
	# Sin amortiguar, la medida es una foto de un balanceo vertical y no un
	# equilibrio: el mismo angulo daba +35 kN*m o -14 segun el tick.
	barco.linear_damp = 2.0
	barco.global_transform = Transform3D(
		Basis(Vector3.FORWARD, deg_to_rad(grados)), Vector3(0.0, -0.2, 0.0))
	for _i in 600:
		await get_tree().physics_frame
	var suma: float = 0.0
	for _i in 120:
		await get_tree().physics_frame
		# El eje de balance es la eslora (-Z local); el par que REDUCE la escora
		# es el negativo de la componente sobre ese eje.
		suma += -barco.constant_torque.dot(-barco.global_basis.z)
	barco.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	return suma / 120.0


# =============================================================================
#  El barco de verdad, en el mar de verdad
# =============================================================================


func _test_vuelve_desde_cualquier_angulo() -> void:
	for caso in [[0.0, 180.0], [7.0, 180.0], [7.0, 130.0]]:
		var r := await _volcar(float(caso[0]), float(caso[1]), 0.0, 1440)
		_check(float(r[&"vuelta"]) >= 0.0 and float(r[&"vuelta"]) < PLAZO_VUELTA,
			"con la bodega seca vuelve del reves (furia %.0f, desde %.0f)" % caso,
			"%.1f s (plazo %.0f)" % [r[&"vuelta"], PLAZO_VUELTA])
		_check(float(r[&"peor_tras"]) < 90.0,
			"y vuelve entero: no se pasa de largo y vuelca hacia el otro lado",
			"peor escora despues: %.0f deg" % r[&"peor_tras"])
		_check(int(r[&"volcado"]) >= 1 and int(r[&"adrizado"]) == int(r[&"volcado"]),
			"el aviso de volcado se enciende y se apaga una vez por vuelco",
			"volcado %d, adrizado %d" % [r[&"volcado"], r[&"adrizado"]])


## La otra mitad de la decision, y la que impide que esto sea un truco: con la
## bodega llena el barco NO vuelve. Si volviera siempre, el agua dejaria de
## matar, la bomba dejaria de importar y el naufragio dejaria de existir.
func _test_con_la_bodega_llena_no_vuelve() -> void:
	var r := await _volcar(0.0, 180.0, 0.85, 1440)
	_check(float(r[&"vuelta"]) < 0.0,
		"inundado hasta arriba se queda del reves: el agua sigue siendo lo que mata",
		"volvio en %.1f s" % r[&"vuelta"])
	_check(float(r[&"inundacion"]) > 0.85,
		"y ademas sigue entrandole agua: el vuelco no es un refugio",
		"%.2f" % r[&"inundacion"])
	# La regla que el vuelco venia a traer: pase lo que pase, el barco no puede
	# quedarse en el limbo. O vuelve, o se declara el naufragio con su causa.
	# Un casco a flote, boca abajo y sin nada dicho es lo que habia antes.
	_check(bool(r[&"hundido"]),
		"y si no vuelve, el naufragio se declara: nunca un barco volcado en el limbo")


## Navegar no puede notar nada de todo esto. El brazo vale CERO por debajo de su
## umbral, asi que basta con comprobar que el mar en el que se juega no escora
## tanto: si un dia lo hace, este test lo dice antes que un playtest.
func _test_navegar_no_toca_el_adrizamiento() -> void:
	Ocean.clear_events()
	Ocean.set_fury_immediate(7.0)
	var barco := _instanciar_barco()
	barco.global_position = Vector3(0.0, 2.0, 0.0)
	var peor: float = 0.0
	for i in 2400:
		await get_tree().physics_frame
		if i > 600:
			peor = maxf(peor, rad_to_deg(barco.inclinacion))
	var umbral: float = barco.adrizamiento_inicio_deg
	barco.queue_free()
	await get_tree().physics_frame
	Ocean.set_fury_immediate(0.0)
	_check(peor < umbral,
		"a furia 7 el mar no llega a despertar el brazo adrizante",
		"escora maxima %.0f deg (el brazo empieza en %.0f)" % [peor, umbral])


## El fallo original, tal y como se midio: el muro del LEVIATAN sobre furia 7.
## Antes de esto el barco terminaba a 172-179 grados y se quedaba ahi el resto
## de la partida: a flote, boca abajo, sin aviso y sin causa.
##
## Lo que se exige aqui no es que SOBREVIVA —cuanta agua mete un tsunami es
## balance del agua embarcada, no del vuelco— sino que el final se pueda LEER: o
## vuelve, o el naufragio queda declarado con su causa. Medido hoy el LEVIATAN
## llena el barco al 90-100 % el solo, y pasa IGUAL sin brazo adrizante (0,90 al
## pasar el muro), asi que lo normal es que salga por la puerta del naufragio; el
## dia que el agua se cuadre saldra por la otra. Las dos son finales. El limbo no.
func _test_el_leviatan_ya_no_lo_deja_boca_abajo() -> void:
	var tier := load(RUTA_LEVIATAN) as TsunamiTier
	if tier == null:
		_check(false, "el tier LEVIATAN existe", RUTA_LEVIATAN)
		return

	Ocean.clear_events()
	Ocean.set_fury_immediate(7.0)
	var barco := _instanciar_barco()
	barco.global_position = Vector3(0.0, 3.0, 0.0)
	for _i in 600:
		await get_tree().physics_frame

	Ocean.spawn_tsunami_tier(barco.global_position, 90.0, 30.0, tier)
	var peor: float = 0.0
	var i: int = 0
	while i < 9000:
		await get_tree().physics_frame
		i += 1
		peor = maxf(peor, rad_to_deg(barco.inclinacion))
		if Ocean.time_until_tsunami(barco.global_position) < -20.0:
			break
	# Margen para que el mar lo devuelva o para que el naufragio se sostenga: el
	# muro ya paso, y la resaca es el valle protegido donde el diseño pone los
	# rescates y las risas.
	for _j in 1200:
		await get_tree().physics_frame

	var final_inc := rad_to_deg(barco.inclinacion)
	var agua := barco.get_node_or_null(^"AguaEmbarcada") as AguaEmbarcada
	var hundido: bool = agua != null and agua.hundido
	var inundacion: float = barco.flooding_level()
	barco.queue_free()
	await get_tree().physics_frame
	Ocean.clear_events()
	Ocean.set_fury_immediate(0.0)

	_check(peor > 45.0,
		"el muro le da de verdad: si no lo llega a tumbar, este test no prueba nada",
		"escora maxima %.0f deg" % peor)
	_check(final_inc < 90.0 or hundido,
		"pasado el LEVIATAN el barco vuelve o se declara hundido, pero no se queda en el limbo",
		"escora final %.0f deg, inundacion %.2f, naufragio %s" % [
			final_inc, inundacion, "si" if hundido else "NO"])


# =============================================================================


## Suelta el barco escorado `grados` con la bodega a `inundacion` y mira si
## vuelve. Devuelve { vuelta, peor_tras, volcado, adrizado, inundacion }.
func _volcar(furia: float, grados: float, inundacion: float, ticks: int) -> Dictionary:
	Ocean.clear_events()
	Ocean.set_fury_immediate(furia)
	var barco := _instanciar_barco()
	var cuenta := {&"volcado": 0, &"adrizado": 0}
	barco.volcado.connect(func() -> void: cuenta[&"volcado"] += 1)
	barco.adrizado.connect(func() -> void: cuenta[&"adrizado"] += 1)
	barco.global_transform = Transform3D(
		Basis(Vector3.FORWARD, deg_to_rad(grados)), Vector3(0.0, 2.0, 0.0))
	if inundacion > 0.0:
		for i in barco.probe_count():
			barco.flood_probe(i, inundacion)

	var vuelta: float = -1.0
	var peor_tras: float = 0.0
	for i in ticks:
		await get_tree().physics_frame
		var inc := rad_to_deg(barco.inclinacion)
		if inc < ADRIZADO and vuelta < 0.0:
			vuelta = float(i) / float(Engine.physics_ticks_per_second)
		elif vuelta >= 0.0:
			peor_tras = maxf(peor_tras, inc)

	var agua := barco.get_node_or_null(^"AguaEmbarcada") as AguaEmbarcada
	var salida := {
		&"vuelta": vuelta,
		&"peor_tras": peor_tras,
		&"volcado": cuenta[&"volcado"],
		&"adrizado": cuenta[&"adrizado"],
		&"inundacion": barco.flooding_level(),
		&"hundido": agua != null and agua.hundido,
	}
	barco.queue_free()
	# Dos frames: `queue_free` no libera hasta el final del frame y el barco de
	# la medida siguiente nace en el mismo sitio. Si coexisten un solo tick, Jolt
	# resuelve la penetracion hundiendo a uno de los dos.
	await get_tree().physics_frame
	await get_tree().physics_frame
	Ocean.set_fury_immediate(0.0)
	return salida


func _instanciar_barco() -> FloatingBody3D:
	var barco: FloatingBody3D = (load(RUTA_BARCO) as PackedScene).instantiate()
	add_child(barco)
	return barco
