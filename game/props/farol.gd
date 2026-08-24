class_name Farol
extends Portable3D

## El farol de tormenta: la unica luz portatil de la noche (DISENO.md §2).
##
## Los verbos del porteo (tomar/colgar/soltar, congelado en mano, herencia de
## velocidad) viven en Portable3D — el farol fue su prototipo y ahora es su
## primera subclase. Aqui queda SOLO lo que hace farol al farol: la luz.
## Energia, parpadeo y brillo del globo son PRESENTACION: se calculan local,
## jamas se replican, y dos clientes con parpadeos distintos siguen viendo el
## mismo farol en la misma mano.
##
## Las decisiones cerradas que este archivo protege (docs/FAROL.md):
##
## 1. NO SE GASTA NI SE APAGA. Sin aceite, sin bateria, sin reencender. El mar
##    ya administra la tension; una barra de combustible solo añadiria una
##    tarea de mantenimiento que compite por manos y que encima castigaria en
##    la oscuridad, justo donde el castigo no se ve venir (regla 8: el feedback
##    jamas miente y todo fallo se telegrafia ANTES de castigar).
## 2. OCUPA UNA MANO, no dos. Andas, saltas y te agarras con el farol
##    encendido; lo que no puedes es coger la caña o la bomba sin colgarlo.
## 3. UNA SOLA LUZ CON SOMBRAS EN TODA LA ESCENA. Una omni con sombras rinde su
##    mapa cada vez que algo se mueve, y aqui se mueve todo siempre. La sombra
##    que el ojo lee es la que gira con TU mano; las de los demas no se echan
##    de menos, y su coste escalaria con el numero de jugadores.
## 4. EL PARPADEO ES FUNCION PURA DE Ocean.sim_time. Podria usar Time —es
##    presentacion, y la regla 2 lo permite en game/—, pero con sim_time sale
##    gratis que la llama se CONGELE al pausar la simulacion, que es lo que el
##    ojo espera de un juego que puede consultar su propio futuro.
## 5. EL FAROL NO ES LA TELEGRAFIA. Ayuda a ver de cerca; el aviso del tsunami
##    vive donde ya vive (sonido, horizonte, HUD, vigia). Si ver el muro
##    dependiera de llevar luz, la noche pasaria de dificil a injusta.

## Energia de la luz en mano. Alrededor de este numero gira todo el ajuste:
## sube y la cubierta entera se lee de noche (y el farol deja de importar),
## baja y el charco no da para trabajar.
const ENERGIA_BASE := 1.6

## Radio en metros. Deliberadamente algo menor que el ancho de cubierta: SIEMPRE
## tiene que quedar oscuridad a la vista, o el objeto pierde su razon de ser.
const RADIO_BASE := 7.5

## Alzado: mas alcance, no mas brillo. El gesto tiene que leerse desde fuera
## (te ilumina la cara desde arriba), no solo desde tus ojos.
const RADIO_ALZADO := 9.5

## Quake animaba sus lightstyles a 10 fps y le sobraba. A 6-7 Hz la llama
## respira; por encima parece un fluorescente roto.
const FLICKER_HZ := 6.4

## +-12 % de energia en calma. Mas profundidad y parece que se apaga —y el
## farol NO se apaga nunca (decision 1).
const FLICKER_DEPTH_CALMA := 0.12

## Con temporal, la llama se agita hasta +-30 %. Es telegrafia gratis del
## estado del mar: el farol tiembla antes de que tu lo notes en los pies.
const FLICKER_DEPTH_TEMPORAL := 0.30

## Un destello por segundo. Las luces de socorro homologadas (codigo LSA
## 2.2.3) destellan entre 50 y 70 veces por minuto: esa cadencia se lee como
## "socorro" sin que nadie tenga que explicarla.
const SOCORRO_HZ := 1.0

@export_group("Presentacion")
## Color de llama de queroseno (~2000 K). Contra el azul de la luna es lo que
## da el contraste; un blanco calido lo perderia.
@export var color_llama := Color(1.0, 0.80, 0.53)
@export var energia_base: float = ENERGIA_BASE
@export var radio_base: float = RADIO_BASE

@export_group("Nodos")
@export var luz_path: NodePath = ^"Luz"
@export var globo_path: NodePath = ^"Globo"

## Solo el farol que lleva el jugador LOCAL proyecta sombras (decision 3). Es
## static para que la invariante no dependa de que alguien lleve la cuenta.
static var _con_sombras: Farol = null

var _luz: OmniLight3D
var _globo: MeshInstance3D
var _globo_mat: StandardMaterial3D


func _ready() -> void:
	super()
	_luz = get_node_or_null(luz_path) as OmniLight3D
	_globo = get_node_or_null(globo_path) as MeshInstance3D
	if _luz == null:
		push_warning("Farol sin OmniLight3D: es un farol apagado y no hay estado apagado.")
	else:
		_luz.light_color = color_llama
		_luz.omni_range = radio_base
		# Arranca sin sombras: las enciende `_actualizar_sombras()` y solo para
		# el portador local. Un farol en el suelo no proyecta nada.
		_luz.shadow_enabled = false
	if _globo != null:
		# Se duplica el material porque cada farol parpadea por su cuenta: sin
		# esto, dos faroles compartirian emision y latirian al unisono.
		var mat := _globo.get_active_material(0)
		if mat is StandardMaterial3D:
			_globo_mat = (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			_globo.material_override = _globo_mat


func _exit_tree() -> void:
	if _con_sombras == self:
		_con_sombras = null


func esta_en_agua() -> bool:
	return Ocean.get_submersion(global_position) > 0.0


## Los verbos de Portable3D avisan por aqui: cada cambio de mano o de gancho
## puede mover la unica sombra de la escena.
func _tras_cambio() -> void:
	_actualizar_sombras()


# =============================================================================
#  Presentacion — local, nunca replicada
# =============================================================================

func _process(_delta: float) -> void:
	if _luz == null:
		return
	var e: float = energia_base * energia01(Ocean.sim_time)
	_luz.light_energy = e
	if _globo_mat != null:
		# El globo late con la misma señal que la luz: si se separan, el ojo
		# nota que el brillo no viene del fuego.
		_globo_mat.emission_energy_multiplier = 2.5 + 2.5 * (e / maxf(energia_base, 0.001))


## Energia normalizada (1.0 = llama tranquila). PURA: mismo sim_time, mismo
## valor, en cualquier maquina. Se expone para que el test la compruebe sin
## instanciar la escena.
func energia01(t: float) -> float:
	if estado == Estado.SUELTO and esta_en_agua():
		return _socorro(t)
	return _flicker(t)


## Tres senos con frecuencias no multiplas: no repiten patron perceptible y
## cuestan menos que muestrear una textura de ruido.
func _flicker(t: float) -> float:
	var furia01: float = clampf(Ocean.fury / 10.0, 0.0, 1.0)
	var prof: float = lerpf(FLICKER_DEPTH_CALMA, FLICKER_DEPTH_TEMPORAL, furia01)
	var f: float = (
		sin(t * FLICKER_HZ)
		+ 0.5 * sin(t * FLICKER_HZ * 2.3 + 1.7)
		+ 0.25 * sin(t * FLICKER_HZ * 5.1 + 4.2)
	)
	return 1.0 + prof * (f / 1.75)


## Cadencia de socorro del farol perdido: ~0,2 s encendido por segundo. No es
## un adorno — es lo que convierte un accidente en una llamada de auxilio
## legible desde el barco, sin HUD y sin que nadie tenga que gritar.
func _socorro(t: float) -> float:
	var fase: float = fposmod(t, 1.0 / SOCORRO_HZ) * SOCORRO_HZ
	var subida: float = smoothstep(0.0, 0.06, fase)
	var bajada: float = 1.0 - smoothstep(0.10, 0.22, fase)
	return 0.3 + 0.7 * subida * bajada


# =============================================================================
#  Interno
# =============================================================================

## La invariante de la decision 3, en un solo sitio: como mucho un farol con
## sombras, y es el que lleva el jugador local en la mano.
func _actualizar_sombras() -> void:
	var merece: bool = estado == Estado.EN_MANO and portador != null and portador.is_multiplayer_authority()
	if merece:
		if _con_sombras != null and _con_sombras != self and is_instance_valid(_con_sombras):
			_con_sombras._set_sombras(false)
		_con_sombras = self
		_set_sombras(true)
	else:
		if _con_sombras == self:
			_con_sombras = null
		_set_sombras(false)


func _set_sombras(on: bool) -> void:
	if _luz == null:
		return
	_luz.shadow_enabled = on
	# El distance fade SOLO ahorra con las sombras apagadas: con sombras
	# encendidas la luz se desvanece a la vista pero su mapa se sigue
	# actualizando (godot#88085). Por eso van juntos y en este orden.
	_luz.distance_fade_enabled = not on
