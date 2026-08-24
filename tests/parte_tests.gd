extends Node

## Pruebas del PARTE METEOROLOGICO (docs/CLIMA.md §8 item 14).
##
##   godot --headless --path . tests/parte_tests.tscn
##
## Lo que de verdad se protege aqui son dos cosas que fallarian en SILENCIO:
##
##   1. [b]El invariante del diseñador[/b]: «si sube la lluvia, sube la furia».
##      Un parte que lo viole produce diluvio sobre mar planchado — que se ve
##      perfectamente bien en una captura, no rompe nada, y destruye la unica
##      inferencia que el jugador puede hacer sobre el clima.
##   2. [b]La consulta al futuro[/b]. Si `furia_en(t+120)` miente, la telegrafia
##      miente, y eso no lo nota nadie hasta que alguien confie en ella.
##
## Y una tercera de proceso: que el carril MANUAL siga intacto. La perilla de
## furia del HUD es sagrada en F1 (CLAUDE.md); un guion que la ignore en
## silencio la vuelve inservible.

var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0

var _fury_previa: float = 3.0
var _rain_previa: float = 0.0


func _ready() -> void:
	print_rich("[b]--- Pruebas del parte meteorologico ---[/b]")
	_fury_previa = Ocean.fury
	_rain_previa = Ocean.rain_level

	_test_hermite_pasa_por_los_nudos()
	_test_hermite_es_c1()
	_test_fuera_del_guion_mantiene()
	_test_extremos_exactos()
	_test_horizonte_inmutable()
	_test_reescribir_nudo()
	_test_semilla_manda()
	_test_techo_del_caladero()
	_test_el_invariante()
	_test_bahia_nunca_diluvia()
	_test_cota_de_pendiente_en_hs()
	_test_lluvia_entra_tarde_sale_temprano()
	_test_empaquetar()
	_test_ocean_carril_comprometido()
	_test_ocean_la_mano_gana()
	_test_ocean_sin_parte_no_cambia_nada()
	_test_consulta_al_futuro_honesta()
	_test_furia_swell()
	_test_rayos_leen_el_guion()
	_test_salto_electrico()
	_test_lluvia_conserva_su_rampa()
	_test_parte_agotado()
	_test_duracion_sorteada_y_acotada()
	_test_mar_de_fondo_precursor()
	_test_canal_rumbo()
	await _test_escena_tsunami("res://game/world/tsunami.tscn")
	await _test_escena("res://game/world/toybox.tscn")

	_restaurar_ocean()
	_report()


func _check(condition: bool, label: String, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("  ok    %s" % label)
	else:
		print("  FALLO %s%s" % [label, ("  ->  " + detail) if detail != "" else ""])
		_failures.append(label + ((" -> " + detail) if detail != "" else ""))


# =============================================================================
#  La curva
# =============================================================================

func _test_hermite_pasa_por_los_nudos() -> void:
	var p := ParteMeteorologico.new()
	p.comprometer(ParteMeteorologico.FURIA, 0.0, 1.0)
	p.comprometer(ParteMeteorologico.FURIA, 100.0, 7.0)
	p.comprometer(ParteMeteorologico.FURIA, 250.0, 3.0)
	_check(absf(p.valor_en(ParteMeteorologico.FURIA, 0.0) - 1.0) < 0.0001, "el spline pasa por el primer nudo")
	_check(absf(p.valor_en(ParteMeteorologico.FURIA, 100.0) - 7.0) < 0.0001, "el spline pasa por el nudo interior")
	_check(absf(p.valor_en(ParteMeteorologico.FURIA, 250.0) - 3.0) < 0.0001, "el spline pasa por el ultimo nudo")
	# Con pendiente 0 en los dos extremos, el tramo ES un smoothstep: a mitad
	# de camino tiene que valer exactamente la media.
	var medio: float = p.valor_en(ParteMeteorologico.FURIA, 50.0)
	_check(absf(medio - 4.0) < 0.01, "a mitad de tramo vale la media (smoothstep)",
		"vale %.3f" % medio)


## Un keyframe suelto entre dos tramos no puede meter un quiebro de pendiente:
## si la derivada salta, el mar da un tiron en ese frame y se ve.
func _test_hermite_es_c1() -> void:
	var p := ParteMeteorologico.new()
	p.comprometer(ParteMeteorologico.FURIA, 0.0, 1.0)
	p.comprometer(ParteMeteorologico.FURIA, 100.0, 7.0, 0.03)
	p.comprometer(ParteMeteorologico.FURIA, 250.0, 3.0)
	var h := 0.01
	var antes: float = (p.valor_en(ParteMeteorologico.FURIA, 100.0)
		- p.valor_en(ParteMeteorologico.FURIA, 100.0 - h)) / h
	var despues: float = (p.valor_en(ParteMeteorologico.FURIA, 100.0 + h)
		- p.valor_en(ParteMeteorologico.FURIA, 100.0)) / h
	_check(absf(antes - despues) < 0.005, "la pendiente es continua en el nudo (C1)",
		"antes %.4f, despues %.4f" % [antes, despues])
	_check(absf(antes - 0.03) < 0.005, "y vale la pendiente que se comprometio",
		"%.4f en vez de 0.03" % antes)


func _test_fuera_del_guion_mantiene() -> void:
	var p := ParteMeteorologico.new()
	p.comprometer(ParteMeteorologico.FURIA, 100.0, 6.0)
	p.comprometer(ParteMeteorologico.FURIA, 200.0, 2.0)
	_check(absf(p.valor_en(ParteMeteorologico.FURIA, -999.0) - 6.0) < 0.0001,
		"antes del guion mantiene el primer valor")
	_check(absf(p.valor_en(ParteMeteorologico.FURIA, 99999.0) - 2.0) < 0.0001,
		"un parte que se acaba deja el mar como lo dejo, no lo devuelve a cero")


## El extremo de un tramo con pendientes no nulas cae DENTRO, no en los nudos.
## Muestrear grueso se lo come, y es justo el pico que la consulta busca.
func _test_extremos_exactos() -> void:
	var p := ParteMeteorologico.new()
	# Pendientes que fuerzan un sobrepico entre los dos nudos.
	p.comprometer(ParteMeteorologico.FURIA, 0.0, 2.0, 0.20)
	p.comprometer(ParteMeteorologico.FURIA, 100.0, 2.0, -0.20)
	var ext := p.extremos_en(ParteMeteorologico.FURIA, 0.0, 100.0)
	_check(ext.y > 4.0, "encuentra el sobrepico interior del tramo",
		"maximo %.3f (los dos nudos valen 2)" % ext.y)

	# Y coincide con la verdad por fuerza bruta.
	var bruto: float = -INF
	for i in 20001:
		bruto = maxf(bruto, p.valor_en(ParteMeteorologico.FURIA, float(i) * 0.005))
	_check(absf(ext.y - bruto) < 0.002, "el maximo analitico coincide con el muestreado fino",
		"analitico %.4f, bruto %.4f" % [ext.y, bruto])

	var ext2 := p.extremos_en(ParteMeteorologico.FURIA, 0.0, 30.0)
	_check(ext2.y < ext.y, "y respeta la ventana pedida")


func _test_horizonte_inmutable() -> void:
	var p := ParteMeteorologico.new()
	var ahora := 500.0
	# Se silencian los push_error: el rechazo es el comportamiento correcto y
	# aqui se esta provocando a proposito.
	var dentro: bool = p.comprometer(ParteMeteorologico.FURIA,
		ahora + ParteMeteorologico.HORIZONTE - 10.0, 9.0, 0.0, ahora)
	var fuera: bool = p.comprometer(ParteMeteorologico.FURIA,
		ahora + ParteMeteorologico.HORIZONTE + 10.0, 9.0, 0.0, ahora)
	_check(not dentro, "rechaza escribir DENTRO del horizonte (la telegrafia no puede mentir)")
	_check(fuera, "acepta escribir fuera del horizonte")
	_check(p.keyframes(ParteMeteorologico.FURIA).size() == 1,
		"y el rechazado no se cuela igual")

	var sin_reloj: bool = p.comprometer(ParteMeteorologico.FURIA, 0.0, 1.0)
	_check(sin_reloj, "sin pasar reloj no hay horizonte (generacion inicial y tests)")


## Reescribir un keyframe existente tiene que SOBRESCRIBIR, no duplicar. Un
## duplicado deja un tramo de duracion cero: `_hermite` lo detecta y devuelve
## `b.y`, pero los extremos y la busqueda binaria empiezan a ver dos nudos en
## el mismo instante y el parte deja de ser una funcion.
func _test_reescribir_nudo() -> void:
	var p := ParteMeteorologico.new()
	p.comprometer(ParteMeteorologico.FURIA, 0.0, 1.0)
	p.comprometer(ParteMeteorologico.FURIA, 100.0, 5.0)
	p.comprometer(ParteMeteorologico.FURIA, 200.0, 3.0)
	var antes: int = p.keyframes(ParteMeteorologico.FURIA).size()

	# El mismo instante, valor nuevo: en un nudo interior, en el primero y en
	# el ultimo (los tres caminos de la insercion ordenada).
	p.comprometer(ParteMeteorologico.FURIA, 100.0, 9.0)
	p.comprometer(ParteMeteorologico.FURIA, 0.0, 2.0)
	p.comprometer(ParteMeteorologico.FURIA, 200.0, 4.0)
	var despues: int = p.keyframes(ParteMeteorologico.FURIA).size()
	_check(despues == antes, "reescribir un nudo NO duplica",
		"eran %d y quedaron %d" % [antes, despues])
	_check(absf(p.valor_en(ParteMeteorologico.FURIA, 100.0) - 9.0) < 0.0001,
		"y el valor nuevo es el que manda",
		"vale %.3f" % p.valor_en(ParteMeteorologico.FURIA, 100.0))

	# Y los nudos siguen ordenados por t: la evaluacion lo da por hecho.
	var kf := p.keyframes(ParteMeteorologico.FURIA)
	var ordenados := true
	for i in kf.size() - 1:
		if kf[i + 1].x <= kf[i].x:
			ordenados = false
	_check(ordenados, "y la lista sigue estrictamente ordenada por t")

	# Insertar ANTES de todos (el caso _indice_de == -1).
	p.comprometer(ParteMeteorologico.FURIA, -50.0, 0.5)
	var kf2 := p.keyframes(ParteMeteorologico.FURIA)
	_check(kf2.size() == antes + 1 and absf(kf2[0].x + 50.0) < 0.0001,
		"un nudo anterior a todos se inserta el primero",
		"primer nudo en t=%.1f" % kf2[0].x)


# =============================================================================
#  El generador
# =============================================================================

func _test_semilla_manda() -> void:
	var a := GeneradorParte.generar(1234, 7.0, 1200.0)
	var b := GeneradorParte.generar(1234, 7.0, 1200.0)
	var c := GeneradorParte.generar(9999, 7.0, 1200.0)

	var iguales := true
	for canal: StringName in [ParteMeteorologico.FURIA, ParteMeteorologico.LLUVIA]:
		if a.keyframes(canal) != b.keyframes(canal):
			iguales = false
	_check(iguales, "misma semilla = mismo parte, byte a byte (semilla diaria de DISENO)")

	var distinto := a.keyframes(ParteMeteorologico.FURIA) != c.keyframes(ParteMeteorologico.FURIA)
	_check(distinto, "otra semilla = otro clima")

	# Y NO puede depender del RNG global: sembrarlo distinto no cambia nada.
	seed(4242)
	var d := GeneradorParte.generar(1234, 7.0, 1200.0)
	_check(d.keyframes(ParteMeteorologico.FURIA) == a.keyframes(ParteMeteorologico.FURIA),
		"no toca el RNG global (regla 4: cada cliente lo calcula solo)")


## «La furia prometida es la furia entregada» (DISENO), y ahora eso incluye el
## cielo. Se mira con extremos_en y no en los nudos: un spline puede SOBREPASAR
## entre dos keyframes sin que ninguno de los dos pase del techo.
func _test_techo_del_caladero() -> void:
	for techo: float in [3.0, 5.0, 7.0, 9.0]:
		var peor: float = -INF
		for semilla in 40:
			var p := GeneradorParte.generar(semilla * 7717, techo, 1800.0)
			var kf := p.keyframes(ParteMeteorologico.FURIA)
			if kf.is_empty():
				continue
			peor = maxf(peor, p.extremos_en(ParteMeteorologico.FURIA, kf[0].x, kf[-1].x).y)
		_check(peor <= techo + 0.001, "techo %.0f: el parte no lo pasa NUNCA (40 semillas)" % techo,
			"peor %.4f" % peor)


## EL test. El invariante del diseñador, sobre 4 caladeros x 60 semillas.
func _test_el_invariante() -> void:
	var total: int = 0
	var rotos: int = 0
	var peor: Dictionary = {}
	for techo: float in [3.0, 5.0, 7.0, 9.0]:
		for semilla in 60:
			total += 1
			var p := GeneradorParte.generar(semilla * 104729 + 13, techo, 2400.0)
			var v := GeneradorParte.violaciones_del_piso(p)
			if not v.is_empty():
				rotos += 1
				if peor.is_empty():
					peor = v[0]
	_check(rotos == 0,
		"«si sube la lluvia, sube la furia»: %d partes sin una sola violacion" % total,
		("primer fallo: t=%.1f furia %.2f con lluvia %.2f (exigia %.2f)" % [
			peor.get(&"desde", 0.0), peor.get(&"furia", 0.0),
			peor.get(&"lluvia", 0.0), peor.get(&"exigida", 0.0)]) if not peor.is_empty() else "")

	# Y el detector no es un sello de goma: un parte torcido a mano tiene que
	# saltar. Sin esto, el test de arriba pasaria aunque `violaciones_del_piso`
	# devolviera siempre vacio.
	var malo := ParteMeteorologico.new()
	malo.comprometer(ParteMeteorologico.FURIA, 0.0, 0.5)
	malo.comprometer(ParteMeteorologico.FURIA, 600.0, 0.5)
	malo.comprometer(ParteMeteorologico.LLUVIA, 0.0, 1.0)
	malo.comprometer(ParteMeteorologico.LLUVIA, 600.0, 1.0)
	_check(not GeneradorParte.violaciones_del_piso(malo).is_empty(),
		"y el detector PILLA un diluvio sobre mar planchado puesto a mano")


func _test_bahia_nunca_diluvia() -> void:
	# BAHIA promete techo 3, asi que su lluvia no puede pasar de 3/6 = 0.5.
	var peor: float = 0.0
	for semilla in 50:
		var p := GeneradorParte.generar(semilla * 31337, 3.0, 2400.0)
		if not p.tiene(ParteMeteorologico.LLUVIA):
			continue
		var kf := p.keyframes(ParteMeteorologico.LLUVIA)
		peor = maxf(peor, p.extremos_en(ParteMeteorologico.LLUVIA, kf[0].x, kf[-1].x).y)
	_check(peor <= 0.5 + 0.001,
		"BAHIA (techo 3) no pasa de llovizna: el caladero promete tambien el cielo",
		"peor lluvia %.3f" % peor)

	# Y en AGUAS NEGRAS el diluvio SI aparece — si no, el piso estaria de
	# adorno cortando toda la lluvia del juego.
	var mejor: float = 0.0
	for semilla in 50:
		var p := GeneradorParte.generar(semilla * 31337, 9.0, 2400.0)
		if not p.tiene(ParteMeteorologico.LLUVIA):
			continue
		var kf := p.keyframes(ParteMeteorologico.LLUVIA)
		mejor = maxf(mejor, p.extremos_en(ParteMeteorologico.LLUVIA, kf[0].x, kf[-1].x).y)
	_check(mejor > 0.75, "y AGUAS NEGRAS (techo 9) si llega al diluvio",
		"la mas fuerte de 50 salidas fue %.3f" % mejor)


## La cota va en METROS de Hs, no en puntos de dial. Se mide la derivada real.
func _test_cota_de_pendiente_en_hs() -> void:
	var peor: float = 0.0
	var t_peor: float = 0.0
	for semilla in 30:
		var p := GeneradorParte.generar(semilla * 6151 + 5, 9.0, 1800.0)
		var kf := p.keyframes(ParteMeteorologico.FURIA)
		if kf.size() < 2:
			continue
		var dt := 0.05
		var t: float = kf[0].x
		while t < kf[-1].x - dt:
			var hs_a: float = Ocean.hs_para_furia(p.valor_en(ParteMeteorologico.FURIA, t))
			var hs_b: float = Ocean.hs_para_furia(p.valor_en(ParteMeteorologico.FURIA, t + dt))
			var v: float = absf(hs_b - hs_a) / dt
			if v > peor:
				peor = v
				t_peor = t
			t += dt
	_check(peor <= GeneradorParte.COTA_HS * 1.05,
		"ningun tramo crece mas rapido de %.2f m/s de Hs" % GeneradorParte.COTA_HS,
		"peor %.3f m/s en t=%.1f" % [peor, t_peor])

	# Y la comparacion que motiva todo esto: el rate limit del carril manual
	# esta MUY por encima de la cota. No es un fallo — es por que el carril
	# comprometido no puede heredarlo.
	var peor_tramo: float = 0.0
	for i in Ocean.DOUGLAS_HS.size() - 1:
		peor_tramo = maxf(peor_tramo, Ocean.DOUGLAS_HS[i + 1] - Ocean.DOUGLAS_HS[i])
	var manual: float = Ocean.FURY_RATE_LIMIT * peor_tramo
	_check(manual > GeneradorParte.COTA_HS * 5.0,
		"y queda documentado que el rate limit manual es %.1fx la cota" % (manual / GeneradorParte.COTA_HS),
		"%.2f m/s contra %.2f" % [manual, GeneradorParte.COTA_HS])


## La envolvente asimetrica: el chubasco entra despues de que el mar suba y se
## va antes de que el mar baje. De ahi sale gratis el beat de «ya paso».
func _test_lluvia_entra_tarde_sale_temprano() -> void:
	var casos: int = 0
	var bien: int = 0
	for semilla in 60:
		var p := GeneradorParte.generar(semilla * 2999 + 7, 9.0, 2400.0)
		if not p.tiene(ParteMeteorologico.LLUVIA):
			continue
		var kf := p.keyframes(ParteMeteorologico.LLUVIA)
		for i in kf.size():
			if kf[i].y < 0.05:
				continue
			casos += 1
			# En el instante en que la lluvia esta en su meseta, la furia tiene
			# que estar ya alta: al menos la que el piso exige.
			var f: float = p.valor_en(ParteMeteorologico.FURIA, kf[i].x)
			if f >= GeneradorParte.piso_furia(kf[i].y) - 0.001:
				bien += 1
	_check(casos > 20, "hay chubascos que mirar", "%d nudos con agua" % casos)
	_check(bien == casos, "cada nudo de lluvia cae sobre furia suficiente",
		"%d de %d" % [bien, casos])


func _test_empaquetar() -> void:
	var a := GeneradorParte.generar(555, 7.0, 1200.0)
	var b := ParteMeteorologico.new()
	b.desempaquetar(a.empaquetar())
	var igual := true
	for canal: StringName in a.canales():
		if a.keyframes(canal) != b.keyframes(canal):
			igual = false
	_check(igual, "el parte va y vuelve por la red sin perder un nudo")
	_check(absf(a.valor_en(ParteMeteorologico.FURIA, 700.0)
		- b.valor_en(ParteMeteorologico.FURIA, 700.0)) < 0.0001,
		"y evalua identico al otro lado del cable")


# =============================================================================
#  Los dos carriles en Ocean
# =============================================================================

func _test_ocean_carril_comprometido() -> void:
	var p := ParteMeteorologico.new()
	p.comprometer(ParteMeteorologico.FURIA, 0.0, 2.0)
	p.comprometer(ParteMeteorologico.FURIA, 600.0, 8.0)
	p.comprometer(ParteMeteorologico.LLUVIA, 0.0, 0.0)
	p.comprometer(ParteMeteorologico.LLUVIA, 600.0, 0.9)

	Ocean.sim_time = 0.0
	Ocean.rain_scale = 1.0
	Ocean.fijar_parte(p)
	_check(Ocean.tiene_parte(), "el parte queda en vigor")
	_check(absf(Ocean.fury - 2.0) < 0.01, "y el mar obedece YA, sin esperar un frame",
		"furia %.3f" % Ocean.fury)

	# Se avanza el reloj a mano (en _ready no corren frames de fisica).
	Ocean.sim_time = 300.0
	Ocean._physics_process(1.0 / 60.0)
	var esperada: float = p.valor_en(ParteMeteorologico.FURIA, Ocean.sim_time)
	_check(absf(Ocean.fury - esperada) < 0.02,
		"a mitad del guion la furia es la que el guion dice",
		"%.3f contra %.3f" % [Ocean.fury, esperada])
	# Y SIN rate limit: el salto de 2 a ~5 fue de un frame porque la pendiente
	# ya viene acotada en el guion, no aqui.
	_check(Ocean.fury > 3.0, "el carril comprometido no re-aplica el rate limit")
	# La lluvia sale del guion pero CON rampa (RAIN_RATE_LIMIT), asi que hay que
	# dejarla llegar: un solo tick no puede subirla 0.45. Antes este check
	# pasaba con un tick porque `_rain` se escribia a pelo — o sea que estaba
	# consagrando el pop que la rampa existe para evitar.
	for _i in 90:
		Ocean._physics_process(1.0 / 60.0)
	_check(absf(Ocean.rain01 - p.valor_en(ParteMeteorologico.LLUVIA, Ocean.sim_time)) < 0.02,
		"la lluvia tambien sale del guion",
		"rain01 = %.3f, guion = %.3f" % [
			Ocean.rain01, p.valor_en(ParteMeteorologico.LLUVIA, Ocean.sim_time)])

	# `rain_scale` sigue siendo el carril inmediato del director. «De golpe»
	# quiere decir en la rampa corta de siempre, no en un frame: el tiempo
	# exacto lo mide `_test_lluvia_conserva_su_rampa`.
	Ocean.rain_scale = 0.0
	for _i in 150:
		Ocean._physics_process(1.0 / 60.0)
	_check(Ocean.rain01 < 0.001, "y la RETIRADA sigue cortando el agua",
		"rain01 = %.3f" % Ocean.rain01)
	Ocean.rain_scale = 1.0

	Ocean.limpiar_parte()
	_check(not Ocean.tiene_parte(), "y se puede quitar")


## La perilla de dios gana, y gana BORRANDO (decision de diseño 2026-08-24:
## «cuando se mueve el dial, se borra para todos y se sobreescribe lo que yo
## pongo»). Nada de suspender-y-reanudar: era poder deshacer algo que nadie
## quiere deshacer, y el aviso acababa recomendando una salida que en red no
## existia — la regla 8 rota dentro del propio clima.
func _test_ocean_la_mano_gana() -> void:
	var p := ParteMeteorologico.new()
	p.comprometer(ParteMeteorologico.FURIA, 0.0, 2.0)
	p.comprometer(ParteMeteorologico.FURIA, 600.0, 8.0)
	p.comprometer(ParteMeteorologico.RUMBO, 0.0, 123.0)
	Ocean.sim_time = 0.0
	Ocean.fijar_parte(p)

	Ocean.set_fury_immediate(9.5)
	_check(Ocean.parte() == null, "mover el dial a mano BORRA el guion")
	_check(not Ocean.tiene_parte(), "y tiene_parte() lo confirma")
	_check(absf(Ocean.fury - 9.5) < 0.001, "y la furia es la que puso la mano")

	Ocean.sim_time = 300.0
	Ocean._physics_process(1.0 / 60.0)
	_check(absf(Ocean.fury - 9.5) < 0.05, "nada la repisa por detras",
		"furia %.3f" % Ocean.fury)
	# Sin guion no hay rumbo de frente que consultar: vuelve al viento. Es lo
	# que impide que el cielo dibuje la pared de una tormenta que ya no existe.
	_check(absf(Ocean.rumbo_frente_en(0.0) - Ocean.wind_direction_deg) < 0.001,
		"y el rumbo del frente vuelve al viento")
	# Y el paquete de bienvenida no tiene nada que mandar: quien se una ahora
	# cae al carril manual, igual que el host. Antes esto resucitaba guiones.
	_check(not Ocean.tiene_parte(), "no queda guion que replicar a quien se une")


func _test_ocean_sin_parte_no_cambia_nada() -> void:
	Ocean.limpiar_parte()
	Ocean.set_fury_immediate(3.0)
	Ocean.fury = 6.0
	# Un segundo de rampa con el rate limit de siempre.
	for i in 60:
		Ocean._physics_process(1.0 / 60.0)
	var esperado: float = 3.0 + Ocean.FURY_RATE_LIMIT
	_check(absf(Ocean.fury - esperado) < 0.02,
		"sin parte, el rate limit manual sigue siendo el de siempre",
		"%.3f contra %.3f" % [Ocean.fury, esperado])
	_check(absf(Ocean.furia_en(Ocean.sim_time + 600.0) - Ocean.fury) < 0.001,
		"y sin guion, la mejor prediccion del futuro es el presente")


## El asterisco que el parte viene a quitar: `get_height_at` evaluaba el oleaje
## de viento con las amplitudes de AHORA, asi que si la furia subia en esos
## segundos la respuesta era incorrecta y nadie se enteraba.
func _test_consulta_al_futuro_honesta() -> void:
	var p := ParteMeteorologico.new()
	p.comprometer(ParteMeteorologico.FURIA, 0.0, 1.0)
	p.comprometer(ParteMeteorologico.FURIA, 900.0, 9.0)
	Ocean.sim_time = 0.0
	Ocean.clear_events()
	Ocean.fijar_parte(p)
	Ocean._physics_process(1.0 / 60.0)

	var ahora := _rms_del_mar(Ocean.sim_time)
	var futuro := _rms_del_mar(600.0)
	_check(futuro > ahora * 3.0,
		"con parte, consultar el futuro devuelve el mar QUE VA A HABER",
		"rms ahora %.3f m, dentro de 10 min %.3f m" % [ahora, futuro])
	_check(absf(Ocean.furia_en(600.0) - p.valor_en(ParteMeteorologico.FURIA, 600.0)) < 0.001,
		"y furia_en() coincide con el guion")

	Ocean.limpiar_parte()
	var plano_ahora := _rms_del_mar(Ocean.sim_time)
	var plano_futuro := _rms_del_mar(600.0)
	_check(absf(plano_futuro - plano_ahora) < plano_ahora * 0.6,
		"sin parte vuelve al comportamiento viejo (mismo mar en todo t)",
		"rms %.3f contra %.3f" % [plano_ahora, plano_futuro])


func _rms_del_mar(t: float) -> float:
	var suma: float = 0.0
	var n: int = 0
	for i in 24:
		for j in 24:
			var pos := Vector3(float(i) * 17.0 - 200.0, 0.0, float(j) * 19.0 - 200.0)
			var h: float = Ocean.get_height_at(pos, t)
			suma += h * h
			n += 1
	return sqrt(suma / maxf(float(n), 1.0))


func _test_furia_swell() -> void:
	var p := ParteMeteorologico.new()
	p.comprometer(ParteMeteorologico.FURIA, 0.0, 2.0)
	p.comprometer(ParteMeteorologico.FURIA, 300.0, 8.0)
	p.comprometer(ParteMeteorologico.FURIA, 600.0, 2.0)
	Ocean.sim_time = 0.0
	Ocean.fijar_parte(p)

	var swell: float = Ocean.furia_swell(0.0, 400.0)
	_check(absf(swell - 8.0) < 0.05,
		"furia_swell ve el pico que viene (es lo que adelanta el mar de fondo)",
		"%.3f" % swell)
	_check(Ocean.furia_swell(0.0, 30.0) < 3.0,
		"con ventana corta todavia no lo ve — la telegrafia tiene alcance finito")
	_check(Ocean.furia_swell(0.0, 400.0) >= Ocean.furia_en(0.0) - 0.001,
		"y nunca es menor que la furia de ahora")

	# El quiebro de derivada declarado en el doc: al pasar el pico, el maximo
	# de la ventana deja de estar en el interior y empieza a caer. Es continuo,
	# que es lo unico que se le exige.
	var a: float = Ocean.furia_swell(299.0, 400.0)
	var b: float = Ocean.furia_swell(301.0, 400.0)
	_check(absf(a - b) < 0.5, "el maximo deslizante es continuo al cruzar el pico",
		"%.3f -> %.3f" % [a, b])
	Ocean.limpiar_parte()


## Con guion, el rayo de un slot se decide con la furia DE ESE SLOT, no con la
## de ahora. Es lo que quita el parche de cuantizacion: dos maquinas evaluan el
## mismo spline en el mismo t0 y no hay deriva que voltear.
func _test_rayos_leen_el_guion() -> void:
	var p := ParteMeteorologico.new()
	# Calma chicha larga y temporal MUY despues. La calma tiene que durar mas
	# que VENTANA_SALTO, o el anticipo electrico la llenaria de relampagos —
	# que es correcto y tiene su propio test (`_test_salto_electrico`), pero
	# aqui taparia lo que se quiere medir.
	p.comprometer(ParteMeteorologico.FURIA, 0.0, 0.0)
	p.comprometer(ParteMeteorologico.FURIA, 1500.0, 0.0)
	p.comprometer(ParteMeteorologico.FURIA, 2100.0, 10.0)
	p.comprometer(ParteMeteorologico.FURIA, 6000.0, 10.0)

	Ocean.regenerate(4242)
	Ocean.sim_time = 0.0
	Ocean.fijar_parte(p)

	var d := LightningDirector.new()
	add_child(d)

	# Slots cuya ventana de anticipo entera cae dentro de la calma.
	var slot_calma: int = int((1500.0 - LightningDirector.VENTANA_SALTO)
		/ LightningDirector.SLOT_SECONDS)
	var en_calma: int = 0
	for i in slot_calma:
		if bool(d.strike_at_slot(i).get(&"active", false)):
			en_calma += 1
	var en_temporal: int = 0
	var desde: int = int(2600.0 / LightningDirector.SLOT_SECONDS)
	for i in range(desde, desde + 200):
		if bool(d.strike_at_slot(i).get(&"active", false)):
			en_temporal += 1

	_check(en_calma == 0, "en la parte CALMA del guion no cae un rayo",
		"%d rayos donde el parte dice furia 0" % en_calma)
	_check(en_temporal > 40, "y en la parte de TEMPORAL caen a mansalva",
		"%d rayos en 200 slots" % en_temporal)

	# Y la furia de AHORA no influye: el slot se resuelve con su propio t0.
	# (Se mira un slot futuro mientras el reloj esta en la calma.)
	var antes: Dictionary = d.strike_at_slot(desde + 7)
	Ocean.sim_time = 3500.0
	var despues: Dictionary = d.strike_at_slot(desde + 7)
	_check(bool(antes.get(&"active", false)) == bool(despues.get(&"active", false))
		and absf(float(antes.get(&"distance", 0.0)) - float(despues.get(&"distance", 0.0))) < 1e-6,
		"un slot da lo mismo consultado desde la calma que desde el temporal",
		"es la propiedad que hace innecesaria la cuantizacion")

	d.queue_free()
	Ocean.limpiar_parte()
	Ocean.sim_time = 0.0


## El «lightning jump» (NASA/NOAA, CLIMA.md §2.4): la actividad electrica se
## dispara ANTES que la meteorologia severa. Solo es posible con parte, porque
## hace falta saber que furia VA a haber.
func _test_salto_electrico() -> void:
	Ocean.regenerate(777)
	var d := LightningDirector.new()
	add_child(d)

	# Mar chico y quieto durante 10 minutos: sin guion no hay ni un rayo.
	var quieto := ParteMeteorologico.new()
	quieto.comprometer(ParteMeteorologico.FURIA, 0.0, 2.0)
	quieto.comprometer(ParteMeteorologico.FURIA, 4000.0, 2.0)
	Ocean.sim_time = 0.0
	Ocean.fijar_parte(quieto)
	var sin_nada: int = 0
	for i in 100:
		if bool(d.strike_at_slot(i).get(&"active", false)):
			sin_nada += 1
	_check(sin_nada == 0, "mar chico que SIGUE chico: cielo electricamente mudo",
		"%d rayos" % sin_nada)

	# El mismo mar chico, pero con un temporal a diez minutos vista.
	var viene := ParteMeteorologico.new()
	viene.comprometer(ParteMeteorologico.FURIA, 0.0, 2.0)
	viene.comprometer(ParteMeteorologico.FURIA, 600.0, 2.0)
	viene.comprometer(ParteMeteorologico.FURIA, 1100.0, 9.0)
	viene.comprometer(ParteMeteorologico.FURIA, 4000.0, 9.0)
	Ocean.fijar_parte(viene)
	var anticipados: int = 0
	var lejos: int = 0
	var bolts: int = 0
	for i in 100:
		var st: Dictionary = d.strike_at_slot(i)
		if not bool(st.get(&"active", false)):
			continue
		anticipados += 1
		if float(st[&"distance"]) > 1300.0:
			lejos += 1
		if bool(st.get(&"bolt", false)):
			bolts += 1
	_check(anticipados > 15,
		"con el temporal a 10 min vista, el horizonte YA relampaguea",
		"%d rayos en los mismos 100 slots donde antes habia 0" % anticipados)
	# Lo que hace que la imagen sea correcta y no solo "mas rayos": la cadencia
	# la manda la tormenta que viene, pero la DISTANCIA la manda el mar de
	# aqui. Sale sheet lightning mudo en el horizonte, sin una linea especial.
	_check(lejos == anticipados, "y TODOS caen lejos (la tormenta no esta aqui)",
		"%d de %d por debajo de 1300 m" % [anticipados - lejos, anticipados])
	_check(bolts == 0, "y ninguno tiene geometria: son resplandores de nube",
		"%d bolts" % bolts)

	# Y cuando la tormenta llega de verdad, ahi si hay rayos cerca y con forma.
	var encima: int = 0
	var cerca: int = 0
	for i in range(200, 400):
		var st2: Dictionary = d.strike_at_slot(i)
		if not bool(st2.get(&"active", false)):
			continue
		encima += 1
		if float(st2[&"distance"]) < 1300.0:
			cerca += 1
	_check(cerca > 0, "y con la tormenta encima SI caen cerca",
		"%d cercanos de %d" % [cerca, encima])

	# Sin parte, el salto no existe: la cadencia vuelve a ser la de siempre.
	Ocean.limpiar_parte()
	Ocean.set_fury_immediate(2.0)
	var manual: int = 0
	for i in 100:
		if bool(d.strike_at_slot(i).get(&"active", false)):
			manual += 1
	_check(manual == 0, "sin guion no hay salto: el carril manual no cambia",
		"%d rayos con furia 2 y sin parte" % manual)

	d.queue_free()
	Ocean.sim_time = 0.0


## El corte de la RETIRADA tiene que seguir siendo una RAMPA corta, tambien con
## guion. Se perdio al pasar al carril comprometido —se escribia `_rain` a pelo—
## y el corte pasaba de ~1.2 s a UN frame: el moteado del agua da un pop, que es
## justo lo que RAIN_RATE_LIMIT existe para evitar (docs/CLIMA.md §1.2).
func _test_lluvia_conserva_su_rampa() -> void:
	var p := ParteMeteorologico.new()
	p.comprometer(ParteMeteorologico.LLUVIA, 0.0, 0.9)
	p.comprometer(ParteMeteorologico.LLUVIA, 3000.0, 0.9)
	p.comprometer(ParteMeteorologico.FURIA, 0.0, 7.0)
	p.comprometer(ParteMeteorologico.FURIA, 3000.0, 7.0)
	Ocean.sim_time = 100.0
	Ocean.rain_scale = 1.0
	Ocean.fijar_parte(p)
	for i in 120:
		Ocean._physics_process(1.0 / 60.0)
	_check(absf(Ocean.rain01 - 0.9) < 0.02, "con guion, la lluvia llega a lo que dice el parte",
		"rain01 = %.3f" % Ocean.rain01)

	# El director entra en RETIRADA: corta el agua de golpe.
	Ocean.rain_scale = 0.0
	Ocean._physics_process(1.0 / 60.0)
	_check(Ocean.rain01 > 0.85,
		"el corte NO es instantaneo (un frame no puede tirar 0.9 a 0)",
		"tras un frame rain01 = %.3f" % Ocean.rain01)
	var frames: int = 1
	while Ocean.rain01 > 0.001 and frames < 600:
		Ocean._physics_process(1.0 / 60.0)
		frames += 1
	var segundos: float = float(frames) / 60.0
	# 0.9 / 0.6 por segundo = 1.5 s.
	_check(segundos > 1.0 and segundos < 2.0,
		"y tarda lo que manda RAIN_RATE_LIMIT (~1.5 s)",
		"tardo %.2f s" % segundos)
	Ocean.rain_scale = 1.0
	Ocean.limpiar_parte()


## Un guion que se acaba sigue respondiendo (mantiene el ultimo valor, que es lo
## correcto) pero el clima queda CONGELADO y la consulta al futuro ya no promete
## nada. Hoy nadie lo renueva, asi que como minimo tiene que poder verse.
func _test_parte_agotado() -> void:
	var p := ParteMeteorologico.new()
	p.comprometer(ParteMeteorologico.FURIA, 0.0, 2.0)
	p.comprometer(ParteMeteorologico.FURIA, 500.0, 6.0)
	Ocean.sim_time = 100.0
	Ocean.fijar_parte(p)
	_check(not Ocean.parte_agotado(), "dentro del guion, no esta agotado")
	# La señal del final: la salida es FINITA (decision 2026-08-24) y que el
	# guion se agote ES «se acabo la marea». Hoy no la escucha nadie (el cierre
	# en puerto es F7), pero tiene que dispararse UNA vez, no una por frame.
	var avisos: Array = []
	var oyente := func() -> void: avisos.append(true)
	Ocean.clima_agotado.connect(oyente)
	Ocean.sim_time = 600.0
	Ocean._physics_process(1.0 / 60.0)
	_check(Ocean.parte_agotado(), "pasado el ultimo nudo, SI lo esta")
	Ocean._physics_process(1.0 / 60.0)
	Ocean._physics_process(1.0 / 60.0)
	_check(avisos.size() == 1, "clima_agotado se emite UNA sola vez",
		"%d emisiones" % avisos.size())
	Ocean.clima_agotado.disconnect(oyente)
	_check(absf(Ocean.furia_en(99999.0) - 6.0) < 0.001,
		"y sigue respondiendo con el ultimo valor (no devuelve el mar a cero)")
	Ocean.limpiar_parte()
	Ocean.sim_time = 0.0


## La salida es FINITA y su duracion la sortea la SEMILLA (decision 2026-08-24:
## entre 10 y 25 minutos). Y la cifra es un TOPE de verdad: antes «pedir 1500 s»
## devolvia hasta 2194 (la constante solo elegia cuantos actos habia).
func _test_duracion_sorteada_y_acotada() -> void:
	var peor: float = 0.0
	var d_min: float = INF
	var d_max: float = 0.0
	for semilla in 40:
		var p := GeneradorParte.generar(semilla * 48271 + 11, 9.0)
		var d: float = p.duracion()
		d_min = minf(d_min, d)
		d_max = maxf(d_max, d)
		peor = maxf(peor, d)
	_check(d_min >= GeneradorParte.DURACION_MIN - 0.001
		and peor <= GeneradorParte.DURACION_MAX + 0.001,
		"40 salidas caen todas entre 10 y 25 minutos",
		"rango medido %.0f-%.0f s" % [d_min, d_max])
	# Y de verdad VARIA con la semilla: si no, el sorteo seria decorativo.
	_check(d_max - d_min > 120.0, "y la duracion cambia de salida a salida",
		"apenas %.0f s de diferencia" % (d_max - d_min))

	var a := GeneradorParte.generar(999, 9.0)
	var b := GeneradorParte.generar(999, 9.0)
	_check(absf(a.duracion() - b.duracion()) < 0.001,
		"misma semilla, misma duracion (las 6 maquinas coinciden)")

	# Pedir una duracion explicita sigue funcionando, y ahora ACOTA.
	var c := GeneradorParte.generar(4242, 9.0, 900.0)
	_check(c.duracion() <= 900.0 + 0.001,
		"una duracion pedida a mano es un tope, no una sugerencia",
		"pidio 900 y duro %.0f" % c.duracion())


## El precursor de mar de fondo (§3.3: «el mar de fondo llega PRIMERO»). Con
## una tormenta en el guion, las olas LARGAS crecen antes de que suba el
## viento — acotadas a PRECURSOR_HS_MAX metros — y el rizado corto ni se
## entera. Es la mitad del sistema de telegrafia que faltaba: el cielo se
## adelantaba 210 s, los rayos 900, y el mar 0.
func _test_mar_de_fondo_precursor() -> void:
	# Referencia: el mismo mar en calma, SIN guion.
	Ocean.limpiar_parte()
	Ocean.regenerate(1717)
	Ocean.set_fury_immediate(2.0)
	var hs_calma: float = Ocean.measured_hs()
	var amp_calma: PackedFloat32Array = Ocean.get_proxy()._amp.duplicate()

	# El mismo mar, con un temporal a cuatro minutos en el guion.
	var p := ParteMeteorologico.new()
	p.comprometer(ParteMeteorologico.FURIA, 0.0, 2.0)
	p.comprometer(ParteMeteorologico.FURIA, 120.0, 2.0)
	p.comprometer(ParteMeteorologico.FURIA, 420.0, 9.0)
	p.comprometer(ParteMeteorologico.FURIA, 3000.0, 9.0)
	Ocean.sim_time = 0.0
	Ocean.fijar_parte(p)
	Ocean._physics_process(1.0 / 60.0)

	var hs_previo: float = Ocean.measured_hs()
	_check(hs_previo > hs_calma + 0.3,
		"con la tormenta en camino, el mar YA es mas grande que la calma",
		"Hs %.2f contra %.2f" % [hs_previo, hs_calma])
	_check(hs_previo < hs_calma + Ocean.PRECURSOR_HS_MAX + 0.2,
		"pero acotado: es un anuncio, no la tormenta llegando antes",
		"Hs %.2f con tope %.1f m" % [hs_previo, Ocean.PRECURSOR_HS_MAX])

	# SOLO las bandas largas: el rizado corto es del viento de AHORA, y un
	# rizado que llega antes que su viento es imposible.
	var proxy := Ocean.get_proxy()
	var cortas_iguales := true
	var alguna_larga_crecio := false
	for i in proxy.count:
		var wl: float = proxy._wavelength[i]
		if wl < OceanWaveProxy.SWELL_BANDA_CORTA:
			if absf(proxy._amp[i] - amp_calma[i]) > 0.0001:
				cortas_iguales = false
		elif proxy._amp[i] > amp_calma[i] + 0.01:
			alguna_larga_crecio = true
	_check(cortas_iguales, "el rizado corto NI SE ENTERA (bandas < %.0f m intactas)"
		% OceanWaveProxy.SWELL_BANDA_CORTA)
	_check(alguna_larga_crecio, "y el crecimiento es todo de las olas largas")

	# Con la tormenta ya encima, el precursor no añade nada: el tope se
	# auto-limita y el mar es el de siempre.
	Ocean.sim_time = 1000.0
	Ocean._physics_process(1.0 / 60.0)
	var con_guion: float = Ocean.measured_hs()
	Ocean.limpiar_parte()
	Ocean.set_fury_immediate(9.0)
	var sin_guion: float = Ocean.measured_hs()
	_check(absf(con_guion - sin_guion) < 0.35,
		"en plena tormenta el precursor se disuelve (mismo mar que a mano)",
		"%.2f contra %.2f" % [con_guion, sin_guion])

	# Y sin parte, pasarle a set_sea_state el swell explicito o no pasarselo
	# da EXACTAMENTE el mismo mar: el carril manual queda bit a bit intacto.
	var solo := OceanWaveProxy.new()
	solo.generate(1717, Ocean.WAVE_COUNT, Ocean.wind_direction_deg)
	solo.set_sea_state(2.5, 0.4)
	var otro := OceanWaveProxy.new()
	otro.generate(1717, Ocean.WAVE_COUNT, Ocean.wind_direction_deg)
	otro.set_sea_state(2.5, 0.4, 2.5)
	_check(solo._amp == otro._amp,
		"sin tormenta que anunciar, el parametro nuevo es un no-op bit a bit")
	Ocean.sim_time = 0.0


## El canal RUMBO se escribia y no lo leia ningun test: alimenta `front_dir` del
## cielo, o sea la direccion por la que se ve venir la tormenta.
func _test_canal_rumbo() -> void:
	var p := GeneradorParte.generar(31415, 9.0, 1800.0)
	_check(p.tiene(ParteMeteorologico.RUMBO), "el generador escribe el canal de rumbo")

	Ocean.sim_time = 0.0
	Ocean.fijar_parte(p)
	var r0: float = Ocean.rumbo_frente_en(0.0)
	# Arranca cerca del VIENTO: si el frente sale por un rumbo suelto, la
	# tormenta se ve venir por babor mientras el mar llega por proa (el
	# espectro JONSWAP, las manchas y las estrias siguen a wind_direction_deg).
	_check(absf(r0 - Ocean.wind_direction_deg) <= 40.001,
		"y arranca alineado con el viento, no en un rumbo cualquiera",
		"rumbo %.1f contra viento %.1f" % [r0, Ocean.wind_direction_deg])

	# Y rola entre actos: un frente que no se mueve no es un sistema pasando.
	var movido := false
	for t in [400.0, 900.0, 1400.0]:
		if absf(Ocean.rumbo_frente_en(t) - r0) > 5.0:
			movido = true
	_check(movido, "y rola a lo largo de la salida")

	Ocean.limpiar_parte()
	_check(absf(Ocean.rumbo_frente_en(0.0) - Ocean.wind_direction_deg) < 0.001,
		"sin parte, el rumbo del frente es el del viento")
	Ocean.sim_time = 0.0


## LA escena donde vivia la divergencia: `tsunami.tscn` tiene TsunamiDirector
## con autostart Y el HUD con los botones de parte. El director escribe
## `Ocean.fury` en CADA tick de su acto, asi que sin pararlo el parte quedaba
## suspendido al frame siguiente de crearlo — y en red eso dejaba al host en
## carril manual con los clientes siguiendo el spline.
func _test_escena_tsunami(ruta: String) -> void:
	var packed: PackedScene = load(ruta)
	if packed == null:
		_check(false, "carga %s" % ruta)
		return
	var root: Node = packed.instantiate()
	add_child(root)
	await get_tree().process_frame

	var hud: Array = root.find_children("*", "OceanDebugHUD", true, false)
	var dir: Array = root.find_children("*", "TsunamiDirector", true, false)
	_check(not hud.is_empty() and not dir.is_empty(),
		"tsunami.tscn tiene director Y HUD (la combinacion del bug)")
	if hud.is_empty() or dir.is_empty():
		root.queue_free()
		await get_tree().process_frame
		return

	(hud[0] as OceanDebugHUD)._on_generar_parte(9.0)
	_check(Ocean.tiene_parte(), "generar el parte deja el guion en vigor")
	_check(not (dir[0] as TsunamiDirector).is_running(),
		"y PARA el director: sin esto le escribe la furia y lo suspende")

	# Y sobrevive a varios ticks de fisica, que es lo que antes lo mataba.
	for i in 10:
		await get_tree().physics_frame
	_check(Ocean.tiene_parte(), "el guion sigue en vigor 10 ticks despues",
		"se suspendio solo")

	Ocean.limpiar_parte()
	root.queue_free()
	await get_tree().process_frame


## Cableado de escena: los botones del HUD y el frente del cielo.
func _test_escena(ruta: String) -> void:
	var packed: PackedScene = load(ruta)
	if packed == null:
		_check(false, "carga %s" % ruta)
		return
	var root: Node = packed.instantiate()
	add_child(root)
	await get_tree().process_frame

	var hud: Array = root.find_children("*", "OceanDebugHUD", true, false)
	_check(not hud.is_empty(), "el toybox tiene el HUD de debug")
	if not hud.is_empty():
		var botones: HBoxContainer = (hud[0] as Node).get_node_or_null(^"%ParteButtons")
		var n: int = botones.get_child_count() if botones != null else -1
		# Cuatro caladeros mas el boton de apagar.
		_check(n == OceanDebugHUD.CALADEROS.size() + 1,
			"y un boton por caladero mas el de quitar el parte",
			"encontrados %d" % n)

	# EL FRENTE del cielo. Estuvo clavado a 0 desde la fase C justo porque le
	# faltaba saber de donde y cuando viene la tormenta.
	var we: Array = root.find_children("*", "WorldEnvironment", true, false)
	var ciclo: Array = root.find_children("*", "DayNightCycle", true, false)
	if we.is_empty() or ciclo.is_empty():
		root.queue_free()
		await get_tree().process_frame
		return
	var mat := ((we[0] as WorldEnvironment).environment.sky.sky_material) as ShaderMaterial
	if mat == null:
		root.queue_free()
		await get_tree().process_frame
		return

	Ocean.limpiar_parte()
	await get_tree().process_frame
	var sin_guion: float = float(mat.get_shader_parameter(&"front01"))
	_check(sin_guion < 0.001, "sin parte el cielo no dibuja frente (no hay futuro que leer)",
		"front01 = %.3f" % sin_guion)

	var p := ParteMeteorologico.new()
	p.comprometer(ParteMeteorologico.FURIA, 0.0, 1.0)
	p.comprometer(ParteMeteorologico.FURIA, 200.0, 9.0)
	p.comprometer(ParteMeteorologico.RUMBO, 0.0, 90.0)
	Ocean.sim_time = 0.0
	Ocean.fijar_parte(p)
	await get_tree().process_frame
	await get_tree().process_frame
	var con_tormenta: float = float(mat.get_shader_parameter(&"front01"))
	_check(con_tormenta > 0.1, "con tormenta en camino, el frente APARECE en el horizonte",
		"front01 = %.3f" % con_tormenta)

	# Y cuando la tormenta ya llego, el frente ya paso: deja de leerse como
	# pared. Sin esto el cielo se quedaria oscuro para siempre.
	Ocean.sim_time = 1200.0
	await get_tree().process_frame
	await get_tree().process_frame
	var ya_llego: float = float(mat.get_shader_parameter(&"front01"))
	_check(ya_llego < con_tormenta * 0.5,
		"y se disuelve cuando la tormenta ya esta encima",
		"front01 %.3f -> %.3f" % [con_tormenta, ya_llego])

	Ocean.limpiar_parte()
	root.queue_free()
	await get_tree().process_frame


func _restaurar_ocean() -> void:
	Ocean.limpiar_parte()
	Ocean.rain_scale = 1.0
	Ocean.rain_level = _rain_previa
	Ocean.set_fury_immediate(_fury_previa)
	Ocean.sim_time = 0.0


func _report() -> void:
	print("")
	if _failures.is_empty():
		print_rich("[color=green][b]%d/%d comprobaciones OK[/b][/color]" % [_checks, _checks])
		get_tree().quit(0)
	else:
		print_rich("[color=red][b]%d de %d han fallado:[/b][/color]" % [_failures.size(), _checks])
		for f in _failures:
			print("   - " + f)
		get_tree().quit(1)
