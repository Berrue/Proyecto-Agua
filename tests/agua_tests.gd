extends Node

## Arnes del AGUA EMBARCADA: la reserva de flotabilidad del barco, el modelo de
## inundacion y los umbrales de naufragio.
##
##   <godot 4.7.2> --headless --path . tests/agua_tests.tscn
##
## Lo que protege es una cadena de numeros que NADIE ve romperse: la linea de
## agua sale del cociente volumen/altura de las sondas, el techo de flotacion
## sale del volumen solo, y de esos dos salen el punto sin retorno y los umbrales
## de alarma y naufragio. Retocar una sonda en el editor mueve todo eso en
## silencio, y el sintoma no aparece hasta que alguien juega una tormenta.
##
## El reparto de papeles que estos tests fijan, medido y no supuesto: el OLEAJE
## (furia 0-10) nunca entierra la cubierta -- mojarse si, quedar debajo no --, y el
## TSUNAMI si. El agua embarcada tiene que venir de las olas sobre la borda y de
## los tragos del tsunami, no de que el barco viva sumergido.

const RUTA_BARCO := "res://game/boat/fishing_boat.tscn"
const RUTA_LEVIATAN := "res://resources/tsunami_tiers/tier_3_leviatan.tres"
const RUTA_BALANCE := "res://resources/agua/agua_embarcada.tres"

## Reserva minima exigida, en multiplos del peso. Manda el TECHO DE INUNDACION:
## el barco pierde la flotacion cuando la inundacion media llega a 1 - peso/empuje,
## que con la reserva vieja (3x) daba 0,667 -- por DEBAJO del 0,689 al que la
## cubierta queda al ras. O sea: se hundia antes de que se viera entrar el agua.
## Con 5x o mas el orden se invierte y el naufragio se puede leer y avisar.
const RESERVA_MINIMA := 5.0

## Area de flotacion = suma de volumen/altura de las sondas. Es lo unico que fija
## el calado de equilibrio y la rigidez: si alguien toca volume SIN tocar height
## (o al reves), el barco cambia de linea de agua y de periodo de cabeceo sin que
## se rompa ningun otro test.
const AREA_FLOTACION := 8.571
const AREA_TOLERANCIA := 0.02

## Margen de seguridad del francobordo con el peor oleaje, en metros. Medido:
## 0,36 m a furia 10 y 0,65 m a furia 9.
const FRANCOBORDO_MINIMO := 0.15

## Segundos DESPUES del paso del muro a partir de los cuales se considera que la
## resaca quedo atras y toca medir si el barco se recupero. Medido en la traza
## del LEVIATAN: a los -20 s el francobordo ya lleva rato estable en ~0,9 m.
const RESACA_PASADA := -20.0

var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0


func _ready() -> void:
	print_rich("[b]--- Pruebas de agua embarcada ---[/b]")
	_test_modelo_puro()
	_test_reserva_de_empuje()
	_test_umbrales_en_frio()
	_test_api_de_celdas()
	_test_escritor_unico()
	_test_puntos_borda_sobre_barandilla()
	_test_las_escenas_jugables_avisan()
	await _test_en_calma_no_entra_agua()
	await _test_lo_que_entra_es_lo_que_dice_el_balance()
	await _test_equilibrio_de_dificultad()
	await _test_el_agua_no_inclina_el_barco()
	await _test_la_piscina_se_ve()
	await _test_naufragio_y_reflote()
	await _test_el_oleaje_no_entierra()
	await _test_el_tsunami_si_entierra()
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


## El modelo puro: aritmetica, sin escena y sin esperar un solo frame.
func _test_modelo_puro() -> void:
	# El margen es lo que separa "me entro una ola" de "la superficie roza la
	# borda", que con mar gruesa pasa continuamente.
	_check(AguaEmbarcadaModel.rebase(2.0, 1.75, 0.30) < 0.0, "rozar la borda no cuenta como embarque")
	_check(AguaEmbarcadaModel.rebase(2.5, 1.75, 0.30) > 0.0, "medio metro por encima si cuenta")

	_check(is_equal_approx(AguaEmbarcadaModel.intensidad_ola(0.0, 1.5), 0.0), "sin rebase no hay intensidad")
	_check(is_equal_approx(AguaEmbarcadaModel.intensidad_ola(3.0, 1.5), 1.0),
		"la intensidad satura: mas altura no mete mas agua")

	_check(is_equal_approx(AguaEmbarcadaModel.aporte_ola(0.0, 0.03, 0.08), 0.0), "una ola nula no aporta nada")
	_check(is_equal_approx(AguaEmbarcadaModel.aporte_ola(1.0, 0.03, 0.08), 0.08),
		"la ola plena aporta el maximo del balance")

	# La conversion media->celda es la que hace que el dial no mienta: mojar 2
	# celdas de 8 tiene que subir la MEDIA lo que dice el balance.
	var por_celda := AguaEmbarcadaModel.aporte_por_celda(0.08, 8, 2)
	_check(is_equal_approx(por_celda * 2.0 / 8.0, 0.08),
		"repartir en 2 celdas de 8 sube la media exactamente lo pedido",
		"%.4f por celda" % por_celda)

	# Mar gruesa: nada por debajo del umbral, y curva acelerada por encima. Es la
	# fuente que sostiene el achique en tormenta, porque las olas de este mar no
	# rebasan la regala ni a furia 9 (ver `embarque_por_mar`).
	_check(is_zero_approx(AguaEmbarcadaModel.embarque_por_mar(4.0, 5.0, 0.045)),
		"con mar de trabajo no embarca nada")
	_check(is_zero_approx(AguaEmbarcadaModel.embarque_por_mar(5.0, 5.0, 0.045)),
		"y justo en el umbral tampoco")
	var e8 := AguaEmbarcadaModel.embarque_por_mar(8.0, 5.0, 0.045)
	var e6 := AguaEmbarcadaModel.embarque_por_mar(6.0, 5.0, 0.045)
	_check(e8 > e6 * 4.0, "la tormenta se dispara, no sube en pendiente",
		"furia 6: %.4f/s vs furia 8: %.4f/s" % [e6, e8])
	_check(is_equal_approx(AguaEmbarcadaModel.embarque_por_mar(10.0, 5.0, 0.045), 0.045),
		"y a furia 10 entra el maximo del balance")

	_check(is_equal_approx(AguaEmbarcadaModel.goteo_lluvia(0.0, 0.0008), 0.0), "sin lluvia no gotea")
	_check(is_equal_approx(AguaEmbarcadaModel.goteo_lluvia(1.0, 0.0008), 0.0008), "con diluvio gotea el maximo")

	# Alarma: enciende en el umbral y aguanta encendida hasta bajar de la banda.
	_check(not AguaEmbarcadaModel.estado_alarma(0.50, 0.55, 0.05, false), "la alarma no se adelanta")
	_check(AguaEmbarcadaModel.estado_alarma(0.55, 0.55, 0.05, false), "la alarma salta en su umbral")
	_check(AguaEmbarcadaModel.estado_alarma(0.52, 0.55, 0.05, true), "y no parpadea al oscilar")
	_check(not AguaEmbarcadaModel.estado_alarma(0.49, 0.55, 0.05, true), "pero se apaga al bajar de la banda")

	# Naufragio sostenido: cruzar el umbral un instante no hunde el barco.
	var acc := AguaEmbarcadaModel.acumular_naufragio(0.9, 0.85, 0.0, 1.0)
	acc = AguaEmbarcadaModel.acumular_naufragio(0.9, 0.85, acc, 1.0)
	_check(is_equal_approx(acc, 2.0), "el acumulador suma mientras esta por encima")
	_check(is_equal_approx(AguaEmbarcadaModel.acumular_naufragio(0.8, 0.85, acc, 1.0), 0.0),
		"y se reinicia en cuanto baja: una ola sola no es un naufragio")

	# Geometria de celdas.
	var celdas := PackedVector2Array([Vector2(-1.5, -4.0), Vector2(1.5, -4.0),
		Vector2(-1.5, 4.5), Vector2(1.5, 4.5)])
	_check(AguaEmbarcadaModel.celda_mas_cercana(celdas, Vector2(-1.4, -3.5)) == 0,
		"la celda mas cercana es la de su rincon")
	_check(AguaEmbarcadaModel.celda_mas_cercana(PackedVector2Array(), Vector2.ZERO) == -1,
		"sin celdas devuelve -1 en vez de reventar")
	var reparto := AguaEmbarcadaModel.reparto_dos_celdas(celdas, Vector2(0.0, -4.0))
	_check(int(reparto[0]) != int(reparto[1]),
		"el reparto usa dos celdas distintas")
	_check(int(reparto[0]) <= 1 and int(reparto[1]) <= 1,
		"y son las dos de la proa, que es donde entro la ola")


## La cuenta en frio de la reserva. No simula nada: lee las sondas reales de la
## escena y hace la aritmetica de Arquimedes.
func _test_reserva_de_empuje() -> void:
	var barco := _instanciar_barco()

	var g: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.81))
	var peso: float = barco.mass * g

	var volumen_total: float = 0.0
	var area: float = 0.0
	var altura_maxima: float = 0.0
	for sonda in barco.probes:
		volumen_total += sonda.volume
		area += sonda.volume / sonda.height
		altura_maxima = maxf(altura_maxima, sonda.height)

	var empuje: float = FloatingBody3D.WATER_DENSITY * g * volumen_total
	var reserva: float = empuje / peso
	_check(reserva >= RESERVA_MINIMA,
		"la reserva deja sitio para inundarse antes de perder la flotacion",
		"%.2f x el peso (minimo %.1f) -> techo de inundacion %.3f" % [
			reserva, RESERVA_MINIMA, 1.0 - 1.0 / reserva])

	_check(absf(area - AREA_FLOTACION) < AREA_TOLERANCIA,
		"el area de flotacion se conserva: misma linea de agua y misma rigidez",
		"%.3f m2 (esperado %.3f)" % [area, AREA_FLOTACION])

	# REGLA 3 de FloatingBody3D: el clamp de profundidad no puede quedar POR
	# DEBAJO de la banda de la sonda, o capa la reserva en silencio.
	_check(barco.max_submersion_depth >= altura_maxima,
		"el clamp del barril cohete no recorta la reserva",
		"clamp %.2f m vs banda de sonda %.2f m" % [barco.max_submersion_depth, altura_maxima])

	_liberar_ya(barco)


## La cadena de umbrales, leida de la ESCENA REAL y del .tres de balance, no de
## constantes copiadas. Es el test que impide que el sistema mienta:
##
##   alarma  <  punto sin retorno  <  techo de flotacion  <=  naufragio
##
## Si alguien retoca las sondas, la masa o el balance y rompe ese orden, el juego
## sigue funcionando pero el feedback pasa a ser deshonesto (avisar cuando ya no
## puedes salvarte, o declarar el naufragio de un barco que todavia flota).
func _test_umbrales_en_frio() -> void:
	var barco := _instanciar_barco()
	var balance := load(RUTA_BALANCE) as AguaEmbarcadaBalance
	if balance == null:
		_check(false, "el balance del agua carga", RUTA_BALANCE)
		_liberar_ya(barco)
		return

	var area: float = 0.0
	var volumen: float = 0.0
	var sonda_y: float = 0.0
	for sonda in barco.probes:
		area += sonda.volume / sonda.height
		volumen += sonda.volume
		sonda_y += sonda.position.y
	sonda_y /= float(barco.probes.size())

	var calado_cubierta: float = _altura_cubierta(barco) - sonda_y
	var neutro := AguaEmbarcadaModel.flooding_neutro(barco.mass, area, calado_cubierta)
	var techo := AguaEmbarcadaModel.techo_flotacion(barco.mass, volumen)

	_check(balance.umbral_alarma < neutro - 0.10,
		"la alarma suena con margen ANTES del punto sin retorno",
		"alarma %.2f vs punto sin retorno %.3f" % [balance.umbral_alarma, neutro])
	_check(neutro < techo,
		"la cubierta se moja antes de que el barco pierda la flotacion",
		"punto sin retorno %.3f vs techo %.3f" % [neutro, techo])
	_check(techo <= balance.umbral_naufragio,
		"el naufragio se declara cuando la fisica ya lo decidio, no antes",
		"techo %.3f vs umbral %.2f" % [techo, balance.umbral_naufragio])
	_check(balance.umbral_naufragio <= 1.0 and balance.sostenido_naufragio > 0.0,
		"el naufragio necesita sostenerse: una ola sola no hunde el barco",
		"%.2f durante %.1f s" % [balance.umbral_naufragio, balance.sostenido_naufragio])

	_liberar_ya(barco)


## La API que consume la bomba: drenar UNA celda y saber en cual esta el cabezal.
func _test_api_de_celdas() -> void:
	var barco := _instanciar_barco()
	_check(barco.probe_count() == 8, "el barco tiene sus ocho celdas",
		"%d" % barco.probe_count())

	# Drenar una celda no puede tocar a las vecinas: si lo hiciera, daria igual
	# donde pongas la manguera y se perderia la decision del achicador.
	barco.flood_probe(0, 0.5)
	barco.flood_probe(1, 0.5)
	var sacado := barco.drain_probe(0, 0.2)
	_check(is_equal_approx(sacado, 0.2), "drenar devuelve lo que saco", "%.3f" % sacado)
	_check(is_equal_approx(barco.probe_flooding(0), 0.3), "baja solo su celda")
	_check(is_equal_approx(barco.probe_flooding(1), 0.5), "y deja en paz a la vecina")

	# Chupar aire: celda seca, caudal cero. Es lo que la bomba usa para saber que
	# esta bombeando en vacio sin tener que leer el estado dos veces.
	barco.bail_out(1.0)
	_check(is_equal_approx(barco.drain_probe(0, 0.2), 0.0),
		"drenar una celda seca devuelve 0: la bomba chupa aire")
	_check(is_equal_approx(barco.drain_probe(99, 0.2), 0.0),
		"un indice invalido no revienta")

	# El mapeo posicion -> celda, que es como la manguera elige compartimento.
	var proa := barco.to_global(Vector3(-0.2, 0.8, -4.0))
	var popa := barco.to_global(Vector3(1.5, 0.8, 4.5))
	var i_proa := barco.probe_index_at(proa)
	var i_popa := barco.probe_index_at(popa)
	_check(i_proa >= 0 and barco.probes[i_proa].name.begins_with("ProbeBow"),
		"el cabezal en la proa cae en una celda de proa",
		barco.probes[i_proa].name if i_proa >= 0 else "-1")
	_check(i_popa >= 0 and barco.probes[i_popa].name == "ProbeSternStarboard",
		"y en la aleta de estribor, en la suya",
		barco.probes[i_popa].name if i_popa >= 0 else "-1")

	# La replica: el cliente copia los ocho niveles de golpe.
	barco.fijar_inundacion(PackedFloat32Array([0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8]))
	_check(is_equal_approx(barco.probe_flooding(7), 0.8), "fijar_inundacion escribe las celdas")
	_check(is_equal_approx(barco.flooding_level(), 0.45),
		"y la media sale de ellas", "%.3f" % barco.flooding_level())

	_liberar_ya(barco)


## Ninguna sonda del barco puede ser `floodable`.
##
## El mecanismo nativo del addon inunda una celda MIENTRAS ESTA SUMERGIDA, y las
## sondas del pesquero viven medio metro bajo el agua en reposo: activarlo seria
## una via de agua permanente desde el primer segundo de partida. El agua entra
## por donde decide `AguaEmbarcada` (olas sobre la borda, lluvia y entierro), y
## esa es la razon por la que `flooding` tiene un solo escritor.
func _test_escritor_unico() -> void:
	var barco := _instanciar_barco()
	var todas_selladas := true
	var culpable := ""
	for sonda in barco.probes:
		if sonda.floodable:
			todas_selladas = false
			culpable = sonda.name
	_check(todas_selladas, "ninguna celda se inunda sola por estar sumergida", culpable)
	_liberar_ya(barco)


## Los puntos de borda tienen que estar EN la tapa de la regala, y la tapa se
## deriva de las barandillas reales de la escena. Si el rework del barco sube o
## baja la borda y los puntos se quedan donde estaban, el barco embarcaria agua
## por una borda imaginaria: nada fallaria, solo entraria mal el agua.
func _test_puntos_borda_sobre_barandilla() -> void:
	var barco := _instanciar_barco()
	var rail := barco.get_node_or_null(^"RailPort") as CollisionShape3D
	var caja := rail.shape as BoxShape3D if rail != null else null
	if caja == null:
		_check(false, "la barandilla de babor existe para medir la tapa")
		_liberar_ya(barco)
		return
	var tapa: float = rail.position.y + caja.size.y * 0.5

	var puntos := barco.get_node_or_null(^"PuntosBorda")
	_check(puntos != null and puntos.get_child_count() >= 4,
		"el barco tiene puntos de borda por los dos costados",
		"%d" % (puntos.get_child_count() if puntos != null else 0))

	var todos_en_la_tapa := true
	var peor := ""
	if puntos != null:
		for hijo in puntos.get_children():
			var m := hijo as Marker3D
			if m == null:
				continue
			if absf(m.position.y - tapa) > 0.10:
				todos_en_la_tapa = false
				peor = "%s a %.2f m (tapa %.2f)" % [m.name, m.position.y, tapa]
	_check(todos_en_la_tapa, "todos los puntos de borda estan en la tapa de la regala", peor)
	_liberar_ya(barco)


## Las dos escenas jugables tienen que llevar el aviso de agua. Es cableado de
## escena, que es donde las cosas se rompen sin ruido: el sistema entero puede
## estar perfecto y el jugador no enterarse de que se hunde porque a una escena
## le falta un nodo. Mismo motivo por el que `net_tests` comprueba que las rutas
## de los props resuelven en las dos escenas.
func _test_las_escenas_jugables_avisan() -> void:
	for ruta in ["res://game/world/toybox.tscn", "res://game/world/tsunami.tscn"]:
		var texto := FileAccess.get_file_as_string(ruta)
		_check(texto.contains("aviso_agua.gd"),
			"%s avisa cuando entra agua" % ruta.get_file())


## En calma y sin lluvia no entra NI UNA GOTA. Parece obvio y es el test que mas
## veces salva: un margen de borda mal puesto, una sonda marcada como `floodable`
## o un signo cambiado hacen que el barco se hunda solo en mar plana, y como
## tarda minutos en notarse nadie lo relaciona con el cambio que lo causo.
func _test_en_calma_no_entra_agua() -> void:
	var r := await _simular_agua(0.0, 0.0, 1200)
	_check(is_zero_approx(float(r[&"nivel"])),
		"en calma y sin lluvia el barco no embarca nada",
		"nivel %.5f tras %d s" % [r[&"nivel"], 10])


## El agua que dice el balance es la que acaba en el barco.
##
## Este test existe porque el de la funcion pura NO basta: `aporte_por_celda`
## estaba bien y aun asi entraba la mitad del agua, porque quien la llamaba
## pedia la porcion "para dos celdas" y luego la partia entre las dos. Un error
## de factor 2 en el dial de dificultad que ningun test unitario podia ver.
func _test_lo_que_entra_es_lo_que_dice_el_balance() -> void:
	var balance := load(RUTA_BALANCE) as AguaEmbarcadaBalance
	if balance == null:
		_check(false, "el balance del agua carga", RUTA_BALANCE)
		return
	var esperado := AguaEmbarcadaModel.embarque_por_mar(
		8.0, balance.furia_umbral_embarque, balance.embarque_mar_max)
	var r := await _simular_agua(8.0, 0.0, 1800)
	var medido: float = float(r[&"ingreso_s"])
	_check(absf(medido - esperado) < esperado * 0.25,
		"lo que entra a furia 8 es lo que promete el balance",
		"medido %.4f/s vs balance %.4f/s" % [medido, esperado])


## El dial de dificultad, automatizado (docs/CLIMA.md §6.4: "con furia 8+, 2
## jugadores achicando deben empatar con el mar; el punto de equilibrio ES el
## dial de dificultad, y se calcula en frio").
##
## No se mide comparando dos numeros, se mide JUGANDOLO: se simula el barco a
## furia 8 con la bomba a pleno rendimiento y se comprueba que aguanta. Comparar
## caudales sobre el papel no valdria, porque el ingreso no es constante: segun
## entra agua el barco se hunde, se le entierran celdas y entra mas todavia. Esa
## espiral es la que decide si la tormenta es jugable o es una sentencia.
func _test_equilibrio_de_dificultad() -> void:
	var balance := load(RUTA_BALANCE) as AguaEmbarcadaBalance
	if balance == null:
		_check(false, "el balance del agua carga", RUTA_BALANCE)
		return

	# Con dos personas en la bomba (caudal pleno) la tormenta se aguanta.
	var con_bomba := await _simular_agua(8.0, 0.0, 3600, balance.caudal_bomba)
	_check(float(con_bomba[&"pico"]) < balance.umbral_alarma,
		"a furia 8, dos personas achicando le ganan al mar",
		"el agua llego al %.0f%% (alarma al %.0f%%)" % [
			float(con_bomba[&"pico"]) * 100.0, balance.umbral_alarma * 100.0])
	# Pero hacen falta LOS DOS. Con medio caudal (una persona sola: bombea sin
	# nadie que dirija la manguera, DISENO.md) el mar gana terreno. Es la
	# comprobacion que de verdad fija el dial: si uno solo diera abasto, la bomba
	# seria un tramite y la tormenta no obligaria a nadie a soltar la caña.
	var medio := await _simular_agua(8.0, 0.0, 3600, balance.caudal_bomba * 0.5)
	_check(float(medio[&"nivel"]) > float(con_bomba[&"pico"]) + 0.05,
		"pero uno solo no da abasto: hacen falta dos",
		"con medio caudal el agua llego al %.0f%%, con caudal pleno al %.0f%%" % [
			float(medio[&"nivel"]) * 100.0, float(con_bomba[&"pico"]) * 100.0])

	# Y sin nadie en la bomba, la misma tormenta se lo lleva.
	#
	# La ventana es de 40 s y no de 30 a proposito. Con 30 s esta comprobacion
	# era una MUESTRA UNICA pegada al umbral y decidida por la fase del oleaje:
	# medido, el mismo escenario da 0,67 corrido solo y 0,46 corrido detras de
	# los otros dos (que dejan `Ocean.sim_time` en otro sitio). Lo que se quiere
	# afirmar es que la tormenta se lleva el barco si nadie achica, no en cuantos
	# segundos exactos; con 40 s el nivel esta ya en 1,00 y la afirmacion aguanta
	# la fase.
	#
	# Se alargo al arreglar la regla 5 de `FloatingBody3D` (los brazos se median
	# desde el origen y no desde el centro de masas): el barco corregido es un
	# 18 % mas estable, escora menos, entierra menos la cubierta y la espiral de
	# inundacion es mas floja — el ingreso a furia 8 baja de 0,0189 a 0,0152/s.
	# Es fisica correcta, no un dial mas flojo, asi que se mueve la ventana y NO
	# el balance: `ritmo_entierro` sigue donde estaba.
	var sin_bomba := await _simular_agua(8.0, 0.0, 4800)
	var ingreso: float = float(sin_bomba[&"ingreso_s"])
	print("        (furia 8: entran %.4f/s de media; con bomba el pico fue %.0f%%)" % [
		ingreso, float(con_bomba[&"pico"]) * 100.0])
	_check(float(sin_bomba[&"nivel"]) > balance.umbral_alarma,
		"y sin nadie en la bomba, esa misma tormenta se lo lleva",
		"llego al %.0f%% en 40 s" % (float(sin_bomba[&"nivel"]) * 100.0))


## El ciclo completo del fallo: se inunda, se declara el naufragio cuando toca, y
## el reflote devuelve un barco jugable.
##
## Lo importante del final es el detalle que no se ve: tras escribirle el
## transform al barco hay que llamar a `olvidar_historial_agua()`, o el primer
## tick despues del teleport calcula decenas de m/s de entrada y dispara un slam
## con su chapuzon y su espuma. Un chapuzon que no ocurrio es feedback que miente
## (regla 8), asi que el test escucha la señal y exige silencio.
## El agua se VE, y esa es la unica razon de ser del paso 2.
##
## Al quitar la escora el sistema se quedo mudo: hundirse un palmo no se nota. El
## plano de cubierta es lo que lo devuelve a ser legible, y lo que este test
## protege NO es que exista un MeshInstance3D — es la CALIBRACION, que es lo que
## de verdad hace que el jugador entienda sin mirar ningun numero:
##
##   charco que moja los pies -> "entra agua"
##   por la rodilla           -> suena la alarma
##   por la cintura           -> pierdes el barco
##
## Si alguien mueve los umbrales del balance y no mueve la curva, el agua deja de
## coincidir con el momento de alarmarse y el indicador empieza a mentir.
func _test_la_piscina_se_ve() -> void:
	var balance := load(RUTA_BALANCE) as AguaEmbarcadaBalance
	if balance == null:
		_check(false, "el balance del agua carga", RUTA_BALANCE)
		return
	await get_tree().physics_frame
	Ocean.clear_events()
	Ocean.set_fury_immediate(0.0)

	var barco := _instanciar_barco()
	barco.global_position = Vector3(0, 2, 0)
	var piscina := barco.get_node_or_null(^"AguaCubierta") as AguaCubierta
	var agua := barco.get_node_or_null(^"AguaEmbarcada") as AguaEmbarcada
	if piscina == null or agua == null:
		_check(false, "el barco trae su AguaCubierta y su AguaEmbarcada")
		_liberar_ya(barco)
		return
	for _i in 200:
		await get_tree().physics_frame

	# --- seco: no se dibuja nada ---
	_check(not piscina.visible,
		"con el barco seco no hay agua que enseñar")

	# --- la calibracion: los tres momentos que el jugador tiene que leer ---
	var charco: float = piscina.curva_profundidad.sample_baked(0.05)
	var alarma: float = piscina.curva_profundidad.sample_baked(balance.umbral_alarma)
	var naufragio: float = piscina.curva_profundidad.sample_baked(balance.umbral_naufragio)

	_check(charco > 0.01 and charco < 0.10,
		"al 5 %% es un charco que moja los pies, no una lamina invisible",
		"%.3f m" % charco)
	_check(alarma > 0.30 and alarma < 0.60,
		"cuando suena la alarma, el agua llega por la RODILLA",
		"%.2f m con el umbral en %.2f" % [alarma, balance.umbral_alarma])
	_check(naufragio > 0.85,
		"y al naufragar, por la CINTURA: se ve venir sin mirar un numero",
		"%.2f m con el umbral en %.2f" % [naufragio, balance.umbral_naufragio])
	_check(alarma > charco and naufragio > alarma,
		"y sube siempre: mas agua nunca puede dibujarse mas baja")

	# --- mojado: aparece, y a la altura que dice la curva ---
	for i in barco.probe_count():
		barco.flood_probe(i, balance.umbral_alarma)
	for _i in 20:
		await get_tree().physics_frame

	_check(piscina.visible, "con el barco a media agua, la piscina se ve")
	var sobre_cubierta: float = piscina.position.y - 0.80
	_check(absf(sobre_cubierta - alarma) < 0.05,
		"y flota a la altura que promete la curva, medida sobre la cubierta",
		"%.2f m sobre cubierta, la curva dice %.2f" % [sobre_cubierta, alarma])
	_check(piscina.profundidad_maxima() > 0.30,
		"y sabe decir cuanta agua hay para el freno al caminar y el chapoteo",
		"%.2f m" % piscina.profundidad_maxima())

	# --- el plano no asoma por los costados ---
	# Y la lamina tiene que caber dentro del casco, INCLUIDA la proa en punta: con
	# un rectangulo el agua asomaba flotando por fuera de la amura. Es un fallo
	# que ningun numero delata y que se vio en una captura.
	var caja_lamina := piscina.mesh.get_aabb() if piscina.mesh != null else AABB()
	var casco := barco.get_node_or_null(^"HullShape") as CollisionShape3D
	var caja := casco.shape as BoxShape3D if casco != null else null
	if caja != null:
		_check(caja_lamina.size.x < caja.size.x,
			"la lamina no asoma por los costados",
			"%.2f de manga contra %.2f" % [caja_lamina.size.x, caja.size.x])
		var semi_en_proa: float = _semianchura_de(piscina.mesh, caja_lamina.position.z + 0.2)
		_check(semi_en_proa < caja.size.x * 0.25,
			"y en la proa se afina como el casco, en vez de acabar en rectangulo",
			"%.2f m de semimanga en la amura" % semi_en_proa)

	_liberar_ya(barco)


## La mitad del ancho que tiene la lamina a esa z. Para comprobar que la proa se
## afina de verdad.
func _semianchura_de(malla: Mesh, z: float) -> float:
	var ancho: float = 0.0
	for i in malla.get_surface_count():
		var arrays := malla.surface_get_arrays(i)
		if arrays.size() <= Mesh.ARRAY_VERTEX:
			continue
		for v: Vector3 in PackedVector3Array(arrays[Mesh.ARRAY_VERTEX]):
			if absf(v.z - z) < 0.35:
				ancho = maxf(ancho, absf(v.x))
	return ancho


## EL agua hunde, no tumba (decision de diseño, 24-ago-2026).
##
## Se le mete toda el agua a UN COSTADO —el caso mas extremo que puede darse— y
## el casco tiene que seguir adrizado. Antes esto lo tumbaba a proposito: cada
## celda perdia su propio empuje y el barco se iba hacia el lado mojado. Se quito
## porque estorbaba al feel y, sobre todo, porque era ilegible: la escora era el
## UNICO aviso de donde estaba el agua.
##
## El test comprueba las dos mitades, porque una sola no significa nada:
##  1. con el agua a un lado NO se inclina, y
##  2. con esa misma agua SI se hunde mas (o sea que el agua sigue castigando —
##     un barco que ni se inclina ni se hunde es un barco que ignora el agua).
func _test_el_agua_no_inclina_el_barco() -> void:
	await get_tree().physics_frame
	Ocean.clear_events()
	Ocean.set_fury_immediate(0.0)

	var barco := _instanciar_barco()
	barco.global_position = Vector3(0, 2, 0)
	for _i in 300:
		await get_tree().physics_frame

	_check(is_zero_approx(barco.sesgo_escora),
		"el sesgo de escora por agua viene apagado de fabrica",
		"%.2f" % barco.sesgo_escora)

	var calado_seco: float = barco.global_position.y
	var escora_seca: float = _escora_grados(barco)

	# Todo el peso a babor: las celdas con x < 0. Es el reparto mas injusto que
	# el juego puede producir, asi que si aqui no se inclina, no se inclina nunca.
	var mojadas: int = 0
	for i in barco.probe_count():
		if barco.probes[i].position.x < 0.0:
			barco.flood_probe(i, 0.8)
			mojadas += 1
	_check(mojadas > 0, "hay celdas a babor que mojar", "%d" % mojadas)
	for _i in 420:
		await get_tree().physics_frame

	var escora_mojada: float = _escora_grados(barco)
	var calado_mojado: float = barco.global_position.y

	_check(absf(escora_mojada - escora_seca) < 3.0,
		"con toda el agua a un costado, el barco NO se tumba",
		"%.1f° seco -> %.1f° mojado" % [escora_seca, escora_mojada])
	_check(calado_mojado < calado_seco - 0.05,
		"pero SI se hunde mas: el agua sigue castigando, solo que hacia abajo",
		"%.2f m -> %.2f m" % [calado_seco, calado_mojado])

	_liberar_ya(barco)


## Cuanto esta escorado el casco, en grados: el angulo entre su vertical y la del
## mundo. Sirve igual para escora y para cabeceo, que es lo que se quiere — la
## pregunta es "¿esta derecho?", no "¿hacia donde se cae?".
func _escora_grados(barco: Node3D) -> float:
	return rad_to_deg(barco.global_basis.y.angle_to(Vector3.UP))


func _test_naufragio_y_reflote() -> void:
	await get_tree().physics_frame
	Ocean.clear_events()
	Ocean.set_fury_immediate(0.0)

	var barco := _instanciar_barco()
	barco.global_position = Vector3(0, 2, 0)
	var agua := barco.get_node_or_null(^"AguaEmbarcada") as AguaEmbarcada
	if agua == null:
		_check(false, "el barco lleva su nodo AguaEmbarcada montado")
		_liberar_ya(barco)
		return

	var avisos: Array[bool] = []
	var causas: Array[String] = []
	agua.alarma_cambiada.connect(func(encendida: bool) -> void: avisos.append(encendida))
	agua.naufragio.connect(func(causa: String) -> void: causas.append(causa))

	for _i in 300:
		await get_tree().physics_frame

	# Se inunda a mano: lo que se prueba es la deteccion y el reflote, no cuanto
	# tarda el mar en meter el agua (eso es `_test_equilibrio_de_dificultad`).
	for i in barco.probe_count():
		barco.flood_probe(i, 0.60)
	for _i in 30:
		await get_tree().physics_frame
	_check(avisos.size() > 0 and avisos[0], "la alarma salta al pasar su umbral",
		"%d avisos" % avisos.size())
	_check(causas.is_empty(), "y con la alarma sonando el barco todavia no naufraga")

	for i in barco.probe_count():
		barco.flood_probe(i, 0.35)
	# El umbral hay que SOSTENERLO: durante el primer segundo no puede declararse.
	for _i in 60:
		await get_tree().physics_frame
	_check(causas.is_empty(), "un instante por encima del umbral no es un naufragio")

	for _i in 420:
		await get_tree().physics_frame
	_check(causas.size() == 1, "sostenido si lo es, y se declara una sola vez",
		"%d señales" % causas.size())
	if causas.size() > 0:
		_check(causas[0].length() > 0 and causas[0].contains("Probe"),
			"la causa dice que celda se anego primero, para la bitacora", causas[0])

	# El reflote: seco, a flote, adrizado y SIN chapuzon fantasma.
	var slams: Array[float] = []
	barco.slammed.connect(func(fuerza: float, _pos: Vector3) -> void: slams.append(fuerza))
	agua.reflotar()
	for _i in 240:
		await get_tree().physics_frame

	_check(is_zero_approx(barco.flooding_level()), "el reflote deja el barco seco",
		"%.3f" % barco.flooding_level())
	_check(not agua.hundido, "y deja de estar hundido")
	_check(slams.is_empty(), "y no fabrica un chapuzon que nunca ocurrio",
		"%d slams" % slams.size())
	var altura := barco.global_position.y - Ocean.get_height(barco.global_position)
	_check(absf(altura) < 3.0, "el barco vuelve a la superficie",
		"%.2f m sobre el agua" % altura)
	_check(rad_to_deg(barco.global_basis.y.angle_to(Vector3.UP)) < 20.0,
		"y adrizado, no del reves",
		"%.0f grados" % rad_to_deg(barco.global_basis.y.angle_to(Vector3.UP)))

	barco.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame


## El oleaje moja pero no sepulta: a furia 9 (Hs 14 m) el CASCO SECO cabalga y le
## queda francobordo. Si esto se rompe, el barco vive medio sumergido y el agua
## embarcada deja de ser un evento para ser una constante.
##
## Se mide con el agua embarcada apagada a proposito. Lo que esta prueba protege
## es la RESERVA DE FLOTABILIDAD, y con el agua entrando mediria otra cosa muy
## distinta —cuanto tarda en inundarse un barco que nadie achica—, que es
## justamente lo que comprueba `_test_equilibrio_de_dificultad`. Mezclar las dos
## deja un test que falla por dos motivos opuestos y no dice cual.
func _test_el_oleaje_no_entierra() -> void:
	var r := await _medir(9.0, 2400, false, false)
	_check(float(r[&"francobordo"]) > FRANCOBORDO_MINIMO,
		"a furia 9 la cubierta conserva francobordo",
		"minimo %.2f m (limite %.2f)" % [r[&"francobordo"], FRANCOBORDO_MINIMO])
	_check(float(r[&"enterrada"]) <= 0.0,
		"y no queda enterrada ni un tick",
		"%.1f%% del tiempo" % (float(r[&"enterrada"]) * 100.0))
	# La sonda no debe saturar con oleaje: si satura, hundirla mas deja de
	# generar empuje y el barco entra en la espiral sin que nada la cause.
	_check(float(r[&"saturacion"]) < 0.75,
		"el empuje no llega a saturar con oleaje",
		"sumersion maxima %.0f%% de la banda" % (float(r[&"saturacion"]) * 100.0))


## Y el dial tiene dientes: el LEVIATAN SI entierra la cubierta. Sin este test,
## "que flote mas" se convierte en "que flote siempre" y el tsunami deja de mojar
## a nadie.
##
## El criterio NO es el porcentaje de tiempo enterrado: el LEVIATAN primero vacia
## el mar (el barco cae ~24 m y se moja en la depresion), 30 s despues llega el
## muro y lo cabalga con francobordo de sobra, y se vuelve a mojar al bajar. O
## sea que el porcentaje depende por completo de donde cortes la ventana.
##
## [b]Y tampoco se exige que el barco se recupere[/b], por mucho que suene a lo
## que uno querria: HOY EL BARCO VUELCA con el tsunami (medido: unas veces si y
## otras no, con la reserva vieja y con la nueva) y se queda flotando boca abajo
## para siempre, porque nada lo endereza. Es un hueco conocido del proyecto,
## anterior a este sistema de agua y con arreglo propio pendiente; poner aqui un
## check de recuperacion haria fallar el arnes de forma intermitente sin que
## nadie hubiera roto nada.
func _test_el_tsunami_si_entierra() -> void:
	# El tope de ticks es solo un seguro: el bucle corta solo en cuanto el muro
	# pasa de largo (RESACA_PASADA).
	var r := await _medir(7.0, 9000, true, false)
	_check(float(r[&"francobordo"]) < -1.0,
		"el LEVIATAN mete la cubierta bajo el agua de verdad",
		"%.2f m bajo el agua en lo peor" % -float(r[&"francobordo"]))
	# El pop-up: mas reserva significa mas aceleracion al salir del muro. Se
	# vigila aqui porque es el unico sitio donde el barco se sumerge de verdad.
	_check(float(r[&"pico_vy"]) < 30.0,
		"el barco sale del muro sin dispararse",
		"pico vertical %.1f m/s" % r[&"pico_vy"])


# =============================================================================


## Simula el barco y mide el francobordo en proa, centro y popa. Devuelve
## { enterrada, francobordo, saturacion, pico_vy }.
func _medir(furia: float, ticks: int, con_tsunami: bool, con_agua: bool = true) -> Dictionary:
	# Que no quede vivo el barco de la prueba anterior (ver la nota del final).
	await get_tree().physics_frame
	Ocean.clear_events()
	Ocean.set_fury_immediate(furia)

	var barco := _instanciar_barco()
	barco.global_position = Vector3(0, 3, 0)
	if not con_agua:
		var agua := barco.get_node_or_null(^"AguaEmbarcada")
		if agua != null:
			agua.set_physics_process(false)

	# Asentarse primero: los primeros segundos son el barco cayendo al agua.
	for _i in 900:
		await get_tree().physics_frame

	if con_tsunami:
		var tier := load(RUTA_LEVIATAN) as TsunamiTier
		if tier == null:
			_check(false, "el tier LEVIATAN existe", RUTA_LEVIATAN)
			barco.queue_free()
			return {&"enterrada": 0.0, &"francobordo": 0.0, &"saturacion": 0.0, &"pico_vy": 0.0}
		Ocean.spawn_tsunami_tier(barco.global_position, 90.0, 30.0, tier)

	var cubierta := _altura_cubierta(barco)
	# Tres puntos porque el cabeceo hunde una punta cada vez: medir solo el
	# centro esconde exactamente el caso que importa.
	var puntos: Array[Vector3] = [
		Vector3(0.0, cubierta, -4.0), Vector3(0.0, cubierta, 0.0), Vector3(0.0, cubierta, 4.5),
	]
	var enterrados: int = 0
	var francobordo: float = INF
	var francobordo_final: float = -INF
	var saturacion: float = 0.0
	var pico_vy: float = 0.0
	var muestras: int = 0

	# FASE 1: el castigo. Con tsunami NO termina por reloj sino cuando el muro
	# paso de largo, porque el barco deriva con la corriente mientras se asienta
	# y el muro tarda cada vez algo distinto en llegar: una ventana fija cae unas
	# veces en plena resaca (barco hundido) y otras en la calma de despues, y el
	# test daria resultados opuestos sin que nadie haya tocado nada.
	var i: int = 0
	while i < ticks:
		await get_tree().physics_frame
		i += 1
		muestras += 1
		pico_vy = maxf(pico_vy, absf(barco.linear_velocity.y))
		var peor := _francobordo(barco, puntos)
		francobordo = minf(francobordo, peor)
		if peor < 0.0:
			enterrados += 1
		for sonda in barco.probes:
			saturacion = maxf(saturacion, sonda.submersion / sonda.height)
		if con_tsunami and Ocean.time_until_tsunami(barco.global_position) < RESACA_PASADA:
			break

	# FASE 2: la recuperacion. Se mide con el MEJOR momento de estos 5 s, no con
	# el ultimo tick: entre ola y ola la cubierta se moja, y un tick suelto diria
	# que el barco sigue hundido cuando solo le paso una cresta por encima.
	for _j in 600:
		await get_tree().physics_frame
		pico_vy = maxf(pico_vy, absf(barco.linear_velocity.y))
		francobordo_final = maxf(francobordo_final, _francobordo(barco, puntos))

	barco.queue_free()
	# Esperar a que el barco muera de verdad: `queue_free` no libera hasta el
	# final del frame, y el barco de la medicion siguiente nace en el MISMO sitio.
	# Si coexisten un solo tick, Jolt resuelve la penetracion hundiendo a uno de
	# los dos y la medida sale disparatada (83% enterrado en vez de 13%).
	await get_tree().physics_frame
	await get_tree().physics_frame

	Ocean.clear_events()
	Ocean.set_fury_immediate(0.0)
	return {
		&"enterrada": float(enterrados) / float(maxi(muestras, 1)),
		&"francobordo": francobordo,
		&"francobordo_final": francobordo_final,
		&"saturacion": saturacion,
		&"pico_vy": pico_vy,
	}


## El peor francobordo de los tres puntos de cubierta, en metros. Negativo = ese
## punto esta bajo el agua.
func _francobordo(barco: Node3D, puntos: Array[Vector3]) -> float:
	var peor: float = INF
	for local in puntos:
		var p := barco.to_global(local)
		peor = minf(peor, p.y - Ocean.get_height(p))
	return peor


## Deja el barco flotando y mide cuanta agua embarca. Devuelve
## { nivel, ingreso_s }: el nivel al final y el ritmo medio de entrada por
## segundo, que es la magnitud con la que se cuadra el dial contra la bomba.
func _simular_agua(furia: float, lluvia: float, ticks: int,
		caudal_achique: float = 0.0) -> Dictionary:
	await get_tree().physics_frame
	Ocean.clear_events()
	Ocean.set_fury_immediate(furia)
	var lluvia_previa: float = Ocean.rain_level
	Ocean.rain_level = lluvia

	var barco := _instanciar_barco()
	barco.global_position = Vector3(0, 3, 0)

	# El agua se cuenta DESPUES de asentarse: el chapuzon inicial de la caida no
	# es oleaje embarcando, es el barco entrando al agua.
	for _i in 900:
		await get_tree().physics_frame
	barco.bail_out(1.0)

	var dt: float = 1.0 / float(maxi(Engine.physics_ticks_per_second, 1))
	var pico: float = 0.0
	for _i in ticks:
		await get_tree().physics_frame
		# La bomba, simulada: drena la celda que mas agua tiene, que es lo que
		# hace un achicador que sabe donde poner la manguera.
		if caudal_achique > 0.0:
			var peor: int = 0
			for i in barco.probe_count():
				if barco.probe_flooding(i) > barco.probe_flooding(peor):
					peor = i
			# El caudal del balance esta expresado sobre la MEDIA, y drenar una
			# sola celda mueve la media una octava parte: por eso se multiplica
			# por el numero de celdas, igual que en la entrada.
			barco.drain_probe(peor, caudal_achique * float(barco.probe_count()) * dt)
		pico = maxf(pico, barco.flooding_level())

	var nivel: float = barco.flooding_level()
	var segundos: float = float(ticks) / float(maxi(Engine.physics_ticks_per_second, 1))

	barco.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	Ocean.rain_level = lluvia_previa
	Ocean.set_fury_immediate(0.0)
	return {
		&"nivel": nivel,
		&"pico": pico,
		&"ingreso_s": nivel / maxf(segundos, 0.001),
	}


func _instanciar_barco() -> FloatingBody3D:
	var barco: FloatingBody3D = (load(RUTA_BARCO) as PackedScene).instantiate()
	add_child(barco)
	return barco


## Los tests que no esperan frames tienen que liberar con `free()` y no con
## `queue_free()`: la cola no se vacia hasta el final del frame, y como estas
## pruebas corren seguidas dentro del mismo `_ready`, los barcos se apilaban
## todos en el origen. Jolt se quedaba resolviendo la penetracion de cuatro
## cascos superpuestos y el arnes pasaba de tres minutos a no terminar nunca.
func _liberar_ya(barco: Node) -> void:
	remove_child(barco)
	barco.free()


## Altura de la cubierta jugable en espacio local, derivada de la tapa del casco.
## No se escribe a mano: si el rework del barco mueve el casco, este test sigue
## midiendo la cubierta de verdad y no un numero copiado.
func _altura_cubierta(barco: Node3D) -> float:
	var casco := barco.get_node_or_null(^"HullShape") as CollisionShape3D
	if casco == null:
		return 0.8
	var caja := casco.shape as BoxShape3D
	if caja == null:
		return 0.8
	return casco.position.y + caja.size.y * 0.5
