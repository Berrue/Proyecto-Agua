extends Node

## Pruebas del farol de tormenta.
##
##   godot --headless --path . tests/farol_tests.tscn
##
## Lo que se protege aqui son las cuatro decisiones que se pueden romper EN
## SILENCIO: que el parpadeo siga siendo funcion pura de sim_time, que la llama
## no llegue nunca a cero (el farol no se apaga), que solo haya UNA luz con
## sombras en la escena, y que llevar el farol ocupe una mano y no dos. Las
## cuatro se ven bien en pantalla aunque esten mal.

const FAROL := preload("res://game/props/farol.tscn")
const GANCHO := preload("res://game/props/gancho_farol.tscn")

var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0


func _ready() -> void:
	print_rich("[b]--- Pruebas del farol ---[/b]")
	_test_flicker_puro()
	_test_flicker_acotado()
	_test_socorro_cadencia()
	_test_cableado_escena()
	_test_gancho()
	await _test_una_sola_sombra()
	await _test_una_mano()
	await _test_flota()
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


func _nuevo_farol() -> Farol:
	var f := FAROL.instantiate() as Farol
	add_child(f)
	return f


# =============================================================================


## Dos faroles distintos, el mismo sim_time, la misma llama. El parpadeo es
## presentacion y PODRIA divergir sin romper nada — pero que no lo haga solo:
## el dia que alguien meta un RNG aqui, el farol dejara de poder hornearse.
func _test_flicker_puro() -> void:
	var a := _nuevo_farol()
	var b := _nuevo_farol()
	var peor: float = 0.0
	for i in 300:
		var t: float = float(i) * 0.137
		peor = maxf(peor, absf(a.energia01(t) - b.energia01(t)))
	_check(peor < 1e-9, "el parpadeo es funcion pura de sim_time", "desviacion %.12f" % peor)
	a.queue_free()
	b.queue_free()


## El farol NO se apaga. Ni en calma ni con temporal: si el minimo toca cero,
## alguien ha convertido el parpadeo en un interruptor.
func _test_flicker_acotado() -> void:
	var f := _nuevo_farol()
	# Lejos del agua: con furia alta el oleaje "moja" el origen y la llama
	# cambia a cadencia de socorro (minimo 0.3) — aqui se prueba la llama.
	f.global_position = Vector3(0.0, 100.0, 0.0)
	for furia: float in [0.0, 5.0, 10.0]:
		Ocean.set_fury_immediate(furia)
		var minimo: float = 99.0
		var maximo: float = -99.0
		for i in 2000:
			var e: float = f.energia01(float(i) * 0.017)
			minimo = minf(minimo, e)
			maximo = maxf(maximo, e)
		_check(minimo > 0.5, "furia %.0f: la llama nunca se apaga" % furia, "minimo %.3f" % minimo)
		_check(maximo < 1.5, "furia %.0f: la llama no ciega" % furia, "maximo %.3f" % maximo)
	Ocean.set_fury_immediate(3.0)
	f.queue_free()


## Un destello por segundo, como una luz de socorro homologada. Es la señal que
## convierte un farol perdido en una llamada de auxilio legible desde el barco.
func _test_socorro_cadencia() -> void:
	var f := _nuevo_farol()
	var destellos: int = 0
	var encendido: bool = false
	var pasos: int = 6000
	for i in pasos:
		var t: float = float(i) * 0.002 # 12 s a 500 Hz
		var e: float = f._socorro(t)
		if e > 0.8 and not encendido:
			destellos += 1
			encendido = true
		elif e < 0.5:
			encendido = false
	_check(destellos >= 11 and destellos <= 13, "cadencia de socorro ~1 Hz",
		"%d destellos en 12 s" % destellos)
	f.queue_free()


func _test_cableado_escena() -> void:
	var f := _nuevo_farol()
	_check(f.get_node_or_null(^"Luz") is OmniLight3D, "el farol trae su OmniLight3D")
	_check(f.get_node_or_null(^"Globo") is MeshInstance3D, "el farol trae su globo emisivo")
	var sonda := f.get_node_or_null(^"Sonda") as BuoyancyProbe3D
	_check(sonda != null, "el farol trae sonda de flotabilidad")
	if sonda != null:
		# Empuje = volumen x 1000 kg/m3. Si no supera la masa, el farol se
		# hunde, y DISENO.md dice que la lampara flota.
		var empuje: float = sonda.volume * 1000.0
		_check(empuje > f.mass * 1.5, "la sonda desplaza mas agua que la masa del farol",
			"%.1f kg de empuje contra %.1f kg" % [empuje, f.mass])
	f.queue_free()


func _test_gancho() -> void:
	var g := GANCHO.instantiate() as GanchoFarol
	add_child(g)
	_check(g.libre(), "un gancho nuevo esta libre")
	g.ocupar()
	_check(not g.libre(), "un gancho ocupado no acepta un segundo farol")
	g.liberar()
	_check(g.libre(), "descolgar libera el gancho")
	g.queue_free()


## La invariante cara: seis faroles en seis manos, UNA sola luz con sombras.
func _test_una_sola_sombra() -> void:
	var faroles: Array[Farol] = []
	var manos: Array[Node3D] = []
	for i in 6:
		var portador := Node3D.new()
		add_child(portador)
		var agarre := Marker3D.new()
		portador.add_child(agarre)
		manos.append(portador)
		var f := _nuevo_farol()
		f.tomar(portador, agarre)
		faroles.append(f)
	await get_tree().process_frame

	var con_sombra: int = 0
	for f in faroles:
		var luz := f.get_node_or_null(^"Luz") as OmniLight3D
		if luz != null and luz.shadow_enabled:
			con_sombra += 1
	_check(con_sombra == 1, "solo un farol proyecta sombras", "%d encendidos" % con_sombra)

	# Y el que no las tiene, se apaga con la distancia (godot#88085: el distance
	# fade solo ahorra con las sombras apagadas).
	var fade_ok: bool = true
	for f in faroles:
		var luz := f.get_node_or_null(^"Luz") as OmniLight3D
		if luz != null and not luz.shadow_enabled and not luz.distance_fade_enabled:
			fade_ok = false
	_check(fade_ok, "los faroles sin sombras se desvanecen con la distancia")

	for f in faroles:
		f.queue_free()
	for m in manos:
		m.queue_free()
	await get_tree().process_frame


## El farol ocupa UNA mano: sigues andando. Si esto se rompe, llevar luz te
## clava en el sitio y el objeto se vuelve inservible en tormenta.
func _test_una_mano() -> void:
	var p := Player.new()
	add_child(p)
	await get_tree().process_frame
	p.hands_used = 1
	_check(not p.hands_busy, "con el farol en la mano el jugador se mueve")
	p.hands_used = 2
	_check(p.hands_busy, "con la caña, las dos manos ocupadas")
	# Soltar la caña no puede borrarte el farol de la otra mano.
	p.hands_busy = true
	p.hands_busy = false
	_check(p.hands_used == 0, "soltar la caña libera las dos manos")
	p.queue_free()
	await get_tree().process_frame


## Flota, y se endereza. El centro de masas esta en el deposito y la sonda por
## encima: es la misma razon por la que un farol de verdad se posa de pie.
func _test_flota() -> void:
	var f := _nuevo_farol()
	var pos := Vector3(0.0, 0.0, 0.0)
	f.global_position = Vector3(pos.x, Ocean.get_height(pos) - 0.5, pos.z)
	f.rotation = Vector3(0.9, 0.0, 0.6)
	for i in 420: # 3,5 s a 120 Hz
		await get_tree().physics_frame

	var sumersion: float = Ocean.get_submersion(f.global_position)
	_check(absf(sumersion) < 0.25, "el farol sube y se queda en la superficie",
		"sumersion %.3f m" % sumersion)

	var arriba := f.global_transform.basis.y
	_check(arriba.dot(Vector3.UP) > 0.7, "el farol se endereza solo",
		"inclinacion %.0f grados" % rad_to_deg(arriba.angle_to(Vector3.UP)))
	f.queue_free()
