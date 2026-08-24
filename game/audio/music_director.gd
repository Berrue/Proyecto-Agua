extends Node

## AUTOLOAD `MusicDirector` — cama musical de fondo.
##
## Un unico track por ahora: el loop de navegacion con el mar en calma (sin
## lluvia). El .ogg ya viene CERRADO como loop: lleva horneado un crossfade
## equal-power de 4 s en la cabeza, asi que loop_offset = 0 y no hay punto de
## loop que ajustar en runtime.
##
## Por que hizo falta el crossfade: el render original arranca en un fade-in de
## -37 dBFS y a los 2:00 esta en -30 dBFS. Empalmado en crudo, la costura media
## 0.68 de distancia espectral (el ruido puro mide 0.99) mas un escalon de +8 dB
## — un bajon audible cada dos minutos. Con el crossfade la costura baja a 0.20,
## contra 0.21 de la continuidad natural del propio tema: el empalme es tan
## continuo como cualquier otro compas.
##
## Regla de mezcla: la musica es CAMA, no protagonista. Vive en su propio bus
## `Music` a -14 dB para que el SFX procedural de SfxLibrary (buses Reel/SFX)
## mande siempre por encima. Sin limiter propio: el HardLimiter del Master ya
## lo cubre.

## Navegacion, mar en calma.
const TRACK_NAVEGACION := "res://game/audio/music/oceanic_routine_loop.ogg"

## Volumen nominal de la cama. Todo fundido vuelve aqui.
const VOLUMEN_BASE_DB := -14.0

## Por debajo de esto el player se considera apagado.
const SILENCIO_DB := -60.0

var _player: AudioStreamPlayer
var _fundido: Tween


func _ready() -> void:
	_asegurar_bus()
	_player = AudioStreamPlayer.new()
	_player.name = "MusicPlayer"
	_player.bus = "Music"
	_player.volume_db = SILENCIO_DB
	add_child(_player)
	reproducir(TRACK_NAVEGACION, 4.0)



## Crea el bus `Music` colgado del Master si falta. Idempotente y autonomo: no
## asume el orden de autoloads ni que SfxLibrary exista.
func _asegurar_bus() -> void:
	if AudioServer.get_bus_index("Music") != -1:
		return
	AudioServer.add_bus()
	var idx: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, "Music")
	AudioServer.set_bus_send(idx, "Master")


## Arranca un track con fundido de entrada. Reentrante: llamarlo con el track
## que ya suena solo re-funde el volumen, no reinicia la reproduccion.
func reproducir(ruta: String, fundido_s: float = 4.0) -> void:
	var stream := load(ruta) as AudioStream
	if stream == null:
		push_warning("MusicDirector: no se pudo cargar %s" % ruta)
		return

	# Cinturon y tiradores: el loop tambien va marcado en el .import, pero el
	# importador de Vorbis tiene loop = false por defecto. Si alguien reimporta
	# con los valores de fabrica, la cama se cortaria a los 2 minutos y no habria
	# ni un error en consola que lo delate. Aqui no puede pasar.
	var ogg := stream as AudioStreamOggVorbis
	if ogg != null:
		ogg.loop = true
		ogg.loop_offset = 0.0

	if _player.stream == stream and _player.playing:
		_fundir(VOLUMEN_BASE_DB, fundido_s)
		return

	_player.stream = stream
	_player.volume_db = SILENCIO_DB
	_player.play()
	_fundir(VOLUMEN_BASE_DB, fundido_s)


## Funde a silencio y detiene. fundido_s = 0.0 corta en seco.
func detener(fundido_s: float = 2.0) -> void:
	_matar_fundido()
	if fundido_s <= 0.0:
		_player.stop()
		return
	_fundido = create_tween()
	_fundido.tween_property(_player, "volume_db", SILENCIO_DB, fundido_s)
	_fundido.tween_callback(_player.stop)


## Agacha o levanta la cama sin detenerla. Para el tsunami: fundir_a(-30.0, 1.5)
## le deja sitio al rugido, y fundir_a(VOLUMEN_BASE_DB, 6.0) la devuelve.
func fundir_a(db: float, fundido_s: float = 1.5) -> void:
	_fundir(db, fundido_s)


func esta_sonando() -> bool:
	return _player != null and _player.playing


func _fundir(db: float, segundos: float) -> void:
	_matar_fundido()
	if segundos <= 0.0:
		_player.volume_db = db
		return
	_fundido = create_tween()
	_fundido.tween_property(_player, "volume_db", db, segundos)


func _matar_fundido() -> void:
	if _fundido != null and _fundido.is_valid():
		_fundido.kill()
	_fundido = null
