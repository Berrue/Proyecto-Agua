extends Node

## Pruebas de la cama musical.
##
##   godot --headless --path . tests/music_tests.tscn
##
## Lo que de verdad se protege aqui es que EL LOOP SIGA SIENDO UN LOOP. El
## importador de Vorbis de Godot trae `loop = false` de fabrica: si alguien
## borra el .import, o lo reimporta desde el editor sin marcar la casilla, la
## musica se corta a los dos minutos y no aparece ni un error en consola. El
## bug seria invisible hasta que alguien juegue una partida larga — justo el
## tipo de fallo que ningun playtest corto encuentra.

const TRACK := "res://game/audio/music/oceanic_routine_loop.ogg"

## El loop se corto a 0:00-2:00 del render original. Exacto, no aproximado: el
## crossfade horneado en la cabeza asume que la cola cae en 120.000 s clavados.
const DURACION_ESPERADA := 120.0

var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0


func _ready() -> void:
	print_rich("[b]--- Pruebas de la cama musical ---[/b]")
	_test_asset_importado()
	_test_bus_music()
	await _test_director_arranca()
	_test_fundidos()
	_test_detener_y_rearrancar()
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


func _player() -> AudioStreamPlayer:
	return MusicDirector.get_node_or_null("MusicPlayer") as AudioStreamPlayer


# =============================================================================


## La casilla `loop` del .import es el unico punto de fallo silencioso de todo
## el sistema de musica. Este es el test que existe por eso.
func _test_asset_importado() -> void:
	var stream := load(TRACK) as AudioStreamOggVorbis
	_check(stream != null, "el .ogg carga como AudioStreamOggVorbis")
	if stream == null:
		return
	_check(stream.loop, "loop = true en el recurso importado",
		"el .import trae loop = false de fabrica: revisar oceanic_routine_loop.ogg.import")
	_check(is_equal_approx(stream.loop_offset, 0.0), "loop_offset = 0",
		"vale %f" % stream.loop_offset)
	_check(absf(stream.get_length() - DURACION_ESPERADA) < 0.01,
		"duracion = %.3f s" % DURACION_ESPERADA,
		"mide %.3f s" % stream.get_length())


## El bus propio es lo que permite bajar la musica sin tocar el SFX.
func _test_bus_music() -> void:
	var idx: int = AudioServer.get_bus_index("Music")
	_check(idx != -1, "existe el bus Music")
	if idx == -1:
		return
	_check(AudioServer.get_bus_send(idx) == "Master", "el bus Music envia al Master",
		"envia a '%s'" % AudioServer.get_bus_send(idx))
	_check(AudioServer.get_bus_index("SFX") != idx and AudioServer.get_bus_index("Reel") != idx,
		"Music no pisa los buses de SfxLibrary")


func _test_director_arranca() -> void:
	await get_tree().process_frame
	var p := _player()
	_check(p != null, "MusicDirector creo su AudioStreamPlayer")
	if p == null:
		return
	_check(p.bus == "Music", "el player sale por el bus Music", "sale por '%s'" % p.bus)
	_check(MusicDirector.esta_sonando(), "la cama arranca sola al entrar al juego")
	_check(p.stream != null and p.stream.resource_path == TRACK,
		"suena el track de navegacion",
		"suena '%s'" % ("null" if p.stream == null else p.stream.resource_path))


## fundir_a() con 0 s es el camino que usara el director de tsunamis cuando
## necesite agachar la cama de golpe.
func _test_fundidos() -> void:
	var p := _player()
	if p == null:
		return
	MusicDirector.fundir_a(-30.0, 0.0)
	_check(is_equal_approx(p.volume_db, -30.0), "fundir_a(-30, 0) agacha la cama al instante",
		"quedo en %.2f dB" % p.volume_db)
	MusicDirector.fundir_a(MusicDirector.VOLUMEN_BASE_DB, 0.0)
	_check(is_equal_approx(p.volume_db, MusicDirector.VOLUMEN_BASE_DB),
		"fundir_a(VOLUMEN_BASE_DB, 0) la devuelve", "quedo en %.2f dB" % p.volume_db)


func _test_detener_y_rearrancar() -> void:
	var p := _player()
	if p == null:
		return
	MusicDirector.detener(0.0)
	_check(not MusicDirector.esta_sonando(), "detener(0) corta en seco")
	MusicDirector.reproducir(MusicDirector.TRACK_NAVEGACION, 0.0)
	_check(MusicDirector.esta_sonando(), "reproducir() la vuelve a levantar")
	_check(is_equal_approx(p.volume_db, MusicDirector.VOLUMEN_BASE_DB),
		"reproducir(fundido 0) deja el volumen nominal", "quedo en %.2f dB" % p.volume_db)
