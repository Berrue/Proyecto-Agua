extends Node

## Herramienta de captura del CLIMA (fase A de docs/CLIMA.md). Saca fotos del
## mar en estados de lluvia y viento concretos para revisar los efectos del
## shader (specular apagado, moteado, cat's paws, estrias) sin tener que jugar.
##
##   godot --path . tests/capture_weather.tscn -- --shots-dir=<carpeta>
##
## Cada toma fija furia y lluvia (modo debug: rain_override) y ademas fuerza el
## reloj de racha a un instante con gust01 alto, para que las manchas de viento
## salgan seguro en la foto en vez de depender de la suerte.

const SETTLE_FRAMES := 150
const SHOT_FRAMES := 90

## (nombre, furia, rain_level, buscar_racha, camara_en_cabina)
const SHOTS: Array = [
	["furia2_racha", 2.0, 0.0, true, false],     # cat's paws: manchas oscuras
	["furia3_lluvia", 3.0, 1.0, false, false],   # aguacero con mar tranquilo: gotas + sin brillo
	["furia6_seco", 6.0, 0.0, false, false],     # tormenta SIN lluvia: estado valido
	["furia8_temporal", 8.5, 1.0, false, false], # temporal completo: gotas + estrias
	["cabina_lluvia", 3.0, 1.0, false, true],    # bajo techo: el refugio debe estar SECO
	["noche_lluvia", 3.0, 1.0, false, false],    # de noche la gota se APAGA con la escena
	["cabina_temporal", 7.0, 1.0, true, true],   # el refugio bajo temporal con viento: SECO
	["cortina_horizonte", 5.0, 1.0, false, false], # la cortina lejana, vista desde cubierta
	["rayo_flash", 9.0, 1.0, false, false],      # el instante del destello: bolt + bandas
	["rayo_noche", 9.0, 1.0, false, false],      # el mismo, de noche (donde mas se nota)
]

## Tomas del PARTE METEOROLOGICO. Van en su propio bucle porque necesitan lo
## contrario que las de arriba: alli la furia se fija a mano —lo que SUSPENDE
## el guion— y aqui lo que hay que fotografiar es justo el guion mandando.
##
## Es el mismo parte en dos momentos, y esa es toda la prueba: el frente tiene
## que estar en el horizonte ANTES de que el mar suba, y haberse disuelto
## cuando la tormenta ya esta encima. Un frente que aparece con la tormenta
## llega tarde, que es la unica forma en que puede estar mal.
const SHOTS_PARTE: Array = [
	["parte_frente_viene", 60.0],    # mar todavia chico, pared de nubes al fondo
	["parte_frente_encima", 900.0],  # la tormenta llego: el frente ya paso
]

var _dir: String = "user://shots"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots-dir="):
			_dir = arg.substr("--shots-dir=".length())
	DirAccess.make_dir_recursive_absolute(_dir)

	var toybox: Node3D = load("res://game/world/toybox.tscn").instantiate()
	add_child(toybox)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var cam := Camera3D.new()
	# El MISMO FOV que la camara del jugador: a 62 los tamaños en pantalla no
	# coinciden con lo que se ve jugando y las decisiones de look salen sesgadas.
	cam.fov = 78.0
	cam.far = 4000.0
	add_child(cam)
	cam.global_position = Vector3(11, 4.0, 15)
	cam.look_at(Vector3(-6, 0.5, -14), Vector3.UP)
	cam.current = true

	var markers := toybox.get_node_or_null(^"ParityMarkers")
	if markers != null:
		markers.visible = false

	for _i in SETTLE_FRAMES:
		await get_tree().process_frame

	var day_night := toybox.get_node_or_null(^"DayNightCycle") as DayNightCycle

	for shot: Array in SHOTS:
		var name_s: String = shot[0]
		Ocean.set_fury_immediate(shot[1])
		Ocean.rain_level = shot[2]
		# Las tomas nocturnas fijan la hora por el offset de debug (jamas
		# sim_time); el resto se ancla a media mañana para ser comparables.
		if day_night != null:
			day_night.set_debug_hour(0.5 if name_s.begins_with("noche") or name_s.ends_with("noche") else 10.0)
		# La lluvia tiene rampa a proposito; para la foto se salta esperando a
		# que llegue (o forzando _rain no — mejor esperar: es lo honesto).
		if bool(shot[3]):
			_seek_gust()
		# Primero que la rampa de lluvia llegue a su objetivo (0.6/s)...
		var guard: int = 0
		while absf(Ocean.rain01 - Ocean.rain_target()) > 0.01 and guard < 600:
			await get_tree().process_frame
			guard += 1
		# ...y LUEGO los frames de asentado: las gotas ya emitidas viven ~0.9 s
		# mas, asi que sin este orden la foto "seca" sale con lluvia residual.
		for _i in SHOT_FRAMES:
			await get_tree().process_frame
		# El encuadre se decide AL FINAL y RELATIVO AL BARCO: deriva durante el
		# asentado y una camara fija en mundo acaba mirando el casco de cerca.
		var boat := find_child("FishingBoat", true, false) as Node3D
		if boat != null:
			if bool(shot[4]):
				cam.global_position = boat.to_global(Vector3(0.0, 2.3, 4.2))
				cam.look_at(boat.to_global(Vector3(0.0, 2.6, 0.0)), boat.global_basis.y)
			elif name_s == "cortina_horizonte":
				# Ojo de cubierta mirando al horizonte: la altura donde la
				# cortina se lee (o se delata).
				cam.global_position = boat.to_global(Vector3(0.0, 2.0, -1.0))
				cam.look_at(boat.to_global(Vector3(0.0, 2.0, -60.0)), Vector3.UP)
			else:
				cam.global_position = boat.global_position + Vector3(10.0, 4.5, 12.0)
				cam.look_at(boat.global_position + Vector3(-4.0, 1.0, -6.0), Vector3.UP)
		await get_tree().process_frame
		if name_s.begins_with("rayo"):
			# Un destello dura decimas: hay que forzarlo y disparar la foto en
			# su pico, no "en algun momento".
			var ld := toybox.get_node_or_null(^"LightningDirector") as LightningDirector
			if ld != null:
				ld.force_strike(420.0)
				# El bolt se REVELA de arriba abajo en ~0.10 s: a los 2 frames
				# solo hay un tercio de rayo. Se espera a que baje entero, aun a
				# costa de fotografiar el destello ya en decaimiento.
				for _f in 8:
					await get_tree().process_frame
		await RenderingServer.frame_post_draw

		var img := get_viewport().get_texture().get_image()
		var err := img.save_png("%s/%s.png" % [_dir, name_s])
		print("%s  %s  furia %.1f  lluvia %.2f  racha %.2f  viento %.1f m/s" % [
			"OK  " if err == OK else "FALLO", name_s,
			Ocean.fury, Ocean.rain01, Ocean.gust01(), Ocean.wind_speed()])

	Ocean.rain_level = 0.0

	# --- El parte ------------------------------------------------------------
	var guion := ParteMeteorologico.new()
	guion.comprometer(ParteMeteorologico.FURIA, 0.0, 1.5)
	guion.comprometer(ParteMeteorologico.FURIA, 400.0, 9.0)
	guion.comprometer(ParteMeteorologico.FURIA, 1400.0, 9.0)
	guion.comprometer(ParteMeteorologico.LLUVIA, 0.0, 0.0)
	guion.comprometer(ParteMeteorologico.LLUVIA, 330.0, 0.0)
	guion.comprometer(ParteMeteorologico.LLUVIA, 430.0, 0.9)
	guion.comprometer(ParteMeteorologico.LLUVIA, 1400.0, 0.9)
	# El frente entra por proa para que se vea en el encuadre de cubierta.
	guion.comprometer(ParteMeteorologico.RUMBO, 0.0, 270.0)

	for shot: Array in SHOTS_PARTE:
		var nombre: String = shot[0]
		Ocean.sim_time = float(shot[1])
		Ocean.fijar_parte(guion)
		if day_night != null:
			day_night.set_debug_hour(10.0)
		for _i in SHOT_FRAMES:
			await get_tree().process_frame
		var barco := find_child("FishingBoat", true, false) as Node3D
		if barco != null:
			# Ojo de cubierta al horizonte: el frente vive en la mitad de
			# ARRIBA de la pantalla, que es la parte que la fase C dejo muda.
			cam.global_position = barco.to_global(Vector3(0.0, 2.2, -1.0))
			cam.look_at(barco.to_global(Vector3(0.0, 3.4, -60.0)), Vector3.UP)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var im := get_viewport().get_texture().get_image()
		var e := im.save_png("%s/%s.png" % [_dir, nombre])
		print("%s  %s  t=%.0f  furia %.2f  lluvia %.2f  pico que viene %.2f" % [
			"OK  " if e == OK else "FALLO", nombre, Ocean.sim_time,
			Ocean.fury, Ocean.rain01, Ocean.furia_swell(Ocean.sim_time, 210.0)])
	Ocean.limpiar_parte()

	# --- A/B del destello ----------------------------------------------------
	# El MISMO mar, mismo instante, mismo encuadre, con lightning01 a 0 y a 1.
	# Las tomas `rayo_*` disparan un rayo de verdad y esperan 8 frames a que el
	# bolt se revele entero, asi que fotografian el destello YA EN DECAIMIENTO:
	# sirven para ver el rayo, no para medir cuanto sube el agua. Esto si.
	Ocean.set_fury_immediate(7.0)
	Ocean.rain_level = 0.6
	if day_night != null:
		day_night.set_debug_hour(10.0)
	for _i in SHOT_FRAMES:
		await get_tree().process_frame
	var barco2 := find_child("FishingBoat", true, false) as Node3D
	if barco2 != null:
		cam.global_position = barco2.global_position + Vector3(10.0, 4.5, 12.0)
		cam.look_at(barco2.global_position + Vector3(-4.0, 1.0, -6.0), Vector3.UP)
	# EL DIRECTOR TIENE QUE CALLARSE: su `_process` escribe `lightning01` CADA
	# frame (0.0 cuando no hay rayo), asi que pisaba el valor de esta prueba
	# antes de que se dibujara nada. Dos medidas seguidas dieron "+0.0 %" por
	# esto y estuvieron a punto de mandar a arreglar un shader que no fallaba.
	var ld2 := toybox.get_node_or_null(^"LightningDirector") as LightningDirector
	if ld2 != null:
		ld2.process_mode = Node.PROCESS_MODE_DISABLED
	for ab: Array in [["flash_off", 0.0], ["flash_on", 1.0]]:
		RenderingServer.global_shader_parameter_set(&"lightning01", float(ab[1]))
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var im2 := get_viewport().get_texture().get_image()
		var e2 := im2.save_png("%s/%s.png" % [_dir, ab[0]])
		print("%s  %s  lightning01 = %.1f" % ["OK  " if e2 == OK else "FALLO", ab[0], ab[1]])
	RenderingServer.global_shader_parameter_set(&"lightning01", 0.0)
	if ld2 != null:
		ld2.process_mode = Node.PROCESS_MODE_INHERIT

	# --- A/B de la TANDA 2 ---------------------------------------------------
	# Cat's paws y estrias entran apagadas (son gusto, no fisica). Esto saca el
	# mismo mar con y sin ellas, cada una a la furia donde de verdad se lee:
	# las manchas con mar chico, las estrias en temporal.
	var mat_mar: ShaderMaterial = null
	var sup := find_child("OceanSurface", true, false)
	if sup != null and sup is GeometryInstance3D:
		mat_mar = (sup as GeometryInstance3D).material_override as ShaderMaterial
		if mat_mar == null and sup is MeshInstance3D:
			mat_mar = (sup as MeshInstance3D).mesh.surface_get_material(0) as ShaderMaterial
	if mat_mar != null:
		# A/B DE VERDAD: camara FIJA en mundo y mar CONGELADO.
		#
		# El primer intento referia la camara al barco y dejaba correr el
		# tiempo: el barco derivaba y rotaba entre las dos tomas, asi que las
		# imagenes no eran el mismo encuadre ni el mismo mar y la comparacion no
		# valia nada. Peor: las manchas turquesa que parecian ser la feature
		# resultaron ser las CRESTAS de siempre, visibles en las dos.
		#
		# Con el oceano en pausa las dos fotos son el mismo instante exacto, asi
		# que cualquier diferencia entre ellas es, necesariamente, el uniform.
		for grupo: Array in [
			# nombre, furia, uniform, buscar_racha, camara, objetivo
			["paws", 2.0, &"paw_amount", true,
				Vector3(0.0, 7.0, 0.0), Vector3(-25.0, 0.0, -45.0)],
			["estrias", 8.0, &"streak_amount", false,
				Vector3(0.0, 12.0, 0.0), Vector3(-25.0, 0.0, -45.0)],
		]:
			Ocean.rain_level = 0.0
			Ocean.set_fury_immediate(float(grupo[1]))
			if bool(grupo[3]):
				_seek_gust()
			for _i in SHOT_FRAMES:
				await get_tree().process_frame
			# Congelado: a partir de aqui el mar no se mueve ni un milimetro.
			Ocean.set_paused(true)
			cam.global_position = grupo[4]
			cam.look_at(grupo[5], Vector3.UP)
			# TRES niveles, no dos. Con solo off/on la decision se toma contra
			# el maximo, y el maximo de las estrias son autopistas blancas: se
			# rechazaria un efecto que a 0.35 puede estar bien.
			# 0.15 es el valor QUE SE ENVIA en las estrias, asi que la toma
			# "suave" es tambien la regresion del ajuste real.
			for ab: Array in [["off", 0.0], ["suave", 0.15], ["fuerte", 1.0]]:
				mat_mar.set_shader_parameter(grupo[2], float(ab[1]))
				await get_tree().process_frame
				await RenderingServer.frame_post_draw
				var im3 := get_viewport().get_texture().get_image()
				var nombre3: String = "%s_%s" % [grupo[0], ab[0]]
				var e3 := im3.save_png("%s/%s.png" % [_dir, nombre3])
				print("%s  %s  furia %.1f  %s = %.1f  racha %.2f" % [
					"OK  " if e3 == OK else "FALLO", nombre3, Ocean.fury,
					grupo[2], float(ab[1]), Ocean.gust01()])
			mat_mar.set_shader_parameter(grupo[2], 0.0)
			Ocean.set_paused(false)
		# El material es un recurso COMPARTIDO: dejarlo encendido contaminaria
		# cualquier captura posterior.
		mat_mar.set_shader_parameter(&"paw_amount", 0.0)
		mat_mar.set_shader_parameter(&"streak_amount", 0.0)
	else:
		print("FALLO  no encuentro el material del oceano para el A/B de tanda 2")

	Ocean.rain_level = 0.0

	print("capturas en: ", ProjectSettings.globalize_path(_dir))
	get_tree().quit(0)


## Adelanta el reloj de simulacion hasta un instante con racha fuerte, para que
## la foto pille las manchas. Saltar sim_time teletransporta las olas, pero en
## una herramienta de captura eso da exactamente igual.
func _seek_gust() -> void:
	var t: float = Ocean.sim_time
	for _i in 2000:
		t += 0.25
		if Ocean.gust01_at(t) > 0.85:
			Ocean.sim_time = t
			return
