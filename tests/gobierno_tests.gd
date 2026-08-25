extends Node

## Arnes del GOBIERNO: la matematica de la superficie sustentadora, el mando de
## dos etapas y el motor con su nafta.
##
##   <godot 4.7.2> --headless --path . tests/gobierno_tests.tscn
##
## Esto es la F1 del plan (docs/TIMON.md §7): aqui SOLO hay modelos puros, cero
## nodos y cero `Ocean`. Las pruebas navales de verdad —circulo de evolucion,
## zig-zag 20/20, parada— llegan en F2, cuando el gobierno este enchufado a un
## `RigidBody3D` y haya un barco al que hacerle dar vueltas.
##
## Lo que si se cierra hoy es [b]el signo[/b], que era lo unico que la
## investigacion dejaba a medias ("no lo afirmo de memoria — se comprueba con el
## circulo de evolucion"). No hace falta esperar a F2 para eso: el par de guiñada
## se calcula a mano con `r x F` y la banda a la que cae la proa se DERIVA de
## `omega x proa` en vez de afirmarse. Si F2 lo desmiente con el barco de verdad,
## hay exactamente una linea que invertir (`TimonModel.pala_rad_desde_mando`) y
## este arnes se dara la vuelta con ella.

const RUTA_TIMON := "res://game/boat/timon_model.gd"
const RUTA_MOTOR := "res://game/boat/motor_model.gd"
const RUTA_BAL_GOBIERNO := "res://game/boat/gobierno_balance.gd"
const RUTA_BAL_MOTOR := "res://game/boat/motor_nafta_balance.gd"
const RUTA_TRES_GOBIERNO := "res://resources/gobierno/gobierno.tres"
const RUTA_TRES_MOTOR := "res://resources/gobierno/motor_nafta.tres"

## Espejo del `center_of_mass` de `fishing_boat.tscn`. Lo unico que el signo del
## par necesita de verdad es que la pala quede a POPA de este punto, y eso se
## comprueba abajo en vez de darse por hecho; el cuerpo real entra en F2.
const CENTRO_MASAS := Vector3(0.0, -0.45, 0.0)

## Un paso de fisica, LEIDO del proyecto y no escrito a mano.
##
## ⚠️ Este arnes nacio con un `1.0 / 60.0` a pelo y el proyecto corre a 120
## (`physics_ticks_per_second` en project.godot): todas las velocidades medidas
## salian a MITAD de lo real y la conclusion sobre el arrastre del casco fue
## erronea por un factor de dos. Un numero de estos nunca se copia.
@onready var DT: float = 1.0 / _hz()

var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0


func _ready() -> void:
	print_rich("[b]--- Pruebas del gobierno: timon, mando y motor ---[/b]")
	_test_los_scripts_compilan()
	_test_la_placa_entra_en_perdida_sola()
	_test_el_angulo_efectivo_es_pala_menos_deriva()
	_test_la_autoridad_va_con_el_cuadrado()
	_test_la_proa_cae_a_la_banda_pedida()
	_test_el_broaching_es_una_resta()
	_test_la_rueda_es_un_rate_limit_de_dos_etapas()
	_test_la_zona_muerta_devuelve_el_control_fino()
	_test_el_telegrafo_tiene_seis_muescas()
	_test_el_motor_no_arranca_sin_llave_ni_sin_nafta()
	_test_la_rampa_del_motor()
	_test_la_nafta_se_gasta_y_avisa_antes_de_morir()
	_test_repostar_conserva_litros()
	_test_el_dial_de_la_nafta()
	# De aqui abajo ya hay un barco de verdad flotando y girando (F2).
	await _test_el_gobierno_esta_montado_en_el_barco()
	await _test_velocidad_punta()
	await _test_circulo_de_evolucion()
	await _test_sin_arrancada_el_timon_no_gira_el_barco()
	await _test_el_golpe_de_maquina()
	await _test_la_parada()
	await _test_zigzag_20_20()
	# F3: el puesto.
	_test_el_arbitro_del_puesto()
	_test_el_texto_del_puesto()
	_test_la_rueda_que_se_ve()
	_test_el_cabo_de_trinca()
	await _test_el_puesto_montado_en_el_barco()
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
#  Cableado
# =============================================================================

func _test_los_scripts_compilan() -> void:
	print_rich("[b]Los scripts cargan[/b]")
	for ruta in [RUTA_TIMON, RUTA_MOTOR, RUTA_BAL_GOBIERNO, RUTA_BAL_MOTOR]:
		_check(load(ruta) != null, "carga %s" % ruta)
	var gob: GobiernoBalance = load(RUTA_TRES_GOBIERNO) as GobiernoBalance
	_check(gob != null, "gobierno.tres es un GobiernoBalance")
	var mot: MotorNaftaBalance = load(RUTA_TRES_MOTOR) as MotorNaftaBalance
	_check(mot != null, "motor_nafta.tres es un MotorNaftaBalance")
	if gob == null or mot == null:
		return
	# El tope de pala tiene que caer POR DEBAJO de la perdida, o la pala solo
	# frenaria. No es una preferencia: `cl` se da la vuelta a los 45 grados.
	_check(gob.pala_max_deg < 45.0, "el tope de pala esta por debajo de la perdida",
			"pala_max_deg = %.1f" % gob.pala_max_deg)
	# La estabilidad direccional entera depende de esto (docs/TIMON.md §3).
	_check(gob.pos_plano_deriva.z > CENTRO_MASAS.z,
			"el plano de deriva esta a POPA del centro de masas")
	_check(gob.pos_pala.z > gob.pos_plano_deriva.z,
			"la pala esta mas a popa que el plano de deriva")


# =============================================================================
#  La superficie sustentadora
# =============================================================================

func _test_la_placa_entra_en_perdida_sola() -> void:
	print_rich("[b]La placa plana entra en perdida sola[/b]")
	_check(is_zero_approx(TimonModel.cl(0.0)), "sin angulo no hay sustentacion")
	_check(is_equal_approx(TimonModel.cl(deg_to_rad(45.0)), 1.0),
			"el pico de sustentacion esta en 45 grados")
	_check(is_zero_approx(TimonModel.cl(deg_to_rad(90.0))),
			"a 90 grados la pala ya no sustenta nada")
	# Esto es lo que hace EMERGER el tope de 35 de los barcos reales.
	_check(TimonModel.cl(deg_to_rad(50.0)) < TimonModel.cl(deg_to_rad(45.0)),
			"pasados 45 grados la sustentacion CAE")
	_check(TimonModel.cd(deg_to_rad(90.0)) > TimonModel.cd(deg_to_rad(45.0)),
			"la resistencia sigue creciendo hasta los 90")
	# Simetria: es lo que hace que funcione marcha atras sin un solo `if`.
	var a := deg_to_rad(20.0)
	_check(is_equal_approx(TimonModel.cl(-a), -TimonModel.cl(a)),
			"la sustentacion es impar: el seno lleva signo")
	_check(is_equal_approx(TimonModel.cd(-a), TimonModel.cd(a)),
			"la resistencia es par: frena igual a las dos bandas")


func _test_el_angulo_efectivo_es_pala_menos_deriva() -> void:
	print_rich("[b]El angulo que manda es el EFECTIVO[/b]")
	var pala := deg_to_rad(20.0)
	_check(is_zero_approx(TimonModel.angulo_ataque(pala, Vector3.ZERO)),
			"sin flujo no hay angulo de ataque que fingir")
	# Avante puro: la proa mira a -Z, asi que el flujo del casco es -z.
	var recto := TimonModel.angulo_ataque(pala, Vector3(0.0, 0.0, -6.0))
	_check(is_equal_approx(recto, pala),
			"con el flujo de proa, el angulo efectivo ES el de la pala")
	# Y aqui esta el auto-limite de la virada: en cuanto el barco derrapa hacia
	# la banda de la pala, la deriva se come angulo efectivo y el giro se asienta
	# solo. Sin esta resta habria que inventarse una amortiguacion.
	var derrapando := TimonModel.angulo_ataque(pala, Vector3(1.5, 0.0, -6.0))
	_check(derrapando < recto,
			"la deriva se COME angulo de pala: la virada se auto-limita",
			"recto %.3f vs derrapando %.3f" % [recto, derrapando])
	_check(derrapando > 0.0, "pero no se lo come entero de golpe")


func _test_la_autoridad_va_con_el_cuadrado() -> void:
	print_rich("[b]La autoridad va con el CUADRADO del flujo[/b]")
	var alfa := deg_to_rad(20.0)
	var lento := TimonModel.fuerza_superficie(Vector3(0.0, 0.0, -3.0), alfa, 1.1,
			Vector3.UP)
	var rapido := TimonModel.fuerza_superficie(Vector3(0.0, 0.0, -6.0), alfa, 1.1,
			Vector3.UP)
	var razon := rapido.length() / maxf(lento.length(), 0.0001)
	_check(is_equal_approx(snappedf(razon, 0.01), 4.0),
			"doblar el flujo da CUATRO veces la fuerza", "razon = %.3f" % razon)
	_check(TimonModel.fuerza_superficie(Vector3(0.0, 0.0, -0.01), alfa, 1.1,
			Vector3.UP) == Vector3.ZERO,
			"sin arrancada no hay timon")
	_check(TimonModel.fuerza_superficie(Vector3(0.0, 0.0, -6.0), alfa, 0.0,
			Vector3.UP) == Vector3.ZERO,
			"sin area no hay fuerza")
	# Flujo paralelo a la mecha: no hay plano donde sustentar. Es el caso raro que
	# reventaria al normalizar un vector nulo.
	_check(TimonModel.fuerza_superficie(Vector3(0.0, -6.0, 0.0), alfa, 1.1,
			Vector3.UP) == Vector3.ZERO,
			"flujo paralelo a la mecha: cero, y sin dividir por cero")


# =============================================================================
#  EL SIGNO — lo que la investigacion dejaba abierto
# =============================================================================

## Hacia donde cae la PROA con ese par de guiñada: +1 estribor, -1 babor.
##
## Se DERIVA en vez de afirmarse. Un par sobre +Y gira la proa (-Z) hacia -X, o
## sea a babor, pero eso es justo la clase de afirmacion de memoria que produce
## barcos que viran al reves: aqui sale de `omega x proa` y no de un comentario.
func _banda_de_proa(par: Vector3) -> float:
	var omega := Vector3(0.0, signf(par.y), 0.0)
	var proa := Vector3(0.0, 0.0, -1.0)
	return signf(omega.cross(proa).x)


## El par de guiñada que produce la pala con el mando en `mando`, navegando
## avante. Ejes de mundo == ejes del casco (el barco va derecho y sin rotar).
func _par_de_pala(mando: float, bal: GobiernoBalance) -> Vector3:
	var v_rel := Vector3(0.0, 0.0, -6.0) # 6 m/s avante
	var pala_rad := TimonModel.pala_rad_desde_mando(mando, bal.pala_max_deg)
	var alfa := TimonModel.angulo_ataque(pala_rad, v_rel)
	var f := TimonModel.fuerza_superficie(v_rel, alfa, bal.area_pala, Vector3.UP)
	# El brazo se mide desde el CENTRO DE MASAS (quinta regla de flotabilidad: el
	# dia que se midio desde el origen del nodo, el lastre del pesquero no hacia
	# nada y encima restaba).
	return (bal.pos_pala - CENTRO_MASAS).cross(f)


func _test_la_proa_cae_a_la_banda_pedida() -> void:
	print_rich("[b]El signo: la proa cae a la banda que pide el timonel[/b]")
	var bal: GobiernoBalance = load(RUTA_TRES_GOBIERNO) as GobiernoBalance
	if bal == null:
		_check(false, "no se pudo cargar gobierno.tres")
		return
	_check(bal.pos_pala.z > CENTRO_MASAS.z,
			"la pala esta a POPA del centro de masas (sin esto el par se invierte)")

	var estribor := _par_de_pala(1.0, bal)
	var babor := _par_de_pala(-1.0, bal)
	_check(_banda_de_proa(estribor) > 0.0,
			"timon a ESTRIBOR: la proa cae a estribor",
			"par.y = %.1f" % estribor.y)
	_check(_banda_de_proa(babor) < 0.0,
			"timon a BABOR: la proa cae a babor", "par.y = %.1f" % babor.y)
	_check(is_equal_approx(estribor.y, -babor.y),
			"las dos bandas son simetricas")
	_check(_par_de_pala(0.0, bal).is_zero_approx(),
			"a la via, la pala no gira el barco")

	# La pala VISIBLE tiene que mirar al mismo lado que la fuerza que produce, o
	# el feedback miente (regla 8) y encima nadie sabria cual de las dos esta mal.
	var pala_rad := TimonModel.pala_rad_desde_mando(1.0, bal.pala_max_deg)
	_check(is_equal_approx(TimonModel.yaw_visual(pala_rad), -pala_rad),
			"la rotacion visual es la hidrodinamica cambiada de signo")
	_check(absf(pala_rad) <= deg_to_rad(bal.pala_max_deg) + 0.0001,
			"el mando a tope no se pasa del tope de pala")
	# Y el mando no puede pedir mas alla del tope aunque llegue sucio del stick.
	_check(is_equal_approx(TimonModel.pala_rad_desde_mando(3.0, bal.pala_max_deg),
			TimonModel.pala_rad_desde_mando(1.0, bal.pala_max_deg)),
			"un mando fuera de rango se clampa, no se amplifica")


# =============================================================================
#  El broaching
# =============================================================================

func _test_el_broaching_es_una_resta() -> void:
	print_rich("[b]El broaching es una resta, no un sistema[/b]")
	var punto := Vector3(0.0, -1.0, 6.0)
	var v_casco := Vector3(0.0, 0.0, -6.0)
	var alfa := deg_to_rad(20.0)

	# Los dos casos de la investigacion, con la orbital co-direccional: mar de
	# proa (orbital floja) contra surf-riding (la ola te lleva a su velocidad).
	var proa := TimonModel.velocidad_relativa(v_casco, Vector3.ZERO, punto,
			CENTRO_MASAS, Vector3(0.0, 0.0, -1.5), 1.0)
	var popa := TimonModel.velocidad_relativa(v_casco, Vector3.ZERO, punto,
			CENTRO_MASAS, Vector3(0.0, 0.0, -5.2), 1.0)
	_check(is_equal_approx(snappedf(proa.length(), 0.01), 4.5),
			"mar de proa: 6 menos 1,5 son 4,5 m/s de flujo real")
	_check(is_equal_approx(snappedf(popa.length(), 0.01), 0.8),
			"surf-riding: 6 menos 5,2 son 0,8 m/s")

	var f_proa := TimonModel.fuerza_superficie(proa, alfa, 1.1, Vector3.UP)
	var f_popa := TimonModel.fuerza_superficie(popa, alfa, 1.1, Vector3.UP)
	var razon := f_proa.length() / maxf(f_popa.length(), 0.0001)
	_check(razon > 28.0 and razon < 36.0,
			"factor ~32 de autoridad entre las dos situaciones, sin una linea que lo decida",
			"razon = %.1f" % razon)

	# El caso limite: la ola te lleva EXACTAMENTE a su velocidad. El timon deja
	# de existir, y no hay ningun `if` que lo declare.
	var llevado := TimonModel.velocidad_relativa(v_casco, Vector3.ZERO, punto,
			CENTRO_MASAS, v_casco, 1.0)
	_check(TimonModel.fuerza_superficie(llevado, alfa, 1.1, Vector3.UP) == Vector3.ZERO,
			"a la velocidad de la ola, el timon NO EXISTE")

	# Y la otra mitad de la resta: la velocidad del PUNTO, no la del centro de
	# masas. Con el barco guiñando, la pala se mueve de lado aunque el casco
	# avance recto — de ahi sale que la virada se amortigue sola.
	var guiñando := TimonModel.velocidad_relativa(v_casco, Vector3(0.0, 0.5, 0.0),
			punto, CENTRO_MASAS, Vector3.ZERO, 1.0)
	_check(absf(guiñando.x) > 0.1,
			"con el barco guiñando, la pala ve flujo lateral",
			"vx = %.3f" % guiñando.x)

	# Y el factor_orbital es una perilla de verdad: a 0 el mar no roba nada.
	var sin_robo := TimonModel.velocidad_relativa(v_casco, Vector3.ZERO, punto,
			CENTRO_MASAS, Vector3(0.0, 0.0, -5.2), 0.0)
	_check(is_equal_approx(sin_robo.length(), 6.0),
			"con factor_orbital 0 el mar no roba gobierno")


# =============================================================================
#  El mando de dos etapas
# =============================================================================

func _test_la_rueda_es_un_rate_limit_de_dos_etapas() -> void:
	print_rich("[b]El mando: dos etapas, y ni una dependencia del framerate[/b]")
	var vuelta := 5.0
	# Tope a tope: el recorrido -1..1 tiene que tardar exactamente `vuelta`.
	var rueda := -1.0
	var t := 0.0
	while rueda < 1.0 and t < 30.0:
		rueda = TimonModel.avanzar_rueda(rueda, 1.0, DT, vuelta)
		t += DT
	_check(absf(t - vuelta) < DT * 1.5,
			"la rueda tarda %0.1f s de tope a tope" % vuelta, "tardo %.3f s" % t)

	# LA prueba que protege de que alguien mueva esto a `_process` o lo cambie
	# por un `lerp`: el mismo tiempo simulado tiene que dar el mismo angulo a
	# cualquier tick rate. Con lerp esto falla; con move_toward no puede.
	var a := 0.0
	for i in 60:
		a = TimonModel.avanzar_rueda(a, 1.0, 1.0 / 60.0, vuelta)
	var b := 0.0
	for i in 30:
		b = TimonModel.avanzar_rueda(b, 1.0, 1.0 / 30.0, vuelta)
	var c := 0.0
	for i in 240:
		c = TimonModel.avanzar_rueda(c, 1.0, 1.0 / 240.0, vuelta)
	_check(is_equal_approx(snappedf(a, 0.0001), snappedf(b, 0.0001))
			and is_equal_approx(snappedf(a, 0.0001), snappedf(c, 0.0001)),
			"un segundo de rueda es el mismo angulo a 30, 60 y 240 Hz",
			"30Hz %.5f / 60Hz %.5f / 240Hz %.5f" % [b, a, c])

	# Determinismo del mando (lo que F8 necesita para que host y cliente corran
	# el MISMO rate-limiter sobre el eje crudo y no divergir).
	var uno := 0.0
	var dos := 0.0
	for i in 100:
		uno = TimonModel.avanzar_rueda(uno, 0.7, DT, vuelta)
		dos = TimonModel.avanzar_rueda(dos, 0.7, DT, vuelta)
	_check(uno == dos, "el mismo eje crudo da el mismo angulo, bit a bit")

	# La segunda etapa: la pala persigue a la rueda y va POR DETRAS, que es lo
	# que se siente como maquina hidraulica.
	var r := 0.0
	var p := 0.0
	for i in 60:
		r = TimonModel.avanzar_rueda(r, 1.0, DT, vuelta)
		p = TimonModel.avanzar_pala(p, r, DT, 10.0, 35.0)
	_check(p < r, "tras un segundo la pala va por detras de la rueda",
			"rueda %.3f, pala %.3f" % [r, p])
	_check(p > 0.0, "pero la sigue de verdad, no se queda clavada")
	# Y acaba alcanzandola: el servo es un retardo, no un tope.
	for i in 600:
		r = TimonModel.avanzar_rueda(r, 1.0, DT, vuelta)
		p = TimonModel.avanzar_pala(p, r, DT, 10.0, 35.0)
	_check(is_equal_approx(p, 1.0) and is_equal_approx(r, 1.0),
			"con tiempo, la pala alcanza a la rueda")
	# La pala persigue a la rueda pero JAMAS la rebasa, venga de donde venga y por
	# grande que sea el paso: si se adelantara a la mano, el jugador dejaria de
	# ser la causa de lo que ve.
	var rebasa := false
	for i in range(-10, 11):
		for j in range(-10, 11):
			var desde := float(i) / 10.0
			var hacia := float(j) / 10.0
			# `dt` deliberadamente enorme: es el caso que se pasaria de largo si
			# alguien cambiara el `move_toward` por una integracion a pelo.
			var paso := TimonModel.avanzar_pala(desde, hacia, 10.0, 10.0, 35.0)
			if absf(paso - hacia) > 0.0001 and signf(paso - hacia) == signf(hacia - desde):
				rebasa = true
	_check(not rebasa, "la pala persigue a la rueda y jamas la rebasa")


func _test_la_zona_muerta_devuelve_el_control_fino() -> void:
	print_rich("[b]La zona muerta[/b]")
	_check(is_zero_approx(TimonModel.aplicar_zona_muerta(0.08, 0.12)),
			"el drift del stick no mueve la rueda")
	_check(is_equal_approx(TimonModel.aplicar_zona_muerta(1.0, 0.12), 1.0),
			"a tope sigue siendo a tope")
	_check(is_equal_approx(TimonModel.aplicar_zona_muerta(-1.0, 0.12), -1.0),
			"y a tope a babor tambien")
	var medio := TimonModel.aplicar_zona_muerta(0.56, 0.12)
	_check(is_equal_approx(snappedf(medio, 0.001), 0.5),
			"lo de fuera de la zona se reescala a [0..1]", "dio %.3f" % medio)
	_check(is_equal_approx(TimonModel.aplicar_zona_muerta(-0.56, 0.12), -medio),
			"simetrica a las dos bandas")
	# El porque del numero, hecho test: con el 0,5 que Godot trae por defecto,
	# medio recorrido de stick no produce NADA.
	_check(is_zero_approx(TimonModel.aplicar_zona_muerta(0.3, 0.5))
			and TimonModel.aplicar_zona_muerta(0.3, 0.12) > 0.0,
			"con la deadzone por defecto de Godot (0,5) se pierde el control fino")


# =============================================================================
#  El motor
# =============================================================================

func _test_el_telegrafo_tiene_seis_muescas() -> void:
	print_rich("[b]El telegrafo[/b]")
	var mot: MotorNaftaBalance = load(RUTA_TRES_MOTOR) as MotorNaftaBalance
	if mot == null:
		_check(false, "no se pudo cargar motor_nafta.tres")
		return
	var n := MotorModel.EMPUJE_MUESCA.size()
	_check(n == 6, "seis muescas: atras toda, atras, stop, poca, media, avante toda")
	_check(MotorModel.NOMBRE_MUESCA.size() == n, "cada muesca tiene su nombre")
	# EL fallo silencioso de este sistema: una tabla de consumos mas corta que las
	# muescas dejaria al motor bebiendo CERO en las muescas altas, sin un solo
	# error en consola y sin que nadie lo notara hasta que la nafta no significara
	# nada.
	_check(mot.consumos_l_min.size() == n,
			"la tabla de consumos cubre TODAS las muescas",
			"%d consumos para %d muescas" % [mot.consumos_l_min.size(), n])

	_check(is_zero_approx(MotorModel.EMPUJE_MUESCA[MotorModel.Muesca.STOP]),
			"stop es stop")
	var monotona := true
	for i in range(1, n):
		if MotorModel.EMPUJE_MUESCA[i] <= MotorModel.EMPUJE_MUESCA[i - 1]:
			monotona = false
	_check(monotona, "la palanca crece de atras toda a avante toda")
	_check(MotorModel.mover_muesca(0, -1) == 0
			and MotorModel.mover_muesca(n - 1, 1) == n - 1,
			"la palanca topa en los extremos en vez de dar la vuelta")
	_check(MotorModel.mover_muesca(MotorModel.Muesca.STOP, 1) == MotorModel.Muesca.POCA,
			"subir una muesca desde stop es poca")
	_check(MotorModel.nombre_muesca(MotorModel.Muesca.AVANTE_TODA) == "avante toda",
			"las muescas se llaman por su nombre")

	# Correr sale desproporcionadamente caro: es lo que hace que la quinta
	# decision del ciclo de marea (la ruta de vuelta) cueste algo.
	var media := MotorModel.consumo_l_s(MotorModel.Muesca.MEDIA, true, mot.consumos_l_min)
	var toda := MotorModel.consumo_l_s(MotorModel.Muesca.AVANTE_TODA, true, mot.consumos_l_min)
	_check(toda > media * 2.0, "avante toda bebe mas del doble que media",
			"media %.4f l/s, toda %.4f l/s" % [media, toda])
	_check(MotorModel.consumo_l_s(MotorModel.Muesca.STOP, true, mot.consumos_l_min) > 0.0,
			"al ralenti tambien bebe: apagar el motor ahorra algo")
	_check(is_zero_approx(MotorModel.consumo_l_s(MotorModel.Muesca.AVANTE_TODA, false,
			mot.consumos_l_min)), "el motor parado no bebe")
	_check(is_zero_approx(MotorModel.consumo_l_s(99, true, mot.consumos_l_min)),
			"una muesca imposible no revienta ni bebe")


func _test_el_motor_no_arranca_sin_llave_ni_sin_nafta() -> void:
	print_rich("[b]La llave[/b]")
	_check(MotorModel.arbitrar_arranque(true, 40.0, false) == MotorModel.MotivoArranque.OK,
			"con llave y con nafta, arranca")
	_check(MotorModel.arbitrar_arranque(false, 40.0, false)
			== MotorModel.MotivoArranque.SIN_LLAVE,
			"sin la llave puesta no hay motor")
	# Distinguir los dos fallos importa: son dos problemas con dos soluciones, y
	# el jugador tiene que saber a por cual correr (a bucear o a por el bidon).
	_check(MotorModel.arbitrar_arranque(true, 0.0, false)
			== MotorModel.MotivoArranque.SIN_NAFTA,
			"con el tanque seco gira y no prende")
	_check(MotorModel.arbitrar_arranque(true, 40.0, true)
			== MotorModel.MotivoArranque.YA_ARRANCADO,
			"dar al contacto con el motor en marcha no es un fallo del jugador")
	_check(MotorModel.texto_motivo(MotorModel.MotivoArranque.SIN_LLAVE) != ""
			and MotorModel.texto_motivo(MotorModel.MotivoArranque.SIN_NAFTA) != "",
			"los dos fallos se le dicen al jugador por su nombre")
	_check(MotorModel.texto_motivo(MotorModel.MotivoArranque.OK) == "",
			"lo que funciona no dice nada")


func _test_la_rampa_del_motor() -> void:
	print_rich("[b]La rampa: el barco no arranca como un coche[/b]")
	var rampa := 2.5
	var e := 0.0
	var t := 0.0
	while e < 1.0 and t < 30.0:
		e = MotorModel.avanzar_empuje(e, 1.0, DT, rampa)
		t += DT
	_check(absf(t - rampa) < DT * 1.5, "de stop a avante toda tarda %.1f s" % rampa,
			"tardo %.3f s" % t)

	var a := 0.0
	for i in 60:
		a = MotorModel.avanzar_empuje(a, 1.0, 1.0 / 60.0, rampa)
	var b := 0.0
	for i in 30:
		b = MotorModel.avanzar_empuje(b, 1.0, 1.0 / 30.0, rampa)
	_check(is_equal_approx(snappedf(a, 0.0001), snappedf(b, 0.0001)),
			"la rampa no depende del tick rate")

	# La palanca se mueve con el motor parado —hace su ruido y se ve desde
	# cubierta—, simplemente no pasa nada. Que el gesto exista es lo que hace
	# legible que falte la llave.
	for m in range(MotorModel.EMPUJE_MUESCA.size()):
		_check(is_zero_approx(MotorModel.empuje_objetivo(m, false)),
				"con el motor parado, la muesca %d no pide empuje" % m)

	# La estela es lo que permite maniobrar sin arrancada: el golpe de maquina.
	_check(MotorModel.estela(4.5, 1.0) > 0.0 and MotorModel.estela(4.5, -1.0) < 0.0,
			"la estela sigue el sentido del empuje")
	_check(is_zero_approx(MotorModel.estela(4.5, 0.0)),
			"sin empuje no hay estela: parado y sin motor, el timon no gira nada")


# =============================================================================
#  La nafta
# =============================================================================

func _test_la_nafta_se_gasta_y_avisa_antes_de_morir() -> void:
	print_rich("[b]La nafta: se gasta, y avisa dos veces[/b]")
	var mot: MotorNaftaBalance = load(RUTA_TRES_MOTOR) as MotorNaftaBalance
	if mot == null:
		_check(false, "no se pudo cargar motor_nafta.tres")
		return

	# Consumo determinista y sin cruzar el cero.
	var consumo := MotorModel.consumo_l_s(MotorModel.Muesca.MEDIA, true,
			mot.consumos_l_min)
	_check(is_equal_approx(MotorModel.paso_nafta(10.0, consumo, DT),
			consumo * DT), "el consumo de un tick es exactamente el del ritmo")
	_check(is_equal_approx(MotorModel.paso_nafta(0.001, 10.0, 1.0), 0.001),
			"nunca se gasta mas nafta de la que hay")
	_check(is_zero_approx(MotorModel.paso_nafta(0.0, consumo, DT)),
			"el tanque seco no puede quedar en negativo")

	# La aguja y la tos leen el MISMO numero, para que no puedan discrepar.
	_check(is_equal_approx(MotorModel.fraccion_tanque(mot.tanque_l * 0.5,
			mot.tanque_l), 0.5), "la aguja marca la mitad a medio tanque")
	_check(is_equal_approx(MotorModel.fraccion_tanque(999.0, mot.tanque_l), 1.0),
			"la aguja no se sale del dial")

	# La tos: el segundo aviso.
	_check(is_equal_approx(MotorModel.factor_tos(mot.tanque_l, mot.umbral_tos_l, 0.0),
			1.0), "con tanque de sobra el motor no tose")
	_check(is_equal_approx(MotorModel.factor_tos(mot.umbral_tos_l,
			mot.umbral_tos_l, 0.0), 1.0), "justo en el umbral todavia no tose")
	_check(is_zero_approx(MotorModel.factor_tos(0.0, mot.umbral_tos_l, 0.0)),
			"en seco no hay empuje")

	# Por debajo del umbral corta A RATOS: ni siempre (seria un lockout) ni nunca
	# (no seria un aviso).
	var cortes := 0
	var muestras := 200
	for i in muestras:
		var t := MotorModel.PERIODO_TOS * float(i) / float(muestras)
		if is_zero_approx(MotorModel.factor_tos(mot.umbral_tos_l * 0.5,
				mot.umbral_tos_l, t)):
			cortes += 1
	_check(cortes > 0, "con el tanque bajo, el motor TOSE")
	_check(cortes < muestras, "pero nunca se queda mudo del todo: no es un lockout")

	# Y tose PEOR segun se acaba: es lo que convierte el aviso en una cuenta atras.
	var cortes_al_fondo := 0
	for i in muestras:
		var t := MotorModel.PERIODO_TOS * float(i) / float(muestras)
		if is_zero_approx(MotorModel.factor_tos(mot.umbral_tos_l * 0.1,
				mot.umbral_tos_l, t)):
			cortes_al_fondo += 1
	_check(cortes_al_fondo > cortes, "cuanto menos queda, mas tose",
			"%d cortes a media reserva, %d en las ultimas gotas" % [cortes,
			cortes_al_fondo])

	# Funcion PURA del tiempo: las seis maquinas tienen que oir el mismo corte en
	# el mismo instante, o el motor sonaria roto en una y sano en otra.
	var t0 := 0.37
	_check(MotorModel.factor_tos(3.0, mot.umbral_tos_l, t0)
			== MotorModel.factor_tos(3.0, mot.umbral_tos_l,
			t0 + MotorModel.PERIODO_TOS),
			"la tos es periodica y determinista en el tiempo del mundo")


func _test_repostar_conserva_litros() -> void:
	print_rich("[b]Repostar: el bidon[/b]")
	var mot: MotorNaftaBalance = load(RUTA_TRES_MOTOR) as MotorNaftaBalance
	if mot == null:
		_check(false, "no se pudo cargar motor_nafta.tres")
		return

	var tanque := 5.0
	var bidon := mot.bidon_l
	var total_antes := tanque + bidon
	var pasos := 0
	while bidon > 0.0 and pasos < 100000:
		var pasa := MotorModel.paso_repostaje(tanque, mot.tanque_l, bidon,
				mot.ritmo_repostaje_l_s, DT)
		if pasa <= 0.0:
			break
		tanque += pasa
		bidon -= pasa
		pasos += 1
	_check(is_equal_approx(snappedf(tanque + bidon, 0.0001),
			snappedf(total_antes, 0.0001)),
			"no se fabrica ni se pierde nafta al trasvasar",
			"antes %.4f, despues %.4f" % [total_antes, tanque + bidon])
	_check(is_zero_approx(bidon), "el bidon se vacia entero si cabe")
	_check(tanque <= mot.tanque_l + 0.0001, "el tanque no rebosa")
	# El ritmo se respeta: volcar el bidon es un gesto que dura, no un boton.
	var esperado := mot.bidon_l / mot.ritmo_repostaje_l_s
	_check(absf(float(pasos) * DT - esperado) < DT * 2.0,
			"volcar el bidon lleva %.1f s" % esperado,
			"llevo %.2f s" % (float(pasos) * DT))
	# Y con el tanque lleno no entra nada (ni desaparece del bidon).
	_check(is_zero_approx(MotorModel.paso_repostaje(mot.tanque_l, mot.tanque_l,
			10.0, mot.ritmo_repostaje_l_s, DT)),
			"con el tanque lleno, el bidon no se vacia en el suelo")


func _test_el_dial_de_la_nafta() -> void:
	print_rich("[b]El dial: holgado, pero no infinito[/b]")
	var mot: MotorNaftaBalance = load(RUTA_TRES_MOTOR) as MotorNaftaBalance
	if mot == null:
		_check(false, "no se pudo cargar motor_nafta.tres")
		return

	# La salida tipo de DISENO §1 (sesion de 25-35 min): unos 15 minutos
	# navegando a media y otros 20 al ralenti mientras se pesca.
	var navegando := MotorModel.consumo_l_s(MotorModel.Muesca.MEDIA, true,
			mot.consumos_l_min) * 15.0 * 60.0
	var pescando := MotorModel.consumo_l_s(MotorModel.Muesca.STOP, true,
			mot.consumos_l_min) * 20.0 * 60.0
	var fraccion := (navegando + pescando) / mot.tanque_l
	# Este es EL dial: por debajo del 30 % la nafta no existiria y volveria a ser
	# el numero de la factura; por encima del 60 % seria la vigilancia constante
	# que DISENO §3 descarto citando a DREDGE.
	_check(fraccion > 0.30 and fraccion < 0.60,
			"una salida normal gasta entre el 30 % y el 60 % del tanque",
			"gasta el %.0f %% (%.1f l de %.0f)" % [fraccion * 100.0,
			navegando + pescando, mot.tanque_l])

	# Y el fallo tiene que ser ELEGIDO: quien va siempre a avante toda se queda
	# seco dentro de la misma salida.
	var abusando := MotorModel.consumo_l_s(MotorModel.Muesca.AVANTE_TODA, true,
			mot.consumos_l_min) * 15.0 * 60.0
	_check(abusando >= mot.tanque_l * 0.95,
			"quince minutos a avante toda vacian el tanque",
			"gastaria %.1f l de %.0f" % [abusando, mot.tanque_l])

	# Un bidon tiene que devolver la salida, no regalar un tanque nuevo.
	var r := mot.bidon_l / mot.tanque_l
	_check(r > 0.35 and r < 0.75, "un bidon es medio tanque largo",
			"es el %.0f %%" % (r * 100.0))


# =============================================================================
#  F2: el barco de verdad — las pruebas navales
# =============================================================================
#
# La arquitectura naval lleva un siglo midiendo maniobrabilidad con pruebas
# estandarizadas, que son literalmente tests de feel REPETIBLES. El valor no esta
# en cumplir los criterios de la IMO —este barco es de mentira y puede
# saltarselos— sino en que el dia que alguien suba la masa un 10 % para arreglar
# otra cosa, los numeros avisen antes de que un tester diga que el barco "se
# siente raro".
#
# ⚠️ Los umbrales de aqui se fijaron con la inercia AUTOMATICA del cuerpo, porque
# la anisotropia de guiñada (F2b: forzar `inertia.y` y bajar `angular_drag`)
# espera a que aterrice la sesion del hundimiento. Cuando eso entre, el circulo
# cambia de tamaño y estos numeros hay que volver a medirlos: es el paso que el
# plan ya avisa que obliga a recalibrar.

const RUTA_BARCO := "res://game/boat/fishing_boat.tscn"

## Eslora del pesquero: `RailBow` en z = -6.2 y `RailStern` en z = +6.4.
const ESLORA := 12.6

## Ventana sobre la que se promedian velocidad y giro. Una sola constante para
## esperar y para dividir: si son dos numeros, un dia dejan de ser el mismo.
const MEDICION_S := 2.0


func _montar_barco() -> FloatingBody3D:
	# Mar planchado: lo que se mide aqui es el barco, no el oleaje.
	Ocean.clear_events()
	Ocean.set_fury_immediate(0.0)
	var barco: FloatingBody3D = (load(RUTA_BARCO) as PackedScene).instantiate()
	add_child(barco)
	return barco


## Ticks de fisica por segundo del proyecto.
func _hz() -> float:
	return float(maxi(Engine.physics_ticks_per_second, 1))


## Espera SEGUNDOS de simulacion, no frames.
##
## La firma es en segundos a proposito: contar frames y luego dividir por un 60
## escrito a mano fue exactamente el bug que hizo medir todas las velocidades a
## la mitad. Si el tiempo entra y sale en segundos, no hay conversion que
## equivocar.
## Pone a alguien en la rueda, que si no el cabo de trinca la centra sola.
##
## Sin esto, escribir `gobierno.mando` desde el arnes no sirve de nada: el puesto
## lo pisa cada tick. Y esta bien que lo pise — un barco sin timonel no se queda
## con el timon metido —, asi que lo que hay que hacer es tener timonel.
func _al_timon(barco: Node) -> RuedaTimon:
	var p := barco.get_node_or_null(
			^"UpgradeSockets/Helm/RuedaTimon") as RuedaTimon
	if p != null:
		p.ocupar_estacion(1, null)
	return p


func _esperar(segundos: float) -> void:
	var frames := int(round(segundos * _hz()))
	for i in frames:
		await get_tree().physics_frame


## Deja al barco navegando a `v_ms` sin simular la aceleracion entera.
##
## Escribir `linear_velocity` NO es un teleport —no se toca el transform—, asi
## que no fabrica ningun slam falso ni ensucia el historial del agua.
func _navegando(v_ms: float) -> Array:
	var barco := _montar_barco()
	var gob := barco.get_node_or_null(^"Gobierno") as Gobierno
	_al_timon(barco)
	if gob != null:
		gob.arrancar()
		gob.muesca = MotorModel.Muesca.AVANTE_TODA
	barco.linear_velocity = -barco.global_basis.z * v_ms
	await _esperar(3.0) # que la maquina y el casco se asienten
	return [barco, gob]


## Rumbo en radianes, creciendo hacia ESTRIBOR. La proa es -Z.
func _rumbo(barco: Node3D) -> float:
	var proa := -barco.global_basis.z
	return atan2(proa.x, -proa.z)


## Lo que giro el rumbo entre dos muestras, sin el salto de +-PI. Solo vale para
## saltos MENORES de media vuelta: para lo demas, [method _rumbo_acumulado].
func _giro(desde: float, hasta: float) -> float:
	return wrapf(hasta - desde, -PI, PI)


## Cuanto gira el rumbo durante `segundos`, sumando tick a tick.
##
## ⚠️ Comparar solo el principio con el final NO vale, y costo un falso fallo:
## `wrapf` no distingue una vuelta de -167 grados de otra de +193, y el barco
## parado con maquina y timon a tope da mas de media vuelta en diez segundos —
## asi que el golpe de maquina parecia girar a la banda contraria cuando lo que
## pasaba es que se habia pasado de largo. Acumulando no hay ambiguedad.
func _rumbo_acumulado(barco: Node3D, segundos: float) -> float:
	var frames := int(round(segundos * _hz()))
	var total := 0.0
	var previo := _rumbo(barco)
	for i in frames:
		await get_tree().physics_frame
		var ahora := _rumbo(barco)
		total += _giro(previo, ahora)
		previo = ahora
	return total


func _desmontar(barco: Node) -> void:
	barco.queue_free()
	await get_tree().physics_frame


func _test_el_gobierno_esta_montado_en_el_barco() -> void:
	print_rich("[b]El gobierno esta en la escena del barco[/b]")
	var barco := _montar_barco()
	var gob := barco.get_node_or_null(^"Gobierno") as Gobierno
	_check(gob != null, "el pesquero trae su nodo Gobierno")
	if gob == null:
		await _desmontar(barco)
		return
	_check(gob.balance != null and gob.motor != null,
			"y trae los dos balances enchufados")
	_check(gob.litros > 0.0, "se zarpa con el tanque lleno (el interim de §0)",
			"%.1f l" % gob.litros)
	_check(not gob.arrancado, "pero con el motor parado: arrancarlo es un gesto")
	gob.llave_puesta = false
	_check(gob.arrancar() == MotorModel.MotivoArranque.SIN_LLAVE,
			"sin la llave no arranca, tambien montado en el barco")
	gob.llave_puesta = true
	_check(gob.arrancar() == MotorModel.MotivoArranque.OK, "con la llave, si")
	await _desmontar(barco)


func _test_velocidad_punta() -> void:
	print_rich("[b]Velocidad punta[/b]")
	var m := await _navegando(3.0)
	var barco: FloatingBody3D = m[0]
	if m[1] == null:
		_check(false, "sin gobierno no hay velocidad")
		await _desmontar(barco)
		return
	# Recto y a tope hasta que se asiente contra el arrastre del casco. Este es
	# el instrumento con el que se calibra `empuje_max`: no hay una velocidad
	# objetivo escrita en ningun sitio, sale de este equilibrio.
	await _esperar(12.0)
	var p0 := barco.global_position
	await _esperar(MEDICION_S)
	var v := (barco.global_position - p0).length() / MEDICION_S
	print("        [velocidad punta %.2f m/s = %.1f nudos]" % [v, v * 1.944])
	# ~3,9 m/s = 7,7 nudos con los 60 000 N del balance. Es el instrumento con el
	# que se calibro `empuje_max`, y el que avisara si F2b (bajar el arrastre) lo
	# dispara: entonces hay que BAJAR el empuje, no dejar el pesquero volando.
	_check(v > 3.0 and v < 6.0, "el pesquero navega a velocidad de pesquero",
			"%.2f m/s = %.1f nudos" % [v, v * 1.944])
	await _desmontar(barco)


func _test_circulo_de_evolucion() -> void:
	print_rich("[b]Circulo de evolucion: el arbitro del signo[/b]")
	var m := await _navegando(5.0)
	var barco: FloatingBody3D = m[0]
	var gob: Gobierno = m[1]
	if gob == null:
		_check(false, "sin gobierno no hay circulo")
		await _desmontar(barco)
		return

	gob.mando = 1.0 # todo a estribor
	await _esperar(12.0) # que la virada se asiente

	# En regimen se mide y se DESPEJA el diametro (D = 2V/omega) en vez de
	# simular media vuelta entera: sale el mismo numero en una fraccion del
	# tiempo de arnes.
	var p0 := barco.global_position
	var giro := await _rumbo_acumulado(barco, MEDICION_S)
	var v := (barco.global_position - p0).length() / MEDICION_S
	var omega := absf(giro) / MEDICION_S
	var diametro := 2.0 * v / maxf(omega, 0.00001)

	# LO QUE ESTE TEST EXISTE PARA DECIDIR: la investigacion dejo el signo de la
	# sustentacion sin cerrar ("se comprueba con el circulo, no razonando"). Las
	# cuentas de F1 ya decian que cae a estribor; esto lo confirma con el casco.
	_check(giro > 0.0, "timon a ESTRIBOR: el barco cae a estribor",
			"giro %.2f grados en %.0f s" % [rad_to_deg(giro), MEDICION_S])
	_check(v > 0.5, "y sigue navegando mientras vira", "%.2f m/s" % v)
	print("        [diametro tactico ~%.0f m = %.1f esloras, a %.2f m/s]" % [
			diametro, diametro / ESLORA, v])
	# ⚠️ La banda es ANCHA a proposito y no es el criterio final. El objetivo son
	# 3-5 esloras, pero eso se fija despues de F2b: forzar `inertia.y` y bajar
	# `angular_drag` cambia el circulo entero, y calibrar `area_pala` contra la
	# inercia automatica seria calibrarlo dos veces. Hoy esto solo caza los dos
	# fallos gordos —que no vire, o que trompee sobre si mismo— y deja el numero
	# impreso para poder comparar cuando F2b entre.
	_check(diametro > 0.4 * ESLORA and diametro < 15.0 * ESLORA,
			"el circulo es finito y de tamaño de barco (objetivo F2b: 3-5 esloras)",
			"%.1f esloras" % (diametro / ESLORA))

	# La trampa dura, comprobada por su CONSECUENCIA: si el gobierno escribiera
	# en `constant_force` borraria el empuje de la flotabilidad y el barco se
	# hundiria sin un solo error en consola. Tras 17 s empujando fuerte, flota.
	var calado := Ocean.get_submersion(barco.global_position)
	_check(absf(calado) < 1.5,
			"el barco sigue a flote: el gobierno no piso la flotabilidad",
			"origen a %.2f m de la superficie" % calado)

	# Y a la otra banda, para que no sea casualidad.
	gob.mando = -1.0
	await _esperar(12.0)
	var vuelta_babor := await _rumbo_acumulado(barco, MEDICION_S)
	_check(vuelta_babor < 0.0, "timon a BABOR: cae a babor",
			"giro %.1f grados" % rad_to_deg(vuelta_babor))
	await _desmontar(barco)


func _test_sin_arrancada_el_timon_no_gira_el_barco() -> void:
	print_rich("[b]Sin arrancada no hay timon[/b]")
	var barco := _montar_barco()
	var gob := barco.get_node_or_null(^"Gobierno") as Gobierno
	_al_timon(barco)
	await _esperar(2.0)
	if gob == null:
		_check(false, "sin gobierno no hay nada que medir")
		await _desmontar(barco)
		return
	# Motor parado y timon a tope: la pala no tiene flujo que morder.
	gob.mando = 1.0
	var giro := absf(await _rumbo_acumulado(barco, 10.0))
	# Si esto gira, alguien metio un torque directo por el camino en vez de una
	# fuerza sobre una superficie.
	_check(rad_to_deg(giro) < 8.0,
			"parado y sin motor, la pala a tope NO gira el barco",
			"giro %.1f grados en 10 s" % rad_to_deg(giro))
	await _desmontar(barco)


func _test_el_golpe_de_maquina() -> void:
	print_rich("[b]El golpe de maquina[/b]")
	var barco := _montar_barco()
	var gob := barco.get_node_or_null(^"Gobierno") as Gobierno
	_al_timon(barco)
	await _esperar(2.0)
	if gob == null:
		_check(false, "sin gobierno no hay golpe de maquina")
		await _desmontar(barco)
		return
	# Parado, pero con la maquina: la estela inyecta flujo en la pala aunque el
	# casco no se haya movido. Es la respuesta al broaching, y la razon de que el
	# motor exista mas alla de ir rapido.
	gob.arrancar()
	gob.muesca = MotorModel.Muesca.AVANTE_TODA
	gob.mando = 1.0
	var giro := await _rumbo_acumulado(barco, 10.0)
	_check(rad_to_deg(giro) > 10.0,
			"parado, pala a tope + maquina: SI gira",
			"giro %.1f grados en 10 s" % rad_to_deg(giro))
	await _desmontar(barco)


func _test_la_parada() -> void:
	print_rich("[b]La parada[/b]")
	var m := await _navegando(5.0)
	var barco: FloatingBody3D = m[0]
	var gob: Gobierno = m[1]
	if gob == null:
		_check(false, "sin gobierno no hay parada")
		await _desmontar(barco)
		return
	gob.muesca = MotorModel.Muesca.STOP
	var p0 := barco.global_position
	var tope := int(30.0 * _hz())
	var frames := 0
	while frames < tope:
		await get_tree().physics_frame
		frames += 1
		if Vector2(barco.linear_velocity.x, barco.linear_velocity.z).length() < 0.5:
			break
	var recorrido := (barco.global_position - p0).length()
	print("        [para en %.1f s y %.0f m = %.1f esloras]" % [
			float(frames) / _hz(), recorrido, recorrido / ESLORA])
	# Define si el combate contra el mar es de posicion o de reflejos: un barco
	# que frena en una eslora se maniobra como un coche.
	_check(frames < tope, "el barco acaba parandose al quitar maquina")
	# ⚠️ DEUDA MEDIDA, no un umbral flojo: hoy para en ~0,2 esloras, o sea que
	# frena como un coche. La causa es la misma que obligo a subir `empuje_max`:
	# el arrastre de la flotabilidad es isotropo y le sobra al avance. El feel
	# que se busca son 2-4 esloras, y llega bajando `drag_coefficient` en F2b,
	# cuando el plano de deriva ya de la resistencia lateral que hoy da ese
	# arrastre. Mientras tanto se comprueba lo unico que hoy es cierto —que no
	# frena EN SECO— y se imprime el numero para que la deuda se vea en cada
	# corrida en vez de dormir en un documento.
	_check(recorrido > 1.0, "no frena en seco (objetivo F2b: 2-4 esloras)",
			"%.1f m = %.2f esloras" % [recorrido, recorrido / ESLORA])
	await _desmontar(barco)


func _test_zigzag_20_20() -> void:
	print_rich("[b]Zig-zag 20/20: lo que cuesta mantener el rumbo[/b]")
	var m := await _navegando(5.0)
	var barco: FloatingBody3D = m[0]
	var gob: Gobierno = m[1]
	if gob == null:
		_check(false, "sin gobierno no hay zig-zag")
		await _desmontar(barco)
		return
	var r0 := _rumbo(barco)

	# Se mete timon a estribor hasta que el rumbo cambia 20 grados...
	gob.mando = 20.0 / gob.balance.pala_max_deg
	var tope := int(30.0 * _hz())
	var frames := 0
	while frames < tope and rad_to_deg(_giro(r0, _rumbo(barco))) < 20.0:
		await get_tree().physics_frame
		frames += 1
	_check(rad_to_deg(_giro(r0, _rumbo(barco))) >= 20.0,
			"el barco alcanza los 20 grados de cambio de rumbo",
			"en %.1f s" % (float(frames) / _hz()))

	# ...y ahi se invierte el timon. Lo que el barco sigue girando ANTES de
	# obedecer es el overshoot: la medida de cuanto trabajo va a tener el
	# timonel manteniendo el rumbo.
	gob.mando = -20.0 / gob.balance.pala_max_deg
	var pico := 0.0
	for i in int(15.0 * _hz()):
		await get_tree().physics_frame
		var g := rad_to_deg(_giro(r0, _rumbo(barco)))
		pico = maxf(pico, g)
		if g < pico - 2.0:
			break
	var overshoot := pico - 20.0
	print("        [overshoot del primer tramo: %.1f grados]" % overshoot)
	_check(overshoot > 0.0, "hay overshoot: el barco no obedece al instante")
	_check(overshoot < 90.0, "pero el timonel puede con el",
			"%.1f grados" % overshoot)
	await _desmontar(barco)


# =============================================================================
#  F3: el puesto — quien agarra la rueda, que dice y que se ve
# =============================================================================

func _test_el_arbitro_del_puesto() -> void:
	print_rich("[b]Quien puede llevar el timon[/b]")
	var M := PuestoTimonModel
	_check(M.arbitrar(M.Verbo.OCUPAR, M.NADIE, 7, 0) == M.Motivo.OK,
			"con las manos libres, la rueda se agarra")
	# La rueda ES el agarre: de aqui sale que el timonel no pueda pescar ni
	# llevar el colador, sin un solo candado de rol.
	_check(M.arbitrar(M.Verbo.OCUPAR, M.NADIE, 7, 1) == M.Motivo.MANOS_LLENAS,
			"con una mano ocupada ya no: son las dos manos")
	_check(M.arbitrar(M.Verbo.OCUPAR, 3, 7, 0) == M.Motivo.OCUPADO,
			"si la lleva otro, no se le quita")
	_check(M.arbitrar(M.Verbo.OCUPAR, 7, 7, 0) == M.Motivo.OK,
			"volver a agarrar la tuya es idempotente, no un error")
	_check(M.arbitrar(M.Verbo.LIBERAR, M.NADIE, 7, 0) == M.Motivo.OK,
			"soltar lo que ya esta suelto tampoco")
	_check(M.arbitrar(M.Verbo.LIBERAR, 3, 7, 2) == M.Motivo.NO_ES_TUYO,
			"pero no se suelta la de otro")
	_check(M.texto_motivo(M.Motivo.OCUPADO) != ""
			and M.texto_motivo(M.Motivo.MANOS_LLENAS) != "",
			"los rechazos se dicen por su nombre")
	_check(M.texto_motivo(M.Motivo.OK) == "", "y lo que funciona no dice nada")


func _test_el_texto_del_puesto() -> void:
	print_rich("[b]Lo que dice el puesto[/b]")
	var M := PuestoTimonModel
	# El prompt tiene que decir el ESTADO, no solo la tecla: sin llave se manda a
	# alguien a buscarla y sin nafta se manda a por el bidon, y son dos
	# problemas distintos con dos soluciones distintas.
	var sin_llave := M.texto_puesto(false, false, MotorModel.Muesca.STOP, false)
	_check(sin_llave.contains("llave"), "sin la llave, lo dice", sin_llave)
	var seco := M.texto_puesto(false, true, MotorModel.Muesca.STOP, true)
	_check(seco.contains("seco"), "con el tanque seco, tambien", seco)
	var listo := M.texto_puesto(false, true, MotorModel.Muesca.STOP, false)
	_check(listo.contains("Q"), "con llave y nafta, ofrece el contacto", listo)
	var andando := M.texto_puesto(true, true, MotorModel.Muesca.AVANTE_TODA, false)
	_check(andando.to_lower().contains("avante toda"),
			"en marcha, canta la muesca del telegrafo", andando)
	for t in [sin_llave, seco, listo, andando]:
		_check((t as String).contains("E"), "y siempre dice como salir")


func _test_la_rueda_que_se_ve() -> void:
	print_rich("[b]La rueda que se ve[/b]")
	var M := PuestoTimonModel
	_check(is_zero_approx(M.angulo_rueda(0.0)), "a la via, el aro esta en su sitio")
	# Tres vueltas de tope a tope es lo que hace CONTABLE el angulo de pala: un
	# aro que girara 35 grados como un volante no dejaria contar cabillas, y
	# contar es como el timonel sabe donde esta la via sin HUD.
	var tope := M.angulo_rueda(1.0)
	_check(absf(tope) > TAU, "de la via al tope hay mas de una vuelta entera",
			"%.2f vueltas" % (absf(tope) / TAU))
	_check(is_equal_approx(M.angulo_rueda(-1.0), -tope),
			"y las dos bandas giran lo mismo")
	_check(is_equal_approx(M.angulo_rueda(3.0), tope),
			"un mando fuera de rango no da vueltas de mas")
	_check(M.a_la_via(0.0) and not M.a_la_via(0.5),
			"la via es la posicion de la RUEDA, no que la marca este arriba")


func _test_el_cabo_de_trinca() -> void:
	print_rich("[b]El cabo de trinca[/b]")
	var M := PuestoTimonModel
	_check(is_equal_approx(M.segundos_trinca(2.0, 12.0, 6.0, 6.0), 12.0),
			"con mar llana el cabo aguanta lo que dice DISENO")
	# Y con mar hecha aguanta la mitad: la ventana para ir a ayudar se cierra
	# justo cuando mas falta hace ayudar. Ahi esta la tension del puesto.
	_check(is_equal_approx(M.segundos_trinca(7.0, 12.0, 6.0, 6.0), 6.0),
			"con Hs por encima del umbral, la mitad")
	_check(is_equal_approx(M.segundos_trinca(6.0, 12.0, 6.0, 6.0), 6.0),
			"justo en el umbral ya cuenta como temporal")


func _test_el_puesto_montado_en_el_barco() -> void:
	print_rich("[b]El puesto, montado en el pesquero[/b]")
	var barco := _montar_barco()
	await _esperar(1.0)
	var puesto := barco.get_node_or_null(
			^"UpgradeSockets/Helm/RuedaTimon") as RuedaTimon
	_check(puesto != null, "el pesquero trae su puesto de timon en el socket Helm")
	if puesto == null:
		await _desmontar(barco)
		return
	var gob := puesto.gobierno()
	_check(gob != null, "y el puesto encontro el gobierno al que manda")
	_check(puesto.estacion_libre(), "nace libre: llevar el timon es una decision")

	# El contacto: sin llave no arranca, con llave si. Es la llave que ya existe
	# como objeto porteable y que SE HUNDE (DISENO §2).
	_check(puesto.dar_al_contacto(false) == MotorModel.MotivoArranque.SIN_LLAVE,
			"sin la llave encima, el contacto no arranca")
	_check(not gob.arrancado, "y el motor sigue parado")
	_check(puesto.dar_al_contacto(true) == MotorModel.MotivoArranque.OK,
			"con la llave, arranca")
	_check(gob.arrancado, "y ahora si esta en marcha")
	# Y la misma tecla lo para: salir tiene que ser siempre el mismo gesto.
	puesto.dar_al_contacto(true)
	_check(not gob.arrancado, "la misma tecla lo para")

	# El telegrafo, muesca a muesca.
	gob.muesca = MotorModel.Muesca.STOP
	puesto.mover_telegrafo(1)
	_check(gob.muesca == MotorModel.Muesca.POCA, "el telegrafo sube una muesca")
	puesto.mover_telegrafo(-1)
	puesto.mover_telegrafo(-1)
	_check(gob.muesca == MotorModel.Muesca.ATRAS, "y baja hasta atras")

	# El cabo de trinca: al soltar, el rumbo aguanta unos segundos y despues la
	# rueda vuelve sola a la via.
	puesto.ocupar_estacion(1, null)
	_check(not puesto.estacion_libre(), "ocupada queda a nombre de quien la agarro")
	gob.mando = 0.8
	puesto.liberar_estacion()
	_check(puesto.estacion_libre(), "y se suelta")
	_check(puesto.trinca_restante > 0.0, "al soltar, el cabo empieza a contar",
			"%.1f s" % puesto.trinca_restante)
	await _esperar(1.0)
	_check(is_equal_approx(gob.mando, 0.8),
			"mientras el cabo aguanta, el rumbo se mantiene solo")
	# Y cuando se corre, la rueda vuelve a la via en vez de quedarse metida para
	# siempre: un barco amarrado a un rumbo que nadie eligio seria una trampa.
	puesto.trinca_restante = 0.02
	await _esperar(0.5)
	_check(is_zero_approx(gob.mando), "vencido el cabo, la rueda vuelve a la via")
	await _desmontar(barco)
