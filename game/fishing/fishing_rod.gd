class_name FishingRod
extends Node3D

## La caña — el verbo del dia 1, ahora con el plan de game feel aplicado.
##
## PRINCIPIOS (de la investigacion, ya podados por el critico adversarial):
## - La tension se OYE: el click del freno del carrete acelera con la tension
##   real (el indicador universal de la pesca). Silencio = vas bien.
## - Los eventos criticos son picos MULTIMODALES en el mismo frame (Stardew):
##   escalonar tres señales debiles no suma un suceso fisico.
## - La picada es un juego de nervios (Animal Crossing): 1-4 toques FALSOS antes
##   del mordisco real, con polaridad sonora opuesta (plip agudo ascendente vs
##   chomp grave descendente). Tras el ultimo falso, el mordisco es GARANTIZADO.
## - La rotura SIEMPRE se telegrafia (crujido + sedal ambar->rojo 1-2 s antes):
##   "me aviso" en vez de "me robo".
## - El feedback jamas miente: todos los canales leen la MISMA tension real
##   (tiron del pez + aceleracion de la borda). Si el chirrido miente una vez,
##   el jugador deja de usarlo y el sistema muere.
## - Legible por la TRIPULACION: chomp y splashes son audio 3D EN la boya, el
##   "!" flota sobre ella, y la amplitud del cabeceo escala con el peso del pez.

signal fish_landed(fish: Fish)
signal line_snapped()
signal fish_escaped()
## Cebo puesto o gastado: lo escucha el cubo para enseñar cuanto queda.
signal cebo_cambiado()

enum State { IDLE, CASTING, WAITING, NIBBLING, BITE, FIGHT }

const CAST_MIN_DIST := 5.0
const CAST_MAX_DIST := 18.0
const CAST_CHARGE_SECONDS := 1.2
## Ventana de picada con la caña EN LA MANO: lo que tarda un clic al ver el "!".
const BITE_WINDOW := 1.8
## Ventana con la caña CLAVADA en un soporte de borda. Casi el doble, y no es
## una concesion: es que el gesto es OTRO. Con la caña en la mano solo hay que
## hacer clic; clavada hay que oir el chomp, soltar lo que portes, cruzar la
## cubierta, apuntar al soporte y retomarla (E) antes de clavar el pez.
##
## El presupuesto medido contra el barco real (sockets Gear* a +-1.92 en X,
## -1.75 en Z; walk_speed 4.2 m/s): reaccion ~0.3 s + soltar la carga ~0.2 s +
## cruzar hasta 3.84 m ~1.1 s + apuntar (el rayo del Portador llega a 2.2 m)
## ~0.3 s + E y clic ~0.2 s = ~2.1 s en el peor caso razonable. Con 1.8 s la
## promesa del soporte ("clavas, achicas o estibas, y vuelves al !") era
## literalmente imposible: la caña pescaba sola para que el pez se te fuera
## siempre. `tests/fishing_tests` protege el margen contra la diagonal REAL de
## la cubierta, asi que agrandar el barco o bajar este numero salta como fallo.
##
## Diegeticamente lo sostiene la fisica de un rod holder de verdad: el pez
## engancha contra una caña AMARRADA que no cede, y esa resistencia lo clava a
## medias sola — por eso los soportes existen en la pesca real.
const BITE_WINDOW_SOPORTE := 3.5
## Cruce del tren de clicks al loop de buzz (correccion del critico: por encima
## de esto el scheduler de frames no llega; la fusion se hornea en el loop).
const BUZZ_CROSSOVER_HZ := 25.0
## Nivel de la cama de recogida (el forcejeo del pez mientras tiras de el).
## Va DEBAJO del tren de clicks a proposito: la tension es el canal que el
## jugador tiene que poder decodificar (regla 8), y una cama continua encima de
## los clicks se los come. Este es el numero a mover si suena alta o baja.
const HAUL_DB := -14.0
## Vueltas por segundo de la manivela mientras recoges, y la multiplicacion del
## carrete (rotor : manivela). El 5.2:1 es la relacion de un carrete de spinning
## real, y no es un adorno: el rotor girando cinco veces mas rapido que la mano
## es lo que hace que la recogida se LEA como recogida y no como una pieza
## suelta dando vueltas. La velocidad escala con `reel_factor`, asi que una caña
## mejor tambien se ve mas rapida — la regla del arbol de mejoras (piezas que se
## ven), aplicada a la unica pieza movil de la caña.
const REEL_TURNS_PER_SECOND := 2.6
const REEL_GEAR_RATIO := 5.2

# --- El doblez: cuanto gira la muñeca y cuanto se CURVA el cuerpo -----------
# `_bend` sigue siendo UN solo numero (la misma señal de tension de siempre,
# regla 8), pero ahora se reparte en dos gestos distintos que un pescador
# distingue de un vistazo: la caña entera inclinandose (tus manos cediendo) y
# el cuerpo arqueandose (el pez cargando la caña). Antes se lo llevaba todo la
# inclinacion, y por eso la caña parecia un palo de escoba con bisagra.
#
# La suma de los dos angulos se mantiene por encima del doblez de antes: la
# silueta cargada tiene que leerse IGUAL de fuerte desde la borda de al lado.
const BEND_RIGID_SHARE := 0.45
const BEND_CURVE_GAIN := 1.3
## Como se reparte la curva entre los seis huesos, de la mano a la punta. Va
## cargada hacia delante porque asi dobla una caña real (accion rapida): el
## tramo de abajo aguanta y la punta es la que se arquea. Repartirlo por igual
## da un arco de circunferencia, que lee como manguera, no como caña.
const BEND_BONE_WEIGHTS := [0.06, 0.10, 0.15, 0.20, 0.24, 0.25]

# --- El sedal enhebrado y el aparejo ----------------------------------------
# La caña tenia carrete, anillas y puntera, pero el hilo solo existia DESPUES de
# lanzar (de la punta a la boya): en la mano era un palo naranja. El sedal
# enhebrado es lo que dice "esto pesca" en la pose que el jugador mira el 90 %
# del tiempo, y ademas ata las tres piezas que ya se movian — la bobina que
# gira, el cuerpo que se arquea y la punta — en un mismo objeto.

## Por donde pasa el sedal, en el espacio del MODELO de la caña y en metros: la
## salida de la bobina, el centro de las seis anillas y la puntera.
##
## Espeja `guide_specs` + el carrete de `tools/build_fishing_rod.py` (alli en
## coordenadas de Blender: aqui `+Z` de Blender es `+Y` y `+Y` es `-Z`). No es
## un numero duplicado a ciegas: `fishing_tests` comprueba que cada punto cae
## DENTRO del aro real de la malla, asi que si alguien mueve una anilla en el
## generador y no aqui, salta en rojo en vez de dibujar el hilo por fuera.
const ENHEBRADO: Array[Vector3] = [
	Vector3(0.0, 0.097, -0.0728), # labio de la bobina, por donde sale el hilo
	Vector3(0.0, 0.330, -0.04069),
	Vector3(0.0, 0.575, -0.03464),
	Vector3(0.0, 0.810, -0.02951),
	Vector3(0.0, 1.020, -0.024986),
	Vector3(0.0, 1.200, -0.021514),
	Vector3(0.0, 1.360, -0.018472),
	Vector3(0.0, 1.536, -0.0117), # puntera: el ultimo aro, casi en el eje
]

## Cuanto sedal cuelga de la puntera con el aparejo en la mano. Treinta
## centimetros es el descuelgue que deja un pescador entre la punta y el anzuelo
## para lanzar: menos no se ve, y mas se pasea el anzuelo por delante de la cara.
const APAREJO_LARGO := 0.30

## Un punto CUALQUIERA del cuerpo de la caña, en el espacio del pivote (el
## cuerpo va a lo largo del eje Y). Sirve para saber por que lado queda la caña
## y plantar el anzuelo con la curva hacia el otro — ver `_orientar_aparejo`.
const PUNTO_DEL_CUERPO := Vector3(0.0, 0.3, 0.0)

## Donde flota el aparejo una vez echado el sedal: al COSTADO de la boya y a
## ras de agua, no colgando debajo.
##
## Un flotador de verdad lleva el anzuelo un metro por debajo, o sea donde no lo
## ve nadie — y aqui menos: la boya son 32 cm de bola que lo tapa desde arriba y
## el agua tapa lo que asome por el lado (medido: no pintaba un pixel). Gana la
## lectura: el jugador tiene que poder ver que en el mar esta EL MISMO aparejo
## que llevaba en la caña, con el mismo cebo. La boya sigue siendo la señal de
## la picada; el aparejo es la prueba de que no hay dos aparejos distintos.
const APAREJO_JUNTO_A_BOYA := 0.34
const APAREJO_SOBRE_EL_AGUA := 0.09

## Cuantas picadas de cebo caben en el anzuelo de una cebada. Seis y no una:
## con una carga por viaje al cubo, cebar seria una tarea; con seis es un
## ritmo — vuelves al cubo cada tantos peces, como a la bodega.
const CEBO_CARGAS_MAX := 6

## El arbol de aparejos en orden (DISENO §3). El HUD de debug las cicla con C;
## cuando exista la lonja, comprarlas recorrera esta misma escalera.
const TIER_PATHS: Array[String] = [
	"res://resources/rod_tiers/tier_1_iniciacion.tres",
	"res://resources/rod_tiers/tier_2_faena.tres",
	"res://resources/rod_tiers/tier_3_altura.tres",
]

@export var player_path: NodePath
@export var fish_scene: PackedScene
## La caña montada (sedal, carrete, alcance). Sin asignar = la de iniciación.
@export var tier: RodTier
@export var view_offset := Vector3(0.3, -0.34, -0.62)
@export var view_angles_deg := Vector3(-55.0, -10.0, -8.0)
## Cuanto rueda el MODELO sobre su propio eje dentro del pivote.
##
## Un carrete de spinning cuelga hacia abajo, y hacia abajo es exactamente donde
## el brazo del viewmodel (una capsula gorda que sale de la esquina de la
## pantalla) lo tapa entero: la pieza que gira cuando recoges, la unica que
## cuenta lo que estan haciendo tus manos, quedaba invisible. Con la caña rodada
## el carrete asoma por la izquierda del brazo sin dejar de colgar por debajo,
## que es como se sujeta una caña de spinning de verdad al recoger.
##
## No se toca el angulo de la caña (`view_angles_deg`): ese esta jugado en
## playtest y mueve la punta, el sedal y el encuadre entero.
@export_range(-90.0, 90.0, 1.0) var model_roll_deg: float = 50.0
## La partida empieza con la caña CLAVADA en un soporte del barco, no en la
## mano: hay que ir a por ella (E). Lo enciende `player.tscn`, que es quien sabe
## que hay un barco debajo; una caña instanciada suelta (tests, capturas) nace
## en la mano, que es el caso sin sorpresas.
@export var empezar_clavada: bool = false

var state: State = State.IDLE
var fight := FightModel.new()
var hooked_species: Dictionary = {}
var deck_accel_y: float = 0.0

var _player: Player
var _camfx: CameraFeedback
## El RNG de la PARTIDA: espera, toques falsos, especie, fases de la lucha.
## Todo lo que decide algo que el jugador vive como resultado.
var _rng := RandomNumberGenerator.new()

## El RNG de la PRESENTACION: clicks del freno, crujidos, el tumbo del pez al
## caer. Separado a proposito (regla 4): mientras compartian secuencia,
## cualquier retoque de audio o de feel desplazaba la cadena de especies — una
## trampa que no se manifiesta hasta el mes seis.
var _rng_fx := RandomNumberGenerator.new()
var _charge: float = 0.0
var _wait_left: float = 0.0
var _bite_left: float = 0.0
var _cast_point := Vector2.ZERO
var _prev_platform_vy: float = 0.0
var _snap_flash: float = 0.0

# --- picada por capas --------------------------------------------------------
var _nibble_delays: PackedFloat32Array = PackedFloat32Array()
var _nibble_index: int = 0
var _nibble_timer: float = 0.0
var _nibble_dip: float = 0.0 ## 0..1, cuanto se hunde la boya en el toque falso

# --- feel: muelle de la caña -------------------------------------------------
var _bend: float = 0.0
var _bend_vel: float = 0.0
var _lateral: float = 0.0
var _lateral_vel: float = 0.0
## Inclinacion sostenida del tira-y-afloja: el pez tira hacia su lado, tus
## teclas tiran hacia el tuyo, y la contra CORRECTA la deja centrada — la caña
## quieta ES la señal de que estas aguantando bien. Las manos del viewmodel
## cuelgan del pivote, asi que acompañan cada tiron sin animar una linea.
var _lean: float = 0.0
var _lean_vel: float = 0.0
var _lean_goal: float = 0.0

# --- feel: audio -------------------------------------------------------------
var _click_cooldown: float = 0.0
var _creak_cooldown: float = 0.0
var _lap_cooldown: float = 0.0
var _prev_bobber_y: float = 0.0
var _prev_pull: FightModel.Pull = FightModel.Pull.NONE

# --- feel: eventos -----------------------------------------------------------
var _freeze_left: float = 0.0 ## hitstop LOCAL de presentacion (max 0.1 s)
var _silence_left: float = 0.0 ## hueco de casi-silencio tras la rotura
var _remnant_left: float = 0.0 ## trozo de sedal colgando tras el snap
var _adrift_left: float = 0.0 ## la boya perdida, a la deriva
var _rumble_refresh: float = 0.0
var _reel_rearm: bool = false ## tras clavar, recoger exige un clic NUEVO

## El cebo en el anzuelo y cuantas picadas le quedan. Lo pone el cubo de
## cubierta; sin cargas, la caña pesca a pelo (que es lo normal y siempre vale).
var cebo: TipoCebo = null
var cebo_cargas: int = 0

## El soporte de borda donde esta clavada, o null si la llevas en la mano.
## Mientras esta clavada, el soporte es su cuerpo visible: recibe el doblez
## del muelle real via set_doblado y presta su punta para el sedal.
var soporte: Node3D = null

## Las dos piezas moviles del carrete y su pose de fabrica. El GLB las exporta
## con el origen EN su eje de giro (`tools/build_fishing_rod.py`), asi que girar
## es componer sobre esa pose: nada de tocar la malla.
var _rotor: Node3D
var _rotor_base: Basis
var _handle: Node3D
var _handle_base: Basis
var _reel_angle: float = 0.0
var _reeling: bool = false

## El rig que curva el cuerpo, y todo lo que hace falta para hablar con el sin
## recalcularlo cada frame. Si el modelo llegara sin esqueleto, `_skel` se queda
## nulo y la caña vuelve al doblez rigido de antes: fea, pero jugable.
var _skel: Skeleton3D
var _huesos := PackedInt32Array()
var _eje_hueso: Array[Vector3] = []
var _esq_a_pivote := Transform3D.IDENTITY
var _punta_esq := Vector3.ZERO
var _rest_punta_inv := Transform3D.IDENTITY

## El sedal enhebrado, en el MISMO espacio en el que se curva la caña (el del
## esqueleto, o el del pivote si el modelo llegara sin rig), mas lo que hace
## falta para pasarle por encima el doblez: la inversa de la pose en reposo de
## cada hueso, la transformada de piel ya compuesta de este frame, y el reparto
## de pesos (centros y luz entre huesos) que usa `tools/build_fishing_rod.py`.
var _hilo_esq := PackedVector3Array()
var _rest_inv: Array[Transform3D] = []
var _piel_cache: Array[Transform3D] = []
var _centros := PackedFloat32Array()
var _luz_hueso: float = 1.0
var _origen_esq := Vector3.ZERO
var _eje_esq := Vector3.UP

## El aparejo colgando de la puntera: posicion y velocidad en el espacio del
## PIVOTE. Ahi el pendulo sale gratis y correcto — cuando la caña se dobla, se
## inclina o la camara gira, es el OBJETIVO el que se mueve dentro de este
## espacio, asi que el anzuelo se queda atras solo, sin simular nada en mundo.
var _aparejo_pos := Vector3.ZERO
var _aparejo_vel := Vector3.ZERO
var _aparejo_colocado: bool = false

var _reel_p: AudioStreamPlayer3D
var _reel_pb: AudioStreamPlaybackPolyphonic
var _buzz_p: AudioStreamPlayer3D
var _cast_p: AudioStreamPlayer3D
var _haul_p: AudioStreamPlayer3D
var _world_p: AudioStreamPlayer3D
var _world_pb: AudioStreamPlaybackPolyphonic
var _ui_p: AudioStreamPlayer
var _ui_pb: AudioStreamPlaybackPolyphonic
var _mark: Label3D
var _hud: FishingHud

@onready var _tip: Node3D = $RodPivot/Tip
@onready var _rod_pivot: Node3D = $RodPivot
@onready var _bobber: MeshInstance3D = $Bobber
@onready var _line: MeshInstance3D = $Line
@onready var _line_mat := StandardMaterial3D.new()
## El sedal que va POR la caña (bobina -> anillas -> puntera -> bajante). Cuelga
## del pivote y no es `top_level` a proposito: dibujado en coordenadas de la
## caña sigue cada doblez en el mismo frame, mientras que en coordenadas de
## mundo se despegaria de las anillas cada vez que la camara gira rapido. El
## nodo tiene que quedarse SIN transform (los vertices ya vienen en su sitio).
@onready var _enhebrado: MeshInstance3D = $RodPivot/Enhebrado
@onready var _aparejo: Node3D = $RodPivot/Aparejo
## El MISMO anzuelo, colgado de la boya: echado el sedal, el aparejo esta ahi y
## no en tu mano. Cuelga de `Bobber` para heredarle la visibilidad — aparece al
## lanzar, se va al recoger y se queda a la deriva con ella tras una rotura, sin
## una sola linea que lo cablee.
@onready var _aparejo_agua: Node3D = $Bobber/Aparejo


## Objetivo de inclinacion lateral (radianes) del tira-y-afloja. Positivo =
## izquierda en pantalla. El pez arrastra hacia SU lado; cada tecla tira hacia
## el suyo (A = izquierda, D = derecha); la contra correcta se cancela y la
## caña queda centrada. Contrar MAL suma los dos tirones: el error se VE gordo.
static func lean_target_for(pull_dir: int, holding_left: bool, holding_right: bool,
		pull_strength: float) -> float:
	var lean: float = 0.0
	if pull_dir == FightModel.Pull.LEFT:
		lean += 0.26 * clampf(pull_strength * 1.6, 0.5, 1.0)
	elif pull_dir == FightModel.Pull.RIGHT:
		lean -= 0.26 * clampf(pull_strength * 1.6, 0.5, 1.0)
	if holding_left:
		lean += 0.2
	if holding_right:
		lean -= 0.2
	return lean


## El plan de toques falsos: 1-4, separados 0.5-1.5 s. Estatica para el test.
static func plan_nibbles(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for _i in rng.randi_range(1, 4):
		out.append(rng.randf_range(0.5, 1.5))
	return out


func _ready() -> void:
	position = view_offset
	rotation_degrees = view_angles_deg
	_player = get_node_or_null(player_path) as Player
	_camfx = get_parent() as CameraFeedback
	var modelo := _rod_pivot.get_node_or_null(^"Cania") as Node3D
	if modelo != null:
		modelo.rotation.y = deg_to_rad(model_roll_deg)
		_rotor = modelo.get_node_or_null(^"ReelRotor") as Node3D
		_handle = modelo.get_node_or_null(^"ReelHandle") as Node3D
		if _rotor != null:
			_rotor_base = _rotor.transform.basis
		if _handle != null:
			_handle_base = _handle.transform.basis
		_setup_doblez(modelo)
	# Escenas viejas o de captura sin tier asignado pescan con la de iniciacion:
	# el fallo seguro es la caña humilde, nunca una caña nula que reviente.
	if tier == null:
		tier = load(TIER_PATHS[0]) as RodTier
	_apply_tier()
	_rng.randomize()
	_rng_fx.randomize()
	_bobber.visible = false
	_bobber.top_level = true
	_aparejo_agua.top_level = true
	_line.top_level = true
	_line.mesh = ImmediateMesh.new()
	_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_mat.albedo_color = Color(0.9, 0.9, 0.85)
	_line.material_override = _line_mat
	# El sedal es UNO: el enhebrado comparte material con el tramo de fuera para
	# que el ambar->rojo de la tension corra por la caña entera (regla 8 — si el
	# hilo de dentro se quedara blanco, el aviso tendria dos versiones).
	_enhebrado.transform = Transform3D.IDENTITY
	_enhebrado.mesh = ImmediateMesh.new()
	_enhebrado.material_override = _line_mat
	cebo_cambiado.connect(_pintar_cebo)
	_pintar_cebo()
	_setup_audio()
	_setup_mark()
	_hud = FishingHud.new()
	add_child(_hud)
	if empezar_clavada:
		_clavar_al_arrancar.call_deferred()


func _setup_audio() -> void:
	_reel_p = AudioStreamPlayer3D.new()
	_reel_p.bus = &"Reel"
	_reel_p.stream = AudioStreamPolyphonic.new()
	_rod_pivot.add_child(_reel_p)
	_reel_p.play()
	_reel_pb = _reel_p.get_stream_playback() as AudioStreamPlaybackPolyphonic

	_buzz_p = AudioStreamPlayer3D.new()
	_buzz_p.bus = &"Reel"
	_buzz_p.stream = SfxLibrary.reel_buzz
	_buzz_p.volume_db = -60.0
	_rod_pivot.add_child(_buzz_p)

	# El latigazo del lanzamiento: sample propio y no polifonico — cuelga del
	# pivote, asi que sale de la caña que tienes en las manos y los compañeros
	# lo oyen desde donde estas. Entra bajo a proposito: viene a fondo de escala
	# y suena a 60 cm de la camara, y el que tiene que mandar es el chomp (el
	# climax de la picada), no el gesto que lo precede.
	_cast_p = AudioStreamPlayer3D.new()
	_cast_p.bus = &"SFX"
	_cast_p.stream = SfxLibrary.cast_whip
	_cast_p.volume_db = -9.0
	_rod_pivot.add_child(_cast_p)

	# La cama de "lo estoy trayendo": loop 3D que vive EN LA BOYA. Como la
	# distancia de la boya ES el progreso de la lucha, el forcejeo se acerca
	# solo segun ganas terreno — y la tripulacion oye desde donde. Arranca mudo
	# y entra/sale con fundido, igual que el buzz: un loop que corta en seco
	# hace click.
	_haul_p = AudioStreamPlayer3D.new()
	_haul_p.bus = &"SFX"
	_haul_p.stream = SfxLibrary.haul_loop
	_haul_p.volume_db = -60.0
	_haul_p.top_level = true
	add_child(_haul_p)

	# Sonidos del MUNDO (boya, splashes): posicional y top_level, para que los
	# compañeros oigan DONDE pica y donde lucha el pez.
	_world_p = AudioStreamPlayer3D.new()
	_world_p.bus = &"SFX"
	_world_p.stream = AudioStreamPolyphonic.new()
	_world_p.top_level = true
	add_child(_world_p)
	_world_p.play()
	_world_pb = _world_p.get_stream_playback() as AudioStreamPlaybackPolyphonic

	_ui_p = AudioStreamPlayer.new()
	_ui_p.bus = &"SFX"
	_ui_p.stream = AudioStreamPolyphonic.new()
	add_child(_ui_p)
	_ui_p.play()
	_ui_pb = _ui_p.get_stream_playback() as AudioStreamPlaybackPolyphonic


## El "!" sobre la boya: la señal coop mas barata del dossier (Stardew) — el
## compañero a 20 m que no oye tu audio posicional VE que te ha picado.
func _setup_mark() -> void:
	_mark = Label3D.new()
	_mark.text = "!"
	# Tamaño de cartel: tiene que leerse a 20 m por un compañero distraido.
	_mark.font = GameTypography.display_hud()
	_mark.font_size = 280
	_mark.pixel_size = 0.012
	_mark.modulate = Color(1.0, 0.9, 0.4)
	_mark.outline_size = 36
	_mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_mark.top_level = true
	_mark.visible = false
	add_child(_mark)


func _physics_process(delta: float) -> void:
	_update_deck_accel(delta)
	_freeze_left = maxf(_freeze_left - delta, 0.0)
	_silence_left = maxf(_silence_left - delta, 0.0)
	_snap_flash = maxf(_snap_flash - delta * 2.0, 0.0)

	match state:
		State.IDLE:
			# Con carga en brazos no hay caña: el click pasa a ser el boton de
			# lanzar del Portador. Soltar (o colgar) primero, pescar despues.
			if Input.is_action_just_pressed(&"grab") and _rod_input_ready():
				state = State.CASTING
				_charge = 0.0
		State.CASTING:
			_charge = minf(_charge + delta / CAST_CHARGE_SECONDS, 1.0)
			# Anticipacion controlada por el jugador: rumble debil creciente.
			_refresh_rumble(delta, 0.1 + _charge * 0.2, 0.0)
			if Input.is_action_just_released(&"grab"):
				# Si agarraste algo a mitad de la carga, la caña se guarda el
				# gesto: lanzar el sedal con un pez en brazos no es un combo.
				if _hands_free():
					_cast()
				else:
					state = State.IDLE
					_stop_rumble()
		State.WAITING:
			_wait_left -= delta
			_lap_sounds(delta)
			if Input.is_action_just_pressed(&"grab") and _rod_input_ready():
				_recall()
			elif _wait_left <= 0.0:
				_begin_nibbling()
		State.NIBBLING:
			_step_nibbling(delta)
		State.BITE:
			_bite_left -= delta
			if Input.is_action_just_pressed(&"grab") and _rod_input_ready():
				_hook()
			elif _bite_left <= 0.0:
				_flee(false) # se escapo sin castigo: la ventana es generosa
		State.FIGHT:
			_step_fight(delta)

	if _camfx != null:
		_camfx.set_tension(_tension_norm() if state == State.FIGHT else 0.0)

	_update_visuals(delta)


## Tension relativa al limite del sedal MONTADO: con una caña mejor, el mismo
## tiron chirria menos porque de verdad esta mas lejos de romper (regla 8).
func _tension_norm() -> float:
	return clampf(fight.tension / fight.max_tension(), 0.0, 1.0)


func _update_deck_accel(delta: float) -> void:
	var vy: float = 0.0
	if _player != null and _player.is_on_floor():
		vy = _player.get_platform_velocity().y
	var raw: float = (vy - _prev_platform_vy) / maxf(delta, 1e-5)
	_prev_platform_vy = vy
	deck_accel_y = lerpf(deck_accel_y, raw, clampf(8.0 * delta, 0.0, 1.0))


# =============================================================================
#  Lanzar y esperar
# =============================================================================

func _cast() -> void:
	var cam := get_viewport().get_camera_3d()
	var dist: float = lerpf(CAST_MIN_DIST, _cast_max_dist(), _charge)
	var fwd: Vector3 = -cam.global_transform.basis.z
	var flat := Vector2(fwd.x, fwd.z).normalized() * dist
	var origin := cam.global_position
	_cast_point = Vector2(origin.x, origin.z) + flat

	state = State.WAITING
	_wait_left = _rng.randf_range(8.0, 25.0) * clampf(1.0 - Ocean.fury * 0.06, 0.4, 1.0)
	# El cebo recorta la espera: es el multiplicador de piezas por salida (mas
	# ciclos en el mismo rato). La tirada del RNG se hace SIEMPRE antes, cebado
	# o no, para que poner cebo no desvie la secuencia de la partida (regla 4).
	var cebo_activo := cebo_puesto()
	if cebo_activo != null:
		_wait_left *= cebo_activo.espera_factor
	_bobber.visible = true
	_bobber.global_position = _tip.global_position
	_stop_rumble()

	# El latigazo del lanzamiento: FOV kick sutil (+4 grados) y el muelle de la
	# caña suelta la carga — el follow-through sale gratis del muelle.
	if _camfx != null:
		_camfx.kick_fov(4.0, 0.12, 0.0, 0.5)
	_bend_vel += 6.0
	if _cast_p != null and _cast_p.stream != null:
		# Pitch ±6% como todo one-shot del repo: dos lanzamientos identicos
		# suenan a boton de menu, no a caña. RNG global a proposito (regla 4):
		# esto es presentacion y puede divergir entre clientes sin consecuencia,
		# y `_rng` lleva la secuencia de la PARTIDA (espera, nibbles) — gastarle
		# tiradas desde el audio seria contaminar logica con adorno.
		_cast_p.pitch_scale = randf_range(0.94, 1.06)
		_cast_p.play()

	# Plop de caida donde aterriza la boya, con un vuelo corto visible.
	get_tree().create_timer(0.45).timeout.connect(func() -> void:
		if state == State.WAITING and _silence_left <= 0.0:
			_world_p.global_position = _bobber_rest_pos()
			SfxLibrary.play_varied(_world_pb, SfxLibrary.splashes, "splash", -14.0, 1.35))


func _bobber_rest_pos() -> Vector3:
	var pos := Vector3(_cast_point.x, 0.0, _cast_point.y)
	pos.y = Ocean.get_height(pos) + 0.05
	return pos


## El lap-lap de la boya en reposo: el fondo contra el que la picada sorprende.
func _lap_sounds(delta: float) -> void:
	_lap_cooldown -= delta
	if not _bobber.visible or _lap_cooldown > 0.0:
		return
	var vy: float = absf(_bobber.global_position.y - _prev_bobber_y) / maxf(delta, 1e-5)
	if vy > 0.35:
		_world_p.global_position = _bobber.global_position
		SfxLibrary.play_one(_world_pb, SfxLibrary.lap, -14.0)
		_lap_cooldown = _rng_fx.randf_range(0.5, 1.1)


# =============================================================================
#  La picada por capas: nibbles falsos -> mordisco garantizado
# =============================================================================

func _begin_nibbling() -> void:
	state = State.NIBBLING
	hooked_species = FishSpecies.choose(Ocean.fury, _rng, _cebo_sesgo())
	_nibble_delays = plan_nibbles(_rng)
	_nibble_index = 0
	_nibble_timer = _nibble_delays[0]


func _step_nibbling(delta: float) -> void:
	_nibble_dip = maxf(_nibble_dip - delta * 3.0, 0.0)
	_nibble_timer -= delta
	_lap_sounds(delta)

	# Clavar durante un toque FALSO = el pez huye. Nace el juego de nervios.
	# (Con las manos llenas o la caña en el soporte, el click no es un clavado:
	# el juego de nervios sigue solo, y si llega el mordisco sin caña en mano,
	# el pez se ira sin castigo — soltarla de las manos fue TU apuesta.)
	if Input.is_action_just_pressed(&"grab") and _rod_input_ready():
		_flee(true)
		return

	if _nibble_timer <= 0.0:
		if _nibble_index < _nibble_delays.size():
			_do_nibble()
			_nibble_index += 1
			_nibble_timer = _nibble_delays[_nibble_index - 1] * 0.7 + 0.4 \
				if _nibble_index < _nibble_delays.size() else _rng.randf_range(0.4, 0.9)
		else:
			_start_bite() # tras el ultimo falso, el mordisco es GARANTIZADO


## Un toque falso: SILENCIOSO (feedback del playtest: el plip sonaba a premio y
## confundia — la señal sonora queda reservada al mordisco real). El toque se
## lee en la boya que se hunde un 20% y el micro-cabeceo de la caña.
func _do_nibble() -> void:
	_nibble_dip = 1.0
	_bend_vel += 2.5
	# El rumble es el canal de la MANO: con la caña clavada no hay mano.
	if soporte == null:
		Input.start_joy_vibration(0, 0.25, 0.0, 0.1)


func _flee(punished: bool) -> void:
	# El pez se va: splash apagado y la sombra desaparece. Sin mas castigo que
	# la propia huida (y la verguenza, que en coop es el castigo real).
	_world_p.global_position = _bobber.global_position
	SfxLibrary.play_varied(_world_pb, SfxLibrary.splashes, "splash", -12.0 if punished else -16.0, 1.2)
	_recall()


func _start_bite() -> void:
	state = State.BITE
	# La ventana la decide DONDE esta la caña: en la mano es un clic, clavada es
	# cruzar la cubierta. Se fija aqui una sola vez — retomarla a mitad de la
	# picada no reinicia el reloj: la apuesta ya estaba hecha.
	_bite_left = BITE_WINDOW_SOPORTE if soporte != null else BITE_WINDOW
	if hooked_species.is_empty():
		hooked_species = FishSpecies.choose(Ocean.fury, _rng, _cebo_sesgo())
	# El pez se COME el cebo al morder, lo subas o te lo robe. Que perder el
	# pez cueste tambien el cebo es lo unico que hace de gastarlo una decision.
	_consumir_cebo()

	# EL PICO MULTIMODAL, todo el mismo frame (Stardew): chomp posicional EN la
	# boya, hundimiento total, tiron de la caña, doble pulso fuerte de rumble,
	# "!" sobre la boya, y punch-in de FOV como UNICO efecto de camara.
	_world_p.global_position = _bobber.global_position
	SfxLibrary.play_one(_world_pb, SfxLibrary.chomp, 0.0,
		clampf(1.3 - float(hooked_species[&"weight"]) * 0.012, 0.55, 1.3))
	_bend_vel += 5.0
	_mark.visible = true
	_mark.scale = Vector3.ONE * 0.2
	var tw := create_tween()
	tw.tween_property(_mark, "scale", Vector3.ONE * 1.25, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_mark, "scale", Vector3.ONE, 0.1)
	# Rumble, FOV y el flash del HUD son canales de PRIMERA PERSONA: con la
	# caña clavada el aviso es el del mundo (chomp 3D, "!", la caña doblandose
	# en la borda) — meterte un punch de camara por una caña que no sostienes
	# seria feedback mintiendo de canal.
	if soporte == null:
		Input.start_joy_vibration(0, 0.0, 0.9, 0.12)
		get_tree().create_timer(0.2).timeout.connect(func() -> void:
			if state == State.BITE and soporte == null:
				Input.start_joy_vibration(0, 0.0, 0.9, 0.12))
		if _camfx != null:
			_camfx.kick_fov(-3.0, 0.08, BITE_WINDOW, 0.3)
		_hud.show_bite()


func _hook() -> void:
	state = State.FIGHT
	fight.start(hooked_species, _rng, tier)
	_reel_rearm = true # recoger exige un clic NUEVO: clavar no es recoger
	_prev_pull = fight.pull_dir
	_mark.visible = false
	_hud.on_hooked()
	_hud.punch_arrow()
	_set_player_lock(true)


# =============================================================================
#  La lucha
# =============================================================================

func _step_fight(delta: float) -> void:
	var counter := FightModel.Pull.NONE
	if Input.is_action_pressed(&"move_left"):
		counter = FightModel.Pull.LEFT
	elif Input.is_action_pressed(&"move_right"):
		counter = FightModel.Pull.RIGHT

	# Acuse en el MISMO frame del input de contra: sacudida lateral + un click.
	if Input.is_action_just_pressed(&"move_left"):
		_ack_counter(-1.0)
	elif Input.is_action_just_pressed(&"move_right"):
		_ack_counter(1.0)

	if _reel_rearm and not Input.is_action_pressed(&"grab"):
		_reel_rearm = false
	var reeling := Input.is_action_pressed(&"grab") and not _reel_rearm
	# Lo ve la presentacion: el carrete gira con la MISMA señal con la que suena
	# la cama de recogida y avanza la lucha (regla 8: ningun canal va por libre).
	_reeling = reeling

	fight.step(delta, reeling, counter, deck_accel_y)
	var norm := _tension_norm()

	# Cambios de fase del pez: el tiron arranca con splash 3D EN la boya (la
	# tripulacion oye donde y cuanto lucha); la pausa es SILENCIO — la señal.
	if fight.pull_dir != _prev_pull:
		if fight.pull_dir != FightModel.Pull.NONE and _rng_fx.randf() < 0.6:
			_world_p.global_position = _bobber.global_position
			SfxLibrary.play_varied(_world_pb, SfxLibrary.splashes, "splash",
				-8.0 + float(hooked_species[&"pull"]) * 6.0, 1.15)
		_hud.punch_arrow() # el ojo va solo a la nueva instruccion
		_prev_pull = fight.pull_dir

	_hud.update_fight(fight.pull_dir, not fight.is_pulling(), norm,
		fight.progress, fight.is_spit_warning(), reeling)

	# --- acompañamiento fisico del tira-y-afloja ------------------------------
	var pull_str: float = float(hooked_species.get(&"pull", 0.3)) 		* (FightModel.TIRED_PULL_FLOOR + (1.0 - FightModel.TIRED_PULL_FLOOR) * fight.stamina)
	_lean_goal = lean_target_for(fight.pull_dir,
		Input.is_action_pressed(&"move_left"), Input.is_action_pressed(&"move_right"),
		pull_str)

	# EL PEZ ESCAPANDOSE SE SIENTE EN LA CAMARA: mientras corre con el sedal te
	# ARRASTRA hacia su lado (traslacion pura, 4.5 cm max). Con la contra bien
	# puesta el tiron cae a un tercio: recomponerte es literalmente contrar.
	if _camfx != null:
		if fight.is_pulling():
			var fish_side: float = 1.0 if fight.pull_dir == FightModel.Pull.LEFT else -1.0
			var countered := (fight.pull_dir == FightModel.Pull.LEFT 				and Input.is_action_pressed(&"move_right")) 				or (fight.pull_dir == FightModel.Pull.RIGHT 				and Input.is_action_pressed(&"move_left"))
			var tug: float = pull_str * (0.35 if countered else 1.0)
			# El tiron respira con el forcejeo del pez, no es un offset muerto.
			tug *= 1.0 + 0.3 * sin(Time.get_ticks_msec() * 0.009)
			_camfx.set_drag(Vector2(-fish_side * 0.055 * tug, -0.012 * tug))
		else:
			_camfx.set_drag(Vector2.ZERO)

	_haul_bed(delta, reeling)
	_click_train(delta, norm)
	_creak(delta, norm, counter)
	_fight_rumble(delta, norm)

	var cam := get_viewport().get_camera_3d()
	var origin := Vector2(cam.global_position.x, cam.global_position.z)
	# La distancia de la boya ES el progreso: recoger la acerca, y el pez
	# corriendo sin contra se la lleva — perder sedal se VE, no solo se oye.
	var target_dist: float = lerpf(_cast_max_dist(), 2.5, fight.progress)
	var dir_out := (_cast_point - origin).normalized()
	if dir_out == Vector2.ZERO:
		dir_out = Vector2.DOWN
	_cast_point = origin + dir_out * lerpf((_cast_point - origin).length(), target_dist,
		clampf(2.0 * delta, 0.0, 1.0))

	if fight.snapped:
		_on_snap()
	elif fight.escaped:
		_on_escape()
	elif fight.landed:
		_land()


func _ack_counter(side: float) -> void:
	_lateral_vel += side * 5.0
	SfxLibrary.play_varied(_reel_pb, SfxLibrary.reel_clicks, "click", -6.0)
	Input.start_joy_vibration(0, 0.2, 0.0, 0.05)


## La cama del forcejeo mientras traes al pez. Suena SOLO mientras recoges de
## verdad: si sonara tambien en las pausas dejaria de significar nada (regla 8,
## el mismo motivo por el que la pausa del pez es silencio). Cada entrada
## arranca en un punto distinto del loop — el jugador suelta y vuelve a apretar
## muchas veces por lucha, y empezar siempre por el mismo medio segundo delata
## el archivo.
func _haul_bed(delta: float, reeling: bool) -> void:
	if _haul_p == null or _haul_p.stream == null:
		return
	if reeling and not _haul_p.playing:
		_haul_p.play(randf() * maxf(_haul_p.stream.get_length() - 1.0, 0.0))
	_haul_p.global_position = _bobber.global_position
	_haul_p.volume_db = lerpf(_haul_p.volume_db, HAUL_DB if reeling else -60.0,
		clampf(10.0 * delta, 0.0, 1.0))
	if _haul_p.playing and not reeling and _haul_p.volume_db < -50.0:
		_haul_p.stop()


## El click del freno: la tension exacta, decodificable como un contador Geiger.
## Bajo el cruce, pulsos por acumulador; por encima, el loop de buzz pitcheado.
func _click_train(delta: float, norm: float) -> void:
	var rate := SfxLibrary.click_rate_for(norm)
	if norm > 0.85: # el zing: la linea saliendo a toda velocidad
		rate = lerpf(30.0, 60.0, (norm - 0.85) / 0.15)

	if rate >= BUZZ_CROSSOVER_HZ:
		if not _buzz_p.playing:
			_buzz_p.play()
		_buzz_p.pitch_scale = rate / 40.0
		_buzz_p.volume_db = lerpf(_buzz_p.volume_db, -6.0, clampf(10.0 * delta, 0.0, 1.0))
	else:
		_buzz_p.volume_db = lerpf(_buzz_p.volume_db, -60.0, clampf(10.0 * delta, 0.0, 1.0))
		if _buzz_p.playing and _buzz_p.volume_db < -50.0:
			_buzz_p.stop()
		if rate > 0.0:
			_click_cooldown -= delta
			if _click_cooldown <= 0.0:
				SfxLibrary.play_varied(_reel_pb, SfxLibrary.reel_clicks, "click",
					-4.0, 1.0 + 0.2 * norm)
				_click_cooldown = (1.0 / rate) * _rng_fx.randf_range(0.85, 1.15)


## El crujido pre-rotura (stick-slip): la rampa que convierte la rotura en
## culpa propia. Tambien cruje al contrar en direccion equivocada.
func _creak(delta: float, norm: float, counter: FightModel.Pull) -> void:
	var wrong := fight.pull_dir != FightModel.Pull.NONE and counter == fight.pull_dir
	if norm < 0.7 and not wrong:
		return
	_creak_cooldown -= delta
	if _creak_cooldown > 0.0:
		return
	var t: float = clampf((norm - 0.7) / 0.3, 0.0, 1.0)
	var creak_rate: float = lerpf(4.0, 28.0, t) if norm >= 0.7 else 8.0
	# Ganancia minima garantizada por encima del 80%: es el aviso que sustituye
	# al rumble para quien juega sin mando.
	var gain: float = -10.0 + t * 6.0
	SfxLibrary.play_varied(_reel_pb, SfxLibrary.creak_pulses, "creak", gain, 1.0 + 0.3 * norm)
	_creak_cooldown = (1.0 / creak_rate) * _rng_fx.randf_range(0.6, 1.4)


## Regla Sea of Thieves: vibra solo cuando algo va mal. Pausas = silencio total.
func _fight_rumble(delta: float, norm: float) -> void:
	if fight.pull_dir == FightModel.Pull.NONE and norm < 0.5:
		_stop_rumble()
		return
	_refresh_rumble(delta, norm * 0.5, clampf((norm - 0.7) / 0.3, 0.0, 1.0) * 0.8)


func _refresh_rumble(delta: float, weak: float, strong: float) -> void:
	_rumble_refresh -= delta
	if _rumble_refresh <= 0.0:
		Input.start_joy_vibration(0, weak, strong, 0.15)
		_rumble_refresh = 0.1


func _stop_rumble() -> void:
	Input.stop_joy_vibration(0)
	_rumble_refresh = 0.0


# =============================================================================
#  Rotura y captura: los dos eventos maximos
# =============================================================================

func _on_snap() -> void:
	# Mismo frame: snap + CORTE en seco de clicks/creak/rumble + hitstop local
	# de 100 ms + trauma. Despues, 300 ms de casi-silencio: el hueco ES el golpe.
	SfxLibrary.play_one(_reel_pb, SfxLibrary.snap, 2.0)
	_buzz_p.stop()
	_buzz_p.volume_db = -60.0
	Input.start_joy_vibration(0, 0.0, 1.0, 0.2)
	get_tree().create_timer(0.25).timeout.connect(_stop_rumble)
	_freeze_left = 0.1
	_silence_left = 0.3
	if _camfx != null:
		_camfx.add_trauma(0.6)
	# PERMANENCIA (Nijman): el compañero ve QUE paso sin haberlo mirado — un
	# trozo de sedal colgando de la caña y la boya perdida, a la deriva.
	_remnant_left = 6.0
	_adrift_left = 8.0
	_snap_flash = 1.0
	_hud.show_result("¡SEDAL ROTO!", Color(1.0, 0.3, 0.25))
	line_snapped.emit()
	_recall(true)


## El pez escupe el anzuelo (sedal flojo sostenido). Fallo BLANDO: splash de
## huida y el sedal vuelve muerto — sin latigazo, sin trauma: la culpa ya la
## repartio el aviso de 1.2 s (comba exagerada + boya derivando).
func _on_escape() -> void:
	_world_p.global_position = _bobber.global_position
	SfxLibrary.play_varied(_world_pb, SfxLibrary.splashes, "splash", -6.0, 1.1)
	Input.start_joy_vibration(0, 0.3, 0.0, 0.12)
	get_tree().create_timer(0.2).timeout.connect(_stop_rumble)
	_hud.show_result("Se escapó...", Color(0.65, 0.7, 0.75))
	fish_escaped.emit()
	_recall()


func _land() -> void:
	var water := _bobber_rest_pos()
	var to_player := _player.global_position - water
	var flat := Vector3(to_player.x, 0, to_player.z)
	var vel := flat * 1.1 + Vector3.UP * (4.5 + flat.length() * 0.45)
	# El tumbo del pez es PRESENTACION: sale del RNG de efectos, no del de la
	# partida. Si gastara tiradas de `_rng`, cualquier cambio futuro en el
	# audio o el feel desplazaria la secuencia de especies (regla 4).
	var giro := Vector3(_rng_fx.randf_range(-6, 6), _rng_fx.randf_range(-6, 6),
		_rng_fx.randf_range(-6, 6))

	# En red el cuerpo lo pare el HOST y llega en 80-150 ms — o sea, DENTRO
	# del hueco de 250 ms que el climax ya tenia reservado para el jingle. La
	# latencia se esconde en un agujero que el diseño ya habia hecho.
	#
	# Y la ESPECIE viaja decidida: la eligio este cliente al clavar y lleva
	# treinta segundos enseñandola en el HUD. Si el host la re-sorteara, el
	# jugador habria peleado media pelea contra un Fletan para sacar una
	# Sardina — feedback que mintio (regla 8). El host ratifica, no re-decide.
	var fish: Fish = null
	if not Net.pedir_pez(FishSpecies.SPECIES.find(hooked_species), water, vel, giro):
		fish = fish_scene.instantiate()
		get_tree().current_scene.add_child(fish)
		fish.setup(hooked_species)
		fish.global_position = water
		fish.linear_velocity = vel
		fish.angular_velocity = giro

	# El climax encadenado: freeze de 70 ms al romper el agua -> splash 3D ->
	# jingle a +250 ms (nunca solapado) -> el thud lo pone el pez al aterrizar.
	# NO espera al pez: es tuyo y suena ya.
	_freeze_left = 0.07
	_world_p.global_position = water
	SfxLibrary.play_varied(_world_pb, SfxLibrary.splashes, "splash", 0.0)
	var valor := int(hooked_species.get(&"value", 0))
	var rarity: int = 2 if valor >= 400 else (1 if valor >= 90 else 0)
	get_tree().create_timer(0.25).timeout.connect(func() -> void:
		SfxLibrary.play_one(_ui_pb, SfxLibrary.jingles[rarity], -4.0))
	# Rumble alegre: doble pulso debil (canal haptico del climax, del critico).
	Input.start_joy_vibration(0, 0.4, 0.0, 0.1)
	get_tree().create_timer(0.15).timeout.connect(func() -> void:
		Input.start_joy_vibration(0, 0.4, 0.0, 0.1))
	if _camfx != null:
		_camfx.add_trauma(0.35)
	_hud.show_result("¡%s  ·  %.0f kg!" % [String(hooked_species.get(&"name", "?")),
		float(hooked_species.get(&"weight", 0.0))], Color(1.0, 0.85, 0.35))

	if fish != null:
		fish_landed.emit(fish)
	_recall()


func _recall(keep_adrift: bool = false) -> void:
	state = State.IDLE
	hooked_species = {}
	if not keep_adrift:
		_bobber.visible = false
	(_line.mesh as ImmediateMesh).clear_surfaces()
	_mark.visible = false
	_hud.hide_all()
	_nibble_dip = 0.0
	if _camfx != null:
		_camfx.set_drag(Vector2.ZERO)
	_stop_rumble()
	_buzz_p.stop()
	_buzz_p.volume_db = -60.0
	# La cama de recogida muere con la lucha: se acabo el pez, se acabo el
	# forcejeo. Pasa por aqui la rotura, la escupida y la captura.
	if _haul_p != null:
		_haul_p.stop()
		_haul_p.volume_db = -60.0
	_set_player_lock(false)


func _set_player_lock(locked: bool) -> void:
	if _player != null:
		_player.hands_busy = locked


## Con algo en las manos no se toca la caña: primero soltalo o colgalo. Es el
## contrato del porteo (docs/PORTEO.md) — el deficit de manos es el diseño.
func _hands_free() -> bool:
	return _player == null or _player.hands_used == 0


## La caña solo escucha el click con las manos libres Y en la mano. Clavada en
## el soporte pesca sola (espera, nibbles, mordisco), pero no se maneja a
## distancia: para clavar el pez hay que RETOMARLA (E en el soporte), y la
## ventana de picada no espera a nadie.
func _rod_input_ready() -> bool:
	return soporte == null and _hands_free()


# =============================================================================
#  El soporte de borda: la caña clavada pesca sola
# =============================================================================

## Las manos ocupadas por el PORTEO: ahi la caña se guarda de la vista (deuda
## declarada de PORTEO.md, saldada aqui). Durante la LUCHA las manos estan
## "llenas" pero de la propia caña (input_captured): ahi se ve, faltaria mas.
func _manos_ocupadas() -> bool:
	return _player != null and _player.hands_used > 0 and not _player.input_captured


## De donde sale el sedal: de la punta de la caña, este donde este.
##
## Antes habia que preguntarle al soporte por SU punta, porque el soporte tenia
## su propia caña de primitivas. Ya no: la caña clavada es ESTA caña, movida al
## barco, asi que hay una sola punta y no puede haber dos que no coincidan.
func _tip_pos() -> Vector3:
	return _tip.global_position


func esta_clavada() -> bool:
	return soporte != null


## Clavar la caña en un soporte de borda: libera las manos sin dejar de
## pescar. Solo en reposo o con el sedal echado — a mitad de un gesto (carga,
## picada, lucha) la caña es tuya o de nadie.
##
## La caña no se "esconde y se sustituye": el pivote entero SE MUDA al soporte,
## con su modelo, su sedal enhebrado, su aparejo y sus altavoces del carrete. Es
## la misma caña vista desde fuera — antes eran dos (el viewmodel escondido y un
## palo gris en la borda), y dos siempre acaban contando cosas distintas.
func clavar_en(nuevo_soporte: Node3D) -> bool:
	if soporte != null or nuevo_soporte == null:
		return false
	if not (state == State.IDLE or state == State.WAITING or state == State.NIBBLING):
		return false
	soporte = nuevo_soporte
	if soporte.has_method(&"ocupar"):
		soporte.call(&"ocupar")
	# La caña se muda a un nodo que NO es nuestro y puede morir antes que
	# nosotros (el barco entero, sin ir mas lejos). Enterarse a tiempo es la
	# diferencia entre recuperarla y quedarse con un puntero muerto al que le
	# escribes `visible` sesenta veces por segundo.
	soporte.tree_exiting.connect(_soporte_se_va, CONNECT_ONE_SHOT)
	var cuna: Node3D = soporte
	if soporte.has_method(&"cuna"):
		cuna = soporte.call(&"cuna") as Node3D
	_mudar_pivote(cuna)
	_stop_rumble()
	return true


## Retomarla del soporte. Si hay picada en curso, la ventana sigue corriendo:
## retomar y clavar el pez en el tiempo que queda ES el minijuego de haberla
## dejado sola.
func retomar() -> void:
	if soporte == null:
		return
	if soporte.has_method(&"liberar"):
		soporte.call(&"liberar")
	if soporte.tree_exiting.is_connected(_soporte_se_va):
		soporte.tree_exiting.disconnect(_soporte_se_va)
	soporte = null
	_mudar_pivote(self)


## El soporte (o el barco entero) se va del arbol con nuestra caña dentro. Pasa
## en los arneses que montan y desmontan barcos, y pasaria en cualquier
## desmontaje parcial del mundo. `tree_exiting` llega ANTES de que se lo lleven,
## asi que da tiempo a recuperarla: la caña vuelve a la mano.
func _soporte_se_va() -> void:
	if soporte == null:
		return
	soporte = null
	_mudar_pivote(self)


## Muda el pivote de la caña a otro padre conservando SU pose local (no la
## global): en la mano cuelga del viewmodel, clavada cuelga de la cuna del
## soporte, y en los dos sitios la pose que vale es la que escriben el doblez y
## el muelle cada frame. El brazo de primera persona se queda quieto donde
## esta —cuelga del pivote— y por eso se apaga en cuanto la caña no es tuya.
func _mudar_pivote(destino: Node) -> void:
	if _rod_pivot == null or not is_instance_valid(_rod_pivot):
		return
	var padre := _rod_pivot.get_parent()
	if padre == destino:
		return
	# A mano y no con `reparent`: esto tiene que funcionar tambien cuando la
	# caña se esta yendo del arbol (ver `_exit_tree`), y ahi `reparent` no vale.
	if padre != null:
		padre.remove_child(_rod_pivot)
	destino.add_child(_rod_pivot)
	_rod_pivot.position = Vector3.ZERO
	_rod_pivot.rotation = Vector3.ZERO
	_aparejo_colocado = false


## Busca un soporte libre en el barco y se clava en el.
##
## Es lo que hace que la partida empiece con la caña EN EL BARCO y no en la mano
## (decision del 24-ago-2026): la caña es un aparejo del pesquero, no una
## extremidad. Se difiere un frame porque el mundo todavia se esta montando
## cuando la caña despierta.
func _clavar_al_arrancar() -> void:
	if soporte != null or not is_inside_tree():
		return
	var raiz := get_tree().current_scene
	if raiz == null:
		return
	for s: Node in raiz.find_children("*", "SoporteCania", true, false):
		if s.has_method(&"libre") and not s.call(&"libre"):
			continue
		if clavar_en(s as Node3D):
			return


# =============================================================================
#  El cebo: compra tiempo y atencion, nunca peces que el mar no da
# =============================================================================

## El cebo puesto AHORA, o null si el anzuelo va desnudo. Las cargas mandan:
## un tipo sin cargas es exactamente lo mismo que no llevar cebo.
func cebo_puesto() -> TipoCebo:
	return cebo if cebo_cargas > 0 else null


func _cebo_sesgo() -> float:
	var c := cebo_puesto()
	return c.sesgo if c != null else 0.0


func _consumir_cebo() -> void:
	if cebo_cargas > 0:
		cebo_cargas -= 1
		cebo_cambiado.emit()


## Cebar la caña desde el cubo. Devuelve cuantas cargas se han cogido de
## verdad, para que el cubo descuente EXACTAMENTE eso (cambiar de cebo tira lo
## que quedaba puesto: no se mezclan masilla y cebo vivo en el mismo anzuelo).
func cebar(tipo: TipoCebo, disponibles: int) -> int:
	if tipo == null or disponibles <= 0:
		return 0
	if tipo != cebo:
		cebo = tipo
		cebo_cargas = 0
	var cogidas: int = mini(CEBO_CARGAS_MAX - cebo_cargas, disponibles)
	if cogidas <= 0:
		return 0
	cebo_cargas += cogidas
	cebo_cambiado.emit()
	return cogidas


# =============================================================================
#  El aparejo montado (tiers de caña)
# =============================================================================

func _cast_max_dist() -> float:
	return CAST_MAX_DIST * (tier.cast_factor if tier != null else 1.0)


## Monta otra caña. La lucha en curso NO cambia de sedal: FightModel copio los
## numeros al clavar — cambiar de aparejo con el pez enganchado seria trampa.
func set_tier(next: RodTier) -> void:
	if next == null:
		return
	tier = next
	_apply_tier()


## Cicla el arbol de aparejos (herramienta de debug/validacion, tecla C en el
## HUD). Solo con la caña en reposo, por el mismo contrato que set_tier.
func cycle_tier() -> void:
	if state != State.IDLE:
		return
	var index := TIER_PATHS.find(tier.resource_path if tier != null else "")
	set_tier(load(TIER_PATHS[(index + 1) % TIER_PATHS.size()]) as RodTier)


## La mejora se VE (regla del arbol: piezas, no "+5%"): la empuñadura DELANTERA
## toma el color del tier.
##
## Es la de delante y no la de atras porque el brazo del viewmodel es una
## capsula de 7 cm de radio que se traga todo lo que quede por detras de la
## mano: pintar la trasera era pintar algo que el jugador no ve nunca. La malla
## se llama `Grip` dentro del GLB (`tools/build_fishing_rod.py`), asi que se
## busca en profundidad y no como hijo directo del pivote.
func _apply_tier() -> void:
	if tier == null:
		return
	var grip := _rod_pivot.find_child("Grip", true, false) as MeshInstance3D
	if grip == null:
		return
	# Un GLB trae su material en la malla, no como override: sin este respaldo
	# el tintado se apagaria EN SILENCIO al cambiar de primitivas a arte propio.
	var base: Material = grip.get_surface_override_material(0)
	if base == null and grip.mesh != null:
		base = grip.mesh.surface_get_material(0)
	var mat := base as StandardMaterial3D
	if mat != null:
		mat = mat.duplicate()
		mat.albedo_color = tier.accent_color
		grip.set_surface_override_material(0, mat)


## Cachea el rig del doblez: los huesos, el eje sobre el que curva cada uno, y
## las dos conversiones de espacio que hacen falta para saber DONDE acaba la
## punta cuando el cuerpo se arquea.
##
## Todo esto es fijo (la caña rueda dentro del pivote una sola vez y el
## esqueleto cuelga del modelo), asi que se calcula aqui y no cada frame.
func _setup_doblez(modelo: Node3D) -> void:
	# El sedal enhebrado se cachea SIEMPRE, con rig o sin el: una caña tiesa
	# tambien tiene hilo. Sin esqueleto los puntos se quedan en el espacio del
	# pivote y `_piel()` los devuelve tal cual (`_esq_a_pivote` es la identidad).
	for punto in ENHEBRADO:
		_hilo_esq.append(modelo.transform * punto)

	var encontrados := modelo.find_children("*", "Skeleton3D", true, false)
	if encontrados.is_empty():
		return
	_skel = encontrados[0] as Skeleton3D
	for i in BEND_BONE_WEIGHTS.size():
		var idx := _skel.find_bone("Cania_%d" % i)
		if idx < 0:
			# Modelo viejo o rig renombrado: mejor caña tiesa que caña rota.
			_skel = null
			return
		_huesos.append(idx)

	_esq_a_pivote = _rod_pivot.global_transform.affine_inverse() * _skel.global_transform
	var a_esqueleto := _esq_a_pivote.affine_inverse()
	# El doblez rigido es un giro sobre el eje X del pivote. Los huesos tienen
	# que curvarse sobre ESE MISMO eje o la caña se doblaria hacia un lado.
	var eje_esq := (a_esqueleto.basis * Vector3.RIGHT).normalized()
	for idx in _huesos:
		var rest := _skel.get_bone_global_rest(idx)
		_eje_hueso.append((rest.basis.inverse() * eje_esq).normalized())
	# La punta, en espacio del esqueleto y en reposo. Con la pose del ultimo
	# hueso encima sale donde esta la punta AHORA — la misma cuenta que hace la
	# GPU al deformar la malla, sin duplicar ninguna formula.
	_punta_esq = a_esqueleto * Vector3(0.0, _tip.position.y, 0.0)
	_rest_punta_inv = _skel.get_bone_global_rest(_huesos[_huesos.size() - 1]).affine_inverse()

	# Y el reparto de pesos, para poder curvar CUALQUIER punto de la caña (las
	# anillas por las que pasa el sedal) y no solo la punta. Los huesos son una
	# cadena de tramos iguales, asi que el centro de cada uno cae a media luz de
	# su cabeza: la misma cuenta que hace el generador al pesar los vertices.
	for i in _huesos.size():
		_rest_inv.append(_skel.get_bone_global_rest(_huesos[i]).affine_inverse())
		_piel_cache.append(Transform3D.IDENTITY)
	_origen_esq = _skel.get_bone_global_rest(_huesos[0]).origin
	var segundo := _skel.get_bone_global_rest(_huesos[1]).origin - _origen_esq
	_luz_hueso = maxf(segundo.length(), 1e-5)
	_eje_esq = segundo / _luz_hueso
	for i in _huesos.size():
		_centros.append((float(i) + 0.5) * _luz_hueso)
	for i in _hilo_esq.size():
		_hilo_esq[i] = a_esqueleto * _hilo_esq[i]


## Donde acaba un punto de la caña cuando el cuerpo se arquea.
##
## No es una aproximacion: es el MISMO skinning que hace la GPU — mezcla lineal
## con los pesos de sombrero que reparte `tools/build_fishing_rod.py`, cada
## vertice entre los dos huesos mas cercanos. Por eso el sedal enhebrado no se
## despega de las anillas ni con el doblez al maximo, y por eso sigue cuadrando
## si mañana cambian los pesos o el numero de huesos: la formula vive en un solo
## sitio conceptual (el generador) y aqui se replica entera, no a ojo.
func _piel(p_esq: Vector3) -> Vector3:
	if _skel == null or _piel_cache.is_empty():
		return p_esq
	var t: float = (p_esq - _origen_esq).dot(_eje_esq)
	# Por debajo del primer hueso empieza el hierro: mango, portacarretes y
	# carrete se quedaron FUERA del rig a proposito (una pieza rigida que se
	# estira delata el truco antes que nada), asi que la salida de la bobina no
	# se curva — se queda donde el carrete la deja.
	if t < 0.0:
		return p_esq
	var suma := Vector3.ZERO
	var total: float = 0.0
	for i in _piel_cache.size():
		var peso: float = maxf(0.0, 1.0 - absf(t - _centros[i]) / _luz_hueso)
		if peso <= 0.0:
			continue
		total += peso
		suma += peso * (_piel_cache[i] * p_esq)
	if total <= 1e-6:
		# Por debajo del primer hueso o por encima del ultimo: pegado al
		# extremo, sin repartir (otra vez, igual que el generador).
		var i: int = 0 if t < _centros[0] else _piel_cache.size() - 1
		return _piel_cache[i] * p_esq
	return suma / total


## Reparte el doblez entre la muñeca (girar la caña entera) y el cuerpo
## (curvarse), y deja el nodo `Tip` donde el sedal tiene que nacer.
##
## Es lo unico que mueve `_rod_pivot.rotation.x`: quien quiera añadir temblor o
## latigazo, que lo sume DESPUES de llamar aqui.
func _aplicar_doblez(bend: float) -> void:
	if _skel == null:
		_rod_pivot.rotation.x = -bend
		return
	_rod_pivot.rotation.x = -bend * BEND_RIGID_SHARE
	var curva := bend * (1.0 - BEND_RIGID_SHARE) * BEND_CURVE_GAIN
	for i in _huesos.size():
		_skel.set_bone_pose_rotation(_huesos[i],
			Quaternion(_eje_hueso[i], -curva * BEND_BONE_WEIGHTS[i]))
	# La punta la dice el HUESO, no una copia de la curva: si mañana cambian los
	# pesos o el numero de huesos, el sedal sigue saliendo de donde acaba la
	# caña. Se escribe en local (el pivote ya gira por su cuenta).
	var piel := _skel.get_bone_global_pose(_huesos[_huesos.size() - 1]) * _rest_punta_inv
	_tip.position = _esq_a_pivote * (piel * _punta_esq)
	# Y la piel de TODOS los huesos, compuesta una sola vez por frame: el sedal
	# pasa por ocho puntos, y recomponerla en cada uno seria pagarla ocho veces.
	for i in _piel_cache.size():
		_piel_cache[i] = _skel.get_bone_global_pose(_huesos[i]) * _rest_inv[i]


## El carrete gira mientras recoges, y solo mientras recoges.
##
## Es la unica pieza movil de la caña, o sea el unico sitio donde el jugador ve
## lo que estan haciendo sus manos: sin esto se spamea el clic y el aparejo se
## queda quieto, que es justo la sensacion de "el juego no me esta oyendo". El
## eje de cada pieza se compone sobre su pose de fabrica y en el espacio del
## PADRE (la manivela sale del GLB con su propia rotacion; girarla por su eje
## local la mandaria de paseo).
func _spin_reel(delta: float) -> void:
	if not _reeling or state != State.FIGHT:
		return
	var factor: float = tier.reel_factor if tier != null else 1.0
	_reel_angle += TAU * REEL_TURNS_PER_SECOND * factor * delta
	if _handle != null:
		_handle.transform.basis = Basis(Vector3.RIGHT, _reel_angle) * _handle_base
	if _rotor != null:
		_rotor.transform.basis = Basis(Vector3.UP, _reel_angle * REEL_GEAR_RATIO) * _rotor_base


func _exit_tree() -> void:
	_stop_rumble()
	# Si la caña se va del mundo estando clavada —un tripulante que se
	# desconecta, sin ir mas lejos— hay que barrer detras: el soporte se queda
	# ocupado por un fantasma que nadie puede liberar, y el pivote (modelo,
	# sedal, aparejo y altavoces del carrete) sigue vivo colgado del barco. Es
	# el mismo cuidado que la bomba tiene con quien se va de la estacion.
	#
	# Se corta y se libera en vez de re-adoptarlo: aqui el arbol se esta
	# desmontando y no es sitio para andar añadiendo hijos.
	if soporte != null and is_instance_valid(soporte) and soporte.has_method(&"liberar"):
		soporte.call(&"liberar")
	if _rod_pivot != null and is_instance_valid(_rod_pivot):
		var padre := _rod_pivot.get_parent()
		if padre != null and padre != self:
			padre.remove_child(_rod_pivot)
			_rod_pivot.queue_free()
			_rod_pivot = null
			set_physics_process(false)


# =============================================================================
#  Visual: la caña ES la interfaz
# =============================================================================

func _update_visuals(delta: float) -> void:
	if _rod_pivot == null or not is_instance_valid(_rod_pivot):
		return
	_prev_bobber_y = _bobber.global_position.y

	# La caña se guarda sola del viewmodel (clavada o porteando); la boya, el
	# sedal y el "!" son top_level y siguen viviendo en el mundo. El brazo
	# cuelga del pivote, asi que se guarda con ella.
	# Clavada, la caña vive en el barco y se ve desde cubierta; en la mano, se
	# guarda si el porteo te ocupa las manos. El brazo de primera persona solo
	# existe cuando la caña es TUYA: clavada, el que se dobla es el aparejo del
	# barco, y un brazo saliendo del soporte seria un fantasma.
	var en_mano: bool = soporte == null
	_rod_pivot.visible = not (en_mano and _manos_ocupadas())
	if _player != null:
		_player.mostrar_brazo(en_mano)

	# Hitstop LOCAL: la presentacion se congela (la camara y el raton JAMAS).
	if _freeze_left > 0.0:
		_aplicar_doblez(_bend)
		_rod_pivot.rotation.x += sin(Time.get_ticks_msec() * 0.08) * 0.01
		_draw_line()
		return

	_spin_reel(delta)

	# Muelle sub-amortiguado (K=120, D=12): la caña tiene masa, no un lerp.
	# El follow-through al soltar tension sale gratis: 1-2 oscilaciones.
	var target: float = 0.0
	match state:
		State.CASTING:
			target = -_charge * 0.5
		State.NIBBLING:
			target = _nibble_dip * 0.12
		State.BITE:
			target = 0.45 + sin(Time.get_ticks_msec() * 0.03) * 0.15
		State.FIGHT:
			# Exagerar mas de lo fisicamente creible (low-poly lo tolera) y
			# escalar con el peso: el compañero lee "es gordo" a 20 m.
			var weight_scale: float = 1.0 + float(hooked_species.get(&"weight", 2.0)) * 0.004
			target = clampf(fight.tension, 0.0, 1.3) * 0.75 * weight_scale
			if fight.is_warning():
				target += sin(Time.get_ticks_msec() * 0.09) * 0.08
	_bend_vel += ((target - _bend) * 120.0 - _bend_vel * 12.0) * delta
	_bend += _bend_vel * delta
	_lateral_vel += ((0.0 - _lateral) * 140.0 - _lateral_vel * 10.0) * delta
	_lateral += _lateral_vel * delta
	# El lean persigue su objetivo con muelle propio (mas blando que el kick):
	# el forcejeo se ve pesado, no electrico.
	if state != State.FIGHT:
		_lean_goal = 0.0
	_lean_vel += ((_lean_goal - _lean) * 90.0 - _lean_vel * 11.0) * delta
	_lean += _lean_vel * delta

	_aplicar_doblez(_bend)
	_rod_pivot.rotation.z = _lateral * 0.03 + _lean
	# La caña ADEMAS se desplaza hacia el lado del forcejeo: manos y mango se
	# van con ella — el acompañamiento que se ve incluso sin mirar la punta.
	_rod_pivot.position.x = _lean * 0.24
	if _snap_flash > 0.0:
		_rod_pivot.rotation.x += _snap_flash * sin(_snap_flash * 40.0) * 0.3

	# El sedal cambia de color con la tension real: neutro -> ambar (70%) ->
	# rojo (90%). Siempre en el centro de la mirada, y visible para el de al lado.
	var norm := _tension_norm() if state == State.FIGHT else 0.0
	var line_col := Color(0.9, 0.9, 0.85)
	if norm > 0.7:
		line_col = Color(0.95, 0.75, 0.25).lerp(Color(0.95, 0.2, 0.15),
			clampf((norm - 0.9) / 0.1, 0.0, 1.0)) if norm > 0.9 \
			else Color(0.9, 0.9, 0.85).lerp(Color(0.95, 0.75, 0.25),
			clampf((norm - 0.7) / 0.2, 0.0, 1.0))
	_line_mat.albedo_color = line_col

	# La boya.
	if _bobber.visible:
		if _adrift_left > 0.0:
			# Perdida: se queda cabalgando la ola donde rompio el sedal.
			_adrift_left -= delta
			var drift := _bobber_rest_pos()
			_bobber.global_position = _bobber.global_position.lerp(drift, clampf(3.0 * delta, 0, 1))
			if _adrift_left <= 0.0:
				_bobber.visible = false
		else:
			var pos := _bobber_rest_pos()
			match state:
				State.NIBBLING:
					pos.y -= _nibble_dip * 0.12 # 15-25% hundida: toque falso
				State.BITE:
					pos.y -= 0.3 + sin(Time.get_ticks_msec() * 0.02) * 0.1 # TODA
				State.FIGHT:
					if fight.is_pulling():
						var side := 1.0 if fight.pull_dir == FightModel.Pull.RIGHT else -1.0
						pos.x += side * sin(Time.get_ticks_msec() * 0.008) * 0.6
					elif fight.is_spit_warning():
						# La boya deriva sin rumbo: el pez se esta soltando.
						pos.x += sin(Time.get_ticks_msec() * 0.003) * 0.9
						pos.z += cos(Time.get_ticks_msec() * 0.0025) * 0.9
				State.WAITING, State.CASTING, State.IDLE:
					pass
			# La picada tira ACELERANDO (algo vivo), la espera flota suave.
			var speed: float = 14.0 if state == State.BITE else 8.0
			_bobber.global_position = _bobber.global_position.lerp(pos, clampf(speed * delta, 0, 1))

	_colocar_aparejo_agua()

	if _mark.visible:
		_mark.global_position = _bobber.global_position + Vector3.UP * 1.1

	_mover_aparejo(delta)
	_draw_line()


## Donde muere el sedal EN la caña: el ultimo aro (la puntera), ya arqueado.
##
## No es `Tip`: la puntera esta un centimetro fuera del eje y es por donde sale
## el hilo de verdad. `Tip` sigue siendo el ancla del tramo que va al mundo —
## ese esta jugado en playtest y no se toca.
func _punta_hilo() -> Vector3:
	if _hilo_esq.is_empty():
		return _tip.position
	return _esq_a_pivote * _piel(_hilo_esq[_hilo_esq.size() - 1])


## El aparejo en la mano: un pendulo colgado de la puntera.
##
## Es lo que convierte la caña de atrezo en herramienta. Al andar, al girar la
## camara y al cargar el lanzamiento, el anzuelo se queda atras y vuelve solo:
## el objetivo (la vertical de la punta, 30 cm por debajo) se mueve DENTRO del
## espacio del pivote y el muelle lo persigue. La constante es `g / largo`, o
## sea el periodo real de un pendulo de esta longitud — no un numero a ojo.
##
## Tras una rotura no hay aparejo que colgar durante los 6 s del trozo de sedal:
## perder el pez se lleva TAMBIEN el anzuelo, y volver a verlo es la señal de
## que has vuelto a montar.
func _mover_aparejo(delta: float) -> void:
	var en_mano: bool = (state == State.IDLE or state == State.CASTING) \
		and _remnant_left <= 0.0
	_aparejo.visible = en_mano
	if not en_mano:
		_aparejo_colocado = false
		return

	var punta := _punta_hilo()
	var abajo: Vector3 = (_rod_pivot.global_transform.basis.inverse() * Vector3.DOWN).normalized()
	var objetivo: Vector3 = punta + abajo * APAREJO_LARGO
	if not _aparejo_colocado:
		# Al retomar la caña (o en el primer frame) el anzuelo aparece donde
		# cuelga, no volando desde el origen del pivote.
		_aparejo_colocado = true
		_aparejo_pos = objetivo
		_aparejo_vel = Vector3.ZERO
	_aparejo_vel += ((objetivo - _aparejo_pos) * (9.8 / APAREJO_LARGO)
		- _aparejo_vel * 2.4) * delta
	_aparejo_pos += _aparejo_vel * delta

	# El sedal no se estira: el anzuelo vive en la esfera de radio APAREJO_LARGO
	# y el tiron del hilo se come la velocidad que se sale de ella.
	var brazo: Vector3 = _aparejo_pos - punta
	var largo: float = brazo.length()
	if largo > APAREJO_LARGO and largo > 1e-5:
		var radial: Vector3 = brazo / largo
		_aparejo_pos = punta + radial * APAREJO_LARGO
		_aparejo_vel -= radial * maxf(_aparejo_vel.dot(radial), 0.0)
	_aparejo.position = _aparejo_pos
	_orientar_aparejo(punta)


## Como se planta el anzuelo: el ojo mirando al hilo (de ahi cuelga) y el PLANO
## de la curva de cara a quien mira.
##
## Lo segundo no es capricho, es lo que hace que exista: colgando en la vertical
## de la puntera, el anzuelo cae casi en la linea de vision de la primera
## persona, y de canto son dos pixeles de alambre pegados al sedal — medido en
## `capture_fishing`, no se veia NADA. De perfil se lee entero. Es el mismo
## criterio que rodo el modelo de la caña 50 grados para que el carrete asomara
## por el brazo (`model_roll_deg`): una pieza que el jugador no puede ver es una
## pieza que no esta. Y no hay fisica que traicionar — un anzuelo colgado de un
## hilo gira libre sobre si mismo, asi que mirar al pescador es tan valido como
## cualquier otra cosa.
func _orientar_aparejo(punta: Vector3) -> void:
	var eje_y: Vector3 = punta - _aparejo_pos
	if eje_y.length_squared() < 1e-8:
		return
	eje_y = eje_y.normalized()
	# La malla tiene la curva en su plano YZ, o sea que ensenia el perfil cuando
	# su eje X apunta a la camara.
	var eje_x := Vector3.RIGHT
	var vista := get_viewport() if is_inside_tree() else null
	var cam := vista.get_camera_3d() if vista != null else null
	if cam != null:
		var mirada: Vector3 = _rod_pivot.to_local(cam.global_position) - _aparejo_pos
		eje_x = mirada - eje_y * mirada.dot(eje_y)
	if eje_x.length_squared() < 1e-8:
		eje_x = eje_y.cross(Vector3.FORWARD)
		if eje_x.length_squared() < 1e-8:
			eje_x = Vector3.RIGHT
	eje_x = eje_x.normalized()
	var eje_z: Vector3 = eje_x.cross(eje_y)
	# Y de las dos caras posibles se elige la que deja la CURVA por fuera. El
	# aparejo cuelga en la vertical de la puntera, o sea justo encima de la
	# silueta de la caña en primera persona: con la curva hacia dentro, el unico
	# trozo que hace reconocible un anzuelo se lo come el cuerpo (medido en
	# `capture_fishing`: de 24 pixeles de alto sobrevivian 6).
	if (PUNTO_DEL_CUERPO - _aparejo_pos).dot(eje_z) < 0.0:
		eje_x = -eje_x
		eje_z = -eje_z
	_aparejo.transform.basis = Basis(eje_x, eje_y, eje_z)


## El aparejo en el agua: al costado de la boya y por el lado que mira quien
## pesca, para que se vea.
##
## Es `top_level` y se coloca a mano en vez de colgar del nodo de la boya porque
## el lado bueno cambia con la camara: pegado debajo, la propia bola lo esconde
## desde cubierta. La visibilidad la SIGUE heredando de la boya (top_level
## desengancha la transformada, no el arbol), asi que aparece al lanzar, se va al
## recoger y se queda a la deriva con ella tras una rotura, sin cablear nada.
func _colocar_aparejo_agua() -> void:
	if not _bobber.visible:
		return
	var centro := _bobber.global_position
	var hacia := Vector3.FORWARD
	var vista := get_viewport() if is_inside_tree() else null
	var cam := vista.get_camera_3d() if vista != null else null
	if cam != null:
		hacia = cam.global_position - centro
		hacia.y = 0.0
	if hacia.length_squared() < 1e-8:
		hacia = Vector3.FORWARD
	hacia = hacia.normalized()
	# Se aparta DE LADO, no hacia la camara: separarlo en profundidad no separa
	# nada en pantalla (la bola se le pone delante igual), y de lado sale limpio
	# contra el agua con el sedal uniendolos.
	var lado := hacia.cross(Vector3.UP).normalized()
	_aparejo_agua.global_position = (centro + lado * APAREJO_JUNTO_A_BOYA
		+ Vector3.UP * APAREJO_SOBRE_EL_AGUA)
	# Cuelga a plomo (el ojo arriba) y de perfil, por lo mismo que el de la mano:
	# de canto es un alambre de dos pixeles.
	_aparejo_agua.global_transform.basis = Basis(hacia, Vector3.UP,
		hacia.cross(Vector3.UP))


## El sedal que va POR la caña, con el doblez de este frame encima.
##
## Se redibuja entero cada vez (son nueve vertices: rebuscar cuando cambia sale
## mas caro que rehacerlo), pero SOLO cuando la caña se ve — guardada, ni se
## toca la malla.
func _dibujar_enhebrado() -> void:
	var im := _enhebrado.mesh as ImmediateMesh
	if im == null:
		return
	im.clear_surfaces()
	if _hilo_esq.is_empty() or not _rod_pivot.visible:
		return
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in _hilo_esq:
		im.surface_add_vertex(_esq_a_pivote * _piel(p))
	# El ultimo tramo depende de donde este el aparejo: baja hasta el anzuelo si
	# lo llevas en la mano, y si no pasa por `Tip`, que es donde nace el tramo
	# de fuera — asi los dos sedales empalman sin un salto en la puntera.
	im.surface_add_vertex(_aparejo.position if _aparejo.visible else _tip.position)
	im.surface_end()


## El cebo se ve DONDE ESTA: clavado en el anzuelo, en la mano Y en el agua.
## Hasta ahora solo lo sabia el HUD de debug, o sea que en una partida de verdad
## no lo sabia nadie; la bola ya venia en el GLB del aparejo, asi que enseñarla
## es encenderla y tintarla.
##
## Los DOS aparejos se pintan con la misma llamada: son el mismo anzuelo visto
## en dos sitios (la mano y el agua), y que uno llevara cebo y el otro no seria
## el feedback mintiendo en el unico canal donde el cebo existe.
func _pintar_cebo() -> void:
	var puesto := cebo_puesto()
	for aparejo: Node3D in [_aparejo, _aparejo_agua]:
		var bola := aparejo.find_child("Cebo", true, false) as MeshInstance3D
		if bola == null:
			continue
		bola.visible = puesto != null
		if puesto == null:
			continue
		# Un GLB trae su material en la malla, no como override (misma trampa
		# que el tintado del tier): sin este respaldo el color se apagaria en
		# silencio.
		var base: Material = bola.get_surface_override_material(0)
		if base == null and bola.mesh != null:
			base = bola.mesh.surface_get_material(0)
		var mat := base as StandardMaterial3D
		if mat != null:
			mat = mat.duplicate()
			mat.albedo_color = puesto.color
			bola.set_surface_override_material(0, mat)


func _draw_line() -> void:
	_dibujar_enhebrado()
	var im := _line.mesh as ImmediateMesh
	im.clear_surfaces()

	# Trozo de sedal colgando tras la rotura: la permanencia del fallo.
	if _remnant_left > 0.0:
		_remnant_left -= get_physics_process_delta_time()
		var a := _tip_pos()
		var sway := sin(Time.get_ticks_msec() * 0.004) * 0.06
		im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for i in 5:
			var t := float(i) / 4.0
			im.surface_add_vertex(_line.to_local(a + Vector3(sway * t, -0.5 * t, 0.05 * t)))
		im.surface_end()
		return

	if not _bobber.visible or _adrift_left > 0.0 or state == State.IDLE or state == State.CASTING:
		return
	var a := _tip_pos()
	var b := _bobber.global_position
	var slack: float = 1.2
	if state == State.FIGHT:
		slack = lerpf(0.9, 0.05, clampf(fight.tension, 0.0, 1.0))
		if fight.is_spit_warning():
			# El anzuelo se afloja: la comba se exagera — el "recoge YA" visual.
			slack += 0.8 + sin(Time.get_ticks_msec() * 0.01) * 0.2
	var mid := (a + b) * 0.5 + Vector3.DOWN * slack
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in 9:
		var t := float(i) / 8.0
		var p := a.lerp(mid, t).lerp(mid.lerp(b, t), t)
		im.surface_add_vertex(_line.to_local(p))
	# El sedal no acaba en la boya: la ATRAVIESA y sigue hasta el anzuelo, que es
	# lo que pesca. La boya es solo el flotador por el que pasa (y por eso este
	# tramo se dibuja aunque quede bajo el agua: cuando el mar abre un valle, ahi
	# esta el aparejo esperando).
	im.surface_add_vertex(_line.to_local(_aparejo_agua.global_position))
	im.surface_end()


## Linea de estado para el HUD de debug (el juego real no la enseña).
func debug_line() -> String:
	# Clavada, el gesto es OTRO: primero E en el soporte para retomarla. Decir
	# "clic" mientras cuelga de la borda seria el HUD mintiendo de canal, que es
	# justo lo que el resto del sistema evita (regla 8) — aqui sale gratis.
	var clavada := soporte != null
	var c := cebo_puesto()
	var cebada := "  ·  %s x%d" % [c.nombre, cebo_cargas] if c != null else "  ·  sin cebo"
	match state:
		State.IDLE:
			if clavada:
				return "%s clavada en la borda%s  ·  E: retomarla" % \
					[tier.tier_name if tier != null else "caña", cebada]
			return "%s lista%s  ·  clic: lanzar  ·  C: cambiar caña" % \
				[tier.tier_name if tier != null else "caña", cebada]
		State.CASTING:
			return "cargando  %d%%" % int(_charge * 100)
		State.WAITING:
			return "esperando  (%.0f s)%s%s  ·  mar %.2f m/s2" % [
				_wait_left, cebada, "  ·  clavada" if clavada else "",
				absf(deck_accel_y)]
		State.NIBBLING:
			return "algo ronda la boya..."
		State.BITE:
			if clavada:
				return "[b]¡PICA![/b]  E para retomarla, luego clavar  (%.1f s)" % _bite_left
			return "[b]¡PICA![/b]  clic para clavar  (%.1f s)" % _bite_left
		State.FIGHT:
			var dir := "<- tira IZQ" if fight.pull_dir == FightModel.Pull.LEFT else \
				("tira DER ->" if fight.pull_dir == FightModel.Pull.RIGHT else "descansa: ¡RECOGE!")
			var warn := "  [color=#ff6b6b]¡¡CHIRRIA!![/color]" if fight.is_warning() else ""
			return "%s %.0f kg  ·  %s  ·  T=%.2f  ·  %d%%%s" % [
				hooked_species[&"name"], hooked_species[&"weight"], dir,
				fight.tension, int(fight.progress * 100), warn]
	return ""
