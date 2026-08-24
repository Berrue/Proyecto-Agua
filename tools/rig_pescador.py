"""Rig del pescador: reestructura pescador.glb para import_as_skeleton_bones.

El GLB del usuario (THREE.GLTFExporter) trae las piezas en un arbol PLANO:
las botas son hermanas de las piernas, las manoplas hermanas de los brazos.
Asi, rotar un brazo no arrastra su mano. Este script lo convierte en cadenas
articuladas con los nombres EXACTOS de SkeletonProfileHumanoid, que es lo que
Godot usa para automapear BoneMap y retargetear animaciones humanoides.

No toca ni un vertice ni un buffer: solo el grafo de nodos del chunk JSON.
Idempotente: si ya hay un nodo "Hips", no hace nada.

    python tools/rig_pescador.py
"""
import json
import os
import struct
import sys

GLB = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)),
	"..", "game", "player", "pescador.glb"))

# Pivotes de articulacion en espacio del modelo (medidos sobre la malla real).
# El personaje mira a +Z; T-pose. Las rodillas y codos caen en las juntas
# naturales de las piezas: los "gaps" al doblar son parte del look de bloques.
J = {
	"Root": (0.0, 0.0, 0.0),
	"Hips": (0.0, 0.55, 0.0),
	"Spine": (0.0, 0.78, 0.0),
	"Chest": (0.0, 0.95, 0.0),
	"UpperChest": (0.0, 1.05, 0.0),  # el perfil cuelga cuello y hombros de aqui
	"Neck": (0.0, 1.09, 0.0),
	"Head": (0.0, 1.12, 0.0),           # el grupo "cabeza" ya pivotaba aqui
	"barba": (0.0, 1.12, 0.0),           # extra (fuera de perfil): jiggle futuro
	"sombrero": (0.0, 1.545, 0.0),       # extra (fuera de perfil)
	"RightShoulder": (-0.16, 1.0, 0.0),   # clavicula: sin ella el brazo hereda el
	"RightUpperArm": (-0.33, 1.0, 0.0),   # frame del pecho y el clip lo sube a la cara
	"RightLowerArm": (-0.50, 1.0, 0.0),   # codo (nuevo, parte el brazo en dos)
	"RightHand": (-0.66, 1.0, 0.0),       # muñeca (era el grupo manopla_L)
	"LeftShoulder": (0.16, 1.0, 0.0),
	"LeftUpperArm": (0.33, 1.0, 0.0),
	"LeftLowerArm": (0.50, 1.0, 0.0),
	"LeftHand": (0.66, 1.0, 0.0),
	"RightUpperLeg": (-0.2, 0.46, 0.0),   # cadera de la pierna (grupo pierna_L)
	"RightLowerLeg": (-0.2, 0.26, 0.02),  # rodilla (era el grupo bota_L)
	"RightFoot": (-0.2, 0.07, 0.04),      # tobillo (nuevo, parte la bota)
	"LeftUpperLeg": (0.2, 0.46, 0.0),
	"LeftLowerLeg": (0.2, 0.26, 0.02),
	"LeftFoot": (0.2, 0.07, 0.04),
}

# ESPEJO (importante, parece un bug y no lo es): el modelo mira a +Z, y con
# Y arriba en un sistema diestro eso pone la DERECHA anatomica en -X
# (derecha = adelante x arriba = Z x Y = -X). El artista etiqueto sus mallas
# "_L" en -X, o sea al reves. Por eso los huesos Right* viven en -X y cargan
# las mallas *_L. Si esto se "corrige", cualquier animacion humanoide
# retargeteada entra espejada y los brazos salen disparados.

# (hueso, [hijos hueso], [mallas que cuelgan de el])
TREE = ("Root", [
	("Hips", [
		("Spine", [
			("Chest", [
			("UpperChest", [
				("Neck", [
					("Head", [
						("barba", [], ["barba_frente", "barba_menton", "barba_lado_L",
							"barba_lado_R", "barba_union_L", "barba_union_R"]),
						("sombrero", [], ["copa", "ala"]),
					], ["craneo", "nariz", "ceja_L", "ojo_L", "ceja_R", "ojo_R", "boca"]),
				], ["cuello"]),
				("RightShoulder", [
				("RightUpperArm", [
					("RightLowerArm", [
						("RightHand", [], ["palma_L"]),
					], ["pu\u00f1o_L"]),
				], ["brazo_geo_L"]),
				], []),
				("LeftShoulder", [
				("LeftUpperArm", [
					("LeftLowerArm", [
						("LeftHand", [], ["palma_R"]),
					], ["pu\u00f1o_R"]),
				], ["brazo_geo_R"]),
				], []),
			], []),
			], ["chubasquero_cuerpo", "tapeta", "boton_1", "boton_2", "boton_3"]),
		], []),
		("RightUpperLeg", [
			("RightLowerLeg", [
				("RightFoot", [], ["bota_puntera_L", "bota_suela_L"]),
			], ["bota_cana_L", "bota_vuelta_L"]),
		], ["pierna_geo_L"]),
		("LeftUpperLeg", [
			("LeftLowerLeg", [
				("LeftFoot", [], ["bota_puntera_R", "bota_suela_R"]),
			], ["bota_cana_R", "bota_vuelta_R"]),
		], ["pierna_geo_R"]),
	], []),
], [])


def mat_mul(a, b):
	out = [0.0] * 16
	for c in range(4):
		for r in range(4):
			out[c * 4 + r] = sum(a[k * 4 + r] * b[c * 4 + k] for k in range(4))
	return out


IDENT = [1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0]


def main():
	raw = open(GLB, "rb").read()
	magic, version, _total = struct.unpack("<III", raw[:12])
	assert magic == 0x46546C67 and version == 2, "no es un GLB v2"
	off, chunks = 12, []
	while off < len(raw):
		clen, ctype = struct.unpack("<II", raw[off:off + 8])
		chunks.append((ctype, raw[off + 8:off + 8 + clen]))
		off += 8 + clen
	gltf = json.loads(chunks[0][1].decode("utf-8"))

	names = [n.get("name") for n in gltf["nodes"]]
	if "Hips" in names:
		print("ya riggeado, no hago nada")
		return 0

	# Matrices de mundo del arbol viejo (los grupos son pura traslacion, pero
	# multiplicamos completo por higiene).
	parent = {}
	for i, n in enumerate(gltf["nodes"]):
		for c in n.get("children", []):
			parent[c] = i

	def world(i):
		m = gltf["nodes"][i].get("matrix", IDENT)
		return m if i not in parent else mat_mul(world(parent[i]), m)

	mesh_nodes = {}
	for i, n in enumerate(gltf["nodes"]):
		if "mesh" in n:
			mesh_nodes[n["name"]] = {"mesh": n["mesh"], "world": world(i)}

	# Emitir el arbol nuevo en profundidad.
	new_nodes = []

	def emit(spec, parent_w):
		name, kids, meshes = spec
		jw = J[name]
		node = {"name": name, "translation": [
			round(jw[0] - parent_w[0], 6),
			round(jw[1] - parent_w[1], 6),
			round(jw[2] - parent_w[2], 6)], "children": []}
		idx = len(new_nodes)
		new_nodes.append(node)
		for mname in meshes:
			src = mesh_nodes.pop(mname)
			m = list(src["world"])
			m[12] = round(m[12] - jw[0], 6)
			m[13] = round(m[13] - jw[1], 6)
			m[14] = round(m[14] - jw[2], 6)
			node["children"].append(len(new_nodes))
			new_nodes.append({"name": mname, "mesh": src["mesh"], "matrix": m})
		for kid in kids:
			node["children"].append(emit(kid, jw))
		return idx

	root_idx = emit(TREE, (0.0, 0.0, 0.0))
	assert not mesh_nodes, "mallas sin colocar: %s" % list(mesh_nodes)

	# Paridad de mundos: el modelo tiene que quedar EXACTAMENTE donde estaba.
	old_worlds = {n["name"]: world(i)[12:15]
		for i, n in enumerate(gltf["nodes"]) if "mesh" in n}
	par2 = {}
	for i, n in enumerate(new_nodes):
		for c in n.get("children", []):
			par2[c] = i

	def world2(i):
		n = new_nodes[i]
		m = n.get("matrix") or (IDENT[:12] + list(n["translation"]) + [1.0])
		return m if i not in par2 else mat_mul(world2(par2[i]), m)

	for i, n in enumerate(new_nodes):
		if "mesh" in n:
			for a, b in zip(world2(i)[12:15], old_worlds[n["name"]]):
				assert abs(a - b) < 1e-5, "%s se movio: %s vs %s" % (n["name"], a, b)

	gltf["nodes"] = new_nodes
	gltf["scenes"] = [{"nodes": [root_idx]}]
	gltf["scene"] = 0

	payload = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
	payload += b" " * (-len(payload) % 4)
	out = b"".join(struct.pack("<II", len(c), t) + c for t, c in
		[(0x4E4F534A, payload)] + [(t, c) for t, c in chunks[1:]])
	blob = struct.pack("<III", 0x46546C67, 2, 12 + len(out)) + out
	open(GLB, "wb").write(blob)
	joints = sum(1 for n in new_nodes if "mesh" not in n)
	print("riggeado: %d nodos (%d articulaciones + %d mallas), mundos identicos"
		% (len(new_nodes), joints, len(new_nodes) - joints))
	return 0


if __name__ == "__main__":
	sys.exit(main())
