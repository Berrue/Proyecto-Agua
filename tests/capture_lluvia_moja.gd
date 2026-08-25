extends Node

## ¿La lluvia moja el barco de verdad? Medido, no supuesto.
##
##   <godot 4.7.2> --headless --path . tests/capture_lluvia_moja.tscn
##
## Nace de un reporte de juego: «no veo agua en el barco cuando llueve». Las dos
## respuestas posibles eran muy distintas —o el goteo esta roto, o entra tan
## despacio que no se nota— y la unica forma de saberlo es cronometrarlo. Imprime
## cuanta agua entra por minuto de diluvio y cuanto tarda en llegar a la alarma.

const RUTA_BARCO := "res://game/boat/fishing_boat.tscn"
const SEGUNDOS := 60.0


func _ready() -> void:
	print_rich("[b]--- ¿Moja la lluvia? ---[/b]")
	await get_tree().physics_frame
	Ocean.clear_events()
	Ocean.set_fury_immediate(0.0)
	var lluvia_previa: float = Ocean.rain_level
	# Diluvio a tope y sin acto que lo recorte: el mejor caso posible.
	Ocean.rain_level = 1.0
	Ocean.rain_scale = 1.0

	var barco: FloatingBody3D = (load(RUTA_BARCO) as PackedScene).instantiate()
	add_child(barco)
	barco.global_position = Vector3(0, 1, 0)
	var agua := barco.get_node_or_null(^"AguaEmbarcada") as AguaEmbarcada
	for _i in 240:
		await get_tree().physics_frame

	print("  lluvia efectiva: %.2f  (rain01)" % Ocean.rain01)
	print("  furia: %.1f   (para que el mar no meta agua y se mida SOLO la lluvia)" % Ocean.fury)
	var antes: float = barco.flooding_level()

	var ticks: int = int(round(SEGUNDOS * float(maxi(Engine.physics_ticks_per_second, 1))))
	for _i in ticks:
		await get_tree().physics_frame
	var despues: float = barco.flooding_level()
	var por_segundo: float = (despues - antes) / SEGUNDOS

	print("")
	print("  nivel antes:   %.4f" % antes)
	print("  nivel despues: %.4f   (tras %.0f s de diluvio)" % [despues, SEGUNDOS])
	print("  entra:         %.5f por segundo" % por_segundo)
	if agua != null:
		print("  nivel que ve el juego: %.4f" % agua.nivel)

	print("")
	if por_segundo <= 0.000001:
		print_rich("[color=#f05a4b][b]LA LLUVIA NO MOJA: esta roto.[/b][/color]")
	else:
		var a_la_alarma: float = 0.55 / por_segundo
		print_rich("[b]La lluvia SI moja.[/b] En un minuto de diluvio sube al %.1f %%." % (
			por_segundo * 60.0 * 100.0))
		print("  A este ritmo, llegar a la alarma (55 %%) son %.0f minutos de lluvia sin parar." % (
			a_la_alarma / 60.0))
		print("  O sea: entra, pero MUY despacio a proposito — la lluvia tiene que")
		print("  costar algo, no matarte sola (docs/CLIMA.md §1).")

	Ocean.rain_level = lluvia_previa
	get_tree().quit(0)
