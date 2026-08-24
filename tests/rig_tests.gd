extends Node

## Pruebas del rig skinned del pescador. El contrato tiene cuatro costuras:
## 1. NOMBRES: los huesos articulados usan los nombres EXACTOS de
##    SkeletonProfileHumanoid — es lo que permite automapear un BoneMap y
##    retargetear cualquier animacion humanoide (Mixamo y cia) sin tocar nada.
## 2. CADENAS: rotar un hueso arrastra TODO lo que cuelga (la jerarquia plana
##    del GLB original no lo hacia: las botas eran hermanas de las piernas).
## 3. T-POSE: la pose de descanso es la de siempre — el modelo no se movio ni
##    un milimetro al riggearlo.
## 4. PIEL Y CARA: las 38 mallas comparten una Skin valida, sus pesos apuntan al
##    Skeleton3D y los diez morphs de expresion sobreviven a cada reexportacion.
##
##   godot --path . tests/rig_tests.tscn

const MODEL_PATH := "res://game/player/pescador_smooth.glb"
const EXPECTED_MESH_COUNT := 38

const JOINTS: Array[String] = [
	"Root", "Hips", "Spine", "Chest", "UpperChest", "Neck", "Head",
	"LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
	"RightUpperLeg", "RightLowerLeg", "RightFoot",
]

const SKIN_BONES: Array[String] = [
	"Root", "Hips", "Spine", "Chest", "UpperChest", "Neck", "Head",
	"barba", "sombrero",
	"RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
	"LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightUpperLeg", "RightLowerLeg", "RightFoot",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
]

const FACE_MORPHS: Array[String] = [
	"blink_L", "blink_R", "smile", "tense", "talk", "effort",
	"look_left", "look_right", "look_up", "look_down",
]

## No alcanza con conservar diez nombres globales: cada control debe seguir en
## la pieza que lo ejecuta, o el controlador facial puede encontrarlo y aun asi
## gesticular con el ojo, ceja o boca equivocados.
const FACE_MORPH_OWNERS := {
	"Brow_L": ["tense", "effort"],
	"Brow_R": ["tense", "effort"],
	"Eye_L": ["blink_L"],
	"Eye_R": ["blink_R"],
	"FaceMouthMesh": ["smile", "tense", "talk", "effort"],
	"Pupil_L": ["look_left", "look_right", "look_up", "look_down", "blink_L"],
	"Pupil_R": ["look_left", "look_right", "look_up", "look_down", "blink_R"],
}

## El asset historico nombra las palmas por el lado de pantalla, no por la
## anatomia. player.gd busca palma_R para el viewmodel, asi que preservar tanto
## el nombre como este bind evita invertir manos sin que nadie avise.
const PALM_BINDINGS := {
	"palma_L": "RightHand",
	"palma_R": "LeftHand",
}

## hueso -> padre esperado. barba y sombrero son extras fuera de perfil
## (candidatos a SpringBoneSimulator3D), pero cuelgan de la cabeza.
const PARENTS := {
	"Hips": "Root", "Spine": "Hips", "Chest": "Spine", "UpperChest": "Chest",
	"Neck": "UpperChest", "Head": "Neck", "barba": "Head", "sombrero": "Head",
	"LeftShoulder": "UpperChest", "LeftUpperArm": "LeftShoulder",
	"LeftLowerArm": "LeftUpperArm", "LeftHand": "LeftLowerArm",
	"RightShoulder": "UpperChest", "RightUpperArm": "RightShoulder",
	"RightLowerArm": "RightUpperArm", "RightHand": "RightLowerArm",
	"LeftUpperLeg": "Hips", "LeftLowerLeg": "LeftUpperLeg",
	"LeftFoot": "LeftLowerLeg",
	"RightUpperLeg": "Hips", "RightLowerLeg": "RightUpperLeg",
	"RightFoot": "RightLowerLeg",
}

var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0


func _ready() -> void:
	print_rich("[b]--- Pruebas del rig ---[/b]")
	await _test_rig()
	await _test_retarget()
	_report()


func _check(condition: bool, label: String, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("  ok    %s" % label)
	else:
		var line := "  FALLO %s%s" % [label, ("  ->  " + detail) if detail != "" else ""]
		print(line)
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


## La prueba que caza el espejo y cualquier rotura del retarget: con el clip de
## Mixamo aplicado, en mitad de la zancada la mano tiene que estar POR DEBAJO
## del hombro. Espejado o con la cadena mal, se va a la cara.
func _test_retarget() -> void:
	var anim_path := "res://game/player/animations/walk_retargeted.res"
	if not ResourceLoader.exists(anim_path):
		_check(false, "existe el clip retargeteado", anim_path)
		return
	_check(true, "existe el clip retargeteado (horneado del FBX de Mixamo)")

	var model := (load(MODEL_PATH) as PackedScene).instantiate() as Node3D
	add_child(model)
	var skel := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var anim: Animation = (load(anim_path) as Animation).duplicate(true)
	var rel := String(model.get_path_to(skel))
	var apuntadas := 0
	for t in anim.get_track_count():
		var hueso := String(anim.track_get_path(t)).split(":")[-1]
		anim.track_set_path(t, NodePath(rel + ":" + hueso))
		if skel.find_bone(hueso) != -1:
			apuntadas += 1
	_check(apuntadas == anim.get_track_count(),
		"todas las pistas del clip apuntan a huesos que existen",
		"%d de %d" % [apuntadas, anim.get_track_count()])

	var lib := AnimationLibrary.new()
	lib.add_animation(&"walk", anim)
	var ap := AnimationPlayer.new()
	model.add_child(ap)
	ap.root_node = ap.get_path_to(model)
	ap.add_animation_library(&"", lib)
	ap.play(&"walk")
	ap.seek(anim.length * 0.25, true)
	await get_tree().process_frame
	await get_tree().process_frame

	var hombro := skel.get_bone_global_pose(skel.find_bone("RightUpperArm")).origin
	var mano := skel.get_bone_global_pose(skel.find_bone("RightHand")).origin
	_check(mano.y < hombro.y - 0.15, "caminando, la mano cuelga por debajo del hombro",
		"hombro y=%.2f mano y=%.2f" % [hombro.y, mano.y])

	var pie_i := skel.get_bone_global_pose(skel.find_bone("LeftFoot")).origin
	var pie_d := skel.get_bone_global_pose(skel.find_bone("RightFoot")).origin
	_check(absf(pie_i.z - pie_d.z) > 0.1, "y un pie va adelante del otro (zancada)",
		"dz=%.2f" % absf(pie_i.z - pie_d.z))

	model.queue_free()
	await get_tree().process_frame


func _test_rig() -> void:
	# Instancia SUELTA del modelo, no la del jugador: encima del jugador corre
	# el AnimationTree, que reescribe las poses cada frame y volveria estas
	# comprobaciones una loteria. Que el modelo este montado en el jugador lo
	# comprueba tests/anim_tests.tscn.
	var model := (load(MODEL_PATH) as PackedScene).instantiate() as Node3D
	add_child(model)
	await get_tree().process_frame
	await get_tree().process_frame

	var skels := model.find_children("*", "Skeleton3D", true, false)
	_check(skels.size() == 1, "hay UN esqueleto dentro del pescador",
		"hay %d" % skels.size())
	if skels.is_empty():
		return
	var skel := skels[0] as Skeleton3D
	_check(skel.get_bone_count() == SKIN_BONES.size(),
		"el esqueleto conserva exactamente sus 23 huesos",
		"hay %d" % skel.get_bone_count())

	# 1. Nombres del perfil humanoide.
	for joint in JOINTS:
		_check(skel.find_bone(joint) != -1, "existe el hueso %s" % joint)

	# 2. Las cadenas: cada hueso cuelga de quien tiene que colgar.
	for bone: String in PARENTS:
		var i := skel.find_bone(bone)
		var pi := skel.get_bone_parent(i) if i != -1 else -1
		var pname := skel.get_bone_name(pi) if pi != -1 else "-"
		_check(pname == PARENTS[bone], "%s cuelga de %s" % [bone, PARENTS[bone]],
			"cuelga de %s" % pname)

	# 3. T-pose de descanso: brazos en cruz a la altura del hombro, cabeza
	# arriba, pies abajo. En espacio del esqueleto (el modelo mira +Z).
	var rest_hand := skel.get_bone_global_rest(skel.find_bone("RightHand")).origin
	var rest_shoulder := skel.get_bone_global_rest(skel.find_bone("RightUpperArm")).origin
	_check(rest_hand.x < rest_shoulder.x - 0.2, "el brazo derecho sale en cruz",
		"mano x=%.2f hombro x=%.2f" % [rest_hand.x, rest_shoulder.x])
	# EL ESPEJO: el modelo mira a +Z, asi que derecha = Z x Y = -X. Si esto se
	# invierte, cualquier animacion humanoide entra espejada (lo cazamos una vez
	# con los brazos disparados a la cara).
	var rest_hand_l := skel.get_bone_global_rest(skel.find_bone("LeftHand")).origin
	_check(rest_hand.x < 0.0 and rest_hand_l.x > 0.0,
		"la mano derecha esta en -X y la izquierda en +X (mirando a +Z)",
		"R.x=%.2f L.x=%.2f" % [rest_hand.x, rest_hand_l.x])
	_check(absf(rest_hand.y - rest_shoulder.y) < 0.01, "y horizontal (T-pose)")
	var rest_head := skel.get_bone_global_rest(skel.find_bone("Head")).origin
	var rest_hips := skel.get_bone_global_rest(skel.find_bone("Hips")).origin
	var rest_foot := skel.get_bone_global_rest(skel.find_bone("LeftFoot")).origin
	_check(rest_head.y > rest_hips.y and rest_hips.y > rest_foot.y,
		"cabeza > cadera > pie")

	# Los huesos articulados no traen escala (escalar huesos rompe ragdoll y
	# retarget; la escala vive solo en las mallas hoja como palma/puntera).
	var scaled: Array[String] = []
	for joint in JOINTS:
		var b := skel.get_bone_rest(skel.find_bone(joint)).basis
		if not b.get_scale().is_equal_approx(Vector3.ONE):
			scaled.append(joint)
	_check(scaled.is_empty(), "ninguna articulacion tiene escala en el rest",
		", ".join(scaled))

	# 4. La prueba FUNCIONAL: rotar el hombro arrastra la mano esqueletica. Las
	# mallas skinned no mueven su Node3D: el vertex shader las deforma. Por eso
	# su costura se prueba abajo, inspeccionando Skin, binds y pesos reales.
	var hand_idx := skel.find_bone("RightHand")
	var hand_rest_y := skel.get_bone_global_rest(hand_idx).origin.y
	var hand_rest := skel.get_bone_global_rest(hand_idx).origin
	var shoulder := skel.find_bone("RightUpperArm")
	# Giramos en el eje LOCAL del hueso: tras el overwrite_axis los ejes son los
	# del perfil, no los del modelo, asi que el test no puede asumir cual es cual.
	skel.set_bone_pose_rotation(shoulder, Quaternion(Vector3(1, 0, 0), deg_to_rad(70)))
	await get_tree().process_frame
	await get_tree().process_frame

	var moved := skel.get_bone_global_pose(hand_idx).origin.distance_to(hand_rest)
	_check(moved > 0.15, "girar el hombro ARRASTRA la mano (cadena viva)",
		"se movio %.2f m" % moved)

	skel.reset_bone_poses()
	await get_tree().process_frame
	_check(absf(skel.get_bone_global_pose(hand_idx).origin.y - hand_rest_y) < 0.001,
		"reset_bone_poses vuelve a la T-pose")

	# 5. La piel nativa reemplaza los 37 BoneAttachment3D rigidos del modelo
	# anterior. Validamos la costura que Godot usa de verdad, no el movimiento
	# del Node3D (que deliberadamente queda quieto durante el skinning).
	_test_native_skin(model, skel)
	_test_face_morphs(model)

	model.queue_free()
	await get_tree().process_frame


func _mesh_of(model: Node, part: String) -> MeshInstance3D:
	var found := model.find_children(part, "MeshInstance3D", true, false)
	return found[0] if not found.is_empty() else null


func _test_native_skin(model: Node3D, skel: Skeleton3D) -> void:
	var meshes: Array[Node] = model.find_children("*", "MeshInstance3D", true, false)
	_check(meshes.size() == EXPECTED_MESH_COUNT,
		"las 38 piezas del pescador smooth siguen ahi",
		"hay %d" % meshes.size())
	_check(_mesh_of(model, "Beard") == null,
		"la barba blanca volumetrica ya no existe")
	_check(_mesh_of(model, "Moustache_L") == null and _mesh_of(model, "Moustache_R") == null,
		"no quedan bigotes flotantes")
	var head_mesh := _mesh_of(model, "HeadMesh")
	var head_surfaces := head_mesh.mesh.get_surface_count() if head_mesh != null \
		and head_mesh.mesh != null else 0
	_check(head_surfaces >= 2,
		"HeadMesh contiene la barba gris como superficie de la piel",
		"hay %d superficies" % head_surfaces)

	var skins: Array[Skin] = []
	var missing_mesh: PackedStringArray = PackedStringArray()
	var missing_skin: PackedStringArray = PackedStringArray()
	var broken_skeleton_path: PackedStringArray = PackedStringArray()
	var weight_errors: PackedStringArray = PackedStringArray()
	for mesh_node: Node in meshes:
		var mesh_instance := mesh_node as MeshInstance3D
		if mesh_instance.mesh == null:
			missing_mesh.append(String(mesh_instance.name))
			continue
		if mesh_instance.skin == null:
			missing_skin.append(String(mesh_instance.name))
			continue
		if not skins.has(mesh_instance.skin):
			skins.append(mesh_instance.skin)
		if mesh_instance.get_node_or_null(mesh_instance.skeleton) != skel:
			broken_skeleton_path.append(String(mesh_instance.name))
		var weight_error := _skin_weight_error(mesh_instance)
		if weight_error != "":
			weight_errors.append("%s: %s" % [mesh_instance.name, weight_error])

	_check(missing_mesh.is_empty(), "cada pieza tiene una Mesh real",
		", ".join(missing_mesh))
	_check(missing_skin.is_empty(), "las 38 piezas tienen Skin",
		", ".join(missing_skin))
	_check(broken_skeleton_path.is_empty(),
		"cada ruta skeleton resuelve al unico Skeleton3D",
		", ".join(broken_skeleton_path))
	_check(weight_errors.is_empty(),
		"todos los vertices tienen binds validos y pesos normalizados",
		" | ".join(weight_errors))
	_check(skins.size() == 1, "las 38 piezas comparten UNA Skin",
		"hay %d recursos Skin" % skins.size())
	if skins.is_empty():
		return

	var skin := skins[0]
	_check(skin.get_bind_count() == SKIN_BONES.size(),
		"la Skin conserva exactamente sus 23 binds",
		"hay %d" % skin.get_bind_count())
	var bind_names: PackedStringArray = PackedStringArray()
	var missing_skeleton_bones: PackedStringArray = PackedStringArray()
	for bind_index: int in skin.get_bind_count():
		var bind_name := String(skin.get_bind_name(bind_index))
		bind_names.append(bind_name)
		if skel.find_bone(bind_name) == -1:
			missing_skeleton_bones.append(bind_name)
	var missing_binds: PackedStringArray = PackedStringArray()
	for bone_name: String in SKIN_BONES:
		if not bind_names.has(bone_name):
			missing_binds.append(bone_name)
	var unexpected_binds: PackedStringArray = PackedStringArray()
	for bind_name: String in bind_names:
		if not SKIN_BONES.has(bind_name):
			unexpected_binds.append(bind_name)
	_check(missing_binds.is_empty() and unexpected_binds.is_empty(),
		"los binds nombrados coinciden con el esqueleto",
		"faltan [%s], sobran [%s]" % [
			", ".join(missing_binds), ", ".join(unexpected_binds)])
	_check(missing_skeleton_bones.is_empty(),
		"cada bind de Skin encuentra su hueso",
		", ".join(missing_skeleton_bones))

	for palm_name: String in PALM_BINDINGS:
		var found: Array[Node] = model.find_children(palm_name, "MeshInstance3D", true, false)
		_check(found.size() == 1, "existe una unica %s" % palm_name,
			"hay %d" % found.size())
		if found.size() != 1:
			continue
		var active_binds := _active_bind_names(found[0] as MeshInstance3D)
		var expected_bind: String = PALM_BINDINGS[palm_name]
		_check(active_binds.size() == 1 and active_binds[0] == expected_bind,
			"%s sigue a %s" % [palm_name, expected_bind],
			"binds activos: %s" % ", ".join(active_binds))


## Devuelve el primer fallo del buffer de skin. Una sola costura rota alcanza
## para invalidar la malla; acumular miles de vertices solo tapa el diagnostico.
func _skin_weight_error(mesh_instance: MeshInstance3D) -> String:
	for surface_index: int in mesh_instance.mesh.get_surface_count():
		var arrays: Array = mesh_instance.mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if vertices.is_empty():
			return "superficie %d sin vertices" % surface_index
		if bones.size() != weights.size() or bones.size() % vertices.size() != 0:
			return "superficie %d despareja bones=%d weights=%d vertices=%d" % [
				surface_index, bones.size(), weights.size(), vertices.size()]
		var influences_per_vertex := bones.size() / vertices.size()
		if influences_per_vertex != 4 and influences_per_vertex != 8:
			return "superficie %d usa %d influencias por vertice" % [
				surface_index, influences_per_vertex]
		for vertex_index: int in vertices.size():
			var weight_sum := 0.0
			var has_positive_weight := false
			for influence_index: int in influences_per_vertex:
				var array_index := vertex_index * influences_per_vertex + influence_index
				var weight := weights[array_index]
				if is_nan(weight) or is_inf(weight) or weight < 0.0:
					return "vertice %d tiene peso invalido %.4f" % [vertex_index, weight]
				weight_sum += weight
				if weight > 0.0001:
					has_positive_weight = true
					var bind_index := bones[array_index]
					if bind_index < 0 or bind_index >= mesh_instance.skin.get_bind_count():
						return "vertice %d apunta al bind %d" % [vertex_index, bind_index]
			if not has_positive_weight:
				return "vertice %d no tiene influencia" % vertex_index
			if absf(weight_sum - 1.0) > 0.001:
				return "vertice %d suma pesos %.5f" % [vertex_index, weight_sum]
	return ""


func _active_bind_names(mesh_instance: MeshInstance3D) -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	for surface_index: int in mesh_instance.mesh.get_surface_count():
		var arrays: Array = mesh_instance.mesh.surface_get_arrays(surface_index)
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for array_index: int in mini(bones.size(), weights.size()):
			if weights[array_index] <= 0.0001:
				continue
			var bind_index := bones[array_index]
			if bind_index < 0 or bind_index >= mesh_instance.skin.get_bind_count():
				continue
			var bind_name := String(mesh_instance.skin.get_bind_name(bind_index))
			if not names.has(bind_name):
				names.append(bind_name)
	names.sort()
	return names


func _test_face_morphs(model: Node3D) -> void:
	var morph_owners: Dictionary[String, PackedStringArray] = {}
	var empty_morphs: PackedStringArray = PackedStringArray()
	var meshes: Array[Node] = model.find_children("*", "MeshInstance3D", true, false)
	for mesh_node: Node in meshes:
		var mesh_instance := mesh_node as MeshInstance3D
		for blend_index: int in mesh_instance.mesh.get_blend_shape_count():
			var morph_name := String(mesh_instance.mesh.get_blend_shape_name(blend_index))
			var owners: PackedStringArray = morph_owners.get(
				morph_name, PackedStringArray()) as PackedStringArray
			owners.append(String(mesh_instance.name))
			morph_owners[morph_name] = owners
			if not _blend_shape_has_delta(mesh_instance, blend_index):
				empty_morphs.append("%s:%s" % [mesh_instance.name, morph_name])

	var missing_morphs: PackedStringArray = PackedStringArray()
	for morph_name: String in FACE_MORPHS:
		if not morph_owners.has(morph_name):
			missing_morphs.append(morph_name)
	var unexpected_morphs: PackedStringArray = PackedStringArray()
	for morph_name: String in morph_owners:
		if not FACE_MORPHS.has(morph_name):
			unexpected_morphs.append(morph_name)
	_check(morph_owners.size() == FACE_MORPHS.size()
			and missing_morphs.is_empty() and unexpected_morphs.is_empty(),
		"la cara conserva exactamente sus 10 morphs",
		"faltan [%s], sobran [%s]" % [
			", ".join(missing_morphs), ", ".join(unexpected_morphs)])
	_check(empty_morphs.is_empty(), "cada morph facial contiene deformacion real",
		", ".join(empty_morphs))

	for owner_name: String in FACE_MORPH_OWNERS:
		var face_mesh := _mesh_of(model, owner_name)
		_check(face_mesh != null, "existe la pieza facial %s" % owner_name)
		if face_mesh == null:
			continue
		var actual: PackedStringArray = PackedStringArray()
		for blend_index: int in face_mesh.mesh.get_blend_shape_count():
			actual.append(String(face_mesh.mesh.get_blend_shape_name(blend_index)))
		var missing: PackedStringArray = PackedStringArray()
		for morph_name: String in FACE_MORPH_OWNERS[owner_name]:
			if not actual.has(morph_name):
				missing.append(morph_name)
		var unexpected: PackedStringArray = PackedStringArray()
		for morph_name: String in actual:
			if morph_name not in FACE_MORPH_OWNERS[owner_name]:
				unexpected.append(morph_name)
		_check(missing.is_empty() and unexpected.is_empty(),
			"%s conserva sus morphs" % owner_name,
			"faltan [%s], sobran [%s]" % [
				", ".join(missing), ", ".join(unexpected)])


func _blend_shape_has_delta(mesh_instance: MeshInstance3D, blend_index: int) -> bool:
	for surface_index: int in mesh_instance.mesh.get_surface_count():
		var blend_shapes: Array[Array] = mesh_instance.mesh.surface_get_blend_shape_arrays(
			surface_index)
		if blend_index >= blend_shapes.size():
			continue
		var shape_arrays: Array = blend_shapes[blend_index]
		var deltas: PackedVector3Array = shape_arrays[Mesh.ARRAY_VERTEX]
		for delta: Vector3 in deltas:
			if delta.length_squared() > 0.00000001:
				return true
	return false
