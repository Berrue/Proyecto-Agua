extends Node

## Contrato silencioso del asset de barco. La fisica vive en Godot y el arte en
## un GLB reexportable: este arnes detecta que una edicion de Blender no cambie
## ejes, escala, jerarquia o nombres de modulo sin que nadie lo note.
##
##   godot --headless --path . tests/boat_asset_tests.tscn

const REQUIRED_MESHES: PackedStringArray = [
	"HullShell",
	"Transom",
	"WorkingDeck",
	"BulwarkPort",
	"BulwarkStarboard",
	"BulwarkStern",
	"BulwarkBow",
	"DeckPlankSeams",
	"WheelhouseFrontFrame",
	"WheelhousePortFrame",
	"WheelhouseStarboardFrame",
	"WheelhouseRearFrame",
	"WheelhouseRoof",
	"WheelhouseDoorOpen",
	"HelmConsole",
	"HelmWheel",
	"HelmHub",
	"InstrumentPanel",
	"SonarDisplay",
	"HatchHoldForward",
	"HatchHoldAft",
	"HatchEngine",
]

const REQUIRED_SOCKETS: PackedStringArray = [
	"Helm",
	"Sonar",
	"PumpPort",
	"PumpStarboard",
	"GearPort",
	"GearStarboard",
	"Winch",
	"HoldForward",
	"HoldAft",
	"Engine",
	"LightBow",
	"LightStern",
	"Lookout",
]

var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0


func _ready() -> void:
	print_rich("[b]--- Pruebas del asset de barco ---[/b]")
	var scene := load("res://game/boat/fishing_boat.tscn") as PackedScene
	_check(scene != null, "la escena del barco carga")
	if scene == null:
		_report()
		return

	var boat := scene.instantiate() as FloatingBody3D
	_check(boat != null, "el root sigue siendo FloatingBody3D")
	if boat == null:
		_report()
		return
	add_child(boat)

	_test_physics_contract(boat)
	_test_visual_contract(boat)
	_test_upgrade_sockets(boat)
	_test_bilge_pump(boat)
	await _test_physical_cabin_route(boat)
	boat.queue_free()
	_report()


func _test_physics_contract(boat: FloatingBody3D) -> void:
	_check(is_equal_approx(boat.mass, 4000.0), "la malla no cambia la masa", "masa %.1f kg" % boat.mass)
	_check(boat.center_of_mass_mode == RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM,
		"el centro de masa sigue siendo explicito")
	_check(boat.center_of_mass.is_equal_approx(Vector3(0.0, -0.45, 0.0)),
		"el centro de masa conserva el balance probado", str(boat.center_of_mass))

	var direct_probes: int = 0
	var direct_shapes: int = 0
	for child in boat.get_children():
		if child is BuoyancyProbe3D:
			direct_probes += 1
		elif child is CollisionShape3D:
			direct_shapes += 1
	_check(direct_probes == 8, "las ocho sondas siguen como hijas directas",
		"encontradas %d" % direct_probes)
	_check(direct_shapes == 17, "las diecisiete colisiones simples siguen separadas del GLB",
		"encontradas %d" % direct_shapes)

	var hull_shape := boat.get_node_or_null(^"HullShape") as CollisionShape3D
	var hull_box := hull_shape.shape as BoxShape3D if hull_shape != null else null
	_check(hull_box != null, "el casco central sigue siendo una caja simple",
		str(hull_box.size if hull_box != null else "sin BoxShape3D"))
	var stern_rail_ref := boat.get_node_or_null(^"RailStern") as CollisionShape3D
	if hull_box != null and hull_shape != null and stern_rail_ref != null:
		# La caja tiene que llegar hasta la borda de popa: si se queda corta, la
		# cubierta de popa se queda sin suelo y el jugador cae por dentro.
		var hull_aft_z: float = hull_shape.position.z + hull_box.size.z * 0.5
		_check(hull_aft_z >= stern_rail_ref.position.z,
			"el casco llega hasta la borda de popa: no queda cubierta sin suelo",
			"casco %.2f m / borda %.2f m" % [hull_aft_z, stern_rail_ref.position.z])

	var bow_shape := boat.get_node_or_null(^"HullBowShape") as CollisionShape3D
	var bow_convex := bow_shape.shape as ConvexPolygonShape3D if bow_shape != null else null
	_check(bow_convex != null and bow_convex.points.size() >= 8,
		"la proa usa una envolvente convexa dinamica, no un trimesh")
	if bow_convex != null:
		var tip_half_width: float = 0.0
		for point in bow_convex.points:
			if point.z < -5.5:
				tip_half_width = maxf(tip_half_width, absf(point.x))
		_check(tip_half_width <= 0.15,
			"la colision de la roda se afina con la malla visible",
			"semimanga %.2f m" % tip_half_width)
		# La caja central y la envolvente de proa tienen que ENCONTRARSE. Si se
		# separan queda un hueco por el que se cuela el jugador; si se pisan,
		# un escalon invisible. Se comprueban una contra otra, nunca contra una
		# medida fija: la eslora vive en tools/build_modular_boat.py.
		var bow_aft_z: float = -INF
		for point in bow_convex.points:
			bow_aft_z = maxf(bow_aft_z, point.z)
		if hull_box != null and hull_shape != null:
			var hull_forward_z: float = hull_shape.position.z - hull_box.size.z * 0.5
			_check(absf(hull_forward_z - bow_aft_z) < 0.02,
				"la caja central y la proa convexa se encuentran sin hueco ni escalón",
				"caja %.3f m / convexa %.3f m" % [hull_forward_z, bow_aft_z])

	var bow_rail := boat.get_node_or_null(^"RailBow") as CollisionShape3D
	var bow_rail_box := bow_rail.shape as BoxShape3D if bow_rail != null else null
	_check(bow_rail_box != null and bow_rail_box.size.x < 1.0,
		"la borda frontal ya no es una pared invisible de 4,5 m",
		str(bow_rail_box.size if bow_rail_box != null else "sin BoxShape3D"))

	_check(boat.get_node_or_null(^"HouseShape") == null,
		"ya no existe la caja solida que cerraba toda la cabina")
	var cabin_shape_names: PackedStringArray = [
		"CabinFrontShape",
		"CabinPortShape",
		"CabinStarboardShape",
		"CabinRearPortShape",
		"CabinRearStarboardShape",
		"CabinRearHeaderShape",
		"CabinRoofShape",
		"HelmConsoleShape",
	]
	for shape_name in cabin_shape_names:
		var cabin_shape := boat.get_node_or_null(NodePath(shape_name)) as CollisionShape3D
		_check(cabin_shape != null and cabin_shape.shape is BoxShape3D,
			"proxy modular de cabina: %s" % shape_name)

	var capsule := _player_capsule()
	_check(capsule != null, "el contrato de acceso usa la capsula real del jugador")
	if capsule != null:
		var rear_port := boat.get_node(^"CabinRearPortShape") as CollisionShape3D
		var rear_starboard := boat.get_node(^"CabinRearStarboardShape") as CollisionShape3D
		var rear_port_box := rear_port.shape as BoxShape3D
		var rear_starboard_box := rear_starboard.shape as BoxShape3D
		var doorway_width: float = (
			rear_starboard.position.x - rear_starboard_box.size.x * 0.5
			- (rear_port.position.x + rear_port_box.size.x * 0.5)
		)
		var header := boat.get_node(^"CabinRearHeaderShape") as CollisionShape3D
		var header_box := header.shape as BoxShape3D
		var doorway_height: float = header.position.y - header_box.size.y * 0.5 - 0.80
		_check(doorway_width >= capsule.radius * 2.0 + 0.20,
			"la puerta deja 20 cm extra respecto al jugador",
			"vano %.2f m / jugador %.2f m" % [doorway_width, capsule.radius * 2.0])
		_check(doorway_height >= capsule.height + 0.15,
			"el dintel supera al jugador por al menos 15 cm",
			"vano %.2f m / jugador %.2f m" % [doorway_height, capsule.height])

		var side_rail := boat.get_node(^"RailStarboard") as CollisionShape3D
		var side_rail_box := side_rail.shape as BoxShape3D
		var cabin_side := boat.get_node(^"CabinStarboardShape") as CollisionShape3D
		var cabin_side_box := cabin_side.shape as BoxShape3D
		var side_passage: float = (
			side_rail.position.x - side_rail_box.size.x * 0.5
			- (cabin_side.position.x + cabin_side_box.size.x * 0.5)
		)
		_check(side_passage >= capsule.radius * 2.0 + 0.12,
			"el pasillo lateral admite la capsula con margen real",
			"paso %.2f m" % side_passage)

		var stern_rail := boat.get_node(^"RailStern") as CollisionShape3D
		var stern_rail_box := stern_rail.shape as BoxShape3D
		var stern_passage: float = (
			stern_rail.position.z - stern_rail_box.size.z * 0.5
			- (rear_port.position.z + rear_port_box.size.z * 0.5)
		)
		_check(stern_passage >= capsule.radius * 2.0 + 0.20,
			"la franja de popa permite girar hacia la puerta",
			"paso %.2f m" % stern_passage)

		var roof := boat.get_node(^"CabinRoofShape") as CollisionShape3D
		var roof_box := roof.shape as BoxShape3D
		var headroom: float = roof.position.y - roof_box.size.y * 0.5 - 0.80
		_check(headroom >= capsule.height + 0.20,
			"la cabina conserva altura libre para permanecer dentro",
			"altura %.2f m" % headroom)

	var probe_port := boat.get_node_or_null(^"ProbeBowPort") as BuoyancyProbe3D
	var probe_starboard := boat.get_node_or_null(^"ProbeBowStarboard") as BuoyancyProbe3D
	_check(probe_port != null and probe_starboard != null,
		"existen las dos sondas de proa")
	if probe_port != null and probe_starboard != null:
		_check(absf(probe_port.position.x) <= 0.20 and absf(probe_starboard.position.x) <= 0.20,
			"las sondas de proa quedan junto a crujia dentro del volumen sumergido",
			"X %.2f / %.2f" % [probe_port.position.x, probe_starboard.position.x])
		_check(is_equal_approx(probe_port.position.z, -4.0)
			and is_equal_approx(probe_starboard.position.z, -4.0),
			"las sondas delanteras conservan brazo de cabeceo util",
			"Z %.2f / %.2f" % [probe_port.position.z, probe_starboard.position.z])


func _test_visual_contract(boat: FloatingBody3D) -> void:
	var visual := boat.get_node_or_null(^"BoatVisual") as Node3D
	_check(visual != null, "existe la subescena visual importada")
	if visual == null:
		return

	var meshes: Array[Node] = visual.find_children("*", "MeshInstance3D", true, false)
	_check(meshes.size() >= 35, "el GLB conserva sus piezas modulares",
		"MeshInstance3D encontrados %d" % meshes.size())
	_check(visual.find_children("*", "CollisionObject3D", true, false).is_empty(),
		"el GLB no importa fisica propia")

	for required in REQUIRED_MESHES:
		_check(visual.find_child(required, true, false) is MeshInstance3D,
			"malla estable: %s" % required)
	_check(visual.find_child("WheelhouseBody", true, false) == null,
		"la visual tampoco conserva el bloque cerrado anterior")

	for window_name in ["FrontWindowPort", "FrontWindowStarboard"]:
		var window := visual.find_child(window_name, true, false) as MeshInstance3D
		if window != null:
			var window_position := boat.to_local(window.global_position)
			_check(window_position.z > 2.15 and window_position.z < 2.30,
				"%s ocupa el hueco real del marco frontal" % window_name,
				str(window_position))

	var working_deck := visual.find_child("WorkingDeck", true, false) as MeshInstance3D
	if working_deck != null and working_deck.mesh != null:
		var deck_material := working_deck.get_active_material(0)
		_check(deck_material != null and deck_material.resource_name.begins_with("M_DeckWood"),
			"la cubierta usa un material de madera editable",
			deck_material.resource_name if deck_material != null else "sin material")
	var plank_seams := visual.find_child("DeckPlankSeams", true, false) as MeshInstance3D
	if plank_seams != null:
		var seams_to_boat := boat.global_transform.affine_inverse() * plank_seams.global_transform
		var seam_bounds := seams_to_boat * plank_seams.get_aabb()
		_check(seam_bounds.size.x > 3.5 and seam_bounds.size.z > 10.0,
			"las juntas de madera recorren la cubierta y el piso de cabina",
			str(seam_bounds))
		_check(absf(seam_bounds.position.y - 0.80) < 0.12,
			"las juntas descansan sobre la cubierta jugable",
			"Y %.2f" % seam_bounds.position.y)

	var helm_wheel := visual.find_child("HelmWheel", true, false) as MeshInstance3D
	if helm_wheel != null:
		var wheel_bounds := helm_wheel.get_aabb()
		_check(wheel_bounds.size.x >= 0.58 and wheel_bounds.size.x <= 0.72
			and wheel_bounds.size.y >= 0.58 and wheel_bounds.size.y <= 0.72,
			"el timon tiene diametro legible para primera persona",
			str(wheel_bounds.size))

	var hull := visual.find_child("HullShell", true, false) as MeshInstance3D
	if hull != null and hull.mesh != null:
		_check(hull.mesh.get_surface_count() == 2,
			"el casco mantiene pintura y antifouling separados",
			"superficies %d" % hull.mesh.get_surface_count())

	var transom := visual.find_child("Transom", true, false) as MeshInstance3D
	if transom != null and transom.mesh != null:
		_check(transom.mesh.get_surface_count() == 2,
			"el espejo separa pintura y antifouling en la linea de agua",
			"superficies %d" % transom.mesh.get_surface_count())
		var transom_to_boat := boat.global_transform.affine_inverse() * transom.global_transform
		var transom_bounds := transom_to_boat * transom.get_aabb()
		# La borda de popa y la tapa del casco cierran la MISMA popa, así que se
		# comparan entre sí. Contra una Z fija esto dejó de restringir nada en
		# cuanto creció la eslora: 5,85 daba 6 cm de margen con 12 m de barco y
		# medio metro con 13. Si una pasada futura escala las cuadernas y olvida
		# la borda de popa (o al revés), aquí queda una ranura abierta al agua.
		var stern_bulwark := visual.find_child("BulwarkStern", true, false) as MeshInstance3D
		if stern_bulwark != null:
			var stern_bulwark_z: float = boat.to_local(stern_bulwark.global_position).z
			_check(absf(stern_bulwark_z - transom_bounds.position.z) < 0.15,
				"el espejo superior cierra contra la tapa de popa del casco",
				"borda %.2f m / tapa %.2f m" % [stern_bulwark_z, transom_bounds.position.z])
			var stern_rail_shape := boat.get_node_or_null(^"RailStern") as CollisionShape3D
			if stern_rail_shape != null:
				_check(absf(stern_rail_shape.position.z - stern_bulwark_z) < 0.15,
					"la borda de popa que frena coincide con la que se ve",
					"colisión %.2f m / malla %.2f m" % [
						stern_rail_shape.position.z, stern_bulwark_z])

	var bulwark := visual.find_child("BulwarkStarboard", true, false) as MeshInstance3D
	if bulwark != null and bulwark.mesh != null:
		var bulwark_to_boat := boat.global_transform.affine_inverse() * bulwark.global_transform
		var bulwark_bounds := bulwark_to_boat * bulwark.get_aabb()
		var rail := boat.get_node_or_null(^"RailStarboard") as CollisionShape3D
		var rail_box := rail.shape as BoxShape3D if rail != null else null
		if rail_box != null:
			# La borda que se ve y la que frena tienen que ser LA MISMA. Si la
			# manga cambia en Blender y nadie mueve esta caja, el jugador choca
			# con aire o cae a traves del arte, y ningun otro check lo delata.
			var rail_outer: float = rail.position.x + rail_box.size.x * 0.5
			_check(absf(rail_outer - bulwark_bounds.end.x) < 0.06,
				"la borda de colision coincide con la borda visible",
				"colision %.2f m / malla %.2f m" % [rail_outer, bulwark_bounds.end.x])

	var bounds := _visual_bounds_in_boat(boat, meshes)
	_check(bounds.size.x > 5.5 and bounds.size.x < 6.1,
		"la manga visual sigue alrededor de 5,4 m", "AABB X %.2f m" % bounds.size.x)
	_check(bounds.size.z > 12.8 and bounds.size.z < 13.2,
		"la eslora visual sigue en 13 m", "AABB Z %.2f m" % bounds.size.z)
	_check(bounds.size.y > 3.7 and bounds.size.y < 4.8,
		"la altura del blockout es coherente", "AABB Y %.2f m" % bounds.size.y)
	_check(bounds.position.z < -6.4 and bounds.end.z > 6.3,
		"la proa y popa ocupan los ejes esperados", str(bounds))


func _visual_bounds_in_boat(boat: Node3D, meshes: Array[Node]) -> AABB:
	var result := AABB()
	var has_bounds: bool = false
	var world_to_boat := boat.global_transform.affine_inverse()
	for node in meshes:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var mesh_to_boat := world_to_boat * mesh_instance.global_transform
		var transformed := mesh_to_boat * mesh_instance.get_aabb()
		if has_bounds:
			result = result.merge(transformed)
		else:
			result = transformed
			has_bounds = true
	return result


func _test_upgrade_sockets(boat: FloatingBody3D) -> void:
	var sockets := boat.get_node_or_null(^"UpgradeSockets") as Node3D
	_check(sockets != null, "los sockets viven en la escena nativa de Godot")
	if sockets == null:
		return
	_check(sockets.get_child_count() == REQUIRED_SOCKETS.size(),
		"el prototipo ofrece trece anclajes de mejora",
		"encontrados %d" % sockets.get_child_count())
	for required in REQUIRED_SOCKETS:
		_check(sockets.get_node_or_null(NodePath(required)) is Marker3D,
			"socket estable: %s" % required)

	var bow_light := sockets.get_node(^"LightBow") as Marker3D
	var stern_light := sockets.get_node(^"LightStern") as Marker3D
	_check(bow_light.position.z < 0.0 and stern_light.position.z > 0.0,
		"los sockets confirman proa -Z y popa +Z")

	var gear_port := sockets.get_node(^"GearPort") as Marker3D
	var gear_starboard := sockets.get_node(^"GearStarboard") as Marker3D
	_check((gear_port.basis * Vector3.FORWARD).dot(Vector3.LEFT) > 0.99,
		"el aparejo de babor orienta -Z local hacia afuera")
	_check((gear_starboard.basis * Vector3.FORWARD).dot(Vector3.RIGHT) > 0.99,
		"el aparejo de estribor orienta -Z local hacia afuera")

	# Los aparejos van CLAVADOS en la borda. Si la manga cambia en Blender y
	# alguien mueve la borda pero no el socket, el soporte de caña queda flotando
	# en mitad de la cubierta: solo se ve jugando, y la orientación de arriba
	# sigue estando bien. Se ata a la borda —no a un número suelto—, porque la
	# manga vive en tools/build_modular_boat.py y aquí solo llega su consecuencia.
	var gear_rail := boat.get_node_or_null(^"RailStarboard") as CollisionShape3D
	var gear_rail_box := gear_rail.shape as BoxShape3D if gear_rail != null else null
	if gear_rail_box != null:
		var rail_inner: float = gear_rail.position.x - gear_rail_box.size.x * 0.5
		var gear_offset: float = rail_inner - absf(gear_starboard.position.x)
		_check(gear_offset > 0.0 and gear_offset < 0.20
			and is_equal_approx(gear_port.position.x, -gear_starboard.position.x),
			"los aparejos siguen clavados en la borda, no sueltos en cubierta",
			"socket %.2f m / cara interior de la borda %.2f m" % [
				absf(gear_starboard.position.x), rail_inner])

	var pump_port := sockets.get_node(^"PumpPort") as Marker3D
	var pump_starboard := sockets.get_node(^"PumpStarboard") as Marker3D
	_check((pump_port.basis * Vector3.FORWARD).dot(Vector3.RIGHT) > 0.99,
		"la bomba de babor mira hacia el pasillo central")
	_check((pump_starboard.basis * Vector3.FORWARD).dot(Vector3.LEFT) > 0.99,
		"la bomba de estribor mira hacia el pasillo central")

	var sonar := sockets.get_node(^"Sonar") as Marker3D
	_check((sonar.basis * Vector3.FORWARD).dot(Vector3.BACK) > 0.99,
		"el sonar mira desde el mamparo hacia el puesto del jugador")
	var helm := sockets.get_node(^"Helm") as Marker3D
	_check((helm.basis * Vector3.FORWARD).dot(Vector3.BACK) > 0.99,
		"el socket del timon mira hacia quien lo opera")
	var visual := boat.get_node_or_null(^"BoatVisual") as Node3D
	var wheel := visual.find_child("HelmWheel", true, false) as MeshInstance3D if visual != null else null
	if wheel != null:
		var wheel_position := boat.to_local(wheel.global_position)
		_check(wheel_position.distance_to(helm.position) < 0.06,
			"el socket Helm coincide con el eje real del volante",
			"wheel %s / socket %s" % [wheel_position, helm.position])

	var bodega := sockets.get_node_or_null(^"HoldAft/Bodega") as Bodega
	var tapa_anterior := visual.find_child(
		"HatchHoldAft", true, false) as MeshInstance3D if visual != null else null
	_check(bodega != null, "la bodega medieval está montada en HoldAft")
	_check(tapa_anterior != null and not tapa_anterior.visible,
		"la vieja tapa gris no oculta el pizarrón de la bodega")


## La bomba manual dejo de ser un modulo standalone y vive en el barco. El arte
## no puede contar solo tres cosas: que cuelga de SU socket sin offsets
## escondidos, que apoya en la cubierta y que el jugador no la atraviesa.
func _test_bilge_pump(boat: FloatingBody3D) -> void:
	var pump := boat.get_node_or_null(^"UpgradeSockets/PumpPort/BombaManual") as Node3D
	_check(pump != null, "la bomba manual está montada en el socket PumpPort")
	if pump == null:
		return
	_check(pump.position.is_equal_approx(Vector3.ZERO)
		and pump.basis.is_equal_approx(Basis.IDENTITY),
		"la bomba no esconde offsets: su raíz ES el socket", str(pump.transform))

	var visual := pump.get_node_or_null(^"PumpVisual") as Node3D
	_check(visual != null, "la bomba conserva su GLB editable montada")
	if visual == null:
		return
	# IntakeHead NO entra en la medida: es la boquilla que `stretch_hose` mueve
	# para seguir a la manguera, asi que su sitio depende del frame. Medirla haria
	# este arnes intermitente, que es peor que no tenerlo.
	var meshes: Array[Node] = []
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		if node.name != &"IntakeHead":
			meshes.append(node)
	var bounds := _visual_bounds_in_boat(boat, meshes)
	_check(absf(bounds.position.y - 0.80) < 0.05,
		"la base de la bomba apoya en la cubierta jugable",
		"Y %.3f m" % bounds.position.y)

	var solid_shape := boat.get_node_or_null(^"PumpPortShape") as CollisionShape3D
	var solid_box := solid_shape.shape as BoxShape3D if solid_shape != null else null
	_check(solid_box != null,
		"la bomba tiene cuerpo sólido en la raíz del barco, como la consola del timón")
	if solid_box == null:
		return
	var solid := AABB(solid_shape.position - solid_box.size * 0.5, solid_box.size)
	_check(solid.position.x > bounds.position.x - 0.05
		and solid.end.x < bounds.end.x + 0.05
		and solid.position.z > bounds.position.z - 0.05
		and solid.end.z < bounds.end.z + 0.05,
		"el cuerpo sólido no sobresale del arte: nada de paredes invisibles",
		"sólido %s / arte %s" % [solid, bounds])
	_check(solid.size.x > bounds.size.x * 0.8 and solid.size.z > bounds.size.z * 0.8,
		"el cuerpo sólido cubre la bomba entera, no una esquina",
		"sólido %s / arte %s" % [solid.size, bounds.size])


func _player_capsule() -> CapsuleShape3D:
	var player_scene := load("res://game/player/player.tscn") as PackedScene
	if player_scene == null:
		return null
	var template := player_scene.instantiate()
	var collision := template.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	var capsule := collision.shape as CapsuleShape3D if collision != null else null
	var copy := capsule.duplicate() as CapsuleShape3D if capsule != null else null
	template.free()
	return copy


func _test_physical_cabin_route(boat: FloatingBody3D) -> void:
	var capsule := _player_capsule()
	if capsule == null:
		_check(false, "la ruta fisica puede cargar la capsula del jugador")
		return

	boat.freeze = true
	boat.linear_velocity = Vector3.ZERO
	boat.angular_velocity = Vector3.ZERO
	boat.position = Vector3.ZERO
	boat.rotation = Vector3.ZERO

	var walker := CharacterBody3D.new()
	walker.name = "CabinRouteProbe"
	walker.collision_layer = 2
	walker.collision_mask = 1
	walker.safe_margin = 0.001
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	walker.add_child(shape)
	add_child(walker)
	var center_y: float = 0.80 + capsule.height * 0.5 + 0.025
	walker.global_position = boat.to_global(Vector3(1.56, center_y, 1.85))
	await get_tree().physics_frame
	await get_tree().physics_frame

	var route_in := PackedVector3Array([
		Vector3(1.56, center_y, 5.20),
		Vector3(0.0, center_y, 5.20),
		Vector3(0.0, center_y, 3.52),
	])
	var entered: bool = true
	for local_target in route_in:
		entered = await _walk_probe_to(walker, boat.to_global(local_target)) and entered
	_check(entered and boat.to_local(walker.global_position).z < 3.60,
		"la capsula real recorre costado, gira en popa y entra hasta el timon",
		"posicion final %s" % boat.to_local(walker.global_position))

	var route_out := PackedVector3Array([
		Vector3(0.0, center_y, 5.20),
		Vector3(1.56, center_y, 5.20),
		Vector3(1.56, center_y, 1.85),
	])
	var exited: bool = true
	for local_target in route_out:
		exited = await _walk_probe_to(walker, boat.to_global(local_target)) and exited
	_check(exited and boat.to_local(walker.global_position).z < 1.95,
		"la misma capsula puede abandonar la cabina sin quedar atrapada",
		"posicion final %s" % boat.to_local(walker.global_position))
	walker.queue_free()


func _walk_probe_to(walker: CharacterBody3D, target: Vector3) -> bool:
	for _step in 100:
		var delta := target - walker.global_position
		if delta.length() <= 0.055:
			return true
		var motion := delta.normalized() * minf(0.08, delta.length())
		walker.move_and_collide(motion)
		await get_tree().physics_frame
	return walker.global_position.distance_to(target) <= 0.08


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
		for failure in _failures:
			print("   - " + failure)
		get_tree().quit(1)
