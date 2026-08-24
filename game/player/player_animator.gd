class_name PlayerAnimator
extends Node

## El cuerpo animado del pescador.
##
## En primera persona NO te ves a ti mismo (el cuerpo esta en solo-sombra), asi
## que esto no anima "lo que ves": anima tu SOMBRA en cubierta — que si se ve y
## es informacion — y, cuando entre la red en F2, la copia tuya que ven los
## demas. Por eso el arbol se monta ya: cambiarlo despues sale mas caro.
##
## El arbol:
##
##   idle ────────────┐
##                    ├─ locomotion ─┐
##   walk ─ TimeScale ┘  (Blend2 por  ├─ water ─┐
##                        velocidad)  │ (Blend2  ├─ rod ── out
##   swim ─────────────────────────---┘  por     │  (Blend2
##   fishing_idle ─────────────────────-─sumersion)  FILTRADO)
##                                                ┘
##
## El FILTRO es el que hace posible el pilar del diseño: de Spine para arriba
## manda la caña, de la cadera para abajo sigue mandando la locomocion. O sea:
## las piernas siguen caminando (y trastabillando) mientras los brazos pescan.
##
## Todo se construye en codigo a proposito: el modelo es un .glb importado, no
## se le pueden meter nodos en el editor, y asi el arbol vive junto a las reglas
## que lo gobiernan en vez de en un .tscn que nadie se anima a tocar.

const CLIPS := {
	&"idle": "res://game/player/animations/idle_retargeted.res",
	&"walk": "res://game/player/animations/walk_retargeted.res",
	&"swim": "res://game/player/animations/swim_retargeted.res",
	&"fishing_idle": "res://game/player/animations/fishing_idle_retargeted.res",
}

## Lo que la caña le quita a la locomocion: LOS BRAZOS (y la mirada), no el
## torso. La regla: el torso pertenece a lo que estas HACIENDO con el cuerpo
## (caminar, flotar); los brazos, a lo que tenes EN LAS MANOS.
##
## Medido antes de decidirlo, porque el ojo miente: meter Spine/Chest/UpperChest
## en el filtro mueve la postura del torso apenas 6 mm nadando (chest-hips 0.318
## vs 0.324) — o sea que la diferencia visible entre "nadando" y "nadando con
## caña" son los brazos, no el tronco. Se eligio brazos-solo por coherencia
## (que el torso no dependa de lo que llevas en la mano), no porque arreglara
## nada roto. Precio: la pose de pesca pierde su inclinacion de tronco propia,
## que en cubierta son otros 5 mm.
const UPPER_BODY: Array[String] = [
	"Neck", "Head",
	"LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
]

## Cadencia del ciclo de paso. El clip de Mixamo camina a su ritmo; lo estiramos
## con la velocidad real para que los pies no patinen MAS de lo inevitable (sin
## root motion, algo de patinaje siempre hay: es una decision consciente).
@export var cadence_min: float = 0.7
@export var cadence_max: float = 1.8

## Velocidad de las mezclas, en unidades por segundo. Alto = seco, bajo = flan.
@export var blend_speed: float = 8.0

var skeleton: Skeleton3D
var tree: AnimationTree

var _locomotion: float = 0.0
var _water: float = 0.0
var _rod: float = 0.0


## Monta reproductor y arbol dentro del modelo. Devuelve false si falta algo
## (sin clips o sin esqueleto el jugador tiene que seguir funcionando igual).
func setup(model: Node3D) -> bool:
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return false
	skeleton = skels[0] as Skeleton3D
	var rel := String(model.get_path_to(skeleton))

	var lib := AnimationLibrary.new()
	for clip: StringName in CLIPS:
		var anim := _load_clip(String(CLIPS[clip]), rel)
		if anim == null:
			return false
		lib.add_animation(clip, anim)

	var player := AnimationPlayer.new()
	player.name = "AnimPlayer"
	model.add_child(player)
	player.root_node = player.get_path_to(model)
	player.add_animation_library(&"", lib)

	tree = AnimationTree.new()
	tree.name = "AnimTree"
	model.add_child(tree)
	tree.root_node = tree.get_path_to(model)
	tree.anim_player = tree.get_path_to(player)
	tree.tree_root = _build_tree(rel)
	tree.active = true
	return true


## Carga un clip horneado y le reapunta las pistas. Vienen como
## "%GeneralSkeleton:Hueso" (nombre unico que pone el BoneMap al importar) y en
## una escena instanciada eso no siempre resuelve: lo reescribimos al path
## relativo real, que si.
func _load_clip(path: String, rel: String) -> Animation:
	if not ResourceLoader.exists(path):
		push_warning("PlayerAnimator: falta el clip %s" % path)
		return null
	var anim: Animation = (load(path) as Animation).duplicate(true)
	for t in anim.get_track_count():
		var hueso := String(anim.track_get_path(t)).split(":")[-1]
		anim.track_set_path(t, NodePath(rel + ":" + hueso))
	anim.loop_mode = Animation.LOOP_LINEAR
	return anim


func _build_tree(rel: String) -> AnimationRootNode:
	var root := AnimationNodeBlendTree.new()

	for clip: StringName in CLIPS:
		var nodo := AnimationNodeAnimation.new()
		nodo.animation = clip
		root.add_node(String(clip), nodo, Vector2(0, 100 * root.get_node_list().size()))

	var escala := AnimationNodeTimeScale.new()
	root.add_node("walk_scale", escala, Vector2(240, 100))
	root.connect_node("walk_scale", 0, "walk")

	var loco := AnimationNodeBlend2.new()
	root.add_node("locomotion", loco, Vector2(460, 60))
	root.connect_node("locomotion", 0, "idle")
	root.connect_node("locomotion", 1, "walk_scale")

	# El agua manda sobre TODO el cuerpo (no filtrada): flotando no hay cubierta
	# que pisar, asi que la locomocion entera deja de tener sentido.
	var agua := AnimationNodeBlend2.new()
	root.add_node("water", agua, Vector2(580, 240))
	root.connect_node("water", 0, "locomotion")
	root.connect_node("water", 1, "swim")

	# El filtrado: solo las pistas listadas escuchan a la caña; el resto
	# (cadera y piernas) pasa de largo desde lo que venga debajo. Va DESPUES del
	# agua a proposito: si te caes al mar peleando un pez, las manos siguen en
	# la caña mientras las piernas patalean.
	var rod := AnimationNodeBlend2.new()
	rod.filter_enabled = true
	for hueso: String in UPPER_BODY:
		rod.set_filter_path(NodePath(rel + ":" + hueso), true)
	root.add_node("rod", rod, Vector2(700, 60))
	root.connect_node("rod", 0, "water")
	root.connect_node("rod", 1, "fishing_idle")

	root.connect_node("output", 0, "rod")
	return root


## Se llama cada frame de fisica desde el jugador.
##   speed_ratio: velocidad / walk_speed, 0..1 (ver _feed_animator en player.gd)
##   water:       0 = pisando cubierta, 1 = flotando
##   hands_busy:  las dos manos en la caña
func update(speed_ratio: float, water: float, hands_busy: bool, delta: float) -> void:
	if tree == null:
		return
	var k: float = clampf(blend_speed * delta, 0.0, 1.0)
	_locomotion = lerpf(_locomotion, clampf(speed_ratio, 0.0, 1.0), k)
	_water = lerpf(_water, clampf(water, 0.0, 1.0), k)
	_rod = lerpf(_rod, 1.0 if hands_busy else 0.0, k)
	_apply()


## Para tests y capturas: saltarse el suavizado y plantar la pose ya.
func force(speed_ratio: float, water: float, hands_busy: bool) -> void:
	if tree == null:
		return
	_locomotion = clampf(speed_ratio, 0.0, 1.0)
	_water = clampf(water, 0.0, 1.0)
	_rod = 1.0 if hands_busy else 0.0
	_apply()


func _apply() -> void:
	tree.set(&"parameters/locomotion/blend_amount", _locomotion)
	tree.set(&"parameters/water/blend_amount", _water)
	tree.set(&"parameters/rod/blend_amount", _rod)
	tree.set(&"parameters/walk_scale/scale",
		lerpf(cadence_min, cadence_max, _locomotion))
