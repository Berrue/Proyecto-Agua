"""Construye el APAREJO de Proyecto Agua: anzuelo + cebo (fuente editable + GLB).

La cania ya tenia carrete, anillas y puntera, pero le faltaba lo unico que de
verdad pesca: el hilo y lo que cuelga de el. Sin anzuelo, la primera persona
enseniaba un palo naranja apuntando al cielo -- y el jugador que mira su propia
cania todo el rato no tenia donde leer que lleva cebo puesto.

El TAMANIO es la decision que costo una tarde. La primera version fue un
anzuelo de playa (2,6 cm, alambre de 1,1 mm) y en primera persona era
literalmente INVISIBLE: cuelga a dos metros de la camara, asi que ese alambre
mide 0,4 pixeles y el rasterizador se lo come entero -- medido con
`tests/capture_fishing.tscn`, el anzuelo entero pintaba UN pixel. La solucion no
es hinchar un anzuelo pequenio: es montar el aparejo que este barco pesca de
verdad. Un 8/0 de mar (7 cm de largo, 3 cm de abertura, alambre de 2,6 mm) es lo
que se le pone a un atun o a una aguja azul, y a dos metros son 24 pixeles de
alto y algo mas de un pixel de grosor: se lee sin mentir sobre nada.

El metal es BRONCE y no cromo por lo mismo: contra el cielo blanco del mar gris
un anzuelo cromado se borra y uno bronceado se recorta. Es la misma razon por la
que el cuerpo de la cania es naranja de seguridad.

Convenciones (las mismas que la cania, `tools/build_fishing_rod.py`):

- Blender: el aparejo cuelga a lo largo de `-Z` (la anilla del ojo en el
  origen, la muerte abajo), y la curva abre hacia `+Y`.
- Godot/glTF: `-Z` pasa a `-Y`, o sea que el aparejo cuelga hacia abajo sin
  tocarle la rotacion, y `+Y` pasa a `-Z`.
- El origen (0,0,0) es EL OJO, el punto por donde se ata el sedal: asi el nodo
  se coloca directamente donde acaba el hilo y `fishing_rod.gd` no necesita
  compensar ningun desplazamiento de la malla.

Piezas exportadas (Godot las convierte en nodos con el MISMO nombre, y hay
codigo que las busca por ese nombre):

- `Anzuelo` -> ojo, tija, curva, punta y muerte, en una sola pieza de alambre.
- `Cebo`    -> la bola de cebo clavada en la curva. `FishingRod` la tinta con
               el color del `TipoCebo` montado y la ESCONDE cuando pescas a
               pelo: el aparejo es el sitio honesto donde mirar si llevas cebo,
               porque es el sitio donde el cebo esta de verdad.

Uso desde la raiz del proyecto:

    blender --background --factory-startup --python tools/build_anzuelo.py
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BLEND = REPO_ROOT / "source_assets" / "fishing" / "anzuelo.blend"
DEFAULT_GLB = REPO_ROOT / "game" / "fishing" / "models" / "anzuelo.glb"

# --- El contrato con la escena de Godot -------------------------------------
# `FishingRod.APAREJO_LARGO` cuelga el aparejo a 30 cm de la puntera y el hilo
# muere EN EL OJO, que es el origen de esta malla. Mover el origen despegaria el
# sedal del anzuelo sin que nadie se entere hasta mirar una captura.
EYE_Z = 0.0
# Las medidas de un 8/0 de mar: tija hasta -5,2 cm, curva de 1,5 cm de radio (3
# cm de abertura) y alambre de 2,6 mm. Ver la cabecera: no es un anzuelo
# hinchado, es el numero de anzuelo que pide un pez de 60 kg.
SHANK_END_Z = -0.0520
BEND_RADIUS = 0.0150
WIRE_RADIUS = 0.0026
WIRE_SIDES = 6


def parse_outputs() -> tuple[Path, Path]:
    values = {"--blend-output": DEFAULT_BLEND, "--glb-output": DEFAULT_GLB}
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    index = 0
    while index < len(args):
        key = args[index]
        if key in values and index + 1 < len(args):
            values[key] = Path(args[index + 1]).resolve()
            index += 2
        else:
            index += 1
    return values["--blend-output"], values["--glb-output"]


# =============================================================================
#  Utilidades de modelado
# =============================================================================

def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.materials):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)


def material(name: str, rgba: tuple[float, float, float, float],
             roughness: float, metallic: float = 0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = rgba
    mat.use_nodes = True
    principled = mat.node_tree.nodes.get("Principled BSDF")
    principled.inputs["Base Color"].default_value = rgba
    principled.inputs["Roughness"].default_value = roughness
    principled.inputs["Metallic"].default_value = metallic
    return mat


def make_wire(name: str, points: list[Vector], radii: list[float], mat,
              sides: int = WIRE_SIDES) -> bpy.types.Object:
    """Barre un perfil hexagonal por una polilinea: UNA pieza de alambre.

    Un anzuelo es un alambre doblado, no seis cilindros pegados: hacerlo por
    barrido evita las costuras del codo (donde mas se mira) y sale con la mitad
    de vertices. El perfil se orienta con X fijo como lado -- toda la polilinea
    vive en el plano YZ, asi que X siempre es perpendicular a la tangente y no
    hace falta transporte paralelo ni aparecen retorcimientos.
    """
    bm = bmesh.new()
    loops = []
    for i, point in enumerate(points):
        before = points[max(i - 1, 0)]
        after = points[min(i + 1, len(points) - 1)]
        tangent = (after - before).normalized()
        side = Vector((1.0, 0.0, 0.0))
        up = tangent.cross(side).normalized()
        loop = [
            bm.verts.new(point + radii[i] * (
                math.cos(math.tau * j / sides) * side
                + math.sin(math.tau * j / sides) * up))
            for j in range(sides)
        ]
        loops.append(loop)
    for i in range(len(loops) - 1):
        for j in range(sides):
            k = (j + 1) % sides
            bm.faces.new((loops[i][j], loops[i][k], loops[i + 1][k], loops[i + 1][j]))
    bm.faces.new(tuple(reversed(loops[0])))
    bm.faces.new(tuple(loops[-1]))
    bm.normal_update()

    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def make_torus(name: str, location: tuple[float, float, float], major: float,
               minor: float, mat, rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
               major_segments: int = 8, minor_segments: int = 4) -> bpy.types.Object:
    bpy.ops.mesh.primitive_torus_add(
        major_segments=major_segments, minor_segments=minor_segments,
        major_radius=major, minor_radius=minor,
        location=location, rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    return obj


def make_box_between(name: str, start: tuple[float, float, float],
                     end: tuple[float, float, float], width: float, thickness: float,
                     mat) -> bpy.types.Object:
    a = Vector(start)
    b = Vector(end)
    delta = b - a
    bpy.ops.mesh.primitive_cube_add(location=tuple((a + b) * 0.5))
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = (width, delta.length, thickness)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = delta.to_track_quat("Y", "Z")
    obj.data.materials.append(mat)
    return obj


def make_sphere(name: str, location: tuple[float, float, float],
                dimensions: tuple[float, float, float], mat,
                subdivisions: int = 1) -> bpy.types.Object:
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=0.5,
                                          location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    return obj


def join_objects(name: str, objects: list[bpy.types.Object]) -> bpy.types.Object:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    joined = bpy.context.object
    joined.name = name
    return joined


# =============================================================================
#  Las piezas
# =============================================================================

def bend_points() -> list[Vector]:
    """La curva del anzuelo: media vuelta desde el final de la tija.

    Seis tramos y no tres: el codo es lo unico que distingue un anzuelo de un
    clavo, y con tres se ve el poligono. Mas no cabe a este tamanio.
    """
    center = Vector((0.0, BEND_RADIUS, SHANK_END_Z))
    return [
        center + BEND_RADIUS * Vector((0.0, -math.cos(t), -math.sin(t)))
        for t in [math.tau / 12.0 * i for i in range(1, 7)]
    ]


def build_hook(mats: dict) -> list[bpy.types.Object]:
    export: list[bpy.types.Object] = []

    # --- El alambre: ojo -> tija -> curva -> punta ---------------------------
    # El radio decrece SOLO en los ultimos tres puntos: un anzuelo es alambre de
    # grosor constante que acaba en aguja, no un cono.
    wire_points = [
        Vector((0.0, 0.0, EYE_Z - 0.0050)),
        Vector((0.0, 0.0, EYE_Z - 0.0300)),
        Vector((0.0, 0.0, SHANK_END_Z)),
    ]
    wire_radii = [WIRE_RADIUS] * len(wire_points)
    for point in bend_points():
        wire_points.append(point)
        wire_radii.append(WIRE_RADIUS)
    # La punta sube por dentro (mira hacia el ojo, como todo anzuelo) y afila.
    wire_points += [
        Vector((0.0, 2.0 * BEND_RADIUS - 0.0005, SHANK_END_Z + 0.0125)),
        Vector((0.0, 2.0 * BEND_RADIUS - 0.0015, SHANK_END_Z + 0.0200)),
        Vector((0.0, 2.0 * BEND_RADIUS - 0.0025, SHANK_END_Z + 0.0240)),
    ]
    wire_radii += [WIRE_RADIUS * 0.85, WIRE_RADIUS * 0.45, WIRE_RADIUS * 0.12]
    wire = make_wire("Alambre", wire_points, wire_radii, mats["bronze"])

    parts = [wire]
    # Ojo: la anilla por la que pasa el sedal. Su plano es el del aparejo (eje
    # en Y) para que se lea de perfil, que es como cuelga en primera persona.
    parts.append(make_torus("Ojo", (0.0, 0.0, EYE_Z - 0.0055), 0.0075, 0.0022,
                            mats["bronze"], rotation=(math.pi / 2.0, 0.0, 0.0)))
    # Muerte (la lengueta): lo que impide que el pez se descuelgue. Es un pelo
    # de geometria, pero es LO que dice "anzuelo" y no "gancho".
    parts.append(make_box_between(
        "Muerte",
        (0.0, 2.0 * BEND_RADIUS - 0.0010, SHANK_END_Z + 0.0155),
        (0.0, 2.0 * BEND_RADIUS + 0.0055, SHANK_END_Z + 0.0075),
        0.0040, 0.0040, mats["bronze"]))

    hook = join_objects("Anzuelo", parts)
    hook["role"] = "aparejo_terminal"
    export.append(hook)

    # --- El cebo: la bola clavada en la curva --------------------------------
    # Va aparte porque Godot la enciende, la apaga y la TINTA con el color del
    # `TipoCebo` montado (`FishingRod._pintar_cebo`).
    cebo = make_sphere("Cebo", (0.0, BEND_RADIUS * 0.62, SHANK_END_Z + 0.0040),
                       (0.0310, 0.0340, 0.0370), mats["bait"], subdivisions=2)
    cebo["role"] = "bola_tintada_por_el_cebo"
    export.append(cebo)
    return export


# =============================================================================
#  Validacion y export
# =============================================================================

def validate(objects: list[bpy.types.Object]) -> None:
    names = {obj.name for obj in objects}
    faltan = {"Anzuelo", "Cebo"} - names
    if faltan:
        raise RuntimeError(f"Faltan piezas por exportar: {sorted(faltan)}")

    by_name = {obj.name: obj for obj in objects}
    hook = by_name["Anzuelo"]
    corners = [hook.matrix_world @ Vector(c) for c in hook.bound_box]

    # El ojo tiene que quedar EN el origen: es donde `fishing_rod.gd` ata el
    # sedal. Si la malla se desplaza, el hilo cuelga de la nada.
    top = max(c.z for c in corners)
    if not (EYE_Z <= top <= EYE_Z + 0.012):
        raise RuntimeError(f"El ojo no esta en el origen: la malla acaba en z={top:.4f}")

    # Y el aparejo tiene que caber en lo que cuelga: un 8/0 anda por los 7 cm,
    # asi que pasados los 9 esto ya no es un anzuelo, es un ancla.
    largo = top - min(c.z for c in corners)
    if largo > 0.090:
        raise RuntimeError(f"El anzuelo mide {largo:.4f} m: demasiado")

    # El cebo tapa la curva pero NO la punta: un cebo que se traga el anzuelo
    # entero se ve como una bola colgando de un hilo.
    cebo_corners = [by_name["Cebo"].matrix_world @ Vector(c)
                    for c in by_name["Cebo"].bound_box]
    if max(c.z for c in cebo_corners) > SHANK_END_Z + 0.0240:
        raise RuntimeError("El cebo se come la punta del anzuelo")


def main() -> None:
    blend_output, glb_output = parse_outputs()
    for path in (blend_output, glb_output):
        path.parent.mkdir(parents=True, exist_ok=True)

    reset_scene()
    mats = {
        # Bronce, no cromo: contra el cielo claro del mar un anzuelo cromado se
        # borra. Ademas es el acabado real de la mayoria de anzuelos de fondo.
        "bronze": material("M_Hook_Bronze", (0.330, 0.245, 0.145, 1.0), 0.34, 0.85),
        # El color de fabrica del cebo es el de `TipoCebo.color` por defecto: una
        # bola sin tintar (capturas, tests) tiene que salir igual que la masilla.
        "bait": material("M_Hook_Bait", (0.550, 0.450, 0.300, 1.0), 0.88),
    }
    export_objects = build_hook(mats)
    validate(export_objects)

    bpy.ops.object.select_all(action="DESELECT")
    for obj in export_objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = export_objects[0]
    bpy.ops.export_scene.gltf(
        filepath=str(glb_output),
        export_format="GLB",
        use_selection=True,
        export_apply=False,
        export_extras=True,
        export_cameras=False,
        export_lights=False,
    )
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_output))

    meshes = [obj for obj in export_objects if obj.type == "MESH"]
    vertices = sum(len(obj.data.vertices) for obj in meshes)
    triangles = sum(len(poly.vertices) - 2 for obj in meshes for poly in obj.data.polygons)
    print(f"ANZUELO_OK meshes={len(meshes)} vertices={vertices} triangles={triangles}")
    for obj in meshes:
        print(f"  {obj.name}: verts={len(obj.data.vertices)} mats={len(obj.data.materials)}")
    print(f"BLEND={blend_output}")
    print(f"GLB={glb_output}")


if __name__ == "__main__":
    main()
