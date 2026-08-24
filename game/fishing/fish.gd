class_name Fish
extends Portable3D

## Un pez capturado. Es un rigidbody CON FLOTABILIDAD: aterriza en cubierta como
## comedia fisica, rueda con la escora, y si cae al agua... flota y se va.
## El botin esta en riesgo hasta el puerto — literalmente.
##
## Y es PORTABLE (docs/PORTEO.md): el paso 7 del loop de la caña es el porteo a
## la bodega. Los chicos van al hombro con una mano; a partir de
## MANOS_DOS_DESDE_KG son un abrazo a dos manos que te quita el salto y te
## frena — cruzar la cubierta con un fletan en plena marejada ES el juego.

## Hasta aqui, una mano (sardina, caballa, jurel al hombro). Desde aqui, las
## dos: el umbral cae entre el jurel (4 kg) y la lubina (8 kg) a proposito,
## para que TODA la banda B te comprometa las manos.
const MANOS_DOS_DESDE_KG := 6.0

var species_name: String = "Sardina"
var weight_kg: float = 2.0
var value: int = 6

var _thuds_left: int = 3
var _sfx: AudioStreamPlayer3D
var _sfx_pb: AudioStreamPlaybackPolyphonic
var authored_visual: Node3D
var _base_collision_length: float
var _base_collision_radius: float
var _base_collision_captured: bool = false


func _ready() -> void:
	super()
	body_entered.connect(_on_body_entered)
	_sfx = AudioStreamPlayer3D.new()
	_sfx.bus = &"SFX"
	_sfx.stream = AudioStreamPolyphonic.new()
	add_child(_sfx)
	_sfx.play()
	_sfx_pb = _sfx.get_stream_playback() as AudioStreamPlaybackPolyphonic


## El thud contra la cubierta: pez gordo = golpe mas grave. Los dos primeros
## rebotes suenan cada vez mas flojos — y luego silencio, que el aleteo del
## rigidbody ya cuenta la historia solo.
func _on_body_entered(_body: Node) -> void:
	if _thuds_left <= 0 or linear_velocity.length() < 1.5:
		return
	_thuds_left -= 1
	var pitch: float = clampf(1.4 - weight_kg * 0.012, 0.5, 1.4)
	SfxLibrary.play_one(_sfx_pb, SfxLibrary.thud, -4.0 - float(2 - _thuds_left) * 5.0, pitch)


func setup(species: Dictionary) -> void:
	species_name = String(species[&"name"])
	weight_kg = float(species[&"weight"])
	value = int(species[&"value"])
	mass = maxf(weight_kg, 1.0)
	nombre = species_name.to_lower()
	manos = 1 if weight_kg < MANOS_DOS_DESDE_KG else 2

	# El tamaño crece con la raiz cubica del peso: un atun de 60 kg es ~3 veces
	# la sardina, no 30. Los comunes tienen medidas autoradas; esta escala sigue
	# cubriendo los tiers cuyo modelo propio todavia no existe.
	var s: float = pow(weight_kg / 2.0, 1.0 / 3.0)
	var body := get_node_or_null(^"Body") as MeshInstance3D
	_set_authored_visual(species, body)
	if body != null:
		body.scale = Vector3(s, s, s) if body.visible else Vector3.ONE
		if body.visible:
			var mat := body.get_surface_override_material(0) as StandardMaterial3D
			if mat != null:
				mat = mat.duplicate()
				mat.albedo_color = species[&"color"]
				body.set_surface_override_material(0, mat)
	var shape := get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	if shape != null:
		var source_capsule := shape.shape as CapsuleShape3D
		if source_capsule == null:
			push_warning("La colision de %s no es una CapsuleShape3D" % species_name)
			return
		# La escena es la unica fuente de verdad de la capsula base. Se captura
		# antes de la primera personalizacion para que setup siga siendo reentrante.
		if not _base_collision_captured:
			_base_collision_length = source_capsule.height
			_base_collision_radius = source_capsule.radius
			_base_collision_captured = true
		var capsule := source_capsule.duplicate() as CapsuleShape3D
		shape.shape = capsule
		var has_length := species.has(&"collision_length")
		var has_radius := species.has(&"collision_radius")
		var has_custom_collision := has_length and has_radius
		if has_length != has_radius:
			push_warning("%s debe definir collision_length y collision_radius juntas" % species_name)
		capsule.height = (float(species[&"collision_length"])
			if has_custom_collision else _base_collision_length)
		capsule.radius = (float(species[&"collision_radius"])
			if has_custom_collision else _base_collision_radius)
		if has_custom_collision:
			# La silueta puede tener aletas grandes, pero la fisica conserva una
			# capsula limpia para caer, rodar y estibarse sin engancharse.
			shape.scale = Vector3.ONE
		else:
			shape.scale = Vector3(s, s, s)
	# Se recorren los hijos, no el cache que FloatingBody3D llena en _ready().
	# Asi setup tambien es correcto en el orden instantiate -> setup -> add_child.
	for child in get_children():
		if child is BuoyancyProbe3D:
			var probe := child as BuoyancyProbe3D
			probe.volume = 0.002 * weight_kg
			probe.drag_area = 0.05 * s * s


## Sustituye solo la capa visual. El RigidBody, la capsula y la sonda siguen en
## Godot para que reexportar arte nunca cambie la jugabilidad en silencio.
func _set_authored_visual(species: Dictionary, fallback: MeshInstance3D) -> void:
	if authored_visual != null:
		authored_visual.free()
		authored_visual = null
	if fallback != null:
		fallback.visible = true

	var visual_path := String(species.get(&"visual_scene", ""))
	if visual_path.is_empty():
		return
	var packed := load(visual_path) as PackedScene
	if packed == null:
		push_warning("No se pudo cargar la visual de %s: %s" % [species_name, visual_path])
		return
	var root := get_node_or_null(^"VisualRoot") as Node3D
	if root == null:
		push_warning("Falta VisualRoot para montar %s" % species_name)
		return
	authored_visual = packed.instantiate() as Node3D
	if authored_visual == null:
		push_warning("La visual de %s no tiene raiz Node3D" % species_name)
		return
	authored_visual.name = species_name
	root.add_child(authored_visual)
	if fallback != null:
		fallback.visible = false


func has_authored_visual() -> bool:
	return authored_visual != null


## El peso del porteo es el de la especie, no la masa fisica (que esta clampada
## a 1 kg para que la sardina no salga volando con cada slam).
func peso_kg() -> float:
	return weight_kg
