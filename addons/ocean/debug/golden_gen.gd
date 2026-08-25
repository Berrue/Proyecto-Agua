extends Node

## GENERADOR de la tabla golden. Necesita VENTANA Y GPU: no corre en headless.
##
##   <godot> --path . addons/ocean/debug/golden_gen.tscn
##
## Pregunta al shader —al de verdad, via `ocean_waves.gdshaderinc`— cuanto vale
## el oleaje en 1024 puntos por combinacion de (semilla, furia, instante), y lo
## guarda en `tests/golden/ocean_golden.res`. Despues `tests/parity_tests.tscn`
## compara la CPU contra eso, y ESE si corre headless en CI.
##
## [b]Se compara ademas aqui mismo.[/b] Al terminar imprime el error maximo
## contra la CPU. No es decoracion: si el empaquetado a bytes estuviera mal, o
## el espacio de color mangara los valores, o los uniforms no llegaran, el error
## saldria enorme y la tabla se guardaria envenenada sin que nadie lo notara
## hasta que el test fallara por el motivo equivocado.

const RUTA := "res://tests/golden/ocean_golden.res"

const SEMILLAS: Array[int] = [1234, 99]
const FURIAS: Array[float] = [1.0, 5.0, 9.0]
## Ocho instantes y no los 32 que menciona PLAN.md, a cambio de subir los puntos
## a 1024 por combinacion. El campo de olas es SUAVE en el tiempo —una formula
## rota lo esta en todos los instantes— pero puede estarlo solo en una zona del
## plano, asi que la cobertura espacial atrapa mas por byte guardado. Con 32
## instantes el archivo pasaria de 3 MB.
const TIEMPOS: Array[float] = [0.0, 3.7, 11.3, 29.1, 60.5, 127.9, 300.3, 941.7]


func _ready() -> void:
	print_rich("[b]--- Generando la tabla golden del oceano ---[/b]")

	var shader: Shader = load("res://addons/ocean/shaders/golden_probe.gdshader")
	if shader == null:
		push_error("No se pudo cargar golden_probe.gdshader")
		get_tree().quit(1)
		return

	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter(&"rango", GoldenOceano.RANGO)

	# Un SubViewport de LADO x LADO: un pixel, una muestra. Nada de filtrado ni
	# de escalado entre lo que el shader calcula y lo que se lee.
	var vp := SubViewport.new()
	vp.size = Vector2i(GoldenOceano.LADO, GoldenOceano.LADO)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	add_child(vp)

	var rect := ColorRect.new()
	rect.material = mat
	rect.size = Vector2(GoldenOceano.LADO, GoldenOceano.LADO)
	vp.add_child(rect)

	var tabla := GoldenOceano.new()
	tabla.semillas = PackedInt32Array(SEMILLAS)
	tabla.furias = PackedFloat32Array(FURIAS)
	tabla.tiempos = PackedFloat32Array(TIEMPOS)
	tabla.valores.resize(tabla.total_muestras())

	var peor_error: float = 0.0
	var peor_donde: String = ""
	var furia_previa: float = Ocean.fury
	var semilla_previa: int = Ocean.ocean_seed
	var t_previo: float = Ocean.sim_time
	# El parte escribiria la furia por su cuenta entre pasada y pasada.
	Ocean.limpiar_parte()

	for s in SEMILLAS.size():
		Ocean.regenerate(SEMILLAS[s])
		for f in FURIAS.size():
			Ocean.set_fury_immediate(FURIAS[f])
			for t in TIEMPOS.size():
				Ocean.sim_time = TIEMPOS[t]
				# Los MISMOS uniforms que alimentan al mar de verdad: si esto se
				# empaquetara aparte, el test comprobaria el empaquetado del test.
				Ocean.apply_to_material(mat)
				mat.set_shader_parameter(&"ocean_time", TIEMPOS[t])

				for comp in GoldenOceano.COMPONENTES:
					mat.set_shader_parameter(&"componente", comp)
					# Dos frames: uno para que el uniform llegue, otro para que
					# el render target contenga ya ESE dibujo.
					await RenderingServer.frame_post_draw
					await RenderingServer.frame_post_draw
					var img: Image = vp.get_texture().get_image()
					# BYTES CRUDOS, no `get_pixel()`. La primera version pedia
					# colores y salia con 39 m de error: lo que se codificaba
					# como 0.612 se leia como 0.303, que es casi exactamente
					# sRGB->lineal. Aqui no se quiere un COLOR, se quieren los
					# cuatro bytes tal cual salieron del shader.
					# Se CONVIERTE a un formato conocido antes de leer bytes: el
					# render target sale en RGB8 (3 bytes/pixel) y dar por
					# supuesto RGBA8 se salia del array. `convert` de RGB8 a
					# RGBA8 solo añade alfa, no toca los colores.
					img.convert(Image.FORMAT_RGBA8)
					var bytes: PackedByteArray = img.get_data()

					for j in GoldenOceano.LADO:
						for i in GoldenOceano.LADO:
							var o: int = (j * GoldenOceano.LADO + i) * 4
							var v: float = GoldenOceano.desempaquetar_bytes(
								bytes[o], bytes[o + 1], bytes[o + 2])
							tabla.valores[tabla.indice(s, f, t, comp, j, i)] = v
							var cpu: float = _cpu(comp, GoldenOceano.punto(i, j), TIEMPOS[t])
							var e: float = absf(v - cpu)
							if e > peor_error:
								peor_error = e
								peor_donde = "semilla %d furia %.1f t=%.1f comp %d (%d,%d): gpu %.6f cpu %.6f" % [
									SEMILLAS[s], FURIAS[f], TIEMPOS[t], comp, i, j, v, cpu]
			print("  semilla %d furia %.1f  ..." % [SEMILLAS[s], FURIAS[f]])

	tabla.generado = "%s  ·  %s  ·  %s" % [
		Time.get_datetime_string_from_system(true),
		Engine.get_version_info().get("string", "?"),
		RenderingServer.get_video_adapter_name()]

	DirAccess.make_dir_recursive_absolute("res://tests/golden")
	var err := ResourceSaver.save(tabla, RUTA)

	print("")
	print("muestras          %d" % tabla.total_muestras())
	print("peor diferencia   %.6f m  (tolerancia %.6f)" % [peor_error, GoldenOceano.TOLERANCIA])
	if peor_donde != "":
		print("  en              %s" % peor_donde)
	print("guardada en       %s  (%s)" % [RUTA, "OK" if err == OK else "FALLO"])

	# Restaurar: este tool puede correrse desde el editor con una escena viva.
	Ocean.regenerate(semilla_previa)
	Ocean.set_fury_immediate(furia_previa)
	Ocean.sim_time = t_previo

	if err != OK:
		get_tree().quit(1)
	elif peor_error > GoldenOceano.TOLERANCIA:
		# Se guarda igual —sirve para investigar— pero se sale en rojo: una
		# tabla que ya nace divergiendo de la CPU no es una referencia.
		print_rich("[color=red][b]LA TABLA NACE DIVERGIENDO. Revisar antes de commitear.[/b][/color]")
		get_tree().quit(1)
	else:
		print_rich("[color=green][b]CPU y GPU coinciden. Tabla lista para commitear.[/b][/color]")
		get_tree().quit(0)


func _cpu(comp: int, p: Vector2, t: float) -> float:
	var proxy := Ocean.get_proxy()
	if comp == 3:
		# EN REPOSO, no `jacobian_at`: esa invierte la posicion primero porque
		# quien pregunta desde el juego da una posicion de mundo. El shader
		# recibe la de reposo, asi que comparar contra `jacobian_at` era
		# comparar dos cosas distintas (se veia como 0.22 m de divergencia).
		return proxy.jacobian_en_reposo(p, t)
	var d: Vector3 = proxy.displacement(p, t)
	if comp == 0:
		return d.x
	if comp == 1:
		return d.y
	return d.z
