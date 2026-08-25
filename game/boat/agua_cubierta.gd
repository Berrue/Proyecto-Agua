class_name AguaCubierta
extends MeshInstance3D

## El agua que se VE en la cubierta. Es el indicador del sistema entero.
##
## [b]Por que existe.[/b] Hasta el 24-ago-2026 el aviso de que entraba agua era
## que el barco se escoraba hacia el costado mojado. Se quito —estorbaba al feel
## y era ilegible: nadie entendia DONDE estaba el agua— y el castigo paso a ser
## hundirse recto (ver `FloatingBody3D._empuje_efectivo`). Pero eso dejaba el
## sistema mudo, porque hundirse un palmo no se nota. Esto es lo que lo devuelve
## a ser legible, y de la unica forma honesta: enseñando el agua.
##
## [b]El agua ES el medidor.[/b] Un charco te moja los pies, a las rodillas suena
## la alarma, a la cintura pierdes el barco. No hay que aprenderse ningun numero
## ni mirar ninguna barra: se mira al suelo. Los avisos de texto se quedan como
## refuerzo, no como fuente.
##
## [b]Presentacion pura: corre en TODAS las maquinas.[/b] No decide nada, solo
## lee `AguaEmbarcada.nivel` —que ya viaja replicado— y lo convierte en altura.
## Por eso no lleva guarda de rol: el invitado tiene que ver la misma agua que el
## anfitrion.
##
## No simula fluidos ni lo pretende (docs/CLIMA.md descarta la shallow-water 2D
## explicitamente): es un plano con retardo, que es el truco barato que usa medio
## genero y que basta de sobra.

## Cuanto tarda el plano en alcanzar la inclinacion del barco, en segundos.
##
## Es TODO el efecto de chapoteo: el agua persigue la inclinacion del casco y
## nunca la iguala, asi que siempre queda un desfase que se lee como liquido. A
## cero seria una tapa pegada a la cubierta; muy alto, un charco que se sale por
## los costados.
const TAU_CHAPOTEO := 0.30

## Por debajo de esta profundidad no se dibuja nada, en metros. Medio centimetro
## de agua es una lamina que hace z-fighting con la cubierta y no comunica nada;
## el primer charco visible tiene que verse charco.
const PROFUNDIDAD_MINIMA := 0.008

## Cuanto se mete la lamina por dentro de la borda, en metros. Sin este margen
## asoma por los costados en cuanto el chapoteo la inclina.
const MARGEN_BORDA := 0.06

## En cuantos tramos se afina la proa. Seis bastan para que la punta no se vea
## facetada desde la cubierta.
const REBANADAS_PROA := 6

@export_group("Cableado")
## De donde sale el nivel. Por defecto, el hermano que lo lleva.
@export var agua_path: NodePath = ^"../AguaEmbarcada"
## De donde se miden la planta y la altura de la cubierta, para no copiar ni la
## eslora ni la manga a mano: si el casco cambia, esto cambia con el.
@export var casco_path: NodePath = ^"../HullShape"
## Y la proa, que es lo que hace que la lamina no sea un rectangulo.
@export var proa_path: NodePath = ^"../HullBowShape"
## Una de las bordas: de ahi sale el FRANCOBORDO, que es el techo del charco.
@export var borda_path: NodePath = ^"../RailPort"

@export_group("Lectura")
## Nivel de agua (0..1) -> profundidad sobre la cubierta, en metros.
##
## Es la calibracion de toda la mecanica y por eso es una `Curve` editable y no
## una formula: 0,05 es un charco de dos centimetros que te moja los pies; 0,55
## —la alarma— te llega a la rodilla; 0,85 —el naufragio— a la cintura. Que esos
## tres momentos se LEAN a simple vista es lo que hace que el jugador no necesite
## ningun HUD.
@export var curva_profundidad: Curve

## Cuanto se ve el fondo a traves. El agua de sentina de un pesquero en tormenta
## esta sucia: demasiado transparente y no se ve, opaca parece pintura.
##
## Se subio de 0,62 a 0,82 mirando capturas: a 0,62 el agua por la CINTURA se
## leia como una niebla gris sobre las tablas, y este nodo existe justamente para
## que el nivel se entienda de un vistazo. Un indicador que no se ve no es un
## indicador.
@export_range(0.0, 1.0, 0.01) var opacidad: float = 0.90

## Y lo transparente que es un charco recien hecho. Que la opacidad DEPENDA de
## la profundidad es lo que hace que los tres momentos se distingan de un
## vistazo, y ademas es lo que hace el agua de verdad: dos centimetros dejan ver
## las tablas y un metro no. Con una opacidad fija, el charco y el naufragio se
## parecian demasiado — la cubierta solo se veia "mas oscura".
@export_range(0.0, 1.0, 0.01) var opacidad_charco: float = 0.30

## Verde sucio de sentina. Frio y saturado a proposito: la cubierta es marron
## calida, asi que el contraste de color es lo que hace que el agua se lea como
## agua y no como una sombra.
@export var color_agua: Color = Color(0.07, 0.20, 0.19)

var _agua: AguaEmbarcada
var _barco: Node3D
var _cubierta_y: float = 0.8
## Cuanto cabe de agua antes de rebasar la regala, en metros. Es un techo fisico,
## no una decision: por encima de la borda el agua se saldria sola, y dibujarla
## ahi la hacia atravesar los costados.
var _francobordo: float = 0.95
var _profundidad: float = 0.0
var _seguido: Quaternion = Quaternion.IDENTITY
var _listo: bool = false


func _ready() -> void:
	_agua = get_node_or_null(agua_path) as AguaEmbarcada
	_barco = get_parent() as Node3D
	_medir_casco()
	if curva_profundidad == null:
		curva_profundidad = _curva_por_defecto()
	if material_override == null:
		material_override = _material_por_defecto()
	# Sombra no: es una lamina translucida dentro del casco y proyectar sombra
	# solo produce manchas raras en la cubierta.
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false
	_listo = true


## La planta y la altura salen de las colisiones REALES del casco. Copiarlas
## seria el "mismo numero en dos sitios" que el repo prohibe, y ademas el casco
## ya cambio de tamaño una vez.
##
## Y la planta no es un rectangulo: el pesquero tiene la proa en punta. Con una
## lamina rectangular el agua asomaba por fuera de la amura —se veia flotando
## sobre el costado blanco, por fuera del barco—, que es exactamente el tipo de
## fallo que un test verde no ve y una captura si.
func _medir_casco() -> void:
	var casco := get_node_or_null(casco_path) as CollisionShape3D
	var caja := casco.shape as BoxShape3D if casco != null else null
	if caja == null:
		push_warning("AguaCubierta no encuentra el HullShape: uso una planta por defecto.")
		mesh = _lamina(2.5, 4.5, -3.25, 2.4, -6.3, 0.1)
		return
	_cubierta_y = casco.position.y + caja.size.y * 0.5
	position = Vector3(0.0, _cubierta_y, 0.0)
	_medir_francobordo()

	var semi: float = caja.size.x * 0.5 - MARGEN_BORDA
	var popa_z: float = casco.position.z + caja.size.z * 0.5 - MARGEN_BORDA
	var union_z: float = casco.position.z - caja.size.z * 0.5

	# La proa, medida de su propio casco convexo: se toman los puntos que estan a
	# la altura de la CUBIERTA o por encima, y de ahi salen donde empieza a
	# afinarse y donde acaba en punta.
	#
	# ⚠️ El filtro es "por encima de la cubierta" y NO "los mas altos", que fue el
	# primer intento y estaba mal: la proa tiene arrufo, o sea que SUBE hacia la
	# punta. Quedarse con los mas altos dejaba solo los dos vertices de la punta,
	# el afinado salia degenerado y el agua se cortaba en seco en la cuaderna
	# maestra — media cubierta seca con el barco supuestamente anegado. Los tests
	# pasaban igual; se vio en una captura.
	var proa_z: float = union_z
	var proa_semi: float = semi
	var union_semi: float = semi
	var convexa := _puntos_de_proa()
	if not convexa.is_empty():
		var suelo: float = _cubierta_y - 0.05
		var z_min: float = INF
		var z_max: float = -INF
		for punto in convexa:
			if punto.y < suelo:
				continue
			z_min = minf(z_min, punto.z)
			z_max = maxf(z_max, punto.z)
		if z_min < z_max:
			proa_z = z_min + MARGEN_BORDA
			union_z = z_max
			proa_semi = _semianchura_en(convexa, suelo, z_min)
			union_semi = minf(_semianchura_en(convexa, suelo, z_max), semi)

	mesh = _lamina(semi, popa_z, union_z, maxf(union_semi - MARGEN_BORDA, 0.05),
		proa_z, maxf(proa_semi - MARGEN_BORDA * 0.5, 0.02))


## El francobordo, medido de la borda real: de la cubierta a la tapa de la
## regala. Es el techo del charco.
func _medir_francobordo() -> void:
	var borda := get_node_or_null(borda_path) as CollisionShape3D
	var caja := borda.shape as BoxShape3D if borda != null else null
	if caja == null:
		return
	var tapa: float = borda.position.y + caja.size.y * 0.5
	# Un dedo por debajo de la tapa: justo al ras se ve atravesar la regala.
	_francobordo = maxf(tapa - _cubierta_y - 0.05, 0.1)


func _puntos_de_proa() -> PackedVector3Array:
	var proa := get_node_or_null(proa_path) as CollisionShape3D
	var convexa := proa.shape as ConvexPolygonShape3D if proa != null else null
	if convexa == null:
		return PackedVector3Array()
	return convexa.points


## La mitad del ancho que tiene el casco a esa z, contando solo lo que esta de la
## cubierta para arriba: por debajo el casco se estrecha hacia la quilla y daria
## un charco mas flaco que la cubierta que pisas.
func _semianchura_en(puntos: PackedVector3Array, suelo: float, z: float) -> float:
	var ancho: float = 0.0
	for punto in puntos:
		if punto.y < suelo or absf(punto.z - z) > 0.05:
			continue
		ancho = maxf(ancho, absf(punto.x))
	return ancho


## La lamina, en rebanadas de popa a proa. Recta hasta donde el casco empieza a
## afinarse y luego en punta, siguiendo la amura.
func _lamina(semi: float, popa_z: float, union_z: float, union_semi: float,
		proa_z: float, proa_semi: float) -> ArrayMesh:
	var rebanadas: Array = [
		[popa_z, semi],
		[union_z, union_semi],
	]
	# Unas cuantas rebanadas en la proa para que la punta no se vea facetada.
	for i in range(1, REBANADAS_PROA + 1):
		var t: float = float(i) / float(REBANADAS_PROA)
		rebanadas.append([
			lerpf(union_z, proa_z, t),
			lerpf(union_semi, proa_semi, t),
		])

	var vertices := PackedVector3Array()
	var normales := PackedVector3Array()
	var uvs := PackedVector2Array()
	for i in range(rebanadas.size() - 1):
		var z0: float = float(rebanadas[i][0])
		var w0: float = float(rebanadas[i][1])
		var z1: float = float(rebanadas[i + 1][0])
		var w1: float = float(rebanadas[i + 1][1])
		var a := Vector3(-w0, 0.0, z0)
		var b := Vector3(w0, 0.0, z0)
		var c := Vector3(w1, 0.0, z1)
		var d := Vector3(-w1, 0.0, z1)
		for v: Vector3 in [a, b, c, a, c, d]:
			vertices.append(v)
			normales.append(Vector3.UP)
			uvs.append(Vector2(v.x * 0.5, v.z * 0.5))

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normales
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


func _process(delta: float) -> void:
	if not _listo or _agua == null or _barco == null:
		return
	_profundidad = profundidad_maxima()
	visible = _profundidad >= PROFUNDIDAD_MINIMA
	if not visible:
		# Sin agua, el chapoteo se olvida: al volver a entrar agua no tiene que
		# aparecer con la inclinacion de hace media hora.
		_seguido = _barco.global_basis.get_rotation_quaternion()
		return

	position.y = _cubierta_y + _profundidad
	_enturbiar()
	_chapotear(delta)


## Cuanto tapa el agua, segun lo honda que sea. Un charco deja ver la madera; con
## el agua por la cintura ya no se ve el fondo y lo que se lee es la SUPERFICIE,
## que es justo lo que convierte "la cubierta esta oscura" en "hay medio metro de
## agua ahi dentro".
func _enturbiar() -> void:
	var m := material_override as StandardMaterial3D
	if m == null:
		return
	var t: float = clampf(_profundidad / maxf(_francobordo, 0.01), 0.0, 1.0)
	# Sube rapido al principio: el salto de "mojado" a "inundado" tiene que
	# notarse ya con un palmo de agua, no solo al final.
	var alfa: float = lerpf(opacidad_charco, opacidad, sqrt(t))
	m.albedo_color = Color(color_agua.r, color_agua.g, color_agua.b, alfa)


## El agua persigue la inclinacion del casco y nunca la alcanza. Ese desfase ES
## el chapoteo: sin el, el plano seria una tapa soldada a la cubierta.
##
## Se sigue en el espacio del MUNDO y luego se descuenta la rotacion del barco,
## porque lo que se retrasa es la superficie del agua, no un hijo del casco.
func _chapotear(delta: float) -> void:
	var casco: Quaternion = _barco.global_basis.get_rotation_quaternion()
	var alfa: float = 1.0 - exp(-delta / maxf(TAU_CHAPOTEO, 0.001))
	_seguido = _seguido.slerp(casco, clampf(alfa, 0.0, 1.0)).normalized()
	basis = Basis(casco.inverse() * _seguido)


# =============================================================================
#  Lo que se puede preguntar desde fuera
# =============================================================================

## Cuanta agua hay en el punto mas hondo de la cubierta, en metros.
func profundidad_maxima() -> float:
	if _agua == null or curva_profundidad == null:
		return 0.0
	var bruta: float = curva_profundidad.sample_baked(clampf(_agua.nivel, 0.0, 1.0))
	# Topada al francobordo: mas agua que eso no cabe dentro del barco.
	return clampf(bruta, 0.0, _francobordo)


## Cuanta agua le llega a alguien que esta en `pos_global`, en metros. 0 si esta
## fuera del barco o por encima de la superficie.
##
## Lo va a usar el freno al caminar (paso 4 del rediseño) y el chapoteo de audio.
## Se pregunta a la SUPERFICIE dibujada y no al nivel, para que lo que frena al
## jugador sea exactamente el agua que esta viendo.
func profundidad_en(pos_global: Vector3) -> float:
	if not visible or _barco == null:
		return 0.0
	var superficie: float = to_global(Vector3.ZERO).y
	return maxf(superficie - pos_global.y, 0.0)


# =============================================================================
#  Los defaults, para que el nodo funcione recien puesto en la escena
# =============================================================================

## La calibracion de fabrica: charco, rodilla en la alarma, cintura en el
## naufragio. Se puede sustituir por una `Curve` autorada sin tocar codigo.
func _curva_por_defecto() -> Curve:
	var c := Curve.new()
	c.max_value = 1.25
	c.add_point(Vector2(0.0, 0.0))
	c.add_point(Vector2(0.05, 0.02))
	c.add_point(Vector2(0.55, 0.45))
	c.add_point(Vector2(0.85, 1.00))
	c.add_point(Vector2(1.0, 1.20))
	c.bake()
	return c


func _material_por_defecto() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(color_agua.r, color_agua.g, color_agua.b, opacidad_charco)
	# Brillo alto y superficie casi pulida: el reflejo del cielo es lo que
	# convierte un plano plano en LIQUIDO. Sin esto es una cartulina translucida,
	# por muy bien que este el color.
	m.roughness = 0.04
	m.metallic = 0.25
	m.metallic_specular = 0.85
	# Un punto de luz propia para que el agua no se apague del todo en la sombra
	# del casco: el aviso tiene que leerse tambien de noche y bajo la cabina.
	m.emission_enabled = true
	m.emission = color_agua
	m.emission_energy_multiplier = 0.18
	# Se ve desde arriba y desde DENTRO: con el agua por la cintura, la camara
	# esta debajo de la superficie y una cara sola desapareceria.
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Sin recibir sombras: es agua dentro de un casco que se sombrea a si mismo, y
	# con sombras se ve sucia y apagada justo cuando tiene que alarmar.
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	return m
