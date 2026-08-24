class_name FishSpecies
extends RefCounted

## Tabla de especies por banda de furia (documento de diseño, sección economía).
##
## La regla que importa: el pez caro vive donde el mar es peor. La banda se
## decide por la furia REAL en el momento de la picada, así que quedarse
## pescando mientras el mar sube es literalmente la apuesta del juego.
##
## El TIER es la banda hecha número (1=A, 2=B, 3=C, 4=legendaria) y es lo que
## lee la lucha: fija la ventana de reacción antes de que rompa el sedal
## (FightModel.SNAP_HOLD_BY_TIER). El pez humilde perdona el error del que
## aprende; el heroico exige los reflejos que ya entrenaste con los humildes.
##
## `rarity` multiplica el peso en el sorteo SIN tocar las bandas: la legendaria
## pica ~1 de cada 12-20 lances en su furia (documento de diseño). Pendiente de
## esa sección: legendarias también durante la retirada pre-tsunami (necesita
## consultar el evento en Ocean, no solo la furia — ver docs/PESCA.md).

const SPECIES: Array[Dictionary] = [
	# banda A (furia 0-3): pica generosa, valor bajo. Pescas mirando al amigo.
	{&"name": "Sardina", &"min_fury": 0.0, &"tier": 1, &"weight": 2.0, &"pull": 0.28, &"value": 6,
		&"color": Color(0.65, 0.72, 0.78),
		&"visual_scene": "res://game/fishing/models/sardina.glb",
		&"collision_length": 0.46, &"collision_radius": 0.082},
	{&"name": "Caballa", &"min_fury": 0.0, &"tier": 1, &"weight": 3.0, &"pull": 0.34, &"value": 8,
		&"color": Color(0.35, 0.55, 0.62),
		&"visual_scene": "res://game/fishing/models/caballa.glb",
		&"collision_length": 0.53, &"collision_radius": 0.098},
	{&"name": "Jurel", &"min_fury": 0.0, &"tier": 1, &"weight": 4.0, &"pull": 0.38, &"value": 8,
		&"color": Color(0.52, 0.58, 0.55),
		&"visual_scene": "res://game/fishing/models/jurel.glb",
		&"collision_length": 0.55, &"collision_radius": 0.13},
	# banda B (furia 3-6): lucha real, dos manos.
	{&"name": "Lubina", &"min_fury": 3.0, &"tier": 2, &"weight": 8.0, &"pull": 0.45, &"value": 35,
		&"color": Color(0.55, 0.60, 0.52)},
	{&"name": "Bacalao", &"min_fury": 3.0, &"tier": 2, &"weight": 12.0, &"pull": 0.55, &"value": 45,
		&"color": Color(0.48, 0.45, 0.38)},
	{&"name": "Fletan", &"min_fury": 4.0, &"tier": 2, &"weight": 20.0, &"pull": 0.64, &"value": 90,
		&"color": Color(0.42, 0.38, 0.3)},
	# banda C (furia 6+): la pesca heroica.
	{&"name": "Atun", &"min_fury": 6.0, &"tier": 3, &"weight": 60.0, &"pull": 0.8, &"value": 450,
		&"color": Color(0.25, 0.3, 0.42)},
	# legendaria (furia 7+). Nombre en la bitácora (futuro).
	# SIEMPRE añadir al final: tests y capturas indexan la tabla por posición,
	# y los PESOS de las especies viejas están fijados por bodega_tests.
	{&"name": "Aguja azul", &"min_fury": 7.0, &"tier": 4, &"rarity": 0.15,
		&"weight": 110.0, &"pull": 1.0, &"value": 800,
		&"color": Color(0.22, 0.3, 0.52)},
	# --- 2ª tanda (el doble de peces) ----------------------------------------
	# Banda A tardía (furia 1.5-2): el mar picado trae caras nuevas. En furia
	# <=1 el sorteo queda EXACTO a los tres comunes con modelo autorado
	# (invariante de fish_asset_tests: la calma nunca enseña un pez-cápsula).
	{&"name": "Boqueron", &"min_fury": 1.5, &"tier": 1, &"weight": 1.0, &"pull": 0.26, &"value": 5,
		&"color": Color(0.72, 0.76, 0.68),
		&"visual_scene": "res://game/fishing/models/boqueron.glb",
		&"collision_length": 0.42, &"collision_radius": 0.068},
	{&"name": "Faneca", &"min_fury": 1.5, &"tier": 1, &"weight": 2.0, &"pull": 0.31, &"value": 8,
		&"color": Color(0.6, 0.52, 0.4),
		&"visual_scene": "res://game/fishing/models/faneca.glb",
		&"collision_length": 0.49, &"collision_radius": 0.105},
	{&"name": "Sargo", &"min_fury": 2.0, &"tier": 1, &"weight": 4.0, &"pull": 0.4, &"value": 14,
		&"color": Color(0.62, 0.62, 0.66),
		&"visual_scene": "res://game/fishing/models/sargo.glb",
		&"collision_length": 0.55, &"collision_radius": 0.155},
	# Banda B: dorada/merluza rellenan la mitad baja; el congrio es el matón
	# que asoma desde furia 5 — el puente hacia la banda C.
	{&"name": "Dorada", &"min_fury": 3.0, &"tier": 2, &"weight": 5.0, &"pull": 0.42, &"value": 28,
		&"color": Color(0.75, 0.7, 0.5)},
	{&"name": "Merluza", &"min_fury": 3.0, &"tier": 2, &"weight": 10.0, &"pull": 0.5, &"value": 40,
		&"color": Color(0.5, 0.54, 0.58)},
	{&"name": "Congrio", &"min_fury": 5.0, &"tier": 2, &"weight": 26.0, &"pull": 0.68, &"value": 130,
		&"color": Color(0.35, 0.38, 0.35)},
	# Banda C: el mero abre la pesca heroica un escalón por debajo del atún.
	{&"name": "Mero", &"min_fury": 6.0, &"tier": 3, &"weight": 45.0, &"pull": 0.74, &"value": 320,
		&"color": Color(0.4, 0.3, 0.25)},
	# Segunda legendaria: el tiburón. Con DOS en el pool, rarity 0.15 cada una
	# deja la suma en ~1 de cada 15-17 lances (la banda 12-20 del diseño).
	{&"name": "Marrajo", &"min_fury": 7.5, &"tier": 4, &"rarity": 0.15,
		&"weight": 160.0, &"pull": 1.05, &"value": 900,
		&"color": Color(0.3, 0.36, 0.44)},
]


## Elige especie para la furia actual: solo pican las de tu banda o inferiores,
## pero las de banda alta pesan mas en el sorteo cuanto mas bravo esta el mar.
##
## `cebo_sesgo` (0 = sin cebo) inclina el sorteo hacia las especies de tu banda
## alta SIN tocar el filtro de furia: el cebo compra la atencion del pez gordo
## que ya esta ahi, jamas uno que el mar no da. Por eso entra multiplicando la
## misma "cercania" que ya decide el sorteo, y no sumando furia falsa: sumarla
## haria aparecer atunes en calma y venderia la tesis del juego en la lonja.
static func choose(fury: float, rng: RandomNumberGenerator,
		cebo_sesgo: float = 0.0) -> Dictionary:
	var pool: Array[Dictionary] = []
	var weights: PackedFloat32Array = PackedFloat32Array()
	var total: float = 0.0
	for s in SPECIES:
		if fury < float(s[&"min_fury"]):
			continue
		pool.append(s)
		# Las especies "de tu furia" dominan el sorteo; las triviales no
		# desaparecen, solo se vuelven raras. `rarity` recorta encima de eso:
		# la legendaria esta EN su banda y aun asi pica a cuentagotas.
		var cercania: float = clampf(1.0 - (fury - float(s[&"min_fury"])) / 3.0, 0.0, 1.0)
		var w: float = 1.0 + 3.0 * cercania
		# El cebo premia justo a las que ya eran "de tu furia" (cercania alta):
		# la sardina de siempre no mejora, la pieza buena de tu banda si.
		w *= 1.0 + maxf(cebo_sesgo, 0.0) * cercania
		w *= float(s.get(&"rarity", 1.0))
		weights.append(w)
		total += w
	if pool.is_empty():
		return SPECIES[0]
	var roll: float = rng.randf() * total
	for i in pool.size():
		roll -= weights[i]
		if roll <= 0.0:
			return pool[i]
	return pool[-1]


## El tier de un pez (1..4). Un diccionario sin campo cuenta como banda A:
## el fallo seguro es el pez indulgente, nunca el que rompe sedales.
static func tier_of(species: Dictionary) -> int:
	return int(species.get(&"tier", 1))
