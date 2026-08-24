extends Node

## Protege el contrato funcional y visual de la bodega integrada al barco:
## presencia física, peso, capacidad y lectura medieval en pizarrón.
##
##   Godot_v4.7.2-stable_win64_console.exe --headless --path . tests/bodega_tests.tscn

const BODEGA_SCENE: PackedScene = preload("res://game/boat/bodega.tscn")
const FISH_SCENE: PackedScene = preload("res://game/fishing/fish.tscn")
const BOAT_SCENE: PackedScene = preload("res://game/boat/fishing_boat.tscn")
const LEVIATAN: TsunamiTier = preload(
	"res://resources/tsunami_tiers/tier_3_leviatan.tres")

var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0


func _ready() -> void:
	print_rich("[b]--- Pruebas de la bodega medieval ---[/b]")
	await _test_scene_contract()
	await _test_physical_count()
	await _test_anclaje_al_casco()
	_report()


func _test_scene_contract() -> void:
	var bodega := BODEGA_SCENE.instantiate() as Bodega
	_check(bodega != null, "la escena carga como Bodega animable")
	if bodega == null:
		return
	add_child(bodega)
	await get_tree().process_frame

	_check(is_equal_approx(bodega.capacidad_kg, 250.0),
		"la capacidad inicial es 250 kg", "%.1f" % bodega.capacidad_kg)
	_check(bodega.position == Vector3.ZERO and bodega.rotation == Vector3.ZERO,
		"el origen queda limpio para el socket del barco")

	var formas: int = 0
	for child in bodega.get_children():
		if child is CollisionShape3D:
			formas += 1
	_check(formas == 5, "piso y cuatro paredes conservan colisión", "%d formas" % formas)

	var zona := bodega.get_node_or_null(^"Zona") as Area3D
	_check(zona != null and zona.monitoring and zona.collision_mask == 1,
		"el volumen escucha cuerpos físicos de peces")

	var titulo := bodega.get_node_or_null(^"Tapa/Pizarron/Titulo") as Label3D
	var cartel := bodega.get_node_or_null(^"Tapa/Pizarron/Cartel") as Label3D
	var piezas := bodega.get_node_or_null(^"Tapa/Pizarron/Piezas") as Label3D
	_check(titulo != null and titulo.text == "BODEGA"
		and titulo.font == GameTypography.display_hud(),
		"el pizarrón usa el título de faena compartido")
	_check(cartel != null and piezas != null
		and cartel.font == GameTypography.display_brand()
		and piezas.font == GameTypography.ui_regular(),
		"peso y piezas usan las voces compartidas de rótulo e información")
	_check(cartel != null and piezas != null
		and cartel.text == "0 de 250 kg" and piezas.text == "sin piezas",
		"la lectura inicial muestra peso, capacidad y piezas")
	_check(bodega.get_node_or_null(^"Tapa/Pizarron/Tabla") is MeshInstance3D
		and bodega.get_node_or_null(^"Tapa/Pizarron/TrazoCentro") is MeshInstance3D
		and bodega.find_child("Screen", true, false) == null
		and bodega.find_child("Gauge", true, false) == null,
		"el contador es madera, pizarra y tiza; no una pantalla")
	_check(bodega.get_node_or_null(^"Tapa/HierroSuperior") is MeshInstance3D
		and bodega.get_node_or_null(^"BisagraBabor") is MeshInstance3D,
		"la tapa conserva herrajes medievales visibles")
	# El valor por defecto (true) reescribe el nodo con la pose que devuelve el
	# servidor, que va un paso por detras del casco: la celda se despega del
	# socket y no vuelve. Colgando de un RigidBody3D manda el arbol de escena.
	_check(not bodega.sync_to_physics,
		"la celda no lee su pose del servidor: la manda el socket del barco")

	bodega.queue_free()
	await get_tree().process_frame


func _test_physical_count() -> void:
	Ocean.set_fury_immediate(0.0)
	var bodega := BODEGA_SCENE.instantiate() as Bodega
	bodega.position = Vector3(0.0, 3.0, 0.0)
	add_child(bodega)
	await get_tree().physics_frame

	var jurel := FISH_SCENE.instantiate() as Fish
	jurel.setup(FishSpecies.SPECIES[2])
	jurel.position = Vector3(0.0, 5.2, 0.0)
	add_child(jurel)

	var entro: bool = false
	for _frame in 300:
		await get_tree().physics_frame
		if bodega.cantidad_peces() == 1:
			entro = true
		if entro and jurel.linear_velocity.length() < 0.15:
			break
	_check(entro and is_equal_approx(bodega.kg, 4.0),
		"un jurel arrojado suma sus 4 kg", "%.1f kg" % bodega.kg)
	var cartel := bodega.get_node(^"Tapa/Pizarron/Cartel") as Label3D
	var piezas := bodega.get_node(^"Tapa/Pizarron/Piezas") as Label3D
	_check(cartel.text == "4 de 250 kg" and piezas.text == "1 pieza",
		"el pizarrón refleja la carga física en singular")
	var marca_1 := bodega.get_node(^"Tapa/Pizarron/Marcas/Marca1") as MeshInstance3D
	var marca_2 := bodega.get_node(^"Tapa/Pizarron/Marcas/Marca2") as MeshInstance3D
	_check(marca_1.visible and not marca_2.visible,
		"las marcas de inventario acompañan la cantidad de peces")

	bodega.capacidad_kg = 3.0
	_check(bodega.esta_llena()
		and cartel.modulate.is_equal_approx(Bodega.COLOR_LLENA),
		"superar la capacidad marca la tiza en rojo arcilla")

	jurel.freeze = true
	jurel.global_position = Vector3(4.0, 5.0, 0.0)
	for _frame in 4:
		await get_tree().physics_frame
	_check(is_zero_approx(bodega.kg) and bodega.cantidad_peces() == 0,
		"sacar el pez devuelve el contador a cero")

	jurel.queue_free()
	bodega.queue_free()
	await get_tree().process_frame


## El fallo SILENCIOSO que motiva este arnes: con `sync_to_physics` en true la
## bodega se hundia 30 cm dentro de la cubierta en el primer segundo de mar
## gruesa y ya no volvia. Nada avisaba: contaba kg igual, solo estaba en otro
## sitio. Aqui se monta en el barco de verdad, se le tira un LEVIATAN encima y
## se exige deriva CERO contra su socket.
func _test_anclaje_al_casco() -> void:
	Ocean.set_fury_immediate(1.0)
	var barco := BOAT_SCENE.instantiate() as Node3D
	add_child(barco)
	var socket := barco.get_node(^"UpgradeSockets/HoldAft") as Node3D
	var bodega := barco.get_node_or_null(^"UpgradeSockets/HoldAft/Bodega") as Bodega
	_check(bodega != null, "la bodega sigue montada en el socket HoldAft")
	if bodega == null:
		barco.queue_free()
		return
	await get_tree().physics_frame

	# El pizarron mira a PROA (-Z del barco): la instancia va rotada 180 grados
	# respecto de la escena suelta, que lo tiene hacia +Z.
	var tapa := bodega.get_node(^"Tapa") as Node3D
	var hacia: Vector3 = (barco.global_basis.inverse() * (tapa.global_basis * Vector3.BACK)).normalized()
	_check(hacia.z < -0.95, "el pizarrón mira hacia proa", str(hacia))
	_check(barco.to_local(tapa.global_position).z > 0.0,
		"la tapa abre hacia popa, detrás de la celda",
		"Z %.2f" % barco.to_local(tapa.global_position).z)

	var peor: float = 0.0
	for frame in 900:
		if frame == 300:
			Ocean.spawn_tsunami_tier(barco.global_position, 0.0, 6.0, LEVIATAN)
		await get_tree().physics_frame
		peor = maxf(peor, bodega.global_position.distance_to(socket.global_position))
	_check(peor < 0.01,
		"la celda no se despega del casco ni con un LEVIATÁN encima",
		"peor desvío %.4f m" % peor)

	Ocean.clear_events()
	Ocean.set_fury_immediate(0.0)
	barco.queue_free()
	await get_tree().process_frame


func _check(condition: bool, label: String, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("  ok    %s" % label)
	else:
		var line := "  FALLO %s%s" % [
			label, ("  ->  " + detail) if not detail.is_empty() else ""]
		print(line)
		_failures.append(label + (" :: " + detail if not detail.is_empty() else ""))


func _report() -> void:
	print("")
	if _failures.is_empty():
		print_rich("[color=green][b]%d/%d comprobaciones de bodega OK[/b][/color]" % [
			_checks, _checks])
		get_tree().quit(0)
	else:
		print_rich("[color=red][b]%d de %d han fallado:[/b][/color]" % [
			_failures.size(), _checks])
		for failure in _failures:
			print("   - " + failure)
		get_tree().quit(1)
