extends Node

## Contrato headless de la bomba manual aislada.
##
## Este arnés se puede guardar antes que el asset: si la escena todavía no
## existe falla una sola vez con un mensaje útil, en lugar de producir errores
## encadenados. Cuando exista, prueba el módulo SIN Player, barco ni océano.
##
##   C:\Godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe \
##     --headless --path . tests/manual_pump_tests.tscn

const PUMP_SCENE_PATH := "res://game/boat/equipment/manual_bilge_pump.tscn"
const BOAT_SCENE_PATH := "res://game/boat/fishing_boat.tscn"
const MAX_FOOTPRINT := Vector2(0.80, 1.20)
const POSITION_TOLERANCE := 0.12

const REQUIRED_MARKERS: PackedStringArray = [
	"MountOrigin",
	"BaseContact",
	"Anchor",
	"HoseRest",
	"OperatorStand",
]

const REQUIRED_NODES: PackedStringArray = [
	"PumpBase",
	"PumpBody",
	"LeverPivot",
	"Lever",
	"CadenceIndicator",
	"CadenceWeightPivot",
	"HoseAssembly",
	"StoredCoil",
	"HoseMesh",
	"PickupHead",
	"PlacementFootprint",
]

const REQUIRED_MEDIEVAL_ART: PackedStringArray = [
	"PumpBase",
	"PumpBody",
	"IronHoops",
	"PumpSpear",
	"LeverArm",
	"LeverGrip",
	"CadenceRack",
	"CadenceTongue",
	"IntakeCoupling",
	"DischargeDale",
	"HoseCradle",
	"HoseCoil",
	"IntakeHead",
]

const FORBIDDEN_MODERN_ART: PackedStringArray = [
	"BasePlate",
	"DiaphragmRing",
	"DischargeElbow",
	"GaugeHousing",
	"GaugeFace",
	"GaugeCadenceBand",
	"GaugeNeedle",
	"GaugeNeedleHub",
]

const REQUIRED_MEDIEVAL_MATERIALS: PackedStringArray = [
	"M_Elm_Adzed",
	"M_Ash_Lever",
	"M_Forged_Iron",
	"M_Tarred_Leather",
	"M_Worn_Leather",
	"M_Hemp_Rope",
	"M_Willow_Wicker",
	"M_Bone_Cadence",
]

const REQUIRED_METHODS: PackedStringArray = [
	"tomar_manguera",
	"soltar_manguera",
	"esta_manguera_tomada",
	"posicion_toma_global",
	"get_hose",
	"get_mount_footprint",
	"get_mount_plane_y",
]

const REQUIRED_HOSE_METHODS: PackedStringArray = [
	"tomar",
	"soltar",
	"esta_tomada",
	"get_tip_global_position",
	"get_deployed_length",
	"get_max_length",
	"set_deployed_length",
	"reset_hose",
]

var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0


func _ready() -> void:
	print_rich("[b]--- Pruebas de la bomba manual ---[/b]")
	_test_instanced_on_boat()

	var exists := ResourceLoader.exists(PUMP_SCENE_PATH, "PackedScene")
	_check(exists, "la escena standalone de la bomba existe", PUMP_SCENE_PATH)
	if not exists:
		_report()
		return

	var packed := load(PUMP_SCENE_PATH) as PackedScene
	_check(packed != null, "la escena standalone carga como PackedScene")
	if packed == null:
		_report()
		return

	var pump := packed.instantiate() as Node3D
	_check(pump != null, "la raiz de la bomba es Node3D")
	if pump == null:
		_report()
		return

	add_child(pump)
	await get_tree().process_frame
	await get_tree().physics_frame

	_test_structure(pump)
	_test_medieval_art_contract(pump)
	_test_mount_contract(pump)
	_test_api(pump)
	if _has_required_api(pump):
		await _test_take_follow_limit_release(pump)
	_test_finite_tree(pump, "estado inicial")

	pump.queue_free()
	await get_tree().process_frame
	_report()


## La fase standalone termino: la bomba ya vive en el barco. Lo que este arnes
## protege ahora es que siga siendo un MODULO — montada sin offsets y por su
## propia escena, no copiada dentro del .tscn del barco, que es como se pierde
## la posibilidad de sustituirla por la bomba electrica de la mejora.
func _test_instanced_on_boat() -> void:
	var text := FileAccess.get_file_as_string(BOAT_SCENE_PATH)
	_check(text.contains(PUMP_SCENE_PATH),
		"la bomba está instanciada en fishing_boat.tscn desde su propia escena")

	var boat := (load(BOAT_SCENE_PATH) as PackedScene).instantiate() as Node3D
	add_child(boat)
	var mounted := boat.get_node_or_null(^"UpgradeSockets/PumpPort/BombaManual") as Node3D
	_check(mounted is ManualBilgePump,
		"cuelga del socket PumpPort y sigue siendo ManualBilgePump")
	if mounted != null:
		_check(mounted.position.is_equal_approx(Vector3.ZERO),
			"el contrato de montaje se cumple sin offsets escondidos",
			str(mounted.position))
		var contact := _find_named(mounted, "BaseContact") as Marker3D
		if contact != null:
			# El socket esta 25 cm sobre la cubierta y BaseContact los compensa:
			# montada de verdad, el plano de apoyo tiene que caer EN la cubierta.
			_check(absf(boat.to_local(contact.global_position).y - 0.80) < 0.01,
				"BaseContact aterriza exactamente en la cubierta jugable",
				"Y %.3f m" % boat.to_local(contact.global_position).y)
	boat.queue_free()


func _test_structure(pump: Node3D) -> void:
	for required in REQUIRED_NODES:
		_check(_find_named(pump, required) != null,
			"nodo contractual: %s" % required)

	for required in REQUIRED_MARKERS:
		_check(_find_named(pump, required) is Marker3D,
			"marcador contractual: %s" % required)

	var interaction := _find_named(pump, "PickupHead")
	_check(interaction is Area3D, "PickupHead es Area3D")
	if interaction is Area3D:
		var area := interaction as Area3D
		var shape := area.find_child("*", true, false) as CollisionShape3D
		# `find_child` no filtra por tipo: comprobar todos evita imponer un nombre
		# al shape, que no forma parte de la interfaz de arte.
		if shape == null:
			for child in area.find_children("*", "CollisionShape3D", true, false):
				shape = child as CollisionShape3D
				break
		_check(shape != null and shape.shape != null,
			"el área de agarre trae una CollisionShape3D")

	var rest := _find_named(pump, "HoseRest") as Marker3D
	var head := _find_named(pump, "PickupHead") as Node3D
	if rest != null and head != null:
		_check(head.global_position.distance_to(rest.global_position) <= 0.02,
			"el colador empieza exactamente en HoseRest",
			"error %.3f m" % head.global_position.distance_to(rest.global_position))

	var hose := _find_named(pump, "HoseAssembly")
	if hose != null and hose.has_method(&"debug_get_mesh_surface_count"):
		_check(int(hose.call(&"debug_get_mesh_surface_count")) >= 2,
			"la manguera genera cuero y refuerzos de cáñamo como superficies separadas")


func _test_medieval_art_contract(pump: Node3D) -> void:
	var visual := pump.get_node_or_null(^"PumpVisual")
	_check(visual != null, "PumpVisual importado está disponible")
	if visual == null:
		return

	for mesh_name in REQUIRED_MEDIEVAL_ART:
		_check(_find_named(visual, mesh_name) is MeshInstance3D,
			"malla medieval editable: %s" % mesh_name)
	for mesh_name in FORBIDDEN_MODERN_ART:
		_check(_find_named(visual, mesh_name) == null,
			"se eliminó la pieza moderna: %s" % mesh_name)

	var material_names: Dictionary = {}
	for child in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		for surface_index: int in mesh_instance.mesh.get_surface_count():
			var active_material := mesh_instance.get_active_material(surface_index)
			if active_material != null:
				material_names[String(active_material.resource_name)] = true
	for material_name in REQUIRED_MEDIEVAL_MATERIALS:
		_check(material_names.has(material_name),
			"material medieval importado: %s" % material_name)

	var lever_art := _find_named(visual, "LeverArm") as Node3D
	var lever_pivot := _find_named(pump, "LeverPivot") as Node3D
	if lever_art != null and lever_pivot != null:
		_check(lever_art.global_position.distance_to(lever_pivot.global_position) <= 0.01,
			"LeverPivot coincide con el origen editable de LeverArm",
			"error %.3f m" % lever_art.global_position.distance_to(lever_pivot.global_position))
	var cadence_art := _find_named(visual, "CadenceTongue") as Node3D
	var cadence_pivot := _find_named(pump, "CadenceWeightPivot") as Node3D
	if cadence_art != null and cadence_pivot != null:
		_check(cadence_art.global_position.distance_to(cadence_pivot.global_position) <= 0.01,
			"CadenceWeightPivot coincide con CadenceTongue",
			"error %.3f m" % cadence_art.global_position.distance_to(cadence_pivot.global_position))


func _test_mount_contract(pump: Node3D) -> void:
	var origin := _find_named(pump, "MountOrigin") as Marker3D
	var contact := _find_named(pump, "BaseContact") as Marker3D
	if origin != null:
		_check(origin.position.is_equal_approx(Vector3.ZERO),
			"MountOrigin coincide con la raíz", str(origin.position))
	if contact != null:
		_check(absf(contact.position.y + 0.25) <= 0.005,
			"BaseContact compensa los 25 cm del socket",
			"y=%.3f" % contact.position.y)

	if pump.has_method(&"get_mount_footprint"):
		var value: Variant = pump.call(&"get_mount_footprint")
		_check(value is Vector2, "get_mount_footprint devuelve Vector2", type_string(typeof(value)))
		if value is Vector2:
			var footprint: Vector2 = value
			_check(footprint.x > 0.0 and footprint.y > 0.0,
				"la huella es positiva", str(footprint))
			_check(footprint.x <= MAX_FOOTPRINT.x + 0.001
					and footprint.y <= MAX_FOOTPRINT.y + 0.001,
				"la huella cabe en PumpPort",
				"%s, máximo %s" % [footprint, MAX_FOOTPRINT])

	var stand := _find_named(pump, "OperatorStand") as Marker3D
	if stand != null:
		_check(stand.position.z < 0.0,
			"OperatorStand queda hacia -Z local", str(stand.position))

	if pump.has_method(&"get_mount_plane_y"):
		var plane: Variant = pump.call(&"get_mount_plane_y")
		_check((plane is float or plane is int) and absf(float(plane) + 0.25) <= 0.005,
			"get_mount_plane_y conserva la compensación del socket", str(plane))


func _test_api(pump: Node3D) -> void:
	for method_name in REQUIRED_METHODS:
		_check(pump.has_method(StringName(method_name)),
			"API independiente: %s()" % method_name)
	if not pump.has_method(&"get_hose"):
		return
	var hose := pump.call(&"get_hose") as Node
	_check(hose != null, "get_hose devuelve HoseAssembly")
	if hose == null:
		return
	for method_name in REQUIRED_HOSE_METHODS:
		_check(hose.has_method(StringName(method_name)),
			"API independiente de HoseAssembly: %s()" % method_name)


func _has_required_api(pump: Node3D) -> bool:
	for method_name in REQUIRED_METHODS:
		if not pump.has_method(StringName(method_name)):
			return false
	var hose := pump.call(&"get_hose") as Node
	if hose == null:
		return false
	for method_name in REQUIRED_HOSE_METHODS:
		if not hose.has_method(StringName(method_name)):
			return false
	return true


func _test_take_follow_limit_release(pump: Node3D) -> void:
	var head := _find_named(pump, "PickupHead") as Node3D
	var area := _find_named(pump, "PickupHead") as Area3D
	if head == null:
		return

	var grip := Marker3D.new()
	grip.name = "AgarreDePrueba"
	add_child(grip)
	grip.global_position = head.global_position

	var available: bool = not bool(pump.call(&"esta_manguera_tomada"))
	_check(available,
		"la manguera empieza disponible")

	var taken: Variant = pump.call(&"tomar_manguera", grip)
	_check(taken is bool and bool(taken), "tomar_manguera acepta un Marker3D")
	_check(bool(pump.call(&"esta_manguera_tomada")),
		"el estado confirma la toma")

	var hose := pump.call(&"get_hose") as Node
	var max_value: Variant = hose.call(&"get_max_length")
	_check(max_value is float or max_value is int,
		"la longitud máxima es numérica", type_string(typeof(max_value)))
	var max_length := float(max_value) if (max_value is float or max_value is int) else 0.0
	_check(is_finite(max_length) and max_length >= 4.0 and max_length <= 10.0,
		"la longitud máxima sirve al barco", "%.3f m" % max_length)

	# El extremo debe seguir exactamente; la forma intermedia sí puede tener
	# inercia. La trayectoria dobla en dos ejes para no aprobar un simple tubo
	# escalado entre origen y mano.
	var target_local := Vector3(max_length * 0.45, 0.35, -max_length * 0.25)
	grip.global_position = pump.to_global(target_local)
	for _frame in 90:
		await get_tree().physics_frame

	var intake: Variant = pump.call(&"posicion_toma_global")
	_check(intake is Vector3, "la posición de aspiración es Vector3")
	if intake is Vector3:
		_check((intake as Vector3).distance_to(grip.global_position) <= POSITION_TOLERANCE,
			"el cabezal sigue al agarre",
			"error %.3f m" % (intake as Vector3).distance_to(grip.global_position))
	_test_deck_clearance(hose)

	await _test_length_cap(pump, grip, max_length)
	await _test_root_motion(pump, grip, max_length)
	_test_finite_tree(pump, "después de mover y rotar la raíz")

	pump.call(&"soltar_manguera")
	await get_tree().physics_frame
	_check(not bool(pump.call(&"esta_manguera_tomada")),
		"soltar_manguera libera el estado")
	_check(not bool(pump.call(&"esta_manguera_tomada")),
		"después de soltar vuelve a estar disponible")
	if area != null:
		_check(area.collision_layer != 0,
			"el cabezal suelto conserva una capa detectable")

	grip.queue_free()


func _test_deck_clearance(hose: Node) -> void:
	if not hose.has_method(&"debug_get_points_local"):
		_check(false, "la manguera expone puntos para validar la comba")
		return
	var points: PackedVector3Array = hose.call(&"debug_get_points_local")
	_check(points.size() >= 3, "la curva utiliza varios puntos físicos")
	if points.size() < 3:
		return
	var endpoint_floor: float = minf(points[0].y, points[points.size() - 1].y)
	var max_sag: float = float(hose.get("comba_maxima_bajo_extremos"))
	var lowest: float = INF
	for index: int in range(1, points.size() - 1):
		lowest = minf(lowest, points[index].y)
	_check(lowest >= endpoint_floor - max_sag - 0.03,
		"la manguera no desaparece bajo una cubierta plana",
		"mínimo %.3f / límite %.3f" % [lowest, endpoint_floor - max_sag])


func _test_length_cap(pump: Node3D, grip: Marker3D, max_length: float) -> void:
	if max_length <= 0.0:
		return
	grip.global_position = pump.to_global(Vector3(max_length * 1.6, 0.2, 0.0))
	for _frame in 60:
		await get_tree().physics_frame
	var hose := pump.call(&"get_hose") as Node
	var value: Variant = hose.call(&"get_deployed_length")
	_check(value is float or value is int,
		"la longitud actual es numérica", type_string(typeof(value)))
	if value is float or value is int:
		var length := float(value)
		_check(is_finite(length) and length >= 0.0
				and length <= max_length + 0.03,
			"la manguera nunca supera su máximo",
			"actual %.3f / máximo %.3f" % [length, max_length])


func _test_root_motion(pump: Node3D, grip: Marker3D, max_length: float) -> void:
	# Simula que el módulo ya cuelga de un barco que traslada y cabecea. El
	# objetivo se expresa de nuevo desde la raíz movida: una simulación en mundo
	# que no transporte sus puntos dejará aquí la manguera atrás.
	pump.global_position = Vector3(4.0, 2.0, -3.0)
	pump.rotation = Vector3(0.18, 1.1, -0.12)
	var reach := minf(max_length * 0.55, 3.5)
	grip.global_position = pump.to_global(Vector3(reach, 0.3, -0.4))
	for _frame in 120:
		await get_tree().physics_frame

	var intake: Variant = pump.call(&"posicion_toma_global")
	if intake is Vector3 and bool(pump.call(&"esta_manguera_tomada")):
		_check((intake as Vector3).distance_to(grip.global_position) <= POSITION_TOLERANCE,
			"el cabezal sigue tras mover/rotar la raíz",
			"error %.3f m" % (intake as Vector3).distance_to(grip.global_position))

	var hose := pump.call(&"get_hose") as Node
	var value: Variant = hose.call(&"get_deployed_length")
	if value is float or value is int:
		var length := float(value)
		_check(is_finite(length) and length <= max_length + 0.03,
			"el movimiento de la raíz conserva el límite",
			"actual %.3f / máximo %.3f" % [length, max_length])


func _test_finite_tree(root: Node3D, label: String) -> void:
	var bad: PackedStringArray = PackedStringArray()
	var nodes: Array[Node] = [root]
	nodes.append_array(root.find_children("*", "Node3D", true, false))
	for node in nodes:
		var spatial := node as Node3D
		if spatial == null:
			continue
		var transform := spatial.global_transform
		if not transform.origin.is_finite() \
				or not transform.basis.x.is_finite() \
				or not transform.basis.y.is_finite() \
				or not transform.basis.z.is_finite():
			bad.append(str(root.get_path_to(spatial)))

	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface_index in mesh_instance.mesh.get_surface_count():
			var arrays := mesh_instance.mesh.surface_get_arrays(surface_index)
			if arrays.is_empty():
				continue
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				if not vertex.is_finite():
					bad.append("%s/surface_%d" % [root.get_path_to(mesh_instance), surface_index])
					break

	_check(bad.is_empty(), "no hay NaN/INF: %s" % label, ", ".join(bad))


func _find_named(root: Node, node_name: String) -> Node:
	if root.name == node_name:
		return root
	return root.find_child(node_name, true, false)


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
		for failure in _failures:
			print("   - " + failure)
		get_tree().quit(1)
