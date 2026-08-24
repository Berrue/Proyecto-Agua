extends Node

## Arnes de la BOMBA DE ACHIQUE: el arbitraje de la estacion y el ciclo de dos
## tiempos.
##
##   <godot 4.7.2> --headless --path . tests/bomba_tests.tscn
##
## `tests/manual_pump_tests.tscn` cubre el modulo como pieza de arte (montaje,
## escala, nodos, manguera). Esto cubre lo otro: quien puede usarla, cuanta agua
## chupa, cuanta escupe y de DONDE la saca. Casi todo son funciones puras de
## `BombaModel`, que es donde vive lo que decide algo — `Net` es un autoload
## singleton y un RPC no se puede testear, asi que una regla metida dentro del
## RPC seria una regla sin prueba.

const RUTA_BARCO := "res://game/boat/fishing_boat.tscn"
const RUTA_BALANCE := "res://resources/agua/agua_embarcada.tres"
const RUTA_BOMBA: NodePath = ^"UpgradeSockets/PumpPort/BombaManual"

## El paso de fisica y la carrera de la bomba, LEIDOS de donde viven y no
## copiados: los tests del ciclo integran a mano, y una copia que se quedara
## vieja mediria una bomba que ya no existe sin que nada fallara.
const SEG := ManualBilgePump.SEGUNDOS_POR_EMBOLADA
@onready var DT: float = 1.0 / float(maxi(Engine.physics_ticks_per_second, 1))

var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0


func _ready() -> void:
	print_rich("[b]--- Pruebas de la bomba de achique ---[/b]")
	_test_los_scripts_compilan()
	_test_arbitrar()
	_test_la_identidad_de_red()
	await _test_los_verbos_se_aplican()
	_test_el_flanco_tardio_no_acusa_a_nadie()
	_test_los_dos_tiempos()
	_test_el_ciclo_da_el_caudal_del_balance()
	_test_el_solitario_rinde_la_mitad()
	await _test_achica_la_celda_del_cabezal()
	await _test_el_agua_pasa_por_el_deposito()
	await _test_apuntar_adentro_no_sirve()
	await _test_el_deposito_lleno_se_nota()
	await _test_la_bomba_parada_no_late()
	await _test_llenar_va_al_doble_con_ayudante()
	_report()


func _check(condition: bool, label: String, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("  ok    %s" % label)
	else:
		print("  FALLO %s%s" % [label, ("  ->  " + detail) if detail != "" else ""])
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


## Que los scripts de la cadena compilen y expongan lo que la bomba necesita.
##
## Este test nace de un fallo SILENCIOSO de verdad: una variable mal escrita
## dejo `portador.gd` sin compilar, y `porteo_tests` siguio saliendo VERDE —
## simplemente ejecuto seis comprobaciones menos, porque las que dependian del
## script roto no llegaron a correr. Un arnés que pasa con el codigo roto es
## peor que uno que falla, asi que aqui se comprueba explicitamente.
func _test_los_scripts_compilan() -> void:
	for ruta in ["res://game/player/portador.gd", "res://game/boat/equipment/manual_bilge_pump.gd",
			"res://game/boat/equipment/bomba_model.gd", "res://game/boat/agua_embarcada.gd"]:
		var script := load(ruta) as GDScript
		_check(script != null and script.can_instantiate(),
			"compila y se puede instanciar: %s" % ruta.get_file())

	# Y que el interactor sepa de la bomba: sin esto la bomba estaria en el barco
	# pero no habria forma de usarla.
	var portador := load("res://game/player/portador.gd") as GDScript
	if portador != null:
		var metodos := PackedStringArray()
		for m in portador.get_script_method_list():
			metodos.append(m["name"])
		_check(metodos.has("_interactuar_bomba"),
			"el interactor del jugador ofrece la bomba")
		_check(metodos.has("_paso_bomba"),
			"y la acciona mientras mantienes el clic")
		# El camino de red: sin estos, la bomba seria de un solo jugador otra vez
		# y nada lo diria — el host arbitra y el Portador tiene que saber
		# escuchar la respuesta.
		for m in ["_pedir_bomba", "aplicar_bomba", "bomba_denegada"]:
			_check(metodos.has(m), "el interactor habla con el host: %s" % m)

	var net := load("res://game/net/network_manager.gd") as GDScript
	if net != null:
		var suyos := PackedStringArray()
		for m in net.get_script_method_list():
			suyos.append(m["name"])
		for m in ["pedir_bomba", "_pedir_bomba", "_resolver_bomba", "_aplicar_bomba",
				"_bomba_denegada", "_ejecutar_bomba", "_liberar_bombas_de"]:
			_check(suyos.has(m), "Net tiene la familia de la bomba: %s" % m)


## El arbitro: exclusividad, manos y propiedad. Es lo que decide la carrera de
## dos jugadores pulsando E a la vez, y por orden total gana el primero.
func _test_arbitrar() -> void:
	var V := BombaModel.Verbo
	var M := BombaModel.Motivo
	var NADIE := BombaModel.NADIE

	_check(BombaModel.arbitrar(V.OCUPAR, NADIE, NADIE, 7, 0) == M.OK,
		"con la bomba libre y las manos vacias, se ocupa")
	_check(BombaModel.arbitrar(V.OCUPAR, 7, NADIE, 9, 0) == M.OCUPADA,
		"pero la carrera la pierde el segundo, y con un motivo que se puede decir")
	_check(BombaModel.arbitrar(V.OCUPAR, 7, NADIE, 7, 0) == M.OK,
		"y volver a pedirla siendo el ocupante no es un error (el agarre es pesimista)")
	_check(BombaModel.arbitrar(V.OCUPAR, NADIE, NADIE, 7, 1) == M.MANOS_LLENAS,
		"bombear son las dos manos: con una ocupada no se puede")

	_check(BombaModel.arbitrar(V.LIBERAR, 7, NADIE, 9, 0) == M.NO_ES_TUYO,
		"nadie te saca de la bomba")
	_check(BombaModel.arbitrar(V.LIBERAR, NADIE, NADIE, 9, 0) == M.OK,
		"soltar lo que ya esta suelto es idempotente, no un fallo")

	_check(BombaModel.arbitrar(V.ACCION_ON, 7, NADIE, 9, 0) == M.NO_ES_TUYO,
		"no puedes accionar la bomba de otro")
	_check(BombaModel.arbitrar(V.ACCION_ON, 7, NADIE, 7, 2) == M.OK,
		"el que la ocupa si, con sus dos manos ya puestas")

	# La manguera es de UNA mano: quien la dirige conserva el movimiento.
	_check(BombaModel.arbitrar(V.TOMAR_MANGUERA, NADIE, NADIE, 9, 1) == M.OK,
		"el cabezal se lleva con una mano, aunque lleves algo en la otra")
	_check(BombaModel.arbitrar(V.TOMAR_MANGUERA, NADIE, NADIE, 9, 2) == M.MANOS_LLENAS,
		"pero no con las dos ocupadas")
	_check(BombaModel.arbitrar(V.TOMAR_MANGUERA, NADIE, 7, 9, 0) == M.MANGUERA_TOMADA,
		"ni si ya lo lleva otro")
	# Y la consecuencia que hace cooperativa la mecanica sin un solo candado: el
	# que bombea NO puede ademas dirigir el cabezal, porque ya no le quedan manos.
	_check(BombaModel.arbitrar(V.TOMAR_MANGUERA, 7, NADIE, 7,
		BombaModel.MANOS_BOMBEAR) == M.MANOS_LLENAS,
		"el que bombea no puede ademas dirigir la manguera: para eso hace falta otro")

	for motivo in [M.OCUPADA, M.MANOS_LLENAS, M.NO_ES_TUYO, M.MANGUERA_TOMADA]:
		_check(BombaModel.texto_motivo(motivo).length() > 0,
			"cada rechazo se puede decir en voz alta", "motivo %d" % motivo)


## La tabla de identidad de las estaciones. El INDICE es lo que viaja, asi que
## una ruta que no resuelve no es "falta un nodo": es un jugador ocupando en su
## pantalla una bomba que en la del host es otra, o ninguna.
func _test_la_identidad_de_red() -> void:
	_check(BombaModel.BOMBAS.size() > 0, "hay al menos una estacion autorada")
	# APPEND-ONLY: el indice 0 es y sera la bomba de babor. Si alguien inserta
	# una delante, dos versiones del juego dejan de entenderse en silencio.
	_check(String(BombaModel.BOMBAS[0]).ends_with("PumpPort/BombaManual"),
		"el indice 0 sigue siendo la bomba de babor (la tabla es APPEND-ONLY)",
		String(BombaModel.BOMBAS[0]))
	_check(BombaModel.BOMBA_NINGUNA < 0,
		"y el 'ninguna' no puede confundirse con un indice valido")

	var barco := (load(RUTA_BARCO) as PackedScene).instantiate() as Node3D
	var vistas := {}
	for i in BombaModel.BOMBAS.size():
		var n := barco.get_node_or_null(BombaModel.BOMBAS[i])
		_check(n is ManualBilgePump,
			"la estacion %d resuelve en el barco" % i, String(BombaModel.BOMBAS[i]))
		_check(not vistas.has(n), "y no hay dos indices apuntando a la misma bomba")
		vistas[n] = i
	barco.queue_free()


## Los verbos aplicados: el punto por el que pasan el host y el solitario. Si
## estos dos caminos se separaran, un cliente veria una cosa y el host otra sin
## que ningun error lo dijera.
func _test_los_verbos_se_aplican() -> void:
	var barco := await _barco_a_flote()
	if barco == null:
		return
	var bomba := barco.get_node_or_null(RUTA_BOMBA) as ManualBilgePump
	if bomba == null:
		_check(false, "la bomba esta montada en el barco")
		await _liberar(barco)
		return
	var V := BombaModel.Verbo
	var mano := Marker3D.new()
	barco.add_child(mano)
	mano.global_position = bomba.posicion_toma_global()

	bomba.aplicar_verbo(7, V.OCUPAR, null)
	_check(bomba.ocupante == 7 and not bomba.estacion_libre(), "OCUPAR deja la estacion a su nombre")
	bomba.aplicar_verbo(7, V.ACCION_ON, null)
	_check(bomba.bombeando, "ACCION_ON acciona la palanca")
	bomba.aplicar_verbo(7, V.ACCION_OFF, null)
	_check(not bomba.bombeando, "y ACCION_OFF la suelta")

	bomba.aplicar_verbo(9, V.TOMAR_MANGUERA, mano)
	_check(bomba.portador_manguera == 9 and bomba.esta_manguera_tomada(),
		"TOMAR_MANGUERA apunta a quien lleva el cabezal: puede ser OTRO peer")
	bomba.aplicar_verbo(9, V.SOLTAR_MANGUERA, null)
	_check(bomba.portador_manguera == BombaModel.NADIE and not bomba.esta_manguera_tomada(),
		"y SOLTAR_MANGUERA lo devuelve")

	# Sin socket de mano no se toma: en un cliente recien llegado la copia del
	# compañero puede no existir todavia, y agarrar contra null dejaria la
	# manguera colgando de la nada.
	bomba.aplicar_verbo(9, V.TOMAR_MANGUERA, null)
	_check(bomba.portador_manguera == BombaModel.NADIE,
		"sin mano donde agarrar, el cabezal no se toma")

	bomba.aplicar_verbo(7, V.ACCION_ON, null)
	bomba.aplicar_verbo(7, V.LIBERAR, null)
	_check(bomba.estacion_libre() and not bomba.bombeando,
		"LIBERAR suelta la estacion Y la palanca: irse no deja la bomba sola bombeando")

	await _liberar(barco)


## Un flanco de palanca que llega DESPUES de tu propio LIBERAR no es una
## usurpacion: es un mensaje que se cruzo con otro por el camino.
##
## Sale de la revision del cableado de red: soltar el clic mientras te alejas de
## la bomba mandaba ACCION_OFF justo detras del LIBERAR, y el host contestaba
## "no es tuyo" en la cara de alguien que acababa de soltarla el mismo. Acusar a
## quien no hizo nada es feedback que miente (regla 8), asi que se distingue.
func _test_el_flanco_tardio_no_acusa_a_nadie() -> void:
	var V := BombaModel.Verbo
	var M := BombaModel.Motivo
	var NADIE := BombaModel.NADIE

	_check(BombaModel.arbitrar(V.ACCION_OFF, NADIE, NADIE, 7, 0) == M.TARDIO,
		"soltar la palanca de una estacion ya libre es TARDIO, no NO_ES_TUYO")
	_check(BombaModel.arbitrar(V.ACCION_ON, NADIE, NADIE, 7, 0) == M.TARDIO,
		"y accionarla tambien: el mensaje se cruzo, nadie te la quito")
	_check(BombaModel.texto_motivo(M.TARDIO) == "",
		"y TARDIO no se le dice al jugador: no hay nada que contarle")

	# Pero usurpar SIGUE siendo usurpar: si la ocupa OTRO, el motivo es el de
	# siempre y se dice en voz alta.
	_check(BombaModel.arbitrar(V.ACCION_ON, 9, NADIE, 7, 0) == M.NO_ES_TUYO,
		"accionar la bomba de otro sigue siendo NO_ES_TUYO, y se dice")
	_check(BombaModel.texto_motivo(M.NO_ES_TUYO) != "",
		"porque ahi si hay algo que contar")

	# APPEND-ONLY: el motivo viaja por el cable. Si alguien inserta uno en medio,
	# dos versiones del juego se dicen cosas distintas.
	_check(int(M.OK) == 0 and int(M.OCUPADA) == 1 and int(M.MANOS_LLENAS) == 2
			and int(M.NO_ES_TUYO) == 3 and int(M.MANGUERA_TOMADA) == 4,
		"los motivos de siempre conservan su numero (la tabla es APPEND-ONLY)")


## Los dos tiempos por separado: que cada uno respete sus topes. La bomba no es
## un grifo — mantener el clic llena una camara, y con la camara llena ya no
## entra nada por mucho que aprietes.
func _test_los_dos_tiempos() -> void:
	var pleno := 0.02
	var succion := pleno * BombaModel.FACTOR_TIEMPO
	var capacidad := succion * SEG

	# --- chupar ---
	_check(is_zero_approx(BombaModel.paso_aspiracion(
			0.0, capacidad, succion, 0.0, true, 0.5, DT)),
		"sobre una celda seca no entra nada: la bomba chupa aire")
	_check(is_zero_approx(BombaModel.paso_aspiracion(
			capacidad, capacidad, succion, 1.0, true, 0.5, DT)),
		"con la camara llena, seguir apretando ya no mete agua")
	_check(is_equal_approx(BombaModel.paso_aspiracion(
			0.0, capacidad, succion, 1.0, true, 0.5, DT), succion * DT),
		"con el cabezal dirigido, la succion entera")
	_check(is_equal_approx(BombaModel.paso_aspiracion(
			0.0, capacidad, succion, 1.0, false, 0.5, DT), succion * DT * 0.5),
		"con el cabezal tirado en cubierta, la mitad")
	_check(is_equal_approx(BombaModel.paso_aspiracion(
			0.0, capacidad, succion, 0.0001, true, 0.5, DT), 0.0001),
		"y nunca mas de lo que la celda tiene dentro")
	_check(is_equal_approx(BombaModel.paso_aspiracion(
			capacidad - 0.0001, capacidad, succion, 1.0, true, 0.5, DT), 0.0001),
		"ni mas de lo que le cabe")

	# --- escupir ---
	_check(is_equal_approx(BombaModel.paso_descarga(capacidad, succion, DT), succion * DT),
		"escupir saca al ritmo de la descarga")
	_check(is_equal_approx(BombaModel.paso_descarga(0.0001, succion, DT), 0.0001),
		"y la ultima gota no inventa agua de mas")
	_check(is_zero_approx(BombaModel.paso_descarga(0.0, succion, DT)),
		"con la camara vacia no sale nada")

	# --- las conversiones celda <-> media ---
	_check(is_equal_approx(BombaModel.caudal_por_celda(0.02, 8), 0.16),
		"sacarle a una celda de ocho baja la media ocho veces menos")
	_check(is_equal_approx(BombaModel.agua_de_celda(0.16, 8), 0.02),
		"y la conversion de vuelta es la inversa exacta")


## EL test del dial de dificultad: un ciclo bien hecho tiene que mover
## exactamente el caudal que promete el balance del agua. Si alguien toca los
## factores de los tiempos, la tormenta deja de estar cuadrada y hay que
## enterarse aqui y no jugando.
func _test_el_ciclo_da_el_caudal_del_balance() -> void:
	var balance := load(RUTA_BALANCE) as AguaEmbarcadaBalance
	if balance == null:
		_check(false, "el balance del agua carga", RUTA_BALANCE)
		return
	var pleno := balance.caudal_bomba
	var succion := pleno * BombaModel.FACTOR_TIEMPO

	_check(is_equal_approx(BombaModel.caudal_sostenido(succion, succion), pleno),
		"sobre el papel, el ciclo perfecto da el caudal del balance",
		"%.5f vs %.5f" % [BombaModel.caudal_sostenido(succion, succion), pleno])

	# Ahora simulado tick a tick, que es lo que de verdad va a pasar: se chupa
	# hasta llenar, se escupe hasta vaciar, y vuelta a empezar. La ventana son
	# OCHO ciclos exactos (chupar + escupir = 2 carreras); sin un numero entero de
	# ciclos la medida se comeria media embolada y el test mentiria por abajo.
	var medido := _simular_ciclo(succion * SEG, succion, succion, SEG * 2.0 * 8.0)
	_check(absf(medido - pleno) < pleno * 0.02,
		"y jugado tick a tick tambien",
		"medido %.5f/s vs balance %.5f/s" % [medido, pleno])

	# Y la capacidad NO entra en la cuenta: una camara del doble da emboladas mas
	# largas y mas espaciadas, no mas agua. Es lo que separa los dos ejes de
	# mejora de los tiers — comodidad no es caudal.
	var doble := _simular_ciclo(succion * SEG * 2.0, succion, succion, SEG * 4.0 * 4.0)
	_check(absf(doble - medido) < pleno * 0.02,
		"y una camara del doble achica igual: mas capacidad es comodidad, no caudal",
		"camara normal %.5f/s vs camara doble %.5f/s" % [medido, doble])


## El 50 % de DISENO.md, comprobado sobre el CICLO ENTERO y no sobre un tiempo
## suelto.
##
## Este test nace de un fallo que el ciclo de dos tiempos fabrica solo, y que se
## descubrio corriendo el arnes: metiendo el 0,5 directo en la aspiracion, el
## solitario rendia el 67 %, porque escupir dura lo mismo lo sostenga alguien o
## no y medio ciclo no se enteraba del castigo. La bomba habria sido un tercio
## mas generosa de lo que dice el diseño, en silencio.
func _test_el_solitario_rinde_la_mitad() -> void:
	var balance := load(RUTA_BALANCE) as AguaEmbarcadaBalance
	if balance == null:
		_check(false, "el balance del agua carga", RUTA_BALANCE)
		return
	var succion := balance.caudal_bomba * BombaModel.FACTOR_TIEMPO
	var capacidad := succion * SEG

	var factor := BombaModel.factor_aspiracion_solo(0.5, succion, succion)
	_check(absf(factor - 1.0 / 3.0) < 0.001,
		"para que el ciclo rinda la mitad, la aspiracion se frena a un tercio",
		"%.4f" % factor)

	# La ventana son ocho ciclos acompañado (2 carreras cada uno) y cuatro solo
	# (la aspiracion tarda el triple, o sea 4 carreras por ciclo): enteros los dos,
	# que es lo unico que hace comparable la medida.
	var ventana: float = SEG * 2.0 * 8.0
	var pleno := _simular_ciclo(capacidad, succion, succion, ventana)
	var solo := _simular_ciclo(capacidad, succion * factor, succion, ventana)
	_check(pleno > 0.0 and absf(solo / pleno - 0.5) < 0.03,
		"y el ciclo del solitario rinde la mitad, no dos tercios",
		"%.1f %% del caudal pleno" % (solo / maxf(pleno, 1e-9) * 100.0))


## Corre el ciclo tick a tick durante `segundos` y devuelve cuanta agua sale del
## barco por segundo. Determinista y sin nodos: es la bomba en el vacio.
func _simular_ciclo(capacidad: float, succion: float, descarga: float,
		segundos: float) -> float:
	var carga: float = 0.0
	var fuera: float = 0.0
	var chupando := true
	var ticks := int(round(segundos / DT))
	for _i in ticks:
		if chupando:
			carga += BombaModel.paso_aspiracion(carga, capacidad, succion, 1.0, true, 0.5, DT)
			chupando = carga < capacidad - 1e-9
		else:
			var soltado := BombaModel.paso_descarga(carga, descarga, DT)
			carga -= soltado
			fuera += soltado
			chupando = carga <= 1e-9
	return fuera / maxf(float(ticks) * DT, 1e-9)


## La prueba de fuego: la bomba le saca agua a la celda donde esta el cabezal, y
## solo a esa. Es lo que convierte "achicar" en una decision.
func _test_achica_la_celda_del_cabezal() -> void:
	var barco := await _barco_a_flote()
	if barco == null:
		return
	var bomba := barco.get_node_or_null(RUTA_BOMBA) as ManualBilgePump
	if bomba == null:
		_check(false, "la bomba esta montada en el barco")
		await _liberar(barco)
		return

	for i in barco.probe_count():
		barco.flood_probe(i, 0.5)
	var celda := barco.probe_index_at(bomba.posicion_toma_global())
	_check(celda >= 0, "el cabezal cae dentro de alguna celda", "%d" % celda)

	var vecina: int = (celda + 4) % barco.probe_count()
	bomba.ocupar_estacion(1)
	bomba.set_bombeando(true)
	for _i in _ticks(2.0):
		await get_tree().physics_frame
	bomba.set_bombeando(false)

	_check(barco.probe_flooding(celda) < 0.5,
		"la bomba le saca agua a la celda del cabezal",
		"%.3f" % barco.probe_flooding(celda))
	_check(is_equal_approx(barco.probe_flooding(vecina), 0.5),
		"y no toca las demas: elegir celda es la decision",
		"%.3f" % barco.probe_flooding(vecina))
	_check(bomba.celda_en_uso() < 0 or not bomba.bombeando,
		"al soltar la palanca deja de achicar")

	await _liberar(barco)


## La regla que sostiene todo el diseño: LLENAR mueve el agua dentro del barco,
## EXTRAER apuntando afuera es lo unico que la saca.
##
## Sin esto, llenar el deposito y no vaciarlo nunca seria una forma gratis de
## esconder agua y burlar el umbral de naufragio.
func _test_el_agua_pasa_por_el_deposito() -> void:
	var barco := await _barco_a_flote()
	if barco == null:
		return
	var bomba := barco.get_node_or_null(RUTA_BOMBA) as ManualBilgePump
	var agua := barco.get_node_or_null(^"AguaEmbarcada") as AguaEmbarcada
	if bomba == null or agua == null:
		_check(false, "la bomba y el agua embarcada estan montadas en el barco")
		await _liberar(barco)
		return

	for i in barco.probe_count():
		barco.flood_probe(i, 0.6)
	await get_tree().physics_frame
	var nivel_antes := agua.nivel
	var celda := barco.probe_index_at(bomba.posicion_toma_global())

	# --- llenar ---
	bomba.ocupar_estacion(1)
	bomba.set_bombeando(true)
	for _i in _ticks(2.0):
		await get_tree().physics_frame

	_check(bomba.carga_deposito > 0.0,
		"bombear llena el deposito", "%.5f" % bomba.carga_deposito)
	_check(barco.probe_flooding(celda) < 0.6,
		"y le quita agua a la celda, asi que el barco se endereza",
		"%.3f" % barco.probe_flooding(celda))
	_check(absf(agua.nivel - nivel_antes) < 0.0005,
		"pero el nivel a bordo NO baja: el agua sigue dentro, en el deposito",
		"antes %.5f, ahora %.5f" % [nivel_antes, agua.nivel])

	# --- extraer, con la punta POR FUERA del casco ---
	var fuera := _mano_en(barco, Vector3(-4.0, 1.5, 0.0))
	bomba.tomar_manguera(fuera)
	await get_tree().physics_frame
	_check(bomba.punta_fuera_del_casco(),
		"la punta llega por fuera de la borda")
	bomba.aplicar_verbo(1, BombaModel.Verbo.MODO_EXTRACCION, null)
	for _i in _ticks(6.0):
		await get_tree().physics_frame

	_check(is_zero_approx(bomba.carga_deposito),
		"extraer vacia el deposito", "%.5f" % bomba.carga_deposito)
	_check(agua.nivel < nivel_antes - 0.0005,
		"y AHI si baja el nivel: el agua salio del barco",
		"antes %.5f, ahora %.5f" % [nivel_antes, agua.nivel])

	await _liberar(barco)


## Y la otra mitad de esa regla: apuntar la manguera hacia DENTRO no arregla
## nada. El deposito se vacia igual, pero el agua cae en la celda de debajo. No
## esta prohibido a proposito — es el fallo que se ve, y el que hace que valga la
## pena sacar la manguera por la borda.
func _test_apuntar_adentro_no_sirve() -> void:
	var barco := await _barco_a_flote()
	if barco == null:
		return
	var bomba := barco.get_node_or_null(RUTA_BOMBA) as ManualBilgePump
	var agua := barco.get_node_or_null(^"AguaEmbarcada") as AguaEmbarcada
	if bomba == null or agua == null:
		await _liberar(barco)
		return

	for i in barco.probe_count():
		barco.flood_probe(i, 0.6)
	var dentro := _mano_en(barco, Vector3(0.0, 1.5, 0.0))
	bomba.tomar_manguera(dentro)
	await get_tree().physics_frame
	_check(not bomba.punta_fuera_del_casco(),
		"la punta apuntando a cubierta cuenta como DENTRO")

	bomba.ocupar_estacion(1)
	bomba.set_bombeando(true)
	for _i in _ticks(2.0):
		await get_tree().physics_frame
	bomba.set_bombeando(false)
	await get_tree().physics_frame
	var nivel_antes := agua.nivel
	var llevaba := bomba.carga_deposito
	_check(llevaba > 0.0, "con el deposito cargado", "%.5f" % llevaba)

	bomba.aplicar_verbo(1, BombaModel.Verbo.MODO_EXTRACCION, null)
	for _i in _ticks(6.0):
		await get_tree().physics_frame

	_check(is_zero_approx(bomba.carga_deposito), "el deposito se vacia igual")
	_check(absf(agua.nivel - nivel_antes) < 0.0005,
		"pero el nivel a bordo NO baja: el agua volvio a la cubierta",
		"antes %.5f, ahora %.5f" % [nivel_antes, agua.nivel])

	await _liberar(barco)


## Con el deposito lleno la bomba deja de mover agua sin que cambie nada en
## pantalla: es la unica forma de fallar de esta mecanica que no se ve sola, y
## por tanto la que hay que telegrafiar (regla 8).
func _test_el_deposito_lleno_se_nota() -> void:
	var barco := await _barco_a_flote()
	if barco == null:
		return
	var bomba := barco.get_node_or_null(RUTA_BOMBA) as ManualBilgePump
	if bomba == null:
		await _liberar(barco)
		return

	for i in barco.probe_count():
		barco.flood_probe(i, 1.0)
	await get_tree().physics_frame
	_check(not bomba.deposito_lleno(), "con el deposito vacio, no avisa de nada")

	bomba.ocupar_estacion(1)
	bomba.set_bombeando(true)
	# Un poco mas de lo que tarda en llenarse, para que llegue al tope seguro.
	for _i in _ticks(bomba.segundos_de_deposito * 2.5):
		await get_tree().physics_frame
	var celda := barco.probe_index_at(bomba.posicion_toma_global())
	var quedaba := barco.probe_flooding(celda)

	_check(bomba.deposito_lleno(),
		"bombeando sin parar el deposito se llena y la bomba puede decirlo",
		"%.5f de %.5f" % [bomba.carga_deposito, bomba.capacidad_deposito()])

	for _i in _ticks(2.0):
		await get_tree().physics_frame
	_check(is_equal_approx(barco.probe_flooding(celda), quedaba),
		"y seguir bombeando ya no le saca nada mas a la celda",
		"%.5f -> %.5f" % [quedaba, barco.probe_flooding(celda)])

	bomba.set_bombeando(false)
	await _liberar(barco)


## La bomba ocupada pero quieta NO late. `embolada` es el pulso del vaiven del
## brazo y de ella colgaran el traqueteo y el chorro: emitirla con la palanca
## parada seria un canal describiendo un movimiento que no ocurre (regla 8).
##
## El caso que se colaba era el corriente: alguien de pie en la bomba esperando a
## que llegue el del colador, oyendo la palanca sola cada 0,75 s.
func _test_la_bomba_parada_no_late() -> void:
	var barco := await _barco_a_flote()
	if barco == null:
		return
	var bomba := barco.get_node_or_null(RUTA_BOMBA) as ManualBilgePump
	if bomba == null:
		_check(false, "la bomba esta montada en el barco")
		await _liberar(barco)
		return

	var latidos := [0]
	bomba.embolada.connect(func(_con_agua: bool) -> void: latidos[0] += 1)

	# Ocupada y quieta, cuatro carreras de reloj.
	bomba.ocupar_estacion(1)
	var ticks: int = int(round(SEG * 4.0 / DT))
	for _i in ticks:
		await get_tree().physics_frame
	_check(int(latidos[0]) == 0,
		"ocupar la bomba y quedarse quieto no suena a palanca",
		"%d emboladas" % int(latidos[0]))

	# Y accionandola si late, para que el test no pase por estar todo mudo.
	for i in barco.probe_count():
		barco.flood_probe(i, 0.6)
	bomba.set_bombeando(true)
	for _i in ticks:
		await get_tree().physics_frame
	_check(int(latidos[0]) > 0,
		"pero bombeando de verdad si late",
		"%d emboladas" % int(latidos[0]))

	bomba.set_bombeando(false)
	await _liberar(barco)


## Llenar va al doble con alguien sujetando el colador. La interdependencia sale
## de las manos, no de un candado: la palanca son dos manos y el colador una.
func _test_llenar_va_al_doble_con_ayudante() -> void:
	var solo := await _llenar_durante(3.0, false)
	var acompanado := await _llenar_durante(3.0, true)
	var proporcion: float = acompanado / maxf(solo, 1e-9)
	_check(solo > 0.0 and absf(proporcion - 2.0) < 0.3,
		"con alguien dirigiendo el colador se llena el doble de rapido",
		"solo %.4f vs acompañado %.4f (x%.2f)" % [solo, acompanado, proporcion])


## Cuanta agua entra en el deposito en `segundos`, con y sin ayudante.
func _llenar_durante(segundos: float, con_ayudante: bool) -> float:
	var barco := await _barco_a_flote()
	if barco == null:
		return 0.0
	var bomba := barco.get_node_or_null(RUTA_BOMBA) as ManualBilgePump
	if bomba == null:
		await _liberar(barco)
		return 0.0
	# A tope: la medida no puede toparse con una celda que se seca a mitad.
	for i in barco.probe_count():
		barco.flood_probe(i, 1.0)
	if con_ayudante:
		# Un ayudante es una mano que sostiene el colador donde hay agua: se
		# simula con un Marker3D quieto, que es justo lo que la API pide.
		bomba.tomar_manguera(_mano_en_global(barco, bomba.posicion_toma_global()))

	bomba.ocupar_estacion(1)
	bomba.set_bombeando(true)
	for _i in _ticks(segundos):
		await get_tree().physics_frame
	var entro := bomba.carga_deposito
	bomba.set_bombeando(false)
	await _liberar(barco)
	return entro


## Cuantos ticks de fisica son `segundos`.
func _ticks(segundos: float) -> int:
	return int(round(segundos / DT))


func _mano_en(barco: Node3D, local: Vector3) -> Marker3D:
	return _mano_en_global(barco, barco.to_global(local))


func _mano_en_global(barco: Node3D, mundo: Vector3) -> Marker3D:
	var m := Marker3D.new()
	barco.add_child(m)
	m.global_position = mundo
	return m


func _barco_a_flote() -> FloatingBody3D:
	await get_tree().physics_frame
	Ocean.clear_events()
	Ocean.set_fury_immediate(0.0)
	# Sin lluvia: es una entrada de agua independiente de la furia, y dejarla al
	# valor que trajera la escena haria que el barco embarcara durante la medida.
	Ocean.rain_level = 0.0
	var barco: FloatingBody3D = (load(RUTA_BARCO) as PackedScene).instantiate()
	add_child(barco)
	barco.global_position = Vector3(0, 1, 0)
	for _i in 240:
		await get_tree().physics_frame
	if barco.probe_count() == 0:
		_check(false, "el barco trae sus celdas de flotacion")
		await _liberar(barco)
		return null
	return barco


func _liberar(barco: Node) -> void:
	if barco == null:
		return
	barco.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
