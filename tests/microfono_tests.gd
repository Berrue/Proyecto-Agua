extends Node

## Arnes del MICROFONO: que aparato se abre y cuanta ganancia lleva.
##
##   <godot 4.7.2> --headless --path . tests/microfono_tests.tscn
##
## En headless no hay tarjeta de sonido ni micrófonos, asi que lo que se prueba
## es la aritmetica pura de `MicrofonoModel` —la conversion del mando, el apaño
## de los cascos desenchufados, el pico— mas el cableado del autoload: que monte
## su bus, que lo monte una sola vez y que NO se enrute a los altavoces.

const PCT_MAX := MicrofonoModel.PCT_MAX

var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0


func _ready() -> void:
	print_rich("[b]--- Pruebas del microfono ---[/b]")
	_test_el_mando_de_volumen()
	_test_el_aparato_que_se_abre()
	_test_el_pico_y_la_barra()
	_test_el_bus()
	_test_no_te_oyes_a_ti_mismo()
	_test_la_entrada_esta_habilitada()
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


## El mando va de 0 a 200 %, y 100 % tiene que ser EXACTAMENTE la señal tal cual
## entra: si el centro del recorrido ya tocara el volumen, nadie podria dejarlo
## "como estaba".
func _test_el_mando_de_volumen() -> void:
	_check(is_equal_approx(MicrofonoModel.porcentaje_a_db(100.0), 0.0),
		"al 100 % el microfono entra tal cual: 0 dB",
		"%.3f dB" % MicrofonoModel.porcentaje_a_db(100.0))
	_check(absf(MicrofonoModel.porcentaje_a_db(200.0) - 6.0206) < 0.01,
		"al 200 % son +6 dB, o sea el doble de amplitud",
		"%.3f dB" % MicrofonoModel.porcentaje_a_db(200.0))
	_check(MicrofonoModel.porcentaje_a_db(0.0) <= MicrofonoModel.DB_SILENCIO,
		"al 0 % es silencio de verdad, no un -infinito que ensucie el bus")
	_check(absf(MicrofonoModel.porcentaje_a_db(50.0) + 6.0206) < 0.01,
		"y al 50 %, -6 dB: el mando es logaritmico, como el oido")

	_check(is_equal_approx(MicrofonoModel.porcentaje_a_db(300.0),
			MicrofonoModel.porcentaje_a_db(PCT_MAX)),
		"pasarse de 200 % no sube mas: el tope es tope")
	_check(is_equal_approx(MicrofonoModel.porcentaje_a_db(-50.0),
			MicrofonoModel.porcentaje_a_db(0.0)),
		"ni bajarse de 0 %")

	# Ida y vuelta: el mando se pinta desde el bus, asi que la conversion tiene
	# que cerrar o el deslizador saltaria solo al abrir los ajustes.
	for pct in [0.0, 25.0, 50.0, 100.0, 150.0, 200.0]:
		var vuelta := MicrofonoModel.db_a_porcentaje(MicrofonoModel.porcentaje_a_db(pct))
		_check(absf(vuelta - pct) < 0.01,
			"el mando y los decibelios cierran el circulo", "%.0f%% -> %.2f%%" % [pct, vuelta])


## El apaño que existe por los cascos USB: si el aparato elegido desaparece hay
## que caer al del sistema, no quedarse mudo apuntando a un fantasma.
func _test_el_aparato_que_se_abre() -> void:
	var lista := PackedStringArray(["Default", "Cascos USB", "Microfono (Realtek)"])

	_check(MicrofonoModel.elegir_dispositivo(lista, "Cascos USB") == "Cascos USB",
		"si el aparato elegido esta, se abre ese")
	_check(MicrofonoModel.elegir_dispositivo(lista, "Webcam vieja") == MicrofonoModel.POR_DEFECTO,
		"si ya no esta, se cae al del sistema en vez de quedarse mudo")
	_check(MicrofonoModel.elegir_dispositivo(lista, "") == MicrofonoModel.POR_DEFECTO,
		"y sin preferencia, el del sistema")
	_check(MicrofonoModel.elegir_dispositivo(PackedStringArray(), "Cascos USB")
			== MicrofonoModel.POR_DEFECTO,
		"aunque no haya ni lista")

	_check(MicrofonoModel.se_perdio(lista, "Webcam vieja"),
		"y se sabe DECIR que se perdio, para poder avisar")
	_check(not MicrofonoModel.se_perdio(lista, "Cascos USB"),
		"sin falsos positivos con el que sigue enchufado")
	_check(not MicrofonoModel.se_perdio(lista, MicrofonoModel.POR_DEFECTO),
		"ni con el del sistema, que no se puede perder")


func _test_el_pico_y_la_barra() -> void:
	var silencio := PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
	var voz := PackedVector2Array([Vector2(0.1, 0.1), Vector2(-0.4, 0.2), Vector2(0.05, 0.05)])
	_check(is_zero_approx(MicrofonoModel.pico(silencio)), "en silencio, pico cero")
	_check(is_equal_approx(MicrofonoModel.pico(voz), 0.4),
		"el pico es el mayor valor absoluto, no la media: la voz son golpes",
		"%.3f" % MicrofonoModel.pico(voz))
	_check(is_zero_approx(MicrofonoModel.pico(PackedVector2Array())),
		"y sin muestras no revienta")

	# La barra tiene que MOVERSE con voz normal. Una barra lineal sobre amplitud
	# se quedaria pegada a la izquierda y el jugador pensaria que no coge nada.
	var barra := MicrofonoModel.barra(0.1)
	_check(barra > 0.3 and barra < 0.95,
		"una voz normal (amplitud 0,1) mueve la barra a media altura",
		"%.2f" % barra)
	_check(is_zero_approx(MicrofonoModel.barra(0.0)), "y el silencio la deja a cero")
	_check(MicrofonoModel.barra(1.0) >= 0.99, "y saturar la llena")
	_check(MicrofonoModel.barra(0.5) > MicrofonoModel.barra(0.1),
		"mas señal es siempre mas barra")


func _test_el_bus() -> void:
	var idx := AudioServer.get_bus_index(Microfono.BUS)
	_check(idx != -1, "el microfono tiene su propio bus")
	if idx == -1:
		return

	var amplify: int = 0
	var capture: int = 0
	var pos_amplify: int = -1
	var pos_capture: int = -1
	for i in AudioServer.get_bus_effect_count(idx):
		var ef := AudioServer.get_bus_effect(idx, i)
		if ef is AudioEffectAmplify:
			amplify += 1
			pos_amplify = i
		elif ef is AudioEffectCapture:
			capture += 1
			pos_capture = i
	_check(amplify == 1 and capture == 1,
		"con una ganancia y una captura, y solo una de cada",
		"%d amplify, %d capture" % [amplify, capture])
	# El orden ES la honestidad del medidor: capturar ANTES de amplificar
	# enseñaria un nivel que no es el que van a oir los demas.
	_check(pos_amplify < pos_capture,
		"primero se amplifica y luego se mide: el medidor enseña lo que va a salir",
		"amplify en %d, capture en %d" % [pos_amplify, pos_capture])

	Microfono.volumen_pct = 200.0
	_check(is_equal_approx(Microfono.volumen_pct, 200.0), "el mando se deja poner al maximo")
	Microfono.volumen_pct = 500.0
	_check(is_equal_approx(Microfono.volumen_pct, PCT_MAX),
		"y clampa, no acepta cualquier numero", "%.0f" % Microfono.volumen_pct)
	Microfono.volumen_pct = 100.0


## Enrutar el microfono a los altavoces es la receta del acoplamiento, y con dos
## jugadores sin cascos en la misma habitacion es un chillido. El bus nace mudo.
func _test_no_te_oyes_a_ti_mismo() -> void:
	var idx := AudioServer.get_bus_index(Microfono.BUS)
	if idx == -1:
		return
	_check(AudioServer.is_bus_mute(idx),
		"el bus del microfono nace SILENCIADO: no te oyes a ti mismo")


## `audio/driver/enable_input` es el interruptor sin el cual Godot ni abre el
## aparato — y no da error, simplemente no captura nada.
func _test_la_entrada_esta_habilitada() -> void:
	_check(bool(ProjectSettings.get_setting("audio/driver/enable_input", false)),
		"el proyecto tiene habilitada la entrada de audio")
