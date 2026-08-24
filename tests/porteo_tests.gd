extends Node

## Pruebas del porteo (docs/PORTEO.md).
##
##   godot --headless --path . tests/porteo_tests.tscn
##
## Lo que se protege aqui son los fallos SILENCIOSOS del sistema: un objeto
## congelado que sigue acumulando empuje del oceano, unas manos que se quedan
## ocupadas para siempre, un pez que cuenta en bodega mientras lo llevas en la
## mano, o el contrato de manos del player torcido de forma que portear a dos
## manos te clave en el sitio (portear CAMINA; la lucha de la caña, no).

const FAROL := preload("res://game/props/farol.tscn")
const GANCHO := preload("res://game/props/gancho_farol.tscn")
const FISH := preload("res://game/fishing/fish.tscn")
const BODEGA := preload("res://game/boat/bodega.tscn")
const RADIO := preload("res://game/props/radio.tscn")
const LLAVE := preload("res://game/props/llave_motor.tscn")
const SOPORTE := preload("res://game/props/soporte_cania.tscn")
const ROD := preload("res://game/fishing/fishing_rod.tscn")

## Especies de laboratorio: sin visual_scene para no cargar GLBs en el test.
const SARDINA := {&"name": "Sardina", &"weight": 2.0, &"value": 6,
	&"color": Color(0.65, 0.72, 0.78)}
const FLETAN := {&"name": "Fletan", &"weight": 20.0, &"value": 90,
	&"color": Color(0.42, 0.38, 0.3)}

var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0


func _ready() -> void:
	print_rich("[b]--- Pruebas del porteo ---[/b]")
	# LA APUESTA DE R1 corre PRIMERO, antes que nada: de ella cuelga la promesa
	# de que con los cuerpos replicados la cuota coincide sola en las seis
	# maquinas. Si falla, la red necesita otra respuesta para el pez, y la
	# bodega es territorio de otra sesion donde no se puede arreglar.
	await _test_bodega_cuenta_congelado_por_red()
	_test_contrato_de_manos()
	_test_tomar_congela()
	_test_congelar_por_red_conserva_capa()
	_test_congelar_borra_fuerza_rancia()
	_test_gancho_no_queda_ocupado()
	_test_hueco_del_cinturon()
	_test_soltar_solo_lo_tuyo()
	await _test_slam_fantasma_al_descongelar()
	_test_soltar_restaura()
	_test_manos_del_pez()
	_test_pez_no_colgable()
	_test_lentitud_por_peso()
	_test_gancho_visible_al_rayo()
	_test_cinturon()
	_test_soporte_y_cana()
	await _test_bodega_cuenta_presencia()
	await _test_llave_se_hunde_radio_flota()
	await _test_cana_se_guarda_clavada()
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
		print_rich("[color=red][b]%d de %d han fallado:[/b][/color]" % [_failures.size(), _checks])
		for f in _failures:
			print("   - " + f)
		get_tree().quit(1)


func _nuevo_pez(especie: Dictionary) -> Fish:
	var pez := FISH.instantiate() as Fish
	add_child(pez)
	pez.setup(especie)
	return pez


# =============================================================================


## El contrato de tres numeros con player.gd. La distincion que protege este
## test: hands_used=2 (porteo pesado) deja hands_busy=true pero NO captura el
## input — caminas con el fletan. Solo la caña captura el input.
func _test_contrato_de_manos() -> void:
	var p := Player.new()
	add_child(p)
	p.hands_used = 1
	_check(not p.hands_busy, "una mano ocupada: el jugador sigue entero")
	p.hands_used = 2
	_check(p.hands_busy, "dos manos ocupadas: hands_busy se lee true")
	_check(not p.input_captured, "portear a dos manos NO captura el input (caminas)")
	p.hands_used = 0
	p.hands_busy = true
	_check(p.input_captured and p.hands_used == 2,
		"la caña (hands_busy=true) captura input y llena las manos")
	p.hands_busy = false
	_check(not p.input_captured and p.hands_used == 0,
		"soltar la caña libera input y manos")
	p.queue_free()


func _test_tomar_congela() -> void:
	var f := FAROL.instantiate() as Farol
	add_child(f)
	var capa: int = f.collision_layer
	var cuerpo := Node3D.new()
	add_child(cuerpo)
	var mano := Marker3D.new()
	cuerpo.add_child(mano)

	_check(f.tomar(cuerpo, mano), "un objeto suelto se deja coger")
	_check(f.estado == Portable3D.Estado.EN_MANO, "en mano su estado lo dice")
	_check(f.freeze, "en mano queda congelado (kinematico)")
	_check(f.collision_layer == 0, "en mano no colisiona (no empuja al portador)")
	_check(not f.is_physics_processing(),
		"en mano el oceano deja de empujarlo (o explota al soltarlo)")
	_check(not f.tomar(cuerpo, mano), "no se puede coger lo que ya esta en una mano")

	f.queue_free()
	cuerpo.queue_free()
	_check(capa != 0, "cordura: la capa original del farol no era 0")


func _test_soltar_restaura() -> void:
	var f := FAROL.instantiate() as Farol
	add_child(f)
	var capa: int = f.collision_layer
	var cuerpo := Node3D.new()
	add_child(cuerpo)
	var mano := Marker3D.new()
	cuerpo.add_child(mano)
	f.tomar(cuerpo, mano)

	f.soltar(self, Vector3(3.0, 0.0, -1.0))
	_check(f.estado == Portable3D.Estado.SUELTO, "soltado vuelve a SUELTO")
	_check(not f.freeze, "soltado recupera la fisica")
	_check(f.collision_layer == capa, "soltado recupera su capa de colision")
	_check(f.linear_velocity.is_equal_approx(Vector3(3.0, 0.0, -1.0)),
		"soltado hereda la velocidad de quien lo soltaba",
		str(f.linear_velocity))
	f.queue_free()
	cuerpo.queue_free()


## El umbral 1<->2 manos cae entre el jurel y la lubina: toda la banda B
## compromete las dos manos. Si esto se mueve sin querer, la mitad del diseño
## de estaciones se afloja en silencio.
func _test_manos_del_pez() -> void:
	var chico := _nuevo_pez(SARDINA)
	_check(chico.manos == 1, "la sardina va al hombro con una mano")
	_check(is_equal_approx(chico.peso_kg(), 2.0), "el peso del porteo es el de la especie")
	_check(chico.nombre == "sardina", "el prompt recibe el nombre en minuscula")
	var gordo := _nuevo_pez(FLETAN)
	_check(gordo.manos == 2, "el fletan exige las dos manos")
	chico.queue_free()
	gordo.queue_free()


func _test_pez_no_colgable() -> void:
	var pez := _nuevo_pez(SARDINA)
	var g := GANCHO.instantiate() as GanchoFarol
	add_child(g)
	_check(not pez.colgar_en(g), "un pez no se cuelga de un gancho de farol")
	_check(g.libre(), "y el gancho sigue libre tras intentarlo")
	pez.queue_free()
	g.queue_free()


func _test_lentitud_por_peso() -> void:
	_check(is_equal_approx(Portador.factor_lentitud(2.0), 1.0),
		"la sardina no frena a nadie")
	var fletan: float = Portador.factor_lentitud(20.0)
	_check(fletan > 0.8 and fletan < 0.9,
		"el fletan frena un poco", "%.3f" % fletan)
	var atun: float = Portador.factor_lentitud(60.0)
	_check(atun >= Portador.LENTITUD_MINIMA and atun < 0.5,
		"el atun te hace procesion, pero JAMAS te clava (regla 6)", "%.3f" % atun)


## El fix silencioso del gancho: su Zona nacia en capa 0 y ningun RayCast la
## veia — colgar y descolgar eran imposibles y no habia ni un warning.
func _test_gancho_visible_al_rayo() -> void:
	var g := GANCHO.instantiate() as GanchoFarol
	add_child(g)
	var zona := g.get_node_or_null(^"Zona") as Area3D
	_check(zona != null, "el gancho trae su Zona de apuntado")
	if zona != null:
		_check(zona.collision_layer != 0,
			"la Zona vive en una capa que la mira del portador puede ver")
	g.queue_free()


## El cinturon a nivel Portable3D: solo los objetos chicos declarados entran,
## guardado queda congelado pero VISIBLE (lo que llevas se ve — principio 1),
## y sacarlo lo devuelve a la mano entero.
func _test_cinturon() -> void:
	var radio := RADIO.instantiate() as Portable3D
	add_child(radio)
	var cinto := Marker3D.new()
	add_child(cinto)

	_check(radio.en_cinturon, "la radio se declara de cinturon")
	_check(radio.guardar_en(cinto), "la radio entra al cinturon")
	_check(radio.estado == Portable3D.Estado.EN_CINTURON, "y su estado lo dice")
	_check(radio.freeze, "en el cinturon va congelada")
	_check(radio.visible, "pero VISIBLE: lo que llevas se ve (principio 1)")
	_check(not radio.guardar_en(cinto), "no se guarda dos veces")

	var mano := Marker3D.new()
	add_child(mano)
	var cuerpo := Node3D.new()
	add_child(cuerpo)
	_check(radio.tomar(cuerpo, mano), "del cinturon vuelve a la mano")
	_check(radio.estado == Portable3D.Estado.EN_MANO, "y queda EN_MANO")

	var pez := _nuevo_pez(SARDINA)
	_check(not pez.guardar_en(cinto), "un pez NO cabe en el cinturon")

	radio.queue_free()
	pez.queue_free()
	cinto.queue_free()
	mano.queue_free()
	cuerpo.queue_free()


## El soporte de borda: clavar la caña, retomarla, y que mientras este clavada
## la caña NO escuche el click (pesca sola, no se maneja a distancia).
func _test_soporte_y_cana() -> void:
	var s := SOPORTE.instantiate() as SoporteCania
	add_child(s)
	var s2 := SOPORTE.instantiate() as SoporteCania
	add_child(s2)
	var rod := ROD.instantiate() as FishingRod
	add_child(rod)

	var zona := s.get_node_or_null(^"Zona") as Area3D
	_check(zona != null and zona.collision_layer != 0,
		"la Zona del soporte es visible para la mira del portador")
	_check(s.libre(), "un soporte nuevo esta libre")

	_check(rod.clavar_en(s), "la caña en reposo se deja clavar")
	_check(rod.esta_clavada(), "y sabe que esta clavada")
	_check(s.ocupado, "el soporte queda ocupado")
	_check(s.get_node(^"CanaVisual").visible, "y muestra la caña clavada")
	_check(not rod._rod_input_ready(), "clavada, la caña no escucha el click")
	_check(not rod.clavar_en(s2), "no se clava en dos soportes a la vez")

	rod.set_tier(rod.tier) # no-op de cordura: nada revienta con la caña clavada
	rod.retomar()
	_check(not rod.esta_clavada(), "retomarla la devuelve a la mano")
	_check(s.libre(), "y libera el soporte")
	_check(not s.get_node(^"CanaVisual").visible, "que esconde su caña visual")
	_check(rod._rod_input_ready(), "en la mano vuelve a escuchar el click")

	rod.queue_free()
	s.queue_free()
	s2.queue_free()


## La bodega cuenta por PRESENCIA fisica: el pez suelto dentro suma; el mismo
## pez EN LA MANO (capa 0) no cuenta aunque este en el mismo sitio. Es la
## invariante que hace honesta la cuota sin una linea de codigo especial.
func _test_bodega_cuenta_presencia() -> void:
	# Lejos del agua: aqui se prueba el conteo, no la flotabilidad.
	var bodega := BODEGA.instantiate() as Bodega
	add_child(bodega)
	bodega.global_position = Vector3(0.0, 80.0, 0.0)

	var pez := _nuevo_pez(SARDINA)
	pez.global_position = Vector3(0.0, 80.35, 0.0)
	for i in 90: # ~0.75 s a 120 Hz: entrar al area y asentarse en el suelo
		await get_tree().physics_frame
	_check(is_equal_approx(bodega.kg, 2.0),
		"el pez suelto dentro de la celda cuenta sus kg", "%.2f kg" % bodega.kg)

	var cuerpo := Node3D.new()
	add_child(cuerpo)
	var mano := Marker3D.new()
	cuerpo.add_child(mano)
	mano.global_position = Vector3(0.0, 80.35, 0.0)
	pez.tomar(cuerpo, mano)
	for i in 30:
		await get_tree().physics_frame
	_check(is_zero_approx(bodega.kg),
		"cogerlo con la mano lo saca de la cuenta (capa 0)", "%.2f kg" % bodega.kg)

	pez.queue_free()
	cuerpo.queue_free()
	bodega.queue_free()
	await get_tree().process_frame


## "La llave se hunde; la lampara flota" (DISENO §2). La llave del motor al
## agua es una MISION, no una molestia — y la radio se queda cabeceando en la
## superficie, recuperable. Si alguien le pone flotabilidad a la llave, borra
## el patron camara de Content Warning sin darse cuenta.
func _test_llave_se_hunde_radio_flota() -> void:
	Ocean.set_fury_immediate(0.0)
	var llave := LLAVE.instantiate() as Portable3D
	add_child(llave)
	llave.global_position = Vector3(30.0, Ocean.get_height(Vector3(30, 0, 0)) - 0.1, 0.0)
	var radio := RADIO.instantiate() as Portable3D
	add_child(radio)
	radio.global_position = Vector3(-30.0, Ocean.get_height(Vector3(-30, 0, 0)) - 0.1, 0.0)

	for i in 360: # 3 s a 120 Hz
		await get_tree().physics_frame

	var agua_llave: float = Ocean.get_height(llave.global_position)
	_check(llave.global_position.y < agua_llave - 1.5,
		"la llave del motor se hunde", "%.2f m bajo el agua" % (agua_llave - llave.global_position.y))
	var sumersion_radio: float = Ocean.get_submersion(radio.global_position)
	_check(absf(sumersion_radio) < 0.6,
		"la radio se queda en la superficie", "sumersion %.2f m" % sumersion_radio)

	Ocean.set_fury_immediate(3.0)
	llave.queue_free()
	radio.queue_free()
	await get_tree().process_frame


## La caña clavada (o las manos cargadas) guardan el viewmodel: el pivote se
## esconde solo. La boya y el sedal son top_level y no dependen de el.
func _test_cana_se_guarda_clavada() -> void:
	var s := SOPORTE.instantiate() as SoporteCania
	add_child(s)
	var rod := ROD.instantiate() as FishingRod
	add_child(rod)
	var pivote := rod.get_node(^"RodPivot") as Node3D

	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(pivote.visible, "caña en mano: el viewmodel se ve")

	rod.clavar_en(s)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(not pivote.visible, "caña clavada: el viewmodel se guarda")

	rod.retomar()
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(pivote.visible, "retomada: el viewmodel vuelve")

	rod.queue_free()
	s.queue_free()
	await get_tree().process_frame


# =============================================================================
#  R1: lo que la red necesita del porteo (docs/RED.md)
# =============================================================================


## LA APUESTA DE R1. Un cuerpo replicado NO se simula en el cliente: se le
## escribe el `global_transform` tick a tick. La promesa de RED.md es que "con
## los props replicados la cuota coincide sola" — o sea que el `Area3D` de la
## bodega tiene que ver a un cuerpo congelado-KINEMATICO movido a mano igual
## que ve a uno que cae libre.
##
## Es una suposicion sobre el MOTOR y no se puede verificar leyendo codigo. Si
## sale roja, R1 necesita otra respuesta para el pez — y no se puede arreglar
## en la bodega, que la escribe otra sesion. El test de al lado
## (`_test_bodega_cuenta_presencia`) deja caer un pez LIBRE: no cubre esto.
func _test_bodega_cuenta_congelado_por_red() -> void:
	var bodega := BODEGA.instantiate() as Bodega
	add_child(bodega)
	bodega.global_position = Vector3(0.0, 140.0, 0.0)

	var pez := _nuevo_pez(SARDINA)
	# Congelado a la manera de la red: kinematico, sin fisica propia, pero con
	# la capa INTACTA (que es justo lo que `congelar_por_red` conserva).
	pez.congelar_por_red(true)
	await get_tree().physics_frame

	# Y ahora se mueve como lo movera el cliente: escribiendole el transform.
	for i in 120:
		pez.global_transform = Transform3D(Basis(), Vector3(0.0, 140.15, 0.0))
		await get_tree().physics_frame

	_check(bodega.cantidad_peces() == 1,
		"LA APUESTA: la bodega ve un cuerpo congelado movido por transform",
		"%d piezas, %.2f kg" % [bodega.cantidad_peces(), bodega.kg])
	_check(is_equal_approx(bodega.kg, 2.0),
		"y le cuenta los kilos igual que a uno que cae solo",
		"%.2f kg" % bodega.kg)

	pez.queue_free()
	bodega.queue_free()
	await get_tree().process_frame


## El congelado de RED conserva capa y mascara; el de PORTEO las pone a cero.
## Copiar el de porteo al camino de red anularia la cuota en TODOS los
## clientes mientras el pizarron del host marca sesenta kilos, y nada mas en
## el juego lo notaria.
func _test_congelar_por_red_conserva_capa() -> void:
	var f := FAROL.instantiate() as Farol
	add_child(f)
	var capa: int = f.collision_layer
	var mascara: int = f.collision_mask

	f.congelar_por_red(true)
	_check(f.freeze and not f.is_physics_processing(),
		"congelado por red: kinematico y sin fisica propia")
	_check(f.collision_layer == capa and f.collision_mask == mascara,
		"congelado por red CONSERVA capa y mascara (la bodega mira la capa 1)",
		"capa %d, mascara %d" % [f.collision_layer, f.collision_mask])

	f.congelar_por_red(false)
	_check(not f.freeze and f.is_physics_processing(),
		"descongelar por red devuelve la fisica")

	var cuerpo := Node3D.new()
	add_child(cuerpo)
	var mano := Marker3D.new()
	cuerpo.add_child(mano)
	f.tomar(cuerpo, mano)
	_check(f.collision_layer == 0,
		"en cambio el congelado de PORTEO si saca al objeto de las capas")

	f.queue_free()
	cuerpo.queue_free()


## `constant_force`/`constant_torque` se escriben de forma PERSISTENTE en
## `FloatingBody3D` (a proposito, para sobrevivir al `tick_divisor`) y no las
## borraba NADIE en todo el repo: al descongelar, el cuerpo se comia el empuje
## de antes del agarre — y con `tick_divisor = 2` podian ser dos ticks.
func _test_congelar_borra_fuerza_rancia() -> void:
	var f := FAROL.instantiate() as Farol
	add_child(f)
	f.constant_force = Vector3(0.0, 900.0, 0.0)
	f.constant_torque = Vector3(0.0, 12.0, 0.0)

	var cuerpo := Node3D.new()
	add_child(cuerpo)
	var mano := Marker3D.new()
	cuerpo.add_child(mano)
	f.tomar(cuerpo, mano)
	_check(f.constant_force.is_zero_approx() and f.constant_torque.is_zero_approx(),
		"congelar por porteo borra la fuerza rancia", str(f.constant_force))

	f.constant_force = Vector3(0.0, 900.0, 0.0)
	f.congelar_por_red(true)
	_check(f.constant_force.is_zero_approx(),
		"congelar por red tambien la borra", str(f.constant_force))

	f.queue_free()
	cuerpo.queue_free()


## `colgar_en` era el unico de los cuatro verbos que no desenganchaba el
## gancho anterior ni ocupaba el nuevo (lo hacia el Portador). Invisible por
## el camino del jugador; por un RPC que llama al verbo directo, deja el
## gancho viejo ocupado para siempre y admite dos objetos en el mismo sitio.
func _test_gancho_no_queda_ocupado() -> void:
	var g1 := GANCHO.instantiate() as GanchoFarol
	var g2 := GANCHO.instantiate() as GanchoFarol
	add_child(g1)
	add_child(g2)
	var f := FAROL.instantiate() as Farol
	add_child(f)

	_check(f.colgar_en(g1), "el farol cuelga del primer gancho")
	_check(not g1.libre(), "que queda ocupado")
	_check(f.colgar_en(g2), "y se pasa al segundo por el verbo directo")
	_check(g1.libre(), "el PRIMERO queda libre (antes se quedaba ocupado para siempre)")
	_check(not g2.libre(), "y el segundo, ocupado")

	var f2 := FAROL.instantiate() as Farol
	add_child(f2)
	_check(not f2.colgar_en(g2), "un gancho ocupado no admite un segundo farol")

	f.queue_free()
	f2.queue_free()
	g1.queue_free()
	g2.queue_free()


## El hueco del cinturon se busca LIBRE, no se deduce del tamaño de la lista:
## la poda borra desde el medio, asi que con dos guardados y el primero
## invalidado, el siguiente iria al marker que el segundo ya esta usando.
func _test_hueco_del_cinturon() -> void:
	var p := Portador.new()
	add_child(p)
	var a := RADIO.instantiate() as Portable3D
	var b := LLAVE.instantiate() as Portable3D
	add_child(a)
	add_child(b)

	p.objeto = a
	p._al_cinturon()
	p.objeto = b
	p._al_cinturon()
	_check(p.cinturon.size() == 2, "los dos objetos chicos entran al cinturon")
	_check(a.hueco_cinturon == 0 and b.hueco_cinturon == 1,
		"y cada uno recuerda SU hueco",
		"a=%d b=%d" % [a.hueco_cinturon, b.hueco_cinturon])

	# Se va el del hueco 0 (lo saca una ola, lo despawnea el host, lo que sea).
	p.cinturon.erase(a)
	a.hueco_cinturon = -1
	_check(p._hueco_libre() == 0,
		"liberado el hueco 0, el siguiente guardado va AHI y no encima del otro",
		"hueco propuesto %d" % p._hueco_libre())

	a.queue_free()
	b.queue_free()
	p.queue_free()


## `soltar()` no tenia NINGUNA guarda de portador: por el camino de un RPC,
## cualquiera podia soltar el objeto de cualquiera.
func _test_soltar_solo_lo_tuyo() -> void:
	var f := FAROL.instantiate() as Farol
	add_child(f)
	var yo := Node3D.new()
	var otro := Node3D.new()
	add_child(yo)
	add_child(otro)
	var mano := Marker3D.new()
	yo.add_child(mano)

	f.tomar(yo, mano)
	_check(not f.soltar(self, Vector3.ZERO, otro),
		"otro jugador NO puede soltar lo que llevo yo")
	_check(f.estado == Portable3D.Estado.EN_MANO, "y el objeto sigue en mi mano")
	_check(f.soltar(self, Vector3.ZERO, yo), "su portador si puede soltarlo")
	_check(f.estado == Portable3D.Estado.SUELTO, "y queda SUELTO")

	f.queue_free()
	yo.queue_free()
	otro.queue_free()


## Una escritura de transform ES un teleport, y un teleport fabricaba un slam:
## chapuzon con SFX y espuma que no ocurrio (regla 8), ademas calculado
## distinto en cada maquina. Es un bug de HOY —soltar un farol bajo el agua ya
## lo produce— que la red multiplicaria por cada cuerpo y cada devolucion.
func _test_slam_fantasma_al_descongelar() -> void:
	Ocean.set_fury_immediate(0.0)
	var f := FAROL.instantiate() as Farol
	add_child(f)
	_check(f.slam_threshold > 0.0, "cordura: el farol tiene deteccion de impacto")

	# Primero, historia de agua SECA: bien por encima de la superficie.
	var seco := Vector3(400.0, 0.0, 0.0)
	f.global_position = Vector3(seco.x, Ocean.get_height(seco) + 6.0, seco.z)
	f.freeze = true
	for i in 6:
		await get_tree().physics_frame

	var golpes: Array[float] = []
	f.slammed.connect(func(fuerza: float, _pos: Vector3) -> void: golpes.append(fuerza))

	# Y ahora el teleport que hara la red: de seco a tres metros bajo el agua.
	f.congelar_por_red(true)
	f.global_position = Vector3(seco.x, Ocean.get_height(seco) - 3.0, seco.z)
	f.congelar_por_red(false)
	for i in 8:
		await get_tree().physics_frame

	_check(golpes.is_empty(),
		"teletransportar un cuerpo bajo el agua NO fabrica un chapuzon",
		"%d slams fantasma" % golpes.size())

	Ocean.set_fury_immediate(3.0)
	f.queue_free()
	await get_tree().process_frame
