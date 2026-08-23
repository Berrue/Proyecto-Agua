class_name Fish
extends FloatingBody3D

## Un pez capturado. Es un rigidbody CON FLOTABILIDAD: aterriza en cubierta como
## comedia fisica, rueda con la escora, y si cae al agua... flota y se va.
## El botin esta en riesgo hasta el puerto — literalmente.

var species_name: String = "Sardina"
var weight_kg: float = 2.0
var value: int = 6


func setup(species: Dictionary) -> void:
	species_name = String(species[&"name"])
	weight_kg = float(species[&"weight"])
	value = int(species[&"value"])
	mass = maxf(weight_kg, 1.0)

	# El tamaño crece con la raiz cubica del peso: un atun de 60 kg es ~3 veces
	# la sardina, no 30.
	var s: float = pow(weight_kg / 2.0, 1.0 / 3.0)
	var body := get_node_or_null(^"Body") as MeshInstance3D
	if body != null:
		body.scale = Vector3(s, s, s)
		var mat := body.get_surface_override_material(0) as StandardMaterial3D
		if mat != null:
			mat = mat.duplicate()
			mat.albedo_color = species[&"color"]
			body.set_surface_override_material(0, mat)
	var shape := get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	if shape != null:
		shape.scale = Vector3(s, s, s)
	# La sonda de flotacion escala con el volumen real.
	for probe in probes:
		probe.volume = 0.002 * weight_kg
		probe.drag_area = 0.05 * s * s
