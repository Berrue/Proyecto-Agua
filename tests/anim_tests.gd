extends Node

## Pruebas del arbol de animacion del jugador.
##
## Lo que se protege aca no es "que se vea lindo", es el CONTRATO:
##  1. El jugador monta el arbol y este manda sobre el esqueleto.
##  2. Quieto = idle (manos colgando, pies juntos). Caminando = zancada.
##  3. EL FILTRO: con las manos ocupadas en la caña, el tren superior obedece a
##     la caña y las piernas SIGUEN caminando. Ese reparto es el pilar fisico
##     del diseño ("pescar te quita el agarre"), no un detalle cosmetico.
##  4. La velocidad que alimenta al arbol es `velocity` tal cual, no la
##     relativa a la plataforma: sobre cubierta el balanceo no debe hacer que
##     el pescador parezca caminar.
##
##   godot --path . tests/anim_tests.tscn

var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0


func _ready() -> void:
	print_rich("[b]--- Pruebas de animacion ---[/b]")
	await _test_animation_tree()
	await _test_camino_real()
	await _test_agua()
	await _test_no_camina_por_el_balanceo()
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


## Devuelve posiciones de huesos clave en el espacio del esqueleto.
func _pose(skel: Skeleton3D) -> Dictionary:
	var out := {}
	for hueso: String in ["Chest", "RightUpperArm", "RightHand", "LeftHand",
			"RightFoot", "LeftFoot", "Hips"]:
		out[hueso] = skel.get_bone_global_pose(skel.find_bone(hueso)).origin
	return out


## Distancia vertical minima cadera->pecho a lo largo de un ciclo: cuanto mas
## chica respecto del rest de ESTE cuerpo, mas doblado esta. Se mide relativo
## porque el pescador smooth es mas petiso de torso que el modelo de bloques.
func _torso_minimo(anim: PlayerAnimator, agua: float, cana: bool) -> float:
	anim.force(0.0, agua, cana)
	var peor := INF
	for _i in 40:
		await get_tree().process_frame
		var p := _pose(anim.skeleton)
		peor = minf(peor, p["Chest"].y - p["Hips"].y)
	return peor


## ¿Las dos manos estan por delante del PECHO, medido en el marco del pecho?
## Ojo con medirlo en Z de mundo: nadando el torso se echa hacia atras y una
## pose de caña perfectamente valida da "detras" en coordenadas de mundo.
func _manos_adelante(skel: Skeleton3D) -> bool:
	var pecho := skel.get_bone_global_pose(skel.find_bone("Chest"))
	var d := pecho.affine_inverse() * skel.get_bone_global_pose(skel.find_bone("RightHand")).origin
	var i := pecho.affine_inverse() * skel.get_bone_global_pose(skel.find_bone("LeftHand")).origin
	return d.z > 0.05 and i.z > 0.05


func _test_animation_tree() -> void:
	var scene: Node3D = load("res://game/world/toybox.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame

	var player := scene.get_node(^"Player") as Player
	_check(player.animator != null, "el jugador monta el PlayerAnimator")
	if player.animator == null:
		scene.queue_free()
		return
	var anim := player.animator
	_check(anim.tree != null and anim.tree.active, "y su AnimationTree esta activo")
	_check(anim.skeleton != null, "con el esqueleto del pescador enganchado")

	# Congelamos la fisica del jugador: si no, su _feed_animator() de cada frame
	# deshace el force() del test y medimos el suavizado en vez de las poses.
	player.set_physics_process(false)

	# --- 1. Quieto: idle ------------------------------------------------------
	anim.force(0.0, 0.0, false)
	for _i in 8:
		await get_tree().process_frame
	var quieto := _pose(anim.skeleton)
	_check(quieto["RightHand"].y < quieto["RightUpperArm"].y - 0.15,
		"parado, las manos cuelgan por debajo del hombro",
		"mano y=%.2f hombro y=%.2f" % [quieto["RightHand"].y, quieto["RightUpperArm"].y])
	var pies_quieto: float = absf(quieto["RightFoot"].z - quieto["LeftFoot"].z)
	_check(pies_quieto < 0.2, "y los pies estan juntos (no hay zancada)",
		"dz=%.2f" % pies_quieto)

	# --- 2. Caminando: zancada ------------------------------------------------
	anim.force(1.0, 0.0, false)
	var zancada_max: float = 0.0
	for _i in 40:
		await get_tree().process_frame
		var p := _pose(anim.skeleton)
		zancada_max = maxf(zancada_max, absf(p["RightFoot"].z - p["LeftFoot"].z))
	_check(zancada_max > 0.25, "caminando, los pies hacen zancada de verdad",
		"maxima dz=%.2f" % zancada_max)
	_check(float(anim.tree.get(&"parameters/walk_scale/scale")) > 1.0,
		"y la cadencia sube con la velocidad",
		"scale=%.2f" % float(anim.tree.get(&"parameters/walk_scale/scale")))

	# --- 3. EL FILTRO: caña arriba, piernas abajo -----------------------------
	anim.force(1.0, 0.0, true)
	var manos_adelante := 0
	# AMPLITUD, no separacion: la pose de pesca ya tiene los pies separados 0.28,
	# asi que medir "dz > 0.25" pasaba incluso con el filtro APAGADO (lo cazo un
	# mutation test). Lo que prueba que las piernas siguen vivas es que la
	# zancada OSCILE; una pose quieta da amplitud ~0.
	var dz_min: float = INF
	var dz_max: float = -INF
	for _i in 40:
		await get_tree().process_frame
		var p := _pose(anim.skeleton)
		var dz: float = absf(p["RightFoot"].z - p["LeftFoot"].z)
		dz_min = minf(dz_min, dz)
		dz_max = maxf(dz_max, dz)
		if _manos_adelante(anim.skeleton):
			manos_adelante += 1
	_check(manos_adelante > 30, "con la caña, las DOS manos van por delante del pecho",
		"%d de 40 frames" % manos_adelante)
	_check(dz_max - dz_min > 0.15,
		"y las piernas SIGUEN caminando (el filtro reparte el cuerpo)",
		"amplitud de zancada=%.2f" % (dz_max - dz_min))

	# --- 4. Soltar la caña vuelve a la locomocion completa --------------------
	anim.force(1.0, 0.0, false)
	for _i in 12:
		await get_tree().process_frame
	var p2 := _pose(anim.skeleton)
	_check(p2["RightHand"].y < p2["RightUpperArm"].y,
		"al soltar la caña los brazos vuelven a caer")

	player.set_physics_process(true)
	scene.queue_free()
	await get_tree().process_frame


## EL CAMINO REAL. Todo lo de arriba entra por force(), que es un helper de
## tests y RE-IMPLEMENTA el mapeo. O sea que update() podia ignorar la caña
## entera y las comprobaciones seguian en verde (lo cazo una revision con
## mutation testing). Esto pisa la cadena de produccion completa:
## velocity/input_captured -> _feed_animator -> update -> parametros del arbol.
func _test_camino_real() -> void:
	var scene: Node3D = load("res://game/world/toybox.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	var player := scene.get_node(^"Player") as Player
	if player.animator == null:
		_check(false, "hay animator para probar el camino real")
		scene.queue_free()
		return
	var anim := player.animator
	player.set_physics_process(false)
	# Estado seco y determinista: con la fisica congelada nadie los actualiza.
	player.state = Player.State.DECK
	player.submerged_fraction = 0.0

	# --- locomocion por el camino real ---
	anim.force(0.0, 0.0, false)
	player.velocity = -player.global_transform.basis.z * player.walk_speed
	for _i in 30:
		player._feed_animator(1.0 / 60.0)
		await get_tree().process_frame
	var loco_andando := float(anim.tree.get(&"parameters/locomotion/blend_amount"))
	_check(loco_andando > 0.9, "moviendo al jugador de verdad, la locomocion sube sola",
		"mezcla=%.2f" % loco_andando)
	player.velocity = Vector3.ZERO
	for _i in 30:
		player._feed_animator(1.0 / 60.0)
		await get_tree().process_frame
	var loco_quieto := float(anim.tree.get(&"parameters/locomotion/blend_amount"))
	_check(loco_quieto < 0.05, "y al frenar vuelve a idle sola",
		"mezcla=%.2f" % loco_quieto)

	# --- la caña por el camino real ---
	player.input_captured = true
	for _i in 30:
		player._feed_animator(1.0 / 60.0)
		await get_tree().process_frame
	var rod_pescando := float(anim.tree.get(&"parameters/rod/blend_amount"))
	_check(rod_pescando > 0.9, "y con la lucha enganchada la pose de caña entra sola",
		"mezcla=%.2f" % rod_pescando)
	player.input_captured = false
	for _i in 30:
		player._feed_animator(1.0 / 60.0)
		await get_tree().process_frame
	_check(float(anim.tree.get(&"parameters/rod/blend_amount")) < 0.05,
		"y al soltar se va sola",
		"mezcla=%.2f" % float(anim.tree.get(&"parameters/rod/blend_amount")))

	# --- cargar a dos manos NO es pescar ---
	# hands_busy es (input_captured OR hands_used >= 2). Si alguien "simplifica"
	# el cableado a hands_busy, cargar un fletan pone pose de PESCAR.
	player.hands_used = 2
	for _i in 30:
		player._feed_animator(1.0 / 60.0)
		await get_tree().process_frame
	var rod_cargando := float(anim.tree.get(&"parameters/rod/blend_amount"))
	_check(rod_cargando < 0.05, "cargar algo a dos manos NO pone pose de pescar",
		"mezcla=%.2f (hands_busy=%s)" % [rod_cargando, player.hands_busy])
	player.hands_used = 0

	player.set_physics_process(true)
	scene.queue_free()
	await get_tree().process_frame


## El agua: flotando manda el clip de nadar sobre TODO el cuerpo (la cubierta ya
## no existe), pero la caña sigue mandando sobre los brazos — si te caes al mar
## peleando un pez, las manos siguen en la caña mientras las piernas patalean.
## Y la mezcla tiene que entrar progresiva desde el muslo, no de golpe.
func _test_agua() -> void:
	var scene: Node3D = load("res://game/world/toybox.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	var player := scene.get_node(^"Player") as Player
	if player.animator == null:
		_check(false, "hay animator para probar el agua")
		scene.queue_free()
		return
	var anim := player.animator
	player.set_physics_process(false)

	# 1. Flotando, el agua le gana a la locomocion aunque el ratio este a tope.
	anim.force(1.0, 1.0, false)
	var zancada: float = 0.0
	var apertura: float = 0.0
	for _i in 40:
		await get_tree().process_frame
		var p := _pose(anim.skeleton)
		zancada = maxf(zancada, absf(p["RightFoot"].z - p["LeftFoot"].z))
		apertura = maxf(apertura, maxf(absf(p["RightHand"].x - p["Chest"].x),
			absf(p["LeftHand"].x - p["Chest"].x)))
	_check(zancada < 0.25, "flotando no hay zancada aunque el ratio este a tope",
		"maxima dz=%.2f" % zancada)
	_check(apertura > 0.48, "y los brazos barren mas abiertos que en idle",
		"apertura x=%.2f" % apertura)

	# 2. Caido al agua CON la caña: manos en la caña, piernas pataleando.
	anim.force(0.0, 1.0, true)
	var manos_adelante := 0
	var piernas_vivas: float = 0.0
	var pie_previo: float = 0.0
	for i in 40:
		await get_tree().process_frame
		var p := _pose(anim.skeleton)
		if _manos_adelante(anim.skeleton):
			manos_adelante += 1
		if i > 0:
			piernas_vivas = maxf(piernas_vivas, absf(p["RightFoot"].z - pie_previo))
		pie_previo = p["RightFoot"].z
	_check(manos_adelante > 30, "en el agua la caña sigue mandando sobre los brazos",
		"%d de 40 frames" % manos_adelante)
	# LA CAÑA NO TOCA EL TORSO. Ojo con el umbral absoluto: el clip de nadar YA
	# inclina el cuerpo 34 grados hacia adelante por su cuenta (medido tambien
	# sobre el esqueleto original de Mixamo, o sea que no es cosa del retarget).
	# Lo que hay que exigir es que la postura sea LA MISMA con y sin caña.
	# Con los clips de hoy la diferencia es de 7 mm, asi que esto no es una
	# trampa para mutaciones: es un seguro para el dia que entre un clip de
	# pesca con una rotacion de tronco grande.
	var torso_con := await _torso_minimo(anim, 1.0, true)
	var torso_sin := await _torso_minimo(anim, 1.0, false)
	_check(absf(torso_con - torso_sin) < 0.03,
		"y la caña no cambia la postura del torso al nadar",
		"con=%.3f sin=%.3f" % [torso_con, torso_sin])
	var pecho_rest := anim.skeleton.get_bone_global_rest(
		anim.skeleton.find_bone("Chest")).origin
	var cadera_rest := anim.skeleton.get_bone_global_rest(
		anim.skeleton.find_bone("Hips")).origin
	var torso_rest: float = pecho_rest.y - cadera_rest.y
	var torso_ratio: float = torso_con / maxf(torso_rest, 0.001)
	_check(torso_ratio > 0.72, "que ademas sigue siendo un torso erguido, no una bola",
		"chest-hips=%.3f, %.0f%% del rest %.3f" % [
			torso_con, torso_ratio * 100.0, torso_rest])
	_check(piernas_vivas > 0.002, "y las piernas siguen pataleando debajo",
		"movimiento por frame=%.4f" % piernas_vivas)

	# 3. La mezcla entra progresiva con la sumersion, no de golpe en el umbral.
	var muestras := {}
	for frac: float in [0.0, 0.45, 1.0]:
		anim.force(0.0, 0.0, false)
		player.submerged_fraction = frac
		for _i in 30:
			player._feed_animator(1.0 / 60.0)
			await get_tree().process_frame
		muestras[frac] = float(anim.tree.get(&"parameters/water/blend_amount"))
	_check(muestras[0.0] < 0.05, "seco = cero agua", "%.2f" % muestras[0.0])
	_check(muestras[1.0] > 0.9, "hundido = agua a tope", "%.2f" % muestras[1.0])
	_check(muestras[0.45] > 0.1 and muestras[0.45] < 0.9,
		"y con el agua por el muslo la mezcla esta A MEDIO CAMINO (no es un interruptor)",
		"%.2f" % muestras[0.45])

	player.set_physics_process(true)
	scene.queue_free()
	await get_tree().process_frame


## El balanceo del barco NO es caminar: con el jugador quieto sobre cubierta la
## mezcla de locomocion tiene que quedarse pegada a cero, por mucho que el barco
## cabecee debajo. (La primera version restaba get_platform_velocity() y el
## pescador "caminaba" con cada ola.)
func _test_no_camina_por_el_balanceo() -> void:
	var scene: Node3D = load("res://game/world/toybox.tscn").instantiate()
	add_child(scene)
	Ocean.set_fury_immediate(4.0)
	for _i in 180:
		await get_tree().physics_frame

	var player := scene.get_node(^"Player") as Player
	if player.animator == null:
		_check(false, "hay animator para medir el balanceo")
		scene.queue_free()
		return
	var maxima: float = 0.0
	var plataforma: float = 0.0
	for _i in 120:
		await get_tree().physics_frame
		maxima = maxf(maxima, float(
			player.animator.tree.get(&"parameters/locomotion/blend_amount")))
		var pv := player.get_platform_velocity()
		plataforma = maxf(plataforma, Vector2(pv.x, pv.z).length())
	_check(plataforma > 0.05, "el barco de verdad se movia debajo (si no, no probamos nada)",
		"plataforma max=%.2f m/s" % plataforma)
	_check(maxima < 0.1, "y aun asi el pescador NO camina por el balanceo",
		"mezcla max=%.2f" % maxima)

	scene.queue_free()
	await get_tree().process_frame
