extends Node

## Pruebas de la capa facial del pescador.
##
## Protegen cuatro fallos silenciosos: que un reexport rompa los nombres de la
## cara, que el fallback rigido deje de gesticular, que un morph se escriba con
## el signo equivocado y —el mas caro— que la cara empiece a pelear con los
## huesos que ya gobierna PlayerAnimator.
##
##   Godot_v4.7.2-stable_win64_console.exe --headless --path . \
##       tests/player_face_animator_tests.tscn

const FACE_SCRIPT := preload("res://game/player/player_face_animator.gd")

var _checks: int = 0
var _failures: PackedStringArray = PackedStringArray()


func _ready() -> void:
	print_rich("[b]--- Pruebas de gesticulacion facial ---[/b]")
	await _test_fallback_rigido()
	await _test_blend_shapes()
	await _test_contexto_corporal_real()
	await _test_player_integration()
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
		for failure: String in _failures:
			print("   - " + failure)
		get_tree().quit(1)


func _test_fallback_rigido() -> void:
	var fixture := _rigid_fixture()
	var model := fixture["model"] as Node3D
	var skeleton := fixture["skeleton"] as Skeleton3D
	add_child(model)
	var face := FACE_SCRIPT.new() as PlayerFaceAnimator
	add_child(face)
	_check(face.setup(model, 12345), "el fallback encuentra una cara rigida")
	face.set_process(false)
	var caps := face.capabilities()
	_check(bool(caps["blink"]), "ojos separados habilitan parpadeo")
	_check(bool(caps["gaze"]), "ojos separados habilitan mirada")
	_check(bool(caps["expression"]), "cejas/boca habilitan expresion")
	_check(bool(caps["speaking"]), "boca separada habilita habla")

	var eye_l := fixture["eye_l"] as MeshInstance3D
	var eye_r := fixture["eye_r"] as MeshInstance3D
	var brow_l := fixture["brow_l"] as MeshInstance3D
	var mouth := fixture["mouth"] as MeshInstance3D
	var eye_l_base: Transform3D = eye_l.transform
	var eye_r_base: Transform3D = eye_r.transform
	var brow_base: Transform3D = brow_l.transform
	var mouth_base: Transform3D = mouth.transform
	var head := skeleton.find_bone("Head")
	var head_before := skeleton.get_bone_pose(head)

	face.force(0.0, 0.0, 0.0, 0.0, Vector2.ZERO, 1.0)
	_check(eye_l.transform.basis.get_scale().y < eye_l_base.basis.get_scale().y * 0.2,
		"force(blink=1) cierra el ojo izquierdo")
	_check(eye_r.transform.basis.get_scale().y < eye_r_base.basis.get_scale().y * 0.2,
		"y cierra el derecho a la vez")

	face.force(0.0, 0.0, 0.0, 0.0, Vector2(1.0, 0.5), 0.0)
	_check(eye_l.position.x < eye_l_base.origin.x and eye_l.position.y > eye_l_base.origin.y,
		"mirar derecha/arriba mueve ambos ejes en el marco anatomico")
	_check((eye_l.position - eye_l_base.origin).is_equal_approx(
		eye_r.position - eye_r_base.origin), "los dos ojos convergen en la misma direccion")

	face.force(1.0, 0.0, 0.0, 0.0)
	_check(mouth.transform.basis.get_scale().x > mouth_base.basis.get_scale().x * 1.2,
		"la sonrisa ensancha la boca rigida")
	_check(brow_l.position.y > brow_base.origin.y, "y levanta las cejas")

	face.force(0.0, 1.0, 0.0, 0.0)
	_check(not brow_l.transform.basis.is_equal_approx(brow_base.basis),
		"la tension inclina las cejas")
	_check(mouth.transform.basis.get_scale().x < mouth_base.basis.get_scale().x,
		"y aprieta la boca")

	face.force(0.0, 0.0, 1.0, 0.0)
	_check(mouth.transform.basis.get_scale().y > mouth_base.basis.get_scale().y * 2.0,
		"hablar abre una boca sin morphs")
	face.force(0.0, 0.0, 0.0, 1.0)
	_check(eye_l.transform.basis.get_scale().y < eye_l_base.basis.get_scale().y,
		"el esfuerzo entrecierra los ojos")

	_check(skeleton.get_bone_pose(head).is_equal_approx(head_before),
		"ninguna gesticulacion escribe el hueso Head")
	face.reset()
	_check(eye_l.transform.is_equal_approx(eye_l_base)
		and mouth.transform.is_equal_approx(mouth_base),
		"reset restaura exactamente la cara importada")

	face.play_emote(&"feliz", 1.0, 0.5)
	face.advance(0.2)
	_check(float(face.debug_state()["smile"]) > 0.7,
		"el emote feliz entra con smoothing")
	face.advance(0.5)
	face.advance(0.5)
	_check(float(face.debug_state()["smile"]) < 0.05,
		"y sale solo al terminar su hold")

	face.teardown()
	_check(eye_l.transform.is_equal_approx(eye_l_base)
		and brow_l.transform.is_equal_approx(brow_base),
		"teardown no deja offsets en el modelo")
	face.queue_free()
	model.queue_free()
	await get_tree().process_frame


func _test_blend_shapes() -> void:
	var model := Node3D.new()
	model.name = "ModeloConMorphs"
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "FaceMesh"
	mesh_node.mesh = _morph_mesh([
		&"blink_L", &"blink_R", &"look_left", &"look_right", &"look_up",
		&"look_down", &"smile", &"tense", &"talk", &"effort",
	])
	model.add_child(mesh_node)
	add_child(model)
	var face := FACE_SCRIPT.new() as PlayerFaceAnimator
	add_child(face)
	_check(face.setup(model, 8), "una cara unificada funciona solo con blend shapes")
	face.set_process(false)
	var caps := face.capabilities()
	_check(int(caps["blend_shape_channels"]) == 10,
		"descubre los diez morphs por nombre", str(caps))

	face.force(0.8, 0.6, 0.7, 0.5, Vector2(0.8, -0.5), 0.75)
	_check(_shape_value(mesh_node, &"blink_L") > 0.74
		and _shape_value(mesh_node, &"blink_R") > 0.74,
		"parpadeo separado escribe ambos morphs")
	_check(_shape_value(mesh_node, &"look_right") > 0.79
		and _shape_value(mesh_node, &"look_left") < 0.01,
		"la mirada derecha no activa el morph opuesto")
	_check(_shape_value(mesh_node, &"look_down") > 0.49,
		"la componente vertical llega al morph")
	_check(_shape_value(mesh_node, &"smile") > 0.2
		and _shape_value(mesh_node, &"tense") > 0.8,
		"sonrisa y tension se combinan sin sobrepasar 1")
	_check(absf(_shape_value(mesh_node, &"talk") - 0.7) < 0.01,
		"force congela una apertura de habla exacta")
	_check(absf(_shape_value(mesh_node, &"effort") - 0.5) < 0.01,
		"el esfuerzo tiene canal independiente")

	face.reset()
	var all_zero := true
	for index: int in mesh_node.mesh.get_blend_shape_count():
		all_zero = all_zero and absf(mesh_node.get_blend_shape_value(index)) < 0.001
	_check(all_zero, "reset devuelve todos los morphs a su peso original")
	face.queue_free()
	model.queue_free()
	await get_tree().process_frame


func _test_contexto_corporal_real() -> void:
	var packed := load("res://game/player/pescador_smooth.glb") as PackedScene
	var model := packed.instantiate() as Node3D
	add_child(model)
	var body := PlayerAnimator.new()
	add_child(body)
	_check(body.setup(model), "el PlayerAnimator real esta disponible para conducir la cara")
	if body.tree == null or body.skeleton == null:
		model.queue_free()
		body.queue_free()
		return
	body.force(0.0, 1.0, true)
	body.tree.active = false
	var head_index := body.skeleton.find_bone("Head")
	var head_before := body.skeleton.get_bone_pose(head_index)

	var face := FACE_SCRIPT.new() as PlayerFaceAnimator
	add_child(face)
	_check(face.setup(model, 22), "el modelo real conserva un contrato facial reconocible")
	face.set_process(false)
	face.bind_body_animator(body)
	for _i: int in 90:
		face.advance(1.0 / 60.0)
	var storm_state := face.debug_state()
	_check(float(storm_state["tension"]) > 0.6,
		"la caña alimenta tension facial automaticamente", str(storm_state))
	_check(float(storm_state["effort"]) > 0.5,
		"el agua alimenta esfuerzo facial automaticamente", str(storm_state))
	_check(body.skeleton.get_bone_pose(head_index).is_equal_approx(head_before),
		"la conduccion automatica tampoco toca Head")

	body.force(0.0, 0.0, false)
	for _i: int in 90:
		face.advance(1.0 / 60.0)
	var calm_state := face.debug_state()
	_check(float(calm_state["tension"]) < 0.05 and float(calm_state["effort"]) < 0.05,
		"al volver a idle la cara suelta esfuerzo y tension", str(calm_state))

	face.queue_free()
	body.queue_free()
	model.queue_free()
	await get_tree().process_frame


## Costura final: no alcanza con que el controlador funcione aislado; la escena
## que usa juego y red tiene que montarlo sobre el mismo modelo y animator.
func _test_player_integration() -> void:
	var player := (load("res://game/player/player.tscn") as PackedScene).instantiate() as Player
	add_child(player)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(player.face_animator != null,
		"player.tscn monta el controlador facial automaticamente")
	if player.face_animator != null:
		_check(player.face_animator.model == player.get_node_or_null(^"Pescador"),
			"la cara controla el mismo pescador que se dibuja")
		_check(player.face_animator.body_animator == player.animator,
			"y escucha el mismo PlayerAnimator que locomocion/red")
	player.queue_free()
	await get_tree().process_frame


func _rigid_fixture() -> Dictionary:
	var model := Node3D.new()
	model.name = "PescadorRigido"
	var skeleton := Skeleton3D.new()
	skeleton.name = "GeneralSkeleton"
	skeleton.add_bone("Head")
	skeleton.set_bone_rest(0, Transform3D(Basis.IDENTITY, Vector3(0.0, 1.1, 0.0)))
	model.add_child(skeleton)
	var eye_l := _part("ojo_L", Vector3(0.09, 1.42, 0.2))
	var eye_r := _part("ojo_R", Vector3(-0.09, 1.42, 0.2))
	var brow_l := _part("ceja_L", Vector3(0.09, 1.50, 0.205))
	var brow_r := _part("ceja_R", Vector3(-0.09, 1.50, 0.205))
	var mouth := _part("boca", Vector3(0.0, 1.27, 0.21))
	for part: MeshInstance3D in [eye_l, eye_r, brow_l, brow_r, mouth]:
		model.add_child(part)
	return {
		"model": model,
		"skeleton": skeleton,
		"eye_l": eye_l,
		"eye_r": eye_r,
		"brow_l": brow_l,
		"brow_r": brow_r,
		"mouth": mouth,
	}


func _part(part_name: String, part_position: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	part.position = part_position
	var box := BoxMesh.new()
	box.size = Vector3(0.08, 0.04, 0.025)
	part.mesh = box
	return part


func _morph_mesh(names: Array[StringName]) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for shape_name: StringName in names:
		mesh.add_blend_shape(shape_name)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	var vertices := PackedVector3Array([
		Vector3(-0.1, -0.1, 0.0),
		Vector3(0.1, -0.1, 0.0),
		Vector3(0.0, 0.1, 0.0),
	])
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var morphs: Array = []
	for _shape_name: StringName in names:
		var morph: Array = []
		morph.resize(Mesh.ARRAY_MAX)
		morph[Mesh.ARRAY_VERTEX] = vertices
		morphs.append(morph)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, morphs)
	return mesh


func _shape_value(mesh_node: MeshInstance3D, shape_name: StringName) -> float:
	for index: int in mesh_node.mesh.get_blend_shape_count():
		if mesh_node.mesh.get_blend_shape_name(index) == shape_name:
			return mesh_node.get_blend_shape_value(index)
	return -99.0
