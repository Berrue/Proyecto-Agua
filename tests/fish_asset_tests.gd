extends Node

## Pruebas del contrato visual de los peces con arte autorado.
##
## Los GLB son solo arte. Esta suite protege que cada especie aprobada tenga una
## silueta importable, que no traiga fisica escondida y que Fish conserve la
## capsula/sonda nativas al montar el modelo. La calma sigue mostrando solo los
## tres peces iniciales; la segunda tanda aparece desde furia 1.5.
##
##   Godot_v4.7.2-stable_win64_console.exe --headless --path . tests/fish_asset_tests.tscn

var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0


func _ready() -> void:
	_test_common_catalog()
	_test_common_draw_pool()
	_test_late_draw_pool()
	_test_authored_catalog()
	_test_authored_visuals()
	_test_fallback_survives()
	_test_setup_before_ready()
	await _test_authored_bodies_float()
	_report()


func _check(condition: bool, label: String, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("  ok    %s" % label)
	else:
		print("  FALLO %s%s" % [label, ("  ->  " + detail) if not detail.is_empty() else ""])
		_failures.append(label + (" :: " + detail if not detail.is_empty() else ""))


func _common_species() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for species in FishSpecies.SPECIES:
		if is_zero_approx(float(species[&"min_fury"])):
			result.append(species)
	return result


func _authored_species() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for species in FishSpecies.SPECIES:
		if species.has(&"visual_scene"):
			result.append(species)
	return result


func _test_common_catalog() -> void:
	var common := _common_species()
	_check(common.size() == 3, "la calma tiene tres peces", "%d" % common.size())
	var names: PackedStringArray = PackedStringArray()
	for species in common:
		names.append(String(species[&"name"]))
	_check(names == PackedStringArray(["Sardina", "Caballa", "Jurel"]),
		"el catalogo comun conserva las tres identidades", ", ".join(names))


func _test_common_draw_pool() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260823
	var names: Dictionary[String, int] = {}
	var only_common := true
	for _draw in 900:
		var species := FishSpecies.choose(1.0, rng)
		var species_name := String(species[&"name"])
		names[species_name] = names.get(species_name, 0) + 1
		if not is_zero_approx(float(species[&"min_fury"])):
			only_common = false
	_check(only_common and names.size() == 3,
		"en calma solo se pescan los tres comunes", str(names))
	var all_frequent := true
	for count in names.values():
		if int(count) < 180:
			all_frequent = false
	_check(all_frequent, "los tres aparecen con frecuencia comparable", str(names))


func _test_late_draw_pool() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260824
	var names: Dictionary[String, int] = {}
	var only_tier_one := true
	for _draw in 1800:
		var species := FishSpecies.choose(2.0, rng)
		var species_name := String(species[&"name"])
		names[species_name] = names.get(species_name, 0) + 1
		if FishSpecies.tier_of(species) != 1:
			only_tier_one = false
	_check(only_tier_one, "en furia 2 solo entra el tier 1", str(names))
	_check(names.has("Boqueron") and names.has("Faneca") and names.has("Sargo"),
		"la segunda tanda entra al sorteo en su furia", str(names))


func _test_authored_catalog() -> void:
	var names: PackedStringArray = PackedStringArray()
	for species in _authored_species():
		names.append(String(species[&"name"]))
	_check(names == PackedStringArray(
		["Sardina", "Caballa", "Jurel", "Boqueron", "Faneca", "Sargo"]),
		"los seis peces aprobados tienen visual autorada", ", ".join(names))


func _triangle_count(mesh: Mesh) -> int:
	var total: int = 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			total += int(vertices.size() / 3)
		else:
			total += int(indices.size() / 3)
	return total


func _test_authored_visuals() -> void:
	for species in _authored_species():
		var species_name := String(species[&"name"])
		var visual_path := String(species.get(&"visual_scene", ""))
		var packed := load(visual_path) as PackedScene
		_check(packed != null, "%s tiene GLB importable" % species_name)
		if packed == null:
			continue

		var imported := packed.instantiate() as Node3D
		add_child(imported)
		var imported_meshes := imported.find_children("*", "MeshInstance3D", true, false)
		_check(imported_meshes.size() == 1,
			"%s usa una sola malla" % species_name, "%d" % imported_meshes.size())
		_check(imported.find_children("*", "CollisionShape3D", true, false).is_empty()
			and imported.find_children("*", "RigidBody3D", true, false).is_empty(),
			"%s no importa fisica desde Blender" % species_name)
		if not imported_meshes.is_empty():
			var mesh_instance := imported_meshes[0] as MeshInstance3D
			var size := mesh_instance.mesh.get_aabb().size
			_check(size.z > maxf(size.x, size.y) * 1.25,
				"%s mira hacia -Z y conserva silueta de pez" % species_name,
				"AABB=(%.2f, %.2f, %.2f)" % [size.x, size.y, size.z])
			_check(mesh_instance.mesh.get_surface_count() >= 3
				and mesh_instance.mesh.get_surface_count() <= 6,
				"%s usa pocos bloques de material" % species_name,
				"%d superficies" % mesh_instance.mesh.get_surface_count())
			var triangles := _triangle_count(mesh_instance.mesh)
			_check(triangles <= 280, "%s respeta el presupuesto low-poly" % species_name,
				"%d triangulos" % triangles)
		imported.free()

		var fish := load("res://game/fishing/fish.tscn").instantiate() as Fish
		add_child(fish)
		fish.freeze = true
		fish.setup(species)
		_check(fish.has_authored_visual() and not (fish.get_node(^"Body") as MeshInstance3D).visible,
			"%s monta su silueta y apaga la capsula visual" % species_name)
		_check((fish.get_node(^"VisualRoot") as Node3D).get_child_count() == 1,
			"%s monta una sola visual" % species_name)
		var shape := (fish.get_node(^"CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D
		_check(is_equal_approx(shape.height, float(species[&"collision_length"]))
			and is_equal_approx(shape.radius, float(species[&"collision_radius"])),
			"%s conserva la capsula autorada en Godot" % species_name)
		_check(is_equal_approx(fish.mass, float(species[&"weight"])),
			"%s conserva su masa de gameplay" % species_name)
		fish.free()


func _test_fallback_survives() -> void:
	var fish := load("res://game/fishing/fish.tscn").instantiate() as Fish
	add_child(fish)
	fish.freeze = true
	var collision := fish.get_node(^"CollisionShape3D") as CollisionShape3D
	var initial_shape := collision.shape as CapsuleShape3D
	var base_height := initial_shape.height
	var base_radius := initial_shape.radius
	# El flujo real llama setup una vez, pero esta transicion protege herramientas
	# de catalogo y futuros pools que reutilicen una instancia.
	fish.setup(_common_species()[0])
	fish.setup(FishSpecies.SPECIES[-1])
	_check(not fish.has_authored_visual() and (fish.get_node(^"Body") as MeshInstance3D).visible,
		"los tiers pendientes siguen usando el fallback")
	var shape := collision.shape as CapsuleShape3D
	var expected_scale: float = pow(float(FishSpecies.SPECIES[-1][&"weight"]) / 2.0, 1.0 / 3.0)
	_check(is_equal_approx(shape.height, base_height)
		and is_equal_approx(shape.radius, base_radius)
		and collision.scale.is_equal_approx(Vector3.ONE * expected_scale),
		"volver al fallback restablece la capsula definida por la escena")
	fish.free()


func _test_setup_before_ready() -> void:
	var species := _common_species()[1]
	var fish := load("res://game/fishing/fish.tscn").instantiate() as Fish
	# Deliberadamente antes de add_child: protege herramientas y pools que
	# configuran la instancia antes de incorporarla al arbol.
	fish.setup(species)
	var probe := fish.get_node(^"Probe") as BuoyancyProbe3D
	var scale_from_weight: float = pow(float(species[&"weight"]) / 2.0, 1.0 / 3.0)
	_check(is_equal_approx(probe.volume, 0.002 * float(species[&"weight"]))
		and is_equal_approx(probe.drag_area, 0.05 * scale_from_weight * scale_from_weight),
		"setup antes de _ready conserva la flotacion de la especie")
	fish.free()


## Las medidas propias no pueden convertir al pez autorado en una piedra ni en
## un globo. Los seis caen juntos al mar real y deben quedar en superficie.
func _test_authored_bodies_float() -> void:
	Ocean.set_fury_immediate(0.0)
	var fish_nodes: Array[Fish] = []
	var authored := _authored_species()
	for index in authored.size():
		var species := authored[index]
		var fish := load("res://game/fishing/fish.tscn").instantiate() as Fish
		add_child(fish)
		fish.setup(species)
		fish.global_position = Vector3(60.0 + float(index) * 2.0, 2.0, 60.0)
		fish_nodes.append(fish)

	for _frame in 500:
		await get_tree().physics_frame
	for fish in fish_nodes:
		var y := fish.global_position.y
		_check(is_finite(y) and absf(y) < 2.0,
			"%s flota con su nueva capsula" % fish.species_name, "y=%.2f" % y)
		fish.queue_free()
	await get_tree().process_frame


func _report() -> void:
	print("")
	if _failures.is_empty():
		print_rich("[color=green][b]%d/%d comprobaciones de peces OK[/b][/color]" % [_checks, _checks])
		get_tree().quit(0)
	else:
		print_rich("[color=red][b]%d de %d han fallado:[/b][/color]" % [_failures.size(), _checks])
		for failure in _failures:
			print("   - " + failure)
		get_tree().quit(1)
