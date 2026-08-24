extends Node

## Arnes de la VOZ POR PROXIMIDAD: cuanto os ois segun lo que ruja el mar.
##
##   <godot 4.7.2> --headless --path . tests/voz_tests.tscn
##
## El transporte de voz (two-voip) es la fase R2 y todavia no existe. Lo que se
## prueba aqui es la otra mitad, la que NO depende de ninguna libreria: la
## mecanica. Casi todo son funciones puras de `VozModel`, mas el cableado del
## nodo y del bus.

const RUTA_BALANCE := "res://resources/audio/voz_proximidad.tres"
const RUTA_BARCO := "res://game/boat/fishing_boat.tscn"

var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0


func _ready() -> void:
	print_rich("[b]--- Pruebas de la voz por proximidad ---[/b]")
	_test_el_balance_carga()
	_test_el_radio_encoge_con_el_ruido()
	_test_el_refugio_devuelve_el_oido()
	_test_el_filtro_se_cierra_con_el_ruido()
	_test_inteligibilidad()
	_test_en_temporal_no_se_grita_de_popa_a_proa()
	await _test_el_nodo_se_cablea()
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


func _balance() -> VozBalance:
	return load(RUTA_BALANCE) as VozBalance


# =============================================================================


func _test_el_balance_carga() -> void:
	var b := _balance()
	_check(b != null, "el balance de la voz carga", RUTA_BALANCE)
	if b == null:
		return
	_check(b.radio_calma > b.radio_temporal,
		"en calma se oye MAS lejos que en temporal (si no, la mecanica esta al reves)",
		"%.1f vs %.1f m" % [b.radio_calma, b.radio_temporal])
	_check(b.hz_calma > b.hz_temporal,
		"y el filtro se CIERRA con el temporal, no se abre")


## El corazon de la mecanica: el radio encoge, monotonamente y sin saltos.
func _test_el_radio_encoge_con_el_ruido() -> void:
	var b := _balance()
	if b == null:
		return
	_check(is_equal_approx(
			VozModel.radio_util(0.0, 0.0, b.radio_calma, b.radio_temporal, b.alivio_interior),
			b.radio_calma),
		"con el mar callado, el radio entero")
	_check(is_equal_approx(
			VozModel.radio_util(1.0, 0.0, b.radio_calma, b.radio_temporal, b.alivio_interior),
			b.radio_temporal),
		"con el temporal encima, el radio de temporal")

	var previo: float = INF
	var monotono := true
	for i in 21:
		var r := VozModel.radio_util(float(i) / 20.0, 0.0,
			b.radio_calma, b.radio_temporal, b.alivio_interior)
		if r > previo + 0.001:
			monotono = false
		previo = r
	_check(monotono, "y entre medias solo baja: mas ruido nunca es mas alcance")

	# El suelo: por muy mal puesto que este el balance, a bocajarro te oyen.
	_check(VozModel.radio_util(1.0, 0.0, 40.0, 0.0, 0.0) >= VozModel.RADIO_MINIMO,
		"con un balance absurdo (radio 0) sigue habiendo un suelo audible",
		"%.2f m" % VozModel.radio_util(1.0, 0.0, 40.0, 0.0, 0.0))


## Meterse en la cabina tiene que devolver el oido: es la razon ACUSTICA para
## reunirse dentro (docs/CLIMA.md §3.5), y si no se nota no existe.
func _test_el_refugio_devuelve_el_oido() -> void:
	var b := _balance()
	if b == null:
		return
	var fuera := VozModel.radio_util(1.0, 0.0, b.radio_calma, b.radio_temporal, b.alivio_interior)
	var dentro := VozModel.radio_util(1.0, 1.0, b.radio_calma, b.radio_temporal, b.alivio_interior)
	_check(dentro > fuera * 1.5,
		"en el peor temporal, dentro de la cabina se oye bastante mas que fuera",
		"fuera %.1f m, dentro %.1f m" % [fuera, dentro])
	_check(dentro < b.radio_calma,
		"pero el refugio no es un mar en calma: sigue costando algo")


func _test_el_filtro_se_cierra_con_el_ruido() -> void:
	var b := _balance()
	if b == null:
		return
	_check(is_equal_approx(
			VozModel.corte_lpf(0.0, 0.0, b.hz_calma, b.hz_temporal, b.alivio_interior),
			b.hz_calma),
		"sin ruido el filtro esta abierto del todo")
	_check(is_equal_approx(
			VozModel.corte_lpf(1.0, 0.0, b.hz_calma, b.hz_temporal, b.alivio_interior),
			b.hz_temporal),
		"con el ruido a tope, cerrado hasta el corte de temporal")

	# A medio camino tiene que estar a medias EN OCTAVAS, no en Hz: interpolar
	# lineal dejaria el filtro sin hacer nada audible hasta el ultimo tramo,
	# porque el oido oye ratios. A ruido 0,5 el corte cae por debajo de 6 kHz.
	var medio := VozModel.corte_lpf(0.5, 0.0, b.hz_calma, b.hz_temporal, b.alivio_interior)
	_check(medio < 6000.0,
		"a medio temporal el filtro ya se nota (se interpola en octavas)",
		"%.0f Hz" % medio)


func _test_inteligibilidad() -> void:
	_check(is_equal_approx(VozModel.inteligibilidad(0.0, 10.0), 1.0),
		"pegado a alguien se le entiende del todo")
	_check(is_zero_approx(VozModel.inteligibilidad(10.0, 10.0)),
		"y en el borde del radio ya no")
	_check(is_zero_approx(VozModel.inteligibilidad(50.0, 10.0)),
		"ni mas alla")
	_check(VozModel.inteligibilidad(5.0, 10.0) > 0.4,
		"a media distancia todavia se le pilla")


## EL test de diseño, atado al barco de verdad y no a un numero copiado: en el
## pico del temporal el radio util tiene que ser MENOR que la eslora, porque esa
## es toda la mecanica — que no puedas darle una orden al de proa desde el timon.
## Si alguien sube `radio_temporal` sin querer, aqui se entera.
func _test_en_temporal_no_se_grita_de_popa_a_proa() -> void:
	var b := _balance()
	if b == null:
		return
	var barco := (load(RUTA_BARCO) as PackedScene).instantiate() as Node3D
	var casco := barco.get_node_or_null(^"HullShape") as CollisionShape3D
	var caja := casco.shape as BoxShape3D if casco != null else null
	if caja == null:
		_check(false, "el barco trae su casco para medir la eslora")
		barco.queue_free()
		return
	var eslora: float = caja.size.z
	var radio := VozModel.radio_util(1.0, 0.0, b.radio_calma, b.radio_temporal, b.alivio_interior)
	_check(radio < eslora,
		"en el pico del temporal no se llega de popa a proa: hay que ir, o señalar",
		"radio %.1f m contra %.1f m de eslora" % [radio, eslora])
	_check(VozModel.radio_util(0.0, 0.0, b.radio_calma, b.radio_temporal, b.alivio_interior) > eslora,
		"pero en calma el barco entero es una conversacion",
		"radio %.1f m contra %.1f m de eslora" % [
			VozModel.radio_util(0.0, 0.0, b.radio_calma, b.radio_temporal, b.alivio_interior), eslora])
	barco.queue_free()


## El cableado: que el nodo monte su bus, lo monte UNA sola vez aunque haya seis
## bocas, y traduzca el radio a los parametros que el motor entiende.
func _test_el_nodo_se_cablea() -> void:
	var a := VozProximidad.new()
	var b := VozProximidad.new()
	add_child(a)
	add_child(b)
	await get_tree().process_frame

	var idx := AudioServer.get_bus_index(VozProximidad.BUS)
	_check(idx != -1, "la voz tiene su propio bus, separado del clima")
	if idx != -1:
		var lpf := 0
		for i in AudioServer.get_bus_effect_count(idx):
			if AudioServer.get_bus_effect(idx, i) is AudioEffectLowPassFilter:
				lpf += 1
		_check(lpf == 1,
			"y un solo paso-bajo aunque haya varias bocas en la escena",
			"%d filtros" % lpf)

	_check(a.bus == VozProximidad.BUS, "cada boca canta por el bus de voz")
	_check(a.max_distance > 0.0 and a.unit_size > 0.0,
		"el radio se traduce a max_distance y unit_size",
		"max %.1f, unit %.1f" % [a.max_distance, a.unit_size])
	_check(is_equal_approx(a.max_distance, a.radio_util()),
		"y max_distance ES el radio util, no una copia que pueda derivar")

	a.queue_free()
	b.queue_free()
	await get_tree().process_frame
