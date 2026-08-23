class_name FishSpecies
extends RefCounted

## Tabla de especies por banda de furia (documento de diseño, sección economía).
##
## La regla que importa: el pez caro vive donde el mar es peor. La banda se
## decide por la furia REAL en el momento de la picada, así que quedarse
## pescando mientras el mar sube es literalmente la apuesta del juego.

const SPECIES: Array[Dictionary] = [
	# banda A (furia 0-3): pica generosa, valor bajo. Pescas mirando al amigo.
	{&"name": "Sardina", &"min_fury": 0.0, &"weight": 2.0, &"pull": 0.28, &"value": 6,
		&"color": Color(0.65, 0.72, 0.78)},
	{&"name": "Caballa", &"min_fury": 0.0, &"weight": 3.0, &"pull": 0.34, &"value": 8,
		&"color": Color(0.35, 0.55, 0.62)},
	# banda B (furia 3-6): lucha real, dos manos.
	{&"name": "Lubina", &"min_fury": 3.0, &"weight": 8.0, &"pull": 0.45, &"value": 35,
		&"color": Color(0.55, 0.60, 0.52)},
	{&"name": "Bacalao", &"min_fury": 3.0, &"weight": 12.0, &"pull": 0.55, &"value": 45,
		&"color": Color(0.48, 0.45, 0.38)},
	{&"name": "Fletan", &"min_fury": 4.0, &"weight": 20.0, &"pull": 0.64, &"value": 90,
		&"color": Color(0.42, 0.38, 0.3)},
	# banda C (furia 6+): la pesca heroica.
	{&"name": "Atun", &"min_fury": 6.0, &"weight": 60.0, &"pull": 0.8, &"value": 450,
		&"color": Color(0.25, 0.3, 0.42)},
]


## Elige especie para la furia actual: solo pican las de tu banda o inferiores,
## pero las de banda alta pesan mas en el sorteo cuanto mas bravo esta el mar.
static func choose(fury: float, rng: RandomNumberGenerator) -> Dictionary:
	var pool: Array[Dictionary] = []
	var weights: PackedFloat32Array = PackedFloat32Array()
	var total: float = 0.0
	for s in SPECIES:
		if fury < float(s[&"min_fury"]):
			continue
		pool.append(s)
		# Las especies "de tu furia" dominan el sorteo; las triviales no
		# desaparecen, solo se vuelven raras.
		var w: float = 1.0 + 3.0 * clampf(1.0 - (fury - float(s[&"min_fury"])) / 3.0, 0.0, 1.0)
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
