class_name AguaEmbarcada
extends Node

## El agua que entra en el barco. Cuelga del [FloatingBody3D] del pesquero y es
## el UNICO que decide cuanta hay: las olas que rebasan la borda, el goteo de la
## lluvia y las celdas que quedan enterradas.
##
## [b]No simula fluidos.[/b] "Agua a bordo" es bajarle el empuje a la celda donde
## entro ([member BuoyancyProbe3D.flooding]). De ahi salen solas la escora hacia
## el lado anegado, el calado que crece y la respuesta pastosa, sin un plano de
## agua ni una linea de HUD: el barco ES el indicador (docs/DISENO.md).
##
## [b]Solo corre en el host.[/b] Los clientes reciben los ocho niveles por la red
## y los copian con [method FloatingBody3D.fijar_inundacion]; aca solo re-emiten
## señales para la UI y el audio. El guard tiene que estar en ESTE nodo y no solo
## en `Net`: cuando el cliente congela el barco le apaga el `_physics_process` al
## cuerpo, pero los hijos siguen procesando tan campantes.
##
## Toda la aritmetica vive en [AguaEmbarcadaModel] (puro y testeable) y todos los
## numeros en el .tres de balance. Aca queda el cableado: muestrear, decidir
## cuando una ola cuenta, y repartir.

signal ola_sobre_borda(intensidad: float, indice_punto: int)
signal alarma_cambiada(encendida: bool)
signal naufragio(causa: String)
signal reflotado()

## Cada cuantos ticks se muestrea la borda. `Ocean.get_height()` es la consulta
## cara del sistema y una cresta tarda cerca de un segundo en pasar: a 120 Hz se
## preguntaria treinta veces lo mismo. A uno de cada cuatro (~30 Hz) no se escapa
## ninguna ola y el coste baja a la cuarta parte.
const TICKS_MUESTREO := 4

## Cuanta agua se lleva la celda mas cercana al punto por el que entro la ola; el
## resto va a la segunda. Repartir en dos evita el pozo en una sola celda y hace
## que el barco se tumbe hacia el costado mojado, que es lo que se quiere leer.
const SESGO_CELDA := 0.6

@export var balance: AguaEmbarcadaBalance

## De donde salen los puntos de borda. Son Marker3D en la tapa de la regala: su
## altura NO se escribe en codigo, se lee de su transform, asi que se mueven con
## la escora y el costado hundido embarca antes, gratis.
@export var puntos_borda_path: NodePath = ^"../PuntosBorda"

## Agua a bordo 0..1, cacheada para la UI y la red.
##
## ⚠️ EN UN CLIENTE solo refleja las celdas que llegan replicadas: el agua que las
## bombas llevan en la camara es host-only y `NetAgua` no la manda, asi que el
## nivel de un invitado puede ir por debajo del real en hasta una camara (~0,03).
## No afecta a lo que se ve —esa agua no le quita empuje a ninguna celda en
## ninguna maquina— ni a la alarma y el naufragio, que viajan como banderas ya
## decididas por el host. Pero si alguien cuelga un umbral de aqui, que sepa que
## en el cliente miente por abajo.
var nivel: float = 0.0
var alarma: bool = false
var hundido: bool = false

var _barco: FloatingBody3D
## Las bombas del barco, para contar lo que llevan chupado y todavia no han
## escupido. Se apuntan solas al encontrar este nodo.
var _bombas: Array[ManualBilgePump] = []
var _puntos: Array[Marker3D] = []
var _enfriamiento: PackedFloat32Array = PackedFloat32Array()
var _sobre_borda: Array[bool] = []
var _celdas_xz: PackedVector2Array = PackedVector2Array()
var _calado_cubierta: float = 1.5
var _linea_de_agua_local: float = -0.23
var _geometria_lista: bool = false
var _acumulado_naufragio: float = 0.0
var _tick: int = 0


func _ready() -> void:
	_barco = get_parent() as FloatingBody3D
	if _barco == null:
		push_warning("AguaEmbarcada tiene que colgar de un FloatingBody3D; no va a entrar agua.")
		set_physics_process(false)
		return
	if balance == null:
		balance = AguaEmbarcadaBalance.new()

	var contenedor := get_node_or_null(puntos_borda_path)
	if contenedor != null:
		for hijo in contenedor.get_children():
			if hijo is Marker3D:
				_puntos.append(hijo)
	if _puntos.is_empty():
		push_warning("AguaEmbarcada sin puntos de borda: las olas no van a embarcar.")
	_enfriamiento.resize(_puntos.size())
	_enfriamiento.fill(0.0)
	_sobre_borda.resize(_puntos.size())
	_sobre_borda.fill(false)


## La geometria NO se puede medir en `_ready`: Godot llama al de los HIJOS antes
## que al del padre, asi que aqui el `FloatingBody3D` todavia no ha recogido sus
## sondas y `probes` esta vacio. Medir ahi daba un area de flotacion de cero, una
## division que mandaba el barco a cuatro millones de metros bajo el mar, y de
## paso un reparto de olas que no mojaba ninguna celda.
func _asegurar_geometria() -> void:
	if _geometria_lista or _barco.probes.is_empty():
		return
	_geometria_lista = true
	_medir_geometria()


## La geometria del casco se lee UNA vez, de la escena real: las celdas para
## repartir el agua y la altura de la cubierta sobre las sondas, que es lo que
## decide cuando una celda esta enterrada. Copiar esos numeros a mano seria
## exactamente el "mismo numero en dos sitios" que el repo prohibe.
func _medir_geometria() -> void:
	_celdas_xz.resize(_barco.probes.size())
	var sonda_y: float = 0.0
	for i in _barco.probes.size():
		var p := _barco.probes[i].position
		_celdas_xz[i] = Vector2(p.x, p.z)
		sonda_y += p.y
	if not _barco.probes.is_empty():
		sonda_y /= float(_barco.probes.size())

	var casco := _barco.get_node_or_null(^"HullShape") as CollisionShape3D
	var caja := casco.shape as BoxShape3D if casco != null else null
	var cubierta_y: float = casco.position.y + caja.size.y * 0.5 if caja != null else 0.8
	_calado_cubierta = maxf(cubierta_y - sonda_y, 0.1)

	# Donde queda la linea de agua con el barco seco: `d0 = masa / (densidad *
	# area de flotacion)` por encima de las sondas. Es la altura a la que hay que
	# dejar el barco al reflotarlo para que aparezca FLOTANDO en vez de caer.
	var area: float = 0.0
	for sonda in _barco.probes:
		area += sonda.volume / sonda.height
	var d0: float = _barco.mass / maxf(
		AguaEmbarcadaModel.DENSIDAD_AGUA * area, 0.001)
	_linea_de_agua_local = sonda_y + d0


func _es_cliente() -> bool:
	return Net != null and Net.rol == Net.Rol.CLIENTE


## Una bomba se apunta para que su camara cuente. Lo hace ella al encontrar este
## nodo, en vez de que este rastree el barco buscando bombas: asi la segunda
## bomba de estribor y la electrica de la mejora entran sin tocar nada de aqui.
func registrar_bomba(bomba: ManualBilgePump) -> void:
	if bomba == null or _bombas.has(bomba):
		return
	_bombas.append(bomba)


## El agua chupada que todavia no se ha escupido, sobre la media del barco.
##
## Cuenta como agua A BORDO, y esa es la regla que sostiene el ciclo de dos
## tiempos: si el nivel bajara al chupar, mantener la palanca con la camara llena
## seria una forma de esconder agua y de burlar el umbral de naufragio. El barco
## no se alivia por chupar, se alivia por escupir.
func agua_en_depositos() -> float:
	var total: float = 0.0
	for i in range(_bombas.size() - 1, -1, -1):
		if not is_instance_valid(_bombas[i]):
			_bombas.remove_at(i)
			continue
		total += maxf(_bombas[i].carga_deposito, 0.0)
	return total


## Todo lo que el barco lleva encima: lo de las celdas mas lo que esta de paso
## por las bombas.
func _nivel_a_bordo() -> float:
	return _barco.flooding_level() + agua_en_depositos()


func _physics_process(delta: float) -> void:
	if _barco == null:
		return
	# En el cliente el agua es un dato que llega por el cable, no algo que se
	# calcule: simularla aqui daria dos respuestas distintas para el mismo barco.
	if _es_cliente():
		nivel = _nivel_a_bordo()
		return

	_asegurar_geometria()
	if not _geometria_lista:
		return

	_tick += 1
	if _tick % TICKS_MUESTREO == 0:
		_muestrear_borda(delta * float(TICKS_MUESTREO))

	_entrar_por_mar(delta)
	_entrar_por_entierro(delta)
	_entrar_por_lluvia(delta)

	nivel = _nivel_a_bordo()
	_revisar_umbrales(delta)


# =============================================================================
#  Las tres fuentes
# =============================================================================

## Olas sobre la borda: el grueso del agua embarcada (docs/CLIMA.md §6.4).
##
## Una ola cuenta UNA vez, en el flanco de subida y con enfriamiento: sin las dos
## cosas, la misma cresta se cobraria treinta veces mientras pasa y el barco se
## llenaria de golpe sin que nadie hubiera visto nada raro.
func _muestrear_borda(paso: float) -> void:
	# El enfriamiento y el flanco se siguen actualizando aunque el barco este
	# volcado: si se dejaran congelados, al adrizarse contarian los seis puntos
	# de golpe y el barco se comeria medio deposito de una vez.
	var hay_cubierta := AguaEmbarcadaModel.cubierta_mira_arriba(_barco.global_basis.y)
	for i in _puntos.size():
		_enfriamiento[i] = maxf(_enfriamiento[i] - paso, 0.0)

		var pos := _puntos[i].global_position
		var rebase := AguaEmbarcadaModel.rebase(
			Ocean.get_height(pos), pos.y, balance.margen_borda)
		var mojado := rebase > 0.0
		var flanco := mojado and not _sobre_borda[i]
		_sobre_borda[i] = mojado

		if not flanco or _enfriamiento[i] > 0.0 or not hay_cubierta:
			continue
		_enfriamiento[i] = balance.enfriamiento_punto

		var intensidad := AguaEmbarcadaModel.intensidad_ola(rebase, balance.rebase_pleno)
		var agregado := AguaEmbarcadaModel.aporte_ola(
			intensidad, balance.aporte_ola_min, balance.aporte_ola_max)
		_repartir(pos, agregado)
		ola_sobre_borda.emit(intensidad, i)
		if Net != null and Net.rol == Net.Rol.HOST:
			Net.avisar_ola_sobre_borda(intensidad, i)


## Reparte un aporte (expresado sobre la media del barco) entre las dos celdas
## mas cercanas al punto por el que entro.
func _repartir(pos_global: Vector3, agregado: float) -> void:
	if agregado <= 0.0 or _celdas_xz.is_empty():
		return
	var local := _barco.to_local(pos_global)
	var reparto := AguaEmbarcadaModel.reparto_dos_celdas(
		_celdas_xz, Vector2(local.x, local.z), SESGO_CELDA)
	var a: int = int(reparto[0])
	var b: int = int(reparto[1])
	var peso: float = float(reparto[2])
	# `aporte_por_celda` dice cuanto sumarle a CADA celda afectada. Aqui no se le
	# suma lo mismo a las dos: se reparte UNA porcion entre ellas con pesos, asi
	# que la porcion que hay que repartir es la de "una sola celda afectada".
	# Pedirla para dos y luego partirla metia justo la mitad del agua que decia
	# el balance, y el dial de dificultad mentia por un factor 2 sin que ningun
	# test unitario lo viera: la funcion pura estaba bien, el uso no.
	var porcion := AguaEmbarcadaModel.aporte_por_celda(
		agregado, _barco.probe_count(), 1)
	_barco.flood_probe(a, porcion * peso)
	_barco.flood_probe(b, porcion * (1.0 - peso))


## Mar gruesa: el agua que entra pulverizada y a crestazos cuando el temporal
## aprieta (ver `AguaEmbarcadaModel.embarque_por_mar` para el porque de que esta
## fuente exista aparte de las olas sobre la borda).
##
## Entra POR BARLOVENTO, no repartida por igual: el costado que recibe el viento
## y las crestas se moja mas, el barco se escora hacia el, y de ahi sale sola la
## decision que el diseño le pide al achicador — que celda vaciar primero
## depende del rumbo que lleve el barco, no de una tabla.
func _entrar_por_mar(delta: float) -> void:
	var por_s := AguaEmbarcadaModel.embarque_por_mar(
		Ocean.fury, balance.furia_umbral_embarque, balance.embarque_mar_max)
	if por_s <= 0.0 or _puntos.is_empty():
		return
	var punto := _punto_de_barlovento()
	if punto == null:
		return
	_repartir(punto.global_position, por_s * delta)


## El punto de borda mas expuesto al viento. `Ocean.wind_dir_vector()` es un
## Vector2 en el plano XZ del mundo y apunta HACIA DONDE sopla, asi que
## barlovento es el costado que le da la cara: el de producto escalar mas
## negativo.
func _punto_de_barlovento() -> Marker3D:
	var soplo := Ocean.wind_dir_vector()
	if soplo.length_squared() < 0.0001:
		return _puntos[0]
	var centro := _barco.global_position
	var mejor: Marker3D = _puntos[0]
	var mejor_exposicion: float = -INF
	for m in _puntos:
		var hacia := m.global_position - centro
		var plano := Vector2(hacia.x, hacia.z)
		if plano.length_squared() < 0.0001:
			continue
		var exposicion: float = -plano.normalized().dot(soplo)
		if exposicion > mejor_exposicion:
			mejor_exposicion = exposicion
			mejor = m
	return mejor


## Celda enterrada: con la cubierta bajo el agua ya no hay borda que valga, y
## entra a un ritmo alto y capado. Es lo que convierte un tsunami en un trago de
## agua de verdad, y lo que remata al barco que ya venia inundado.
##
## El factor de escora es lo que impide que esta misma fuente remate tambien al
## barco VOLCADO, que es un caso que no le toca: ver
## `AguaEmbarcadaModel.factor_entierro`.
func _entrar_por_entierro(delta: float) -> void:
	var factor := AguaEmbarcadaModel.factor_entierro(_barco.global_basis.y)
	for i in _barco.probes.size():
		if _barco.probes[i].submersion > _calado_cubierta:
			_barco.flood_probe(i, balance.ritmo_entierro * factor * delta)


## Lluvia: goteo lento y parejo. No amenaza sola —a diluvio pleno tarda unos once
## minutos en llegar a la alarma— pero obliga a achicar de vez en cuando, que es
## justo lo que se le pide (docs/CLIMA.md §1: la lluvia debe COSTAR algo).
func _entrar_por_lluvia(delta: float) -> void:
	var goteo := AguaEmbarcadaModel.goteo_lluvia(Ocean.rain01, balance.goteo_lluvia_max)
	if goteo <= 0.0:
		return
	# Repartido entre todas: la lluvia cae sobre la cubierta entera.
	var por_celda := goteo * delta
	for i in _barco.probes.size():
		_barco.flood_probe(i, por_celda)


# =============================================================================
#  Alarma y naufragio
# =============================================================================

func _revisar_umbrales(delta: float) -> void:
	var encendida := AguaEmbarcadaModel.estado_alarma(
		nivel, balance.umbral_alarma, balance.histeresis_alarma, alarma)
	if encendida != alarma:
		alarma = encendida
		alarma_cambiada.emit(alarma)

	_acumulado_naufragio = AguaEmbarcadaModel.acumular_naufragio(
		nivel, balance.umbral_naufragio, _acumulado_naufragio, delta)
	if hundido or _acumulado_naufragio < balance.sostenido_naufragio:
		return
	hundido = true
	naufragio.emit(_causa())


## Que celda se anego primero, para la bitacora y para que el aviso pueda decir
## algo mas util que "te hundiste".
func _causa() -> String:
	var peor: int = 0
	for i in _barco.probes.size():
		if _barco.probes[i].flooding > _barco.probes[peor].flooding:
			peor = i
	return "furia %.0f, %s" % [Ocean.fury, _barco.probes[peor].name]


## Devuelve el barco a la superficie, seco y adrizado. Hoy es la salida de
## emergencia del HUD de debug; el dia que exista el puerto sera el reflote de
## verdad (docs/DISENO.md: naufragar es barato, se pierde la captura).
func reflotar() -> void:
	if _barco == null:
		return
	_asegurar_geometria()
	var pos := _barco.global_position
	# En su linea de flotacion exacta, no "unos metros por encima": soltarlo
	# desde el aire lo hace caer, y esa caida entierra las celdas y le mete el
	# agua que acabamos de sacarle. Un reflote que te devuelve inundado no es un
	# reflote.
	pos.y = Ocean.get_height(pos) - _linea_de_agua_local
	# Quilla abajo conservando el rumbo: si el barco venia volcado, dejarlo como
	# estaba seria devolverlo al mismo problema.
	var rumbo := _barco.global_basis.get_euler().y
	_barco.global_transform = Transform3D(Basis(Vector3.UP, rumbo), pos)
	_barco.linear_velocity = Vector3.ZERO
	_barco.angular_velocity = Vector3.ZERO
	_barco.bail_out(1.0)
	# Las bombas tambien: el agua de una camara cuenta a bordo, asi que un reflote
	# que la dejara llena devolveria el barco con una gota de la vida anterior.
	for bomba in _bombas:
		if is_instance_valid(bomba):
			bomba.vaciar_camara()
	# OBLIGATORIO tras escribir un transform: una escritura de transform ES un
	# teleport, y un teleport fabrica un slam de decenas de m/s con su chapuzon
	# que nunca ocurrio (regla 8).
	_barco.olvidar_historial_agua()

	_acumulado_naufragio = 0.0
	hundido = false
	_enfriamiento.fill(0.0)
	for i in _sobre_borda.size():
		_sobre_borda[i] = false
	nivel = 0.0
	if alarma:
		alarma = false
		alarma_cambiada.emit(false)
	reflotado.emit()


## El cliente no simula el agua: la recibe. Esto solo refleja las banderas que
## mandan la UI y el audio, para que un naufragio o una alarma se vean igual en
## las seis pantallas sin que ninguna lo haya decidido por su cuenta.
func aplicar_estado_remoto(alarma_remota: bool, hundido_remoto: bool) -> void:
	if alarma_remota != alarma:
		alarma = alarma_remota
		alarma_cambiada.emit(alarma)
	if hundido_remoto and not hundido:
		hundido = true
		naufragio.emit("el host declaro el naufragio")
	elif not hundido_remoto and hundido:
		hundido = false


## Los ocho niveles, para que la red los empaquete.
func niveles() -> PackedFloat32Array:
	var salida := PackedFloat32Array()
	if _barco == null:
		return salida
	salida.resize(_barco.probes.size())
	for i in _barco.probes.size():
		salida[i] = _barco.probes[i].flooding
	return salida
