extends Node

## Pruebas de la red minima (docs/RED.md).
##
##   godot --headless --path . tests/net_tests.tscn
##
## Lo que se protege aqui son los tres contratos de la costura, que fallan EN
## SILENCIO y por eso son los mas caros del proyecto: la composicion en
## espacio local del barco (sin ella todos flotan despegados de la cubierta
## ajena), el reloj que persigue sin saltar (un salto teletransporta la
## superficie del mar entera), y la interpolacion que clampa en vez de
## extrapolar. Mas un loopback ENet REAL en un solo proceso: si el transporte
## no levanta en localhost, mejor enterarse aqui que en el playtest.

var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0


func _ready() -> void:
	print_rich("[b]--- Pruebas de la red minima ---[/b]")
	_test_ida_y_vuelta_local()
	_test_reloj_persigue_sin_saltar()
	_test_interpolacion_clampa()
	_test_autoload()
	# R1: las piezas PURAS. Todo lo que decide algo vive aca y no dentro de un
	# RPC, porque `Net` es un autoload singleton y no hay forma de que dos
	# instancias se hablen en un mismo proceso (ver la cabecera de NetPorteo).
	_test_arbitro_de_porteo()
	_test_arbitro_cuenta_las_manos()
	_test_codec_del_lote_ida_y_vuelta()
	_test_lag_ordena_por_canal_y_no_adelanta()
	_test_indice_de_especie_ida_y_vuelta()
	_test_rutas_y_censo_en_las_dos_escenas()
	_test_sin_maquinaria_nativa()
	_test_t0_del_host_da_la_misma_ola()
	_test_eventos_ida_y_vuelta()
	_test_desborde_de_slots_avisa()
	await _test_agarrar_apaga_la_replicacion()
	await _test_director_mudo_en_cliente()
	await _test_fase_de_tick_divisor_diverge()
	await _test_loopback_enet()
	_test_puerta_de_transporte()
	_test_codec_de_camaras()
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


# =============================================================================


## Contrato 1: lo que se manda en espacio local del barco vuelve EXACTO al
## componerlo contra el mismo barco — con el barco escorado, cabeceando y
## lejos del origen, que es cuando el atajo "mandalo en mundo" revienta.
func _test_ida_y_vuelta_local() -> void:
	var barco := Transform3D(
		Basis.from_euler(Vector3(0.31, 2.1, -0.22)), Vector3(184.0, 3.7, -92.0))
	var jugador := Transform3D(
		Basis.from_euler(Vector3(0.0, 0.8, 0.0)), Vector3(185.2, 5.1, -91.4))

	var local := NetMath.a_local(barco, jugador)
	var reconstruido := NetMath.a_mundo(barco, local)
	var err_pos: float = (reconstruido.origin - jugador.origin).length()
	_check(err_pos < 1e-4, "espacio local: la posicion sobrevive la ida y vuelta",
		"error %.6f m" % err_pos)
	var err_rot: float = (reconstruido.basis.get_rotation_quaternion().angle_to(
		jugador.basis.get_rotation_quaternion()))
	_check(err_rot < 1e-4, "espacio local: la rotacion sobrevive la ida y vuelta",
		"error %.6f rad" % err_rot)

	# Y el punto del contrato: contra OTRO instante del barco, el jugador
	# queda en el MISMO sitio de la cubierta (no en el mismo sitio del mundo).
	var barco2 := Transform3D(
		Basis.from_euler(Vector3(-0.18, 2.4, 0.15)), Vector3(190.0, 2.1, -88.0))
	var pegado := NetMath.a_mundo(barco2, local)
	var en_cubierta := NetMath.a_local(barco2, pegado)
	_check((en_cubierta.origin - local.origin).length() < 1e-4,
		"espacio local: el jugador queda pegado a la cubierta, no al mundo")


## Contrato 2: el reloj converge persiguiendo y JAMAS salta ni retrocede mas
## que el slew permitido. 0.3 s de error inicial a 120 Hz con slew del 25%:
## tiene que cerrarse en ~1.2 s de simulacion.
func _test_reloj_persigue_sin_saltar() -> void:
	var dt := 1.0 / 120.0
	var reloj := 10.0
	var host := 10.3
	var peor_paso: float = 0.0
	var retrocedio := false
	for i in 400: # ~3.3 s
		var previo := reloj
		reloj = NetMath.corregir_reloj(reloj + dt, host + dt - 0.0, dt, 0.25)
		host += dt
		peor_paso = maxf(peor_paso, absf(reloj - previo) - dt)
		if reloj < previo:
			retrocedio = true
	_check(absf(reloj - host) < 0.01, "el reloj alcanza al host",
		"error final %.4f s" % absf(reloj - host))
	_check(peor_paso <= 0.25 * dt + 1e-9, "la correccion respeta el slew maximo",
		"exceso %.6f" % peor_paso)
	_check(not retrocedio, "el reloj nunca retrocede persiguiendo hacia adelante")


## Contrato de interpolacion: entre snapshots interpola; fuera, CLAMPA (nunca
## extrapola un barco cabeceando).
func _test_interpolacion_clampa() -> void:
	var a := {&"t": 10.0, &"pos": Vector3(0, 0, 0),
		&"rot": Quaternion(Vector3.UP, 0.0)}
	var b := {&"t": 11.0, &"pos": Vector3(4, 2, 0),
		&"rot": Quaternion(Vector3.UP, PI * 0.5)}
	var buffer: Array[Dictionary] = [a, b]

	var medio := NetMath.muestrear_buffer(buffer, 10.5)
	_check(medio.origin.is_equal_approx(Vector3(2, 1, 0)),
		"a mitad de camino interpola la posicion", str(medio.origin))
	var ang: float = medio.basis.get_euler().y
	_check(absf(ang - PI * 0.25) < 1e-4, "y la rotacion (slerp)", "%.3f rad" % ang)

	var antes := NetMath.muestrear_buffer(buffer, 9.0)
	_check(antes.origin.is_equal_approx(Vector3.ZERO), "antes del buffer clampa al primero")
	var despues := NetMath.muestrear_buffer(buffer, 12.0)
	_check(despues.origin.is_equal_approx(Vector3(4, 2, 0)), "despues del buffer clampa al ultimo")
	var vacio := NetMath.muestrear_buffer([] as Array[Dictionary], 10.0)
	_check(vacio == Transform3D.IDENTITY, "el buffer vacio devuelve identidad, no revienta")


func _test_autoload() -> void:
	var net := get_node_or_null(^"/root/Net")
	_check(net != null, "el autoload Net existe")
	if net != null:
		_check(int(net.get(&"rol")) == 0, "y arranca OFFLINE (la red es opt-in)")


## La puerta de transporte: ENet para desarrollar y probar, Steam para publicar.
##
## Lo que este test protege NO es Steam —que no existe todavia— sino lo
## contrario: que ENet siga siendo el transporte por DEFECTO. Si alguien
## cambiara ese default, el ciclo de dos ventanas en una maquina y el loopback de
## aqui al lado se irian al suelo a la vez, y el sintoma seria "los tests tardan
## mucho" o "F10 ya no conecta", nunca "alguien cambio el transporte".
##
## Y que pedir STEAM sin el addon FALLE EN VOZ ALTA sin dejar a `Net` a medias:
## caer en silencio a ENet significaria que un build publicado creyera estar en
## Steam mientras abre un puerto en el router del jugador.
## El byte de banderas del agua lleva ahora tambien las camaras llenas. Cabia en
## los bits que sobraban, y NO se le puede añadir un byte al final: el numero de
## celdas se deduce de `datos.size() - 1`.
func _test_codec_de_camaras() -> void:
	var niveles := PackedFloat32Array([0.1, 0.25, 0.5, 0.75, 1.0, 0.0, 0.33, 0.66])
	var ida := NetAgua.empaquetar(niveles, true, false, 0b101)
	_check(ida.size() == niveles.size() + 1,
		"el paquete no crece: las camaras van en el byte que ya viajaba",
		"%d bytes" % ida.size())
	var vuelta := NetAgua.desempaquetar(ida)
	_check(int(vuelta[&"camaras"]) == 0b101,
		"las camaras llenas sobreviven el viaje", "%d" % int(vuelta[&"camaras"]))
	_check(bool(vuelta[&"alarma"]) and not bool(vuelta[&"naufragio"]),
		"y no pisan la alarma ni el naufragio")
	_check(PackedFloat32Array(vuelta[&"niveles"]).size() == niveles.size(),
		"ni el numero de celdas, que se deduce del tamaño")
	var vacio := NetAgua.desempaquetar(PackedByteArray())
	_check(int(vacio[&"camaras"]) == 0, "un paquete vacio no inventa camaras llenas")


func _test_puerta_de_transporte() -> void:
	_check(Net.transporte == Net.Transporte.ENET,
		"el transporte por defecto es ENet: es el que sostiene F9/F10 y los tests")
	# GodotSteam ya esta vendorizado (win64, ver THIRD_PARTY.md). Que la clase
	# EXISTA es la mitad del spike de R2 contestada: el GDExtension carga en
	# 4.7.2 aunque su `compatibility_minimum` diga 4.4.
	_check(ClassDB.class_exists(&"SteamMultiplayerPeer"),
		"GodotSteam carga en 4.7.2 y trae su MultiplayerPeer")

	var rol_previo: int = Net.rol
	if rol_previo != Net.Rol.OFFLINE:
		_check(false, "el arnes empieza con Net en OFFLINE", "rol %d" % rol_previo)
		return
	Net.transporte = Net.Transporte.STEAM
	Net.hostear()
	_check(Net.rol == Net.Rol.OFFLINE,
		"pedir STEAM sin el addon no deja a Net a medio hostear",
		"rol %d" % Net.rol)
	Net.unirse("0")
	_check(Net.rol == Net.Rol.OFFLINE,
		"ni a medio unirse")
	Net.transporte = Net.Transporte.ENET


## El transporte de verdad: dos ENetMultiplayerPeer en el mismo proceso,
## localhost, un paquete fiable de ida. Si esto no anda, nada de lo demas
## importa — y es exactamente lo que F9/F10 van a hacer con dos ventanas.
func _test_loopback_enet() -> void:
	var puerto := 4299
	var servidor := ENetMultiplayerPeer.new()
	var err := servidor.create_server(puerto, 1)
	_check(err == OK, "el servidor ENet abre en localhost", "error %d" % err)
	if err != OK:
		return
	var cliente := ENetMultiplayerPeer.new()
	_check(cliente.create_client("127.0.0.1", puerto) == OK, "el cliente ENet se crea")

	var conectado := false
	for i in 240: # hasta 2 s
		servidor.poll()
		cliente.poll()
		if cliente.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			conectado = true
			break
		await get_tree().physics_frame
	_check(conectado, "el cliente conecta al servidor local",
		"estado cliente %d" % cliente.get_connection_status())
	if not conectado:
		servidor.close()
		cliente.close()
		return

	# Asentar el lado servidor: el cliente puede verse CONNECTED un poll antes
	# de que el servidor procese su evento de entrada, y un broadcast en ese
	# hueco sale hacia cero peers y se pierde (fiable no es retroactivo).
	for i in 30:
		servidor.poll()
		cliente.poll()
		await get_tree().physics_frame
	_check(servidor.host.get_peers().size() > 0,
		"el servidor registro al peer", "%d peers" % servidor.host.get_peers().size())

	servidor.set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_RELIABLE)
	servidor.set_target_peer(0) # a todos
	var mensaje := "el mismo mar".to_utf8_buffer()
	servidor.put_packet(mensaje)

	var recibido := PackedByteArray()
	for i in 240:
		servidor.poll()
		cliente.poll()
		if cliente.get_available_packet_count() > 0:
			recibido = cliente.get_packet()
			break
		await get_tree().physics_frame
	_check(recibido == mensaje, "el paquete fiable llega entero",
		recibido.get_string_from_utf8())

	servidor.close()
	cliente.close()


# =============================================================================
#  R1 — las piezas puras
# =============================================================================


## La tabla entera del arbitro. Existe como funcion estatica precisamente para
## poder martillearla aca: dentro del cuerpo de un RPC no habria forma de
## probar ni una de estas reglas.
func _test_arbitro_de_porteo() -> void:
	const V := NetPorteo.Verbo
	const M := NetPorteo.Motivo
	var MANO: int = NetPorteo.socket_de_mano(1)
	var GANCHO_ID: int = 4
	var CINTO: int = NetPorteo.socket_de_cinturon(0)

	# Coger algo que no lleva nadie.
	_check(NetPorteo.arbitrar(V.SUELTO, NetPorteo.NADIE, 7, V.EN_MANO, MANO,
		false, 2, false, false) == M.OK, "coger lo que esta en el suelo: OK")

	# LA CARRERA: A ya lo tiene, B lo pide. Gana el orden total del host.
	_check(NetPorteo.arbitrar(V.EN_MANO, 7, 9, V.EN_MANO, MANO,
		false, 2, false, false) == M.YA_ES_DE_OTRO,
		"la carrera la pierde el segundo, y con un motivo que se puede decir")

	# Descolgar y sacar del cinturon son el MISMO gesto que coger.
	_check(NetPorteo.arbitrar(V.COLGADO, NetPorteo.NADIE, 7, V.EN_MANO, MANO,
		false, 2, true, false) == M.OK, "descolgar de un gancho es coger")
	_check(NetPorteo.arbitrar(V.EN_CINTURON, 7, 7, V.EN_MANO, MANO,
		false, 2, false, true) == M.OK, "sacar del cinturon es coger")

	# Soltar: solo lo tuyo.
	_check(NetPorteo.arbitrar(V.EN_MANO, 7, 7, V.SUELTO, NetPorteo.SOCKET_NINGUNO,
		false, 2, false, false) == M.OK, "soltar lo que llevo: OK")
	_check(NetPorteo.arbitrar(V.EN_MANO, 7, 9, V.SUELTO, NetPorteo.SOCKET_NINGUNO,
		false, 2, false, false) == M.NO_ES_TUYO,
		"soltar lo que lleva OTRO: rechazado")

	# Colgar: hay que llevarlo, tiene que ser colgable y el gancho estar libre.
	_check(NetPorteo.arbitrar(V.EN_MANO, 7, 7, V.COLGADO, GANCHO_ID,
		false, 2, true, false) == M.OK, "colgar el farol en un gancho libre: OK")
	_check(NetPorteo.arbitrar(V.EN_MANO, 7, 7, V.COLGADO, GANCHO_ID,
		true, 2, true, false) == M.SOCKET_OCUPADO, "gancho ocupado: rechazado")
	_check(NetPorteo.arbitrar(V.EN_MANO, 7, 7, V.COLGADO, GANCHO_ID,
		false, 2, false, false) == M.VERBO_IMPOSIBLE,
		"un pez no se cuelga: rechazado")

	# Cinturon: solo lo chico, y solo si queda hueco.
	_check(NetPorteo.arbitrar(V.EN_MANO, 7, 7, V.EN_CINTURON, CINTO,
		false, 1, false, true) == M.OK, "guardar la radio con hueco libre: OK")
	_check(NetPorteo.arbitrar(V.EN_MANO, 7, 7, V.EN_CINTURON, CINTO,
		false, 0, false, true) == M.CINTURON_LLENO, "cinturon lleno: rechazado")
	_check(NetPorteo.arbitrar(V.EN_MANO, 7, 7, V.EN_CINTURON, CINTO,
		false, 2, false, false) == M.VERBO_IMPOSIBLE,
		"un pez NO cabe en el cinturon: rechazado")

	# Sockets cruzados: colgar en un socket del jugador o encinturar en uno del
	# barco son imposibles, y hay que rechazarlos por construccion.
	_check(NetPorteo.arbitrar(V.EN_MANO, 7, 7, V.COLGADO, CINTO,
		false, 2, true, false) == M.VERBO_IMPOSIBLE,
		"colgar en un socket del cuerpo: imposible")
	_check(NetPorteo.arbitrar(V.SUELTO, NetPorteo.NADIE, 7, V.EN_MANO, GANCHO_ID,
		false, 2, true, false) == M.VERBO_IMPOSIBLE,
		"tener en la mano un socket del barco: imposible")

	# Las tablas de identidad: los dos SoporteCania se llaman IGUAL, asi que el
	# indice tiene que distinguirlos.
	_check(NetPorteo.SOCKETS[6] != NetPorteo.SOCKETS[7],
		"los dos soportes de caña son sockets DISTINTOS pese al mismo nombre")
	_check(not NetPorteo.socket_es_del_jugador(6)
		and NetPorteo.socket_es_del_jugador(0),
		"la frontera jugador/barco parte la tabla donde toca")
	_check(NetPorteo.socket_de_mano(1) != NetPorteo.socket_de_mano(2),
		"una mano y dos manos son markers distintos")
	_check(NetPorteo.cinturon_de_socket(NetPorteo.socket_de_cinturon(1)) == 1,
		"el hueco de cinturon sobrevive la ida y vuelta a socket")
	_check(not NetPorteo.texto_motivo(M.YA_ES_DE_OTRO, "Ana").is_empty(),
		"cada rechazo tiene texto que decirle al jugador (regla 8)")


## Las manos son DOS, y el arbitro es el unico que puede contarlas: con el
## agarre pesimista, el cliente todavia no sabe que ya tiene algo cuando pulsa
## E por segunda vez. Sin esta cuenta, dos toques dentro de la misma ventana de
## ida y vuelta sueldan dos objetos al mismo marker y el primero queda
## inalcanzable —imposible de soltar, de colgar y de apuntar— para el resto de
## la sesion, en las seis pantallas.
func _test_arbitro_cuenta_las_manos() -> void:
	const V := NetPorteo.Verbo
	const M := NetPorteo.Motivo
	var MANO: int = NetPorteo.socket_de_mano(1)
	var MANO2: int = NetPorteo.socket_de_mano(2)

	_check(NetPorteo.arbitrar(V.SUELTO, NetPorteo.NADIE, 7, V.EN_MANO, MANO,
		false, 2, false, false, 0, 1) == M.OK, "con las manos vacias, se coge")
	_check(NetPorteo.arbitrar(V.SUELTO, NetPorteo.NADIE, 7, V.EN_MANO, MANO,
		false, 2, false, false, 1, 1) == M.OK,
		"con una mano ocupada, todavia entra algo de una mano")
	_check(NetPorteo.arbitrar(V.SUELTO, NetPorteo.NADIE, 7, V.EN_MANO, MANO2,
		false, 2, false, false, 1, 2) == M.MANOS_LLENAS,
		"pero NO algo de dos manos: no te quedan")
	_check(NetPorteo.arbitrar(V.SUELTO, NetPorteo.NADIE, 7, V.EN_MANO, MANO,
		false, 2, false, false, 2, 1) == M.MANOS_LLENAS,
		"y con las dos llenas, nada")

	# Y pedir DOS VECES lo mismo no es perder una carrera: es ya tenerlo.
	_check(NetPorteo.arbitrar(V.EN_MANO, 7, 7, V.EN_MANO, MANO,
		false, 2, false, false, 1, 1) == M.YA_LO_LLEVAS,
		"pedir lo que YA llevas se distingue de perder la carrera")
	_check(NetPorteo.texto_motivo(M.YA_LO_LLEVAS, "").is_empty(),
		"y no se le dice nada al jugador: no paso nada malo")
	_check(NetPorteo.arbitrar(V.EN_MANO, 9, 7, V.EN_MANO, MANO,
		false, 2, false, false, 0, 1) == M.YA_ES_DE_OTRO,
		"perder la carrera de verdad SI se distingue")
	_check(not NetPorteo.texto_motivo(M.MANOS_LLENAS, "").is_empty(),
		"y quedarse sin manos se dice (regla 8)")


## Un codec que se desalinea medio byte convierte el mundo replicado en ruido
## sin un solo error de Godot.
func _test_codec_del_lote_ida_y_vuelta() -> void:
	var cuerpos: Array[Dictionary] = []
	for i in 12:
		cuerpos.append({
			&"id": i * 37,
			&"flags": (NetMath.FLAG_LOCAL if i % 2 == 0 else 0)
				| (NetMath.FLAG_DORMIDO if i % 3 == 0 else 0),
			&"pos": Vector3(-420.5 + float(i) * 31.25, 7.5 - float(i), 918.75 + float(i)),
			&"rot": Quaternion(Vector3(0.0, 1.0, 0.0).normalized(), float(i) * 0.37),
		})
	var datos := NetMath.empaquetar_cuerpos(1234.5, cuerpos)
	_check(datos.size() == NetMath.LOTE_CABECERA + 12 * NetMath.CUERPO_BYTES,
		"el lote mide exactamente lo que promete", "%d B" % datos.size())

	var vuelta := NetMath.desempaquetar_lote(datos)
	_check(is_equal_approx(float(vuelta[&"t"]), 1234.5), "el reloj del lote sobrevive")
	var salidos: Array = vuelta[&"cuerpos"]
	_check(salidos.size() == 12, "vuelven los 12 cuerpos", str(salidos.size()))

	var peor_pos: float = 0.0
	var peor_rot: float = 0.0
	var flags_ok := true
	for i in salidos.size():
		var a: Dictionary = cuerpos[i]
		var b: Dictionary = salidos[i]
		if int(a[&"id"]) != int(b[&"id"]) or int(a[&"flags"]) != int(b[&"flags"]):
			flags_ok = false
		peor_pos = maxf(peor_pos, ((a[&"pos"] as Vector3) - (b[&"pos"] as Vector3)).length())
		peor_rot = maxf(peor_rot,
			absf((a[&"rot"] as Quaternion).angle_to(b[&"rot"] as Quaternion)))
	_check(flags_ok, "ids y flags vuelven intactos")
	_check(peor_pos < 0.02, "la posicion aguanta el viaje (f32)", "%.4f m" % peor_pos)
	_check(peor_rot < 2e-3, "y la rotacion tambien (f16)", "%.5f rad" % peor_rot)

	# Un paquete mordido no puede tirar el tick entero.
	var mordido := datos.slice(0, datos.size() - 9)
	var parcial := NetMath.desempaquetar_lote(mordido)
	_check((parcial[&"cuerpos"] as Array).size() == 11,
		"un lote truncado devuelve los cuerpos COMPLETOS que haya",
		str((parcial[&"cuerpos"] as Array).size()))
	_check((NetMath.desempaquetar_lote(PackedByteArray())[&"cuerpos"] as Array).is_empty(),
		"y un lote vacio no revienta")
	_check(NetMath.cuerpos_por_paquete() * NetMath.CUERPO_BYTES
		+ NetMath.LOTE_CABECERA <= NetMath.MTU_SEGURO,
		"el tope por paquete se queda por debajo del MTU (fragmentar pierde el tick)")


## Un simulador que miente es peor que no tener ninguno: si reordena DENTRO de
## un canal, rompe una garantia del transporte y manda al equipo a cazar
## durante dias un bug del juego que no existe.
func _test_lag_ordena_por_canal_y_no_adelanta() -> void:
	var lag := NetLag.new()
	lag.sembrar(4247)
	lag.configurar(120.0, 40.0, 0.0)
	_check(lag.activo(), "con demora configurada, el simulador esta activo")

	var llegadas: Array[int] = []
	var t: float = 0.0
	# Se encolan los 50 en el mismo instante y se drena avanzando el reloj: asi
	# la comprobacion "nada llega antes de tiempo" es sobre la demora MINIMA
	# posible (base menos jitter), no sobre cuanto tardo el bucle.
	var encolados: int = 0
	for i in 50:
		var n := i
		if lag.encolar(NetLag.Canal.ORDENADO, 0.0,
				func(v: int) -> void: llegadas.append(v), [n]):
			encolados += 1
	_check(encolados == 50, "los 50 mensajes se encolan", str(encolados))

	t = (120.0 - 40.0) * 0.001 - 0.001 # justo antes de la entrega mas temprana
	lag.drenar(t)
	_check(llegadas.is_empty(), "nada se entrega antes de que venza la demora",
		"%d entregados a los %.0f ms" % [llegadas.size(), t * 1000.0])

	for i in 200:
		t += 0.008
		lag.drenar(t)
	_check(llegadas.size() == 50, "y al final llegan todos", str(llegadas.size()))
	var en_orden := true
	for i in llegadas.size():
		if llegadas[i] != i:
			en_orden = false
	_check(en_orden, "EN ORDEN dentro del canal, pese al jitter")

	# Sembrado: la misma semilla da exactamente la misma secuencia, o dos
	# maquinas de desarrollo no pueden reproducir el bug de la otra.
	var a := NetLag.new()
	var b := NetLag.new()
	a.sembrar(99)
	b.sembrar(99)
	a.configurar(100.0, 50.0, 0.3)
	b.configurar(100.0, 50.0, 0.3)
	var ca: int = 0
	var cb: int = 0
	for i in 200:
		if a.encolar(NetLag.Canal.ORDENADO, 0.0, func() -> void: pass, []):
			ca += 1
		if b.encolar(NetLag.Canal.ORDENADO, 0.0, func() -> void: pass, []):
			cb += 1
	_check(a.pendientes() == b.pendientes(),
		"misma semilla, misma secuencia de perdidas", "%d vs %d" % [a.pendientes(), b.pendientes()])
	_check(a.pendientes() < 200 and a.pendientes() > 100,
		"y la perdida del 30%% cae en tolerancia", "%d de 200 sobreviven" % a.pendientes())

	# Con el simulador apagado no se encola NADA: el camino de produccion
	# tiene que quedar intacto.
	var mudo := NetLag.new()
	_check(not mudo.activo(), "recien creado esta apagado")
	_check(not mudo.encolar(NetLag.Canal.FIABLE, 0.0, func() -> void: pass, []),
		"apagado, encolar() deja pasar de largo")
	_check(mudo.resumen().is_empty(), "y no anuncia nada en el overlay")
	_check(not lag.resumen().is_empty(), "encendido, el overlay lo DICE (regla 8)")


## El pez viaja como INDICE en la tabla de especies. Insertar una especie en
## medio (el archivo lo prohibe en un comentario, pero nada lo hace cumplir)
## haria que cada cliente aterrice un pez distinto al que el pescador peleo.
func _test_indice_de_especie_ida_y_vuelta() -> void:
	var n := FishSpecies.SPECIES.size()
	_check(n > 0, "la tabla de especies existe", "%d especies" % n)
	var todas_ok := true
	for i in n:
		var s: Dictionary = FishSpecies.SPECIES[i]
		if FishSpecies.SPECIES.find(s) != i:
			todas_ok = false
	_check(todas_ok, "cada especie se encuentra en SU indice (sin duplicados)")

	var pez := preload("res://game/fishing/fish.tscn").instantiate() as Fish
	add_child(pez)
	var elegida: Dictionary = FishSpecies.SPECIES[n - 1]
	pez.setup(FishSpecies.SPECIES[FishSpecies.SPECIES.find(elegida)])
	_check(is_equal_approx(pez.weight_kg, float(elegida[&"weight"]))
		and pez.value == int(elegida[&"value"]),
		"reconstruir por indice da el MISMO pez (peso y valor)")
	pez.queue_free()


## `_barco()` y `_jugador_local()` buscan por ruta LITERAL: si alguien renombra
## un nodo, la red entera enmudece sin un solo warning. Y en R1 es peor, porque
## un prop renombrado deja de replicarse EL SOLO mientras todo lo demas sigue.
func _test_rutas_y_censo_en_las_dos_escenas() -> void:
	for ruta: String in ["res://game/world/toybox.tscn", "res://game/world/tsunami.tscn"]:
		var escena := (load(ruta) as PackedScene).instantiate()
		add_child(escena)
		var nombre := ruta.get_file()

		_check(escena.get_node_or_null(^"FishingBoat") is RigidBody3D,
			"%s: FishingBoat esta donde Net lo busca" % nombre)
		_check(escena.get_node_or_null(^"Player") is Player,
			"%s: Player esta donde Net lo busca" % nombre)

		var censados: int = 0
		for cuerpo_ruta: NodePath in NetPorteo.CUERPOS_ESCENA:
			if escena.get_node_or_null(cuerpo_ruta) is RigidBody3D:
				censados += 1
		_check(censados == NetPorteo.CUERPOS_ESCENA.size(),
			"%s: los %d cuerpos autorados resuelven" % [nombre, NetPorteo.CUERPOS_ESCENA.size()],
			"%d encontrados" % censados)

		var barco := escena.get_node_or_null(^"FishingBoat") as Node3D
		var jugador := escena.get_node_or_null(^"Player") as Node3D
		# Los markers de mano y de cinturon los crea el Portador en su _ready,
		# que ya corrio al entrar la escena en el arbol: los 8 tienen que estar.
		var faltan := PackedStringArray()
		for i in NetPorteo.SOCKETS.size():
			var base: Node3D = jugador if NetPorteo.socket_es_del_jugador(i) else barco
			if base == null or base.get_node_or_null(NetPorteo.SOCKETS[i]) == null:
				faltan.append(String(NetPorteo.SOCKETS[i]))
		_check(faltan.is_empty(),
			"%s: los %d sockets de porteo resuelven" % [nombre, NetPorteo.SOCKETS.size()],
			"faltan: %s" % ", ".join(faltan))

		# Las estaciones, por INDICE. El indice viaja por el cable, asi que una
		# ruta que no resuelve no es un nodo que falta: es un jugador pidiendo
		# ocupar una bomba que en la otra maquina es otra cosa, o nada.
		var estaciones: int = 0
		for bomba_ruta: NodePath in BombaModel.BOMBAS:
			if barco != null and barco.get_node_or_null(bomba_ruta) is ManualBilgePump:
				estaciones += 1
		_check(estaciones == BombaModel.BOMBAS.size(),
			"%s: las %d estaciones de bombeo resuelven" % [nombre, BombaModel.BOMBAS.size()],
			"%d encontradas" % estaciones)

		escena.queue_free()


## Nada de maquinaria nativa de replicacion, y el motivo es el MECANISMO: la
## identidad de un `MultiplayerSynchronizer` es su ruta ABSOLUTA y se
## renegocia en cada salida/entrada del arbol, mientras que `Portable3D.tomar`
## REPARENTA el objeto al marker de la camara de quien lo coge. Un prop
## congelado para siempre tras un agarre con latencia, o un pez que se borra
## del mundo de tus cinco amigos al cogerlo.
## El `t0` explicito es lo que hace que las seis maquinas evaluen LA MISMA
## onda. Sin el, cada receptor la estampa con SU reloj —que va un retardo de
## interpolacion por detras— y la ola sale tarde: a 45 m/s, 0,12 s son 5,4 m
## de frente desplazado y una ETA distinta en cada pantalla (regla 8).
func _test_t0_del_host_da_la_misma_ola() -> void:
	var punto := Vector2(300.0, 0.0)
	var t_host := 1000.0
	var t_cliente := t_host - 0.12 # el cliente vive en el pasado exacto

	var host := OceanEvents.new()
	host.spawn(Vector2.ZERO, Vector2(1.0, 0.0), 18.0, 45.0, 90.0, t_host)
	var eta_host := host.time_until_crest(punto, t_host)

	# Con t0 EXPLICITO: el cliente ve la misma ola en su propio reloj.
	var bien := OceanEvents.new()
	bien.spawn(Vector2.ZERO, Vector2(1.0, 0.0), 18.0, 45.0, 90.0, t_host)
	var eta_bien := bien.time_until_crest(punto, t_cliente)
	_check(absf(eta_bien - (eta_host + 0.12)) < 1e-3,
		"con t0 del host, la ola llega cuando tiene que llegar",
		"%.4f s de desfase" % absf(eta_bien - (eta_host + 0.12)))

	# Sin el: el cliente lo estampa con SU reloj y la onda sale tarde.
	var mal := OceanEvents.new()
	mal.spawn(Vector2.ZERO, Vector2(1.0, 0.0), 18.0, 45.0, 90.0, t_cliente)
	var eta_mal := mal.time_until_crest(punto, t_cliente)
	_check(absf(eta_mal - eta_host) < 1e-3 and absf(eta_mal - eta_bien) > 0.1,
		"y sin t0 la misma ola sale 0,12 s corrida (5,4 m de frente)",
		"%.4f s" % absf(eta_mal - eta_bien))


## Quien se une a mitad de tsunami tiene que ver LA MISMA ola, no una nueva.
func _test_eventos_ida_y_vuelta() -> void:
	var host := OceanEvents.new()
	host.spawn(Vector2(-100.0, 20.0), Vector2(0.6, 0.8), 22.0, 51.0, 120.0, 777.0,
		11.0, 8.0, 0.5)
	var cliente := OceanEvents.new()
	cliente.unpack(host.pack())

	_check(cliente.has_active(), "el evento sobrevive el viaje")
	var p := Vector2(400.0, 90.0)
	var a := host.height_at(p, 800.0)
	var b := cliente.height_at(p, 800.0)
	_check(absf(a - b) < 1e-3, "y da la MISMA altura en el mismo instante",
		"%.5f vs %.5f" % [a, b])
	_check(absf(host.time_until_crest(p, 800.0)
		- cliente.time_until_crest(p, 800.0)) < 1e-3,
		"y la misma cuenta atras")

	# Y el vacio tambien viaja: si el host limpio, el cliente limpia.
	host.clear_all()
	cliente.unpack(host.pack())
	_check(not cliente.has_active(), "limpiar tambien se replica")


## Los slots son DOS. Desbordarlos era completamente mudo: un cliente con el
## hueco quemado veia mar plano mientras su barco, host-autoritativo, subia
## diecinueve metros.
func _test_desborde_de_slots_avisa() -> void:
	var e := OceanEvents.new()
	var ok: int = 0
	for i in OceanEvents.MAX_EVENTS:
		if e.spawn(Vector2.ZERO, Vector2(1.0, 0.0), 18.0, 45.0, 90.0, 0.0) >= 0:
			ok += 1
	_check(ok == OceanEvents.MAX_EVENTS,
		"caben exactamente %d eventos" % OceanEvents.MAX_EVENTS, str(ok))
	_check(e.spawn(Vector2.ZERO, Vector2(1.0, 0.0), 18.0, 45.0, 90.0, 0.0) == -1,
		"y el que sobra devuelve -1 en vez de perderse en silencio")


## EL bug mas caro de R1, y el que ningun test veia: un cuerpo que entra en una
## mano DEJA de moverse por snapshots — su sitio lo dice el socket del que
## cuelga. Sin limpiar los buffers, `_aplicar_cuerpos` le reescribia el
## transform cada tick y el objeto se quedaba SOLDADO a la cubierta mientras su
## dueño caminaba con la mano vacia. Y no hacia falta ninguna carrera de
## paquetes: al agarrar, el buffer ya tiene snapshots legitimos, el host deja
## de mandar mas (los no-SUELTO no entran en el lote) y `muestrear_buffer`
## CLAMPA al ultimo en vez de apagarse.
##
## Se puede probar en un proceso porque `_ejecutar_porteo` NO es un RPC: es un
## metodo normal. Los RPC son envoltorios de dos lineas justamente para que
## todo lo que decide algo quede de este lado.
func _test_agarrar_apaga_la_replicacion() -> void:
	var rol_previo: int = Net.rol
	var escena_previa := get_tree().current_scene
	var escena := (load("res://game/world/toybox.tscn") as PackedScene).instantiate()
	# Cuelga de la RAIZ, no de este nodo: `set_current_scene` exige que el
	# padre sea root. Y hay que apuntar `current_scene` a ella porque es donde
	# `Net` busca `FishingBoat` y `Player`, igual que en partida.
	#
	# `call_deferred` no es higiene: este test corre desde `_ready`, y ahi la
	# raiz todavia esta montando sus hijos — un `add_child` directo FALLA. Es
	# la misma trampa de Godot que dejo los markers del cinturon fuera del
	# arbol durante toda la fase B sin que nadie se enterara.
	get_tree().root.add_child.call_deferred(escena)
	await get_tree().process_frame
	get_tree().current_scene = escena
	await get_tree().physics_frame

	Net.rol = Net.Rol.CLIENTE
	Net._censar_escena()
	var id: int = 0 # el Farol, primero de NetPorteo.CUERPOS_ESCENA
	var farol := Net.cuerpo_de(id) as Portable3D
	_check(farol != null, "el farol esta censado en la escena de prueba")
	if farol == null:
		get_tree().current_scene = escena_previa
		Net.rol = rol_previo
		escena.queue_free()
		return

	# Como si el host hubiera estado mandando su posicion en cubierta.
	var cubierta := farol.global_transform
	Net._buffers[id] = ([{&"t": Ocean.sim_time, &"pos": cubierta.origin,
		&"rot": cubierta.basis.get_rotation_quaternion(), &"local": false}] as Array[Dictionary])
	Net._reposo[id] = {&"local": false, &"t": cubierta}

	# Y ahora alguien lo agarra.
	var yo: int = multiplayer.get_unique_id()
	Net._ejecutar_porteo(id, yo, NetPorteo.Verbo.EN_MANO,
		NetPorteo.socket_de_mano(farol.manos), Vector3.ZERO, cubierta)
	_check(farol.estado == Portable3D.Estado.EN_MANO,
		"el farol acaba en la mano", str(farol.estado))
	_check(not Net._buffers.has(id) and not Net._reposo.has(id),
		"agarrarlo APAGA su replicacion (buffers y reposo)")

	# La prueba de fuego: el tick del cliente no puede devolverlo a la cubierta.
	await get_tree().physics_frame
	var en_mano := farol.global_transform
	Net._aplicar_cuerpos()
	_check(farol.global_position.distance_to(en_mano.origin) < 0.001,
		"y el tick del cliente ya NO lo devuelve a la cubierta",
		"se movio %.3f m" % farol.global_position.distance_to(en_mano.origin))
	_check(farol.global_position.distance_to(cubierta.origin) > 0.01
		or cubierta.origin.distance_to(en_mano.origin) < 0.01,
		"cordura: el farol ya no esta donde estaba en cubierta")

	get_tree().current_scene = escena_previa
	Net.rol = rol_previo
	escena.queue_free()
	await get_tree().process_frame


## Los autoloads procesan ANTES que la escena, asi que `_update_sea()` del
## director seria la ULTIMA escritura de `Ocean.fury` de cada tick y le ganaria
## siempre al goteo del host. Un guard puesto solo en `Net` da test VERDE y
## falla en partida — por eso el guard vive tambien en el director.
func _test_director_mudo_en_cliente() -> void:
	var rol_previo: int = Net.rol
	Ocean.set_fury_immediate(4.0)

	var director := TsunamiDirector.new()
	add_child(director)
	director.start()
	_check(director._running, "el director arranca en solitario")

	# A partir de aca mandaria el host: se mide desde el CAMBIO de rol, porque
	# lo que el director escribio mientras era autoridad es legitimo.
	Net.rol = Net.Rol.CLIENTE
	Ocean.set_fury_red(6.5, 6.5) # lo que "acaba de llegar" del host
	Ocean.rain_scale = 0.5
	for i in 5:
		director._physics_process(0.016)
		await get_tree().physics_frame
	_check(not director._running,
		"en un cliente el director se calla SOLO, sin que nadie se lo diga")
	# Se mira el OBJETIVO y no la furia visible: `Ocean.fury` se mueve a 0,4 por
	# segundo, o sea 0,017 en los cinco ticks que dura esta ventana — cualquier
	# tolerancia razonable la pasaria un director que SI escribe. El setter de
	# `fury` toca `_fury_target`, y eso cambia al instante.
	_check(absf(Ocean.fury_objetivo() - 6.5) < 0.01,
		"y no pisa la furia que manda el host",
		"objetivo %.2f" % Ocean.fury_objetivo())
	# `rain_scale` es lo que corta la lluvia en la RETIRADA, y `_update_sea` la
	# pisa igual que a la furia. Nadie la miraba.
	_check(is_equal_approx(Ocean.rain_scale, 0.5),
		"ni la escala de lluvia", "rain_scale %.2f" % Ocean.rain_scale)

	# Y `ceder_al_host()` no puede borrar el tsunami del host: `stop()` llama a
	# `clear_events()`, asi que usarlo aqui haria que unirse a mitad de ola
	# borrara la ola.
	Ocean.spawn_tsunami(Vector3.ZERO, 90.0, 30.0)
	director.ceder_al_host()
	_check(Ocean.has_tsunami(),
		"ceder_al_host() NO borra los eventos (stop() si lo haria)")

	Ocean.clear_events()
	Ocean.set_fury_immediate(3.0)
	Net.rol = rol_previo
	director.queue_free()
	await get_tree().process_frame


## EL test que sostiene la decision de replicar los props en vez de dejar que
## cada maquina los simule "porque el oceano es determinista".
##
## Lo es — pero el cliente NO evalua el oceano en el mismo instante que el
## host: vive un retardo de interpolacion por detras (contrato 2 de RED.md), y
## eso es deliberado, porque su barco tambien vive ahi. Un prop simulado en
## local flotaria sobre un agua que NO es la del host, y la diferencia no es
## teorica: este test la mide.
##
## Nota de metodo, que costo un diagnostico: la version anterior de este test
## afirmaba que dos cuerpos identicos divergen por el desfase de `tick_divisor`
## y pasaba en verde. Al medirlo de verdad, los dos cuerpos resultaron
## calcular en LOS MISMOS ticks (`_tick` identico) y quedar a 0,0000 m: lo que
## el test media era que los dos faroles nacian superpuestos y el solver los
## separaba a empujones. Acreditaba una tesis correcta con un mecanismo falso.
func _test_fase_de_tick_divisor_diverge() -> void:
	var furia_previa := Ocean.fury
	var peor_por_furia: Dictionary = {}
	for furia: float in [3.0, 6.0]:
		Ocean.set_fury_immediate(furia)
		var peor: float = 0.0
		# Un barrido determinista: mismos puntos, mismos instantes, siempre.
		for i in 300:
			var p := Vector3(float(i) * 7.3 - 900.0, 0.0, float(i) * 3.1)
			var t := 500.0 + float(i) * 0.37
			peor = maxf(peor, absf(Ocean.get_height_at(p, t)
				- Ocean.get_height_at(p, t - Net.RETARDO_INTERP)))
		peor_por_furia[furia] = peor

	_check(float(peor_por_furia[3.0]) > 0.05,
		"con marejada, el mar del cliente ya difiere del host varios cm",
		"%.3f m" % float(peor_por_furia[3.0]))
	_check(float(peor_por_furia[6.0]) > 0.25,
		"y con mar gruesa, DECIMETROS: un prop simulado en local no coincidiria",
		"%.3f m" % float(peor_por_furia[6.0]))
	_check(float(peor_por_furia[6.0]) > float(peor_por_furia[3.0]),
		"y el error crece con la furia, que es cuando mas importa")

	Ocean.set_fury_immediate(furia_previa)
	await get_tree().process_frame


func _test_sin_maquinaria_nativa() -> void:
	for ruta: String in ["res://game/world/toybox.tscn", "res://game/world/tsunami.tscn",
			"res://game/player/player.tscn", "res://game/boat/fishing_boat.tscn"]:
		var escena := (load(ruta) as PackedScene).instantiate()
		add_child(escena)
		var sinc := escena.find_children("*", "MultiplayerSynchronizer", true, false)
		var spawn := escena.find_children("*", "MultiplayerSpawner", true, false)
		_check(sinc.is_empty() and spawn.is_empty(),
			"%s: sin maquinaria nativa de replicacion" % ruta.get_file(),
			"%d sincronizadores, %d spawners" % [sinc.size(), spawn.size()])
		escena.queue_free()
