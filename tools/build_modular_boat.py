"""Construye la fuente Blender y el GLB del pesquero modular.

El casco jugable ya tiene contratos de fisica en Godot (huella, colisiones y
sondas). Este script solo genera la capa visual, en objetos separados, para que
las iteraciones de arte no cambien silenciosamente la flotabilidad.

Uso desde la raiz del proyecto:

    blender --background --factory-startup --python tools/build_modular_boat.py

Los parametros principales estan agrupados al comienzo del archivo. La fuente
``.blend`` resultante se puede editar a mano; volver a ejecutar el script la
regenera desde cero.
"""

from __future__ import annotations

import math
import os
import sys
from dataclasses import dataclass
from pathlib import Path

import bpy
import bmesh
from mathutils import Euler, Vector


# ---------------------------------------------------------------------------
# Contrato dimensional con game/boat/fishing_boat.tscn.
# Blender: X = babor/estribor, Y+ = proa, Z = arriba.
# Godot tras glTF: X = babor/estribor, -Z = proa, Y = arriba.
# ---------------------------------------------------------------------------
LENGTH = 13.0
BEAM = 5.4
DECK_EDGE_Z = 0.80
DECK_CENTER_Z = 0.86
WATERLINE_Z = -0.23

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BLEND = REPO_ROOT / "source_assets" / "boat" / "modular_fishing_boat.blend"
DEFAULT_GLB = REPO_ROOT / "game" / "boat" / "models" / "modular_fishing_boat.glb"
DEFAULT_PREVIEW = REPO_ROOT / "docs" / "images" / "modular_fishing_boat_preview.png"
DEFAULT_CABIN_PREVIEW = REPO_ROOT / "docs" / "images" / "modular_fishing_boat_cabin.png"


GODOT_SCENE = REPO_ROOT / "game" / "boat" / "fishing_boat.tscn"


def _godot_nodes(scene_text: str) -> list[dict]:
    """Parte un .tscn en bloques de nodo con sus propiedades sueltas."""

    nodes: list[dict] = []
    current: dict | None = None
    for raw_line in scene_text.splitlines():
        line = raw_line.strip()
        if line.startswith("[node "):
            current = {"header": line, "props": {}}
            nodes.append(current)
        elif line.startswith("["):
            current = None
        elif current is not None and "=" in line:
            key, _, value = line.partition("=")
            current["props"][key.strip()] = value.strip()
    return nodes


def _header_field(header: str, field: str) -> str:
    marker = field + '="'
    if marker not in header:
        return ""
    return header.split(marker, 1)[1].split('"', 1)[0]


def _origin_godot(props: dict) -> tuple[float, float, float]:
    """Origen del nodo, venga como ``position`` o dentro de un ``Transform3D``."""

    for key, first in (("position", 0), ("transform", 9)):
        if key in props:
            numbers = props[key].split("(", 1)[1].rstrip(")").split(",")
            # Los tres ultimos valores de un Transform3D son el origen.
            return tuple(float(n) for n in numbers[first:first + 3])
    return (0.0, 0.0, 0.0)


def _to_blender(godot_xyz: tuple[float, float, float]) -> tuple[float, float, float]:
    """Godot (x, arriba, +Z popa) -> Blender (x, +Y proa, +Z arriba)."""

    x, up, z = godot_xyz
    return (x, -z, up)


def read_godot_anchors() -> tuple[dict, dict]:
    """Lee sockets y sondas DEL PROPIO .tscn en vez de copiarlos aqui.

    Las guias existen para modelar contra ellas. Escritas a mano acaban
    mintiendo el dia que alguien mueve un anclaje en Godot: al ensanchar la
    manga los sockets de aparejo se fueron con la borda nueva y su empty se
    quedo medio metro adentro, sobre la cubierta, sin que nada avisara. Godot es
    el dueno de los anclajes (CLAUDE.md: "nunca el mismo numero en dos sitios"),
    asi que aqui solo se leen. Si el parseo falla, revienta: una guia silenciosa
    y equivocada es peor que no generar la fuente.
    """

    nodes = _godot_nodes(GODOT_SCENE.read_text(encoding="utf-8"))
    sockets: dict[str, tuple[float, float, float]] = {}
    probes: dict[str, dict] = {}
    for node in nodes:
        header = node["header"]
        name = _header_field(header, "name")
        parent = _header_field(header, "parent")
        origin = _to_blender(_origin_godot(node["props"]))
        if parent == "UpgradeSockets" and 'type="Marker3D"' in header:
            sockets["SOCKET_" + name] = origin
        elif parent == "." and "2_probe" in node["props"].get("script", ""):
            probes["PROBE_" + name.removeprefix("Probe")] = {
                "location": origin,
                "volume": float(node["props"].get("volume", 1.5)),
                "height": float(node["props"].get("height", 1.4)),
            }

    if len(sockets) != 13 or len(probes) != 8:
        raise RuntimeError(
            "fishing_boat.tscn ya no ofrece 13 sockets y 8 sondas: leidos "
            f"{len(sockets)} y {len(probes)}. Revisa el parseo antes de generar "
            "una fuente con guias equivocadas."
        )
    return sockets, probes


@dataclass(frozen=True)
class Station:
    """Una cuaderna simplificada del casco, de popa a proa."""

    y: float
    half_beam: float
    keel_z: float
    sheer_z: float


# La manga se conserva casi completa en el centro para que seis jugadores
# puedan cruzarse. La entrada de proa se afina tarde; las sondas delanteras se
# acercan a crujia en Godot y aparecen como guias en la fuente Blender.
#
# El casco crecio en dos pasadas de playtest ("ensanchar un poco", y despues
# "un poco mas, de ancho y de largo"): 12,0 x 4,5 -> 12,0 x 5,0 -> 13,0 x 5,4 m.
# Cada pasada ESCALA, no redibuja: la Y por LENGTH/12,0 y la semimanga por
# BEAM/4,5, asi que flare, chines y entrada de proa son los del primer dia, solo
# mas grandes. Lo unico que nunca escala es la roda: es un filo y debe seguir
# siendo un filo. Las alturas (quilla, sheer, cubierta) tampoco se tocan — el
# jugador mide siempre lo mismo —, y masa, centro de masa y sondas se quedan
# donde estaban probadas para que la flotabilidad no cambie en silencio
# (ver docs/BARCO_MODULAR.md).
STATIONS: tuple[Station, ...] = (
    Station(-6.50, 2.18, -0.92, 0.82),
    Station(-5.80, 2.49, -1.04, 0.81),
    Station(-4.60, 2.67, -1.10, 0.80),
    Station(-2.71, 2.70, -1.14, 0.79),
    Station(-0.54, 2.70, -1.16, 0.79),
    Station(1.63, 2.64, -1.13, 0.82),
    Station(3.36, 2.42, -1.02, 0.91),
    Station(4.71, 1.94, -0.78, 1.05),
    Station(5.69, 1.10, -0.42, 1.23),
    Station(6.26, 0.33, -0.02, 1.38),
    Station(6.50, 0.055, 0.30, 1.45),
)


def parse_outputs() -> tuple[Path, Path, Path, Path]:
    """Admite overrides simples despues de ``--`` sin depender de argparse."""

    values = {
        "--blend-output": DEFAULT_BLEND,
        "--glb-output": DEFAULT_GLB,
        "--preview-output": DEFAULT_PREVIEW,
        "--cabin-preview-output": DEFAULT_CABIN_PREVIEW,
    }
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    index = 0
    while index < len(args):
        key = args[index]
        if key in values and index + 1 < len(args):
            values[key] = Path(args[index + 1]).resolve()
            index += 2
        else:
            index += 1
    return (
        values["--blend-output"],
        values["--glb-output"],
        values["--preview-output"],
        values["--cabin-preview-output"],
    )


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in list(bpy.data.collections):
        if collection.name != "Collection":
            bpy.data.collections.remove(collection)
    root = bpy.context.scene.collection.children.get("Collection")
    if root is not None:
        root.name = "EXPORT"


def material(name: str, rgba: tuple[float, float, float, float], roughness: float, metallic: float = 0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = rgba
    mat.use_nodes = True
    principled = mat.node_tree.nodes.get("Principled BSDF")
    principled.inputs["Base Color"].default_value = rgba
    principled.inputs["Roughness"].default_value = roughness
    principled.inputs["Metallic"].default_value = metallic
    principled.inputs["Alpha"].default_value = rgba[3]
    if rgba[3] < 1.0:
        # Blender 4.2+ reemplazo ``blend_method`` por
        # ``surface_render_method``. La rama antigua conserva el generador
        # utilizable si se abre la fuente con otra version.
        if hasattr(mat, "surface_render_method"):
            mat.surface_render_method = "DITHERED"
        elif hasattr(mat, "blend_method"):
            mat.blend_method = "BLEND"
    return mat


def recalculate_normals(mesh: bpy.types.Mesh) -> None:
    editable = bmesh.new()
    editable.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(editable, faces=editable.faces)
    editable.to_mesh(mesh)
    editable.free()


def mesh_object(
    name: str,
    vertices: list[tuple[float, float, float]],
    faces: list[tuple[int, ...]],
    materials: list[bpy.types.Material],
    material_indices: list[int] | None = None,
    smooth: bool = False,
) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    recalculate_normals(mesh)
    mesh.use_mirror_x = True
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.children["EXPORT"].objects.link(obj)
    for mat in materials:
        mesh.materials.append(mat)
    for index, polygon in enumerate(mesh.polygons):
        polygon.use_smooth = smooth
        if material_indices is not None and index < len(material_indices):
            polygon.material_index = material_indices[index]
    return obj


def make_box(
    name: str,
    location: tuple[float, float, float],
    scale: tuple[float, float, float],
    mat: bpy.types.Material,
    bevel: float = 0.0,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    if bevel > 0.0:
        modifier = obj.modifiers.new("Bordes suaves", "BEVEL")
        modifier.width = bevel
        modifier.segments = 2
    return obj


def make_combined_boxes(
    name: str,
    boxes: list[
        tuple[
            tuple[float, float, float],
            tuple[float, float, float],
            tuple[float, float, float],
        ]
    ],
    mat: bpy.types.Material,
    bevel: float = 0.0,
) -> bpy.types.Object:
    """Agrupa paneles desconectados en una unica malla modular.

    Cada pieza conserva volumen y caras interiores; por eso la caseta se lee
    bien desde ambos lados sin depender de materiales double-sided. La lista
    usa ``(centro, dimensiones, rotacion XYZ)`` en coordenadas Blender.
    """

    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[int, ...]] = []
    cube_faces = (
        (0, 4, 6, 2),
        (1, 3, 7, 5),
        (0, 1, 5, 4),
        (2, 6, 7, 3),
        (0, 2, 3, 1),
        (4, 5, 7, 6),
    )
    for location, dimensions, rotation_xyz in boxes:
        base = len(vertices)
        rotation = Euler(rotation_xyz, "XYZ").to_matrix()
        center = Vector(location)
        half = Vector(dimensions) * 0.5
        for x_sign, y_sign, z_sign in (
            (-1.0, -1.0, -1.0),
            (-1.0, -1.0, 1.0),
            (-1.0, 1.0, -1.0),
            (-1.0, 1.0, 1.0),
            (1.0, -1.0, -1.0),
            (1.0, -1.0, 1.0),
            (1.0, 1.0, -1.0),
            (1.0, 1.0, 1.0),
        ):
            point = rotation @ Vector((half.x * x_sign, half.y * y_sign, half.z * z_sign))
            point += center
            vertices.append(point[:])
        faces.extend(tuple(base + index for index in face) for face in cube_faces)

    obj = mesh_object(name, vertices, faces, [mat], smooth=False)
    if bevel > 0.0:
        modifier = obj.modifiers.new("Bordes suaves", "BEVEL")
        modifier.width = bevel
        modifier.segments = 2
    return obj


def make_cylinder(
    name: str,
    location: tuple[float, float, float],
    radius: float,
    depth: float,
    mat: bpy.types.Material,
    vertices: int = 12,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    return obj


def half_beam_at(y: float) -> float:
    for left, right in zip(STATIONS, STATIONS[1:]):
        if left.y <= y <= right.y:
            t = (y - left.y) / (right.y - left.y)
            return left.half_beam + (right.half_beam - left.half_beam) * t
    return STATIONS[0].half_beam if y < STATIONS[0].y else STATIONS[-1].half_beam


def build_hull(hull_paint, antifouling) -> bpy.types.Object:
    vertices: list[tuple[float, float, float]] = []
    # Solo se modela estribor. Mirror conserva una fuente realmente editable y
    # el exportador GLB recibe el resultado evaluado completo.
    points_per_station = 4
    for station in STATIONS:
        # La cubierta jugable es plana a 0,80 m. La elevacion de proa pertenece
        # a la borda; si el casco sube por encima, atraviesa la cubierta como
        # triangulos rojos visibles desde dentro.
        shell_sheer_z = DECK_EDGE_Z
        depth = shell_sheer_z - station.keel_z
        lower_z = station.keel_z + depth * 0.34
        upper_z = station.keel_z + depth * 0.67
        hb = station.half_beam
        vertices.extend(
            [
                (0.0, station.y, station.keel_z),
                (hb * 0.60, station.y, lower_z),
                (hb * 0.94, station.y, upper_z),
                (hb, station.y, shell_sheer_z),
            ]
        )

    faces: list[tuple[int, ...]] = []
    indices: list[int] = []
    for ring in range(len(STATIONS) - 1):
        for cross in range(points_per_station - 1):
            a = ring * points_per_station + cross
            b = (ring + 1) * points_per_station + cross
            face = (a, b, b + 1, a + 1)
            faces.append(face)
            avg_z = sum(vertices[i][2] for i in face) / 4.0
            indices.append(1 if avg_z < WATERLINE_Z else 0)

    # La popa se cierra con un Transom modular separado. En la proa, cada media
    # tapa necesita quilla y sheer sobre crujia; sin el punto superior, Mirror
    # deja un hueco en V.
    bow_center_top = len(vertices)
    vertices.append((0.0, STATIONS[-1].y, DECK_EDGE_Z))

    # La tapa de roda hace legible la silueta sin convertirse en colision.
    offset = (len(STATIONS) - 1) * points_per_station
    faces.append((*[offset + i for i in range(points_per_station)], bow_center_top))
    indices.append(0)

    # El casco es de doble pantoque: el flat shading deja leer quilla, chines y
    # flare. Suavizar toda la jaula borra esos planos y pinza la roda.
    obj = mesh_object("HullShell", vertices, faces, [hull_paint, antifouling], indices, smooth=False)
    mirror = obj.modifiers.new("Simetria editable", "MIRROR")
    mirror.use_axis[0] = True
    mirror.use_clip = True
    mirror.use_mirror_merge = True
    mirror.merge_threshold = 0.001
    obj["role"] = "visual_hull"
    obj["waterline_local_z"] = WATERLINE_Z
    return obj


def build_transom(hull_paint, antifouling) -> bpy.types.Object:
    """Cierra la popa como modulo reemplazable y respeta la linea de agua."""

    station = STATIONS[0]
    depth = station.sheer_z - station.keel_z
    lower_z = station.keel_z + depth * 0.34
    upper_z = station.keel_z + depth * 0.67
    x_lower = station.half_beam * 0.60
    x_upper = station.half_beam * 0.94
    water_t = (WATERLINE_Z - lower_z) / (upper_z - lower_z)
    x_water = x_lower + (x_upper - x_lower) * water_t
    y = station.y

    vertices = [
        (0.0, y, station.keel_z),
        (-x_lower, y, lower_z),
        (-x_water, y, WATERLINE_Z),
        (-x_upper, y, upper_z),
        (-station.half_beam, y, station.sheer_z),
        (0.0, y, station.sheer_z),
        (station.half_beam, y, station.sheer_z),
        (x_upper, y, upper_z),
        (x_water, y, WATERLINE_Z),
        (x_lower, y, lower_z),
        (0.0, y, WATERLINE_Z),
    ]
    faces = [
        (0, 1, 2, 10),
        (0, 10, 8, 9),
        (10, 2, 3, 4, 5),
        (10, 5, 6, 7, 8),
    ]
    obj = mesh_object(
        "Transom",
        vertices,
        faces,
        [hull_paint, antifouling],
        [1, 1, 0, 0],
        smooth=False,
    )
    obj["role"] = "replaceable_transom"
    return obj


def deck_station_values() -> list[tuple[float, float]]:
    ys = [-6.42, -4.60, -2.71, -0.54, 1.63, 3.36, 4.71, 5.69, 6.09, 6.50]
    values: list[tuple[float, float]] = []
    for y in ys:
        # Cerca de las tapas de proa y popa la cubierta llega casi al costado;
        # en el resto se retira para dejar sitio a la borda.
        inset = 0.03 if abs(y) > 6.07 else 0.18
        values.append((y, max(0.04, half_beam_at(y) - inset)))
    return values


def build_deck(deck_mat) -> bpy.types.Object:
    stations = deck_station_values()
    vertices: list[tuple[float, float, float]] = []
    for y, hb in stations:
        vertices.extend([(-hb, y, DECK_EDGE_Z), (0.0, y, DECK_CENTER_Z), (hb, y, DECK_EDGE_Z)])
    faces: list[tuple[int, ...]] = []
    for ring in range(len(stations) - 1):
        a = ring * 3
        b = (ring + 1) * 3
        faces.extend([(a, b, b + 1, a + 1), (a + 1, b + 1, b + 2, a + 2)])
    return mesh_object("WorkingDeck", vertices, faces, [deck_mat], smooth=False)


def deck_half_beam_at(y: float) -> float:
    stations = deck_station_values()
    for left, right in zip(stations, stations[1:]):
        if left[0] <= y <= right[0]:
            t = (y - left[0]) / (right[0] - left[0])
            return left[1] + (right[1] - left[1]) * t
    return stations[0][1] if y < stations[0][0] else stations[-1][1]


def deck_surface_z(x: float, y: float) -> float:
    half_beam = max(0.04, deck_half_beam_at(y))
    camber = min(1.0, abs(x) / half_beam)
    return DECK_CENTER_Z + (DECK_EDGE_Z - DECK_CENTER_Z) * camber


def build_deck_plank_seams(seam_mat) -> bpy.types.Object:
    """Dibuja juntas de tablas sobre la cubierta sin convertirla en 100 nodos.

    El color base ya es madera. Esta segunda malla, apenas elevada, da lectura
    de tablas longitudinales y empalmes alternados tanto afuera como dentro de
    la cabina. Sigue siendo una unica pieza editable en Blender/Godot.
    """

    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[int, ...]] = []
    overlay = 0.012

    def add_quad(x0: float, x1: float, y0: float, y1: float) -> None:
        base = len(vertices)
        vertices.extend(
            [
                (x0, y0, deck_surface_z(x0, y0) + overlay),
                (x1, y0, deck_surface_z(x1, y0) + overlay),
                (x1, y1, deck_surface_z(x1, y1) + overlay),
                (x0, y1, deck_surface_z(x0, y1) + overlay),
            ]
        )
        faces.append((base, base + 1, base + 2, base + 3))

    stations = deck_station_values()
    seam_width = 0.018
    # Tablas de unos 28 cm, alineadas con la eslora.
    for seam_index in range(-9, 10):
        x = seam_index * 0.28
        for (y0, hb0), (y1, hb1) in zip(stations, stations[1:]):
            if abs(x) + seam_width < min(hb0, hb1):
                add_quad(x - seam_width * 0.5, x + seam_width * 0.5, y0, y1)

    # Empalmes cortos y alternados: rompen la grilla perfecta y hacen que el
    # piso se lea como tablas largas incluso sin una textura externa.
    plank_width = 0.28
    joint_depth = 0.018
    for plank_index in range(-9, 9):
        x0 = plank_index * plank_width + seam_width
        x1 = (plank_index + 1) * plank_width - seam_width
        offset = (plank_index % 3) * 0.55
        y = -5.69 + offset
        while y < 5.90:
            if max(abs(x0), abs(x1)) + 0.03 < deck_half_beam_at(y):
                add_quad(x0, x1, y - joint_depth * 0.5, y + joint_depth * 0.5)
            y += 1.65

    seams = mesh_object("DeckPlankSeams", vertices, faces, [seam_mat], smooth=False)
    seams["role"] = "wood_plank_joints"
    seams["plank_width_m"] = plank_width
    return seams


def build_side_bulwark(name: str, side: float, bulwark_mat) -> bpy.types.Object:
    stations = deck_station_values()
    vertices: list[tuple[float, float, float]] = []
    thickness = 0.18
    for y, hb in stations:
        # El borde exterior solapa el sheer del casco: no puede quedar una
        # ranura visible entre HullShell y la borda al mirar desde el agua.
        outer_x = side * (hb + thickness)
        inner_x = side * hb
        bow_rise = max(0.0, (y - 3.25) / 2.82) * 0.28
        top = DECK_EDGE_Z + 0.82 + bow_rise
        vertices.extend(
            [
                (inner_x, y, DECK_EDGE_Z),
                (outer_x, y, DECK_EDGE_Z - 0.03),
                (outer_x, y, top),
                (inner_x, y, top - thickness * 0.20),
            ]
        )
    faces: list[tuple[int, ...]] = []
    for ring in range(len(stations) - 1):
        a = ring * 4
        b = (ring + 1) * 4
        for edge in range(4):
            faces.append((a + edge, b + edge, b + ((edge + 1) % 4), a + ((edge + 1) % 4)))
    faces.append((3, 2, 1, 0))
    last = (len(stations) - 1) * 4
    faces.append((last, last + 1, last + 2, last + 3))
    return mesh_object(name, vertices, faces, [bulwark_mat], smooth=False)


def build_cabin(cabin_mat, roof_mat, glass_mat, trim_mat, wood_mat, metal_mat) -> list[bpy.types.Object]:
    """Caseta transitable: cuatro frames con huecos reales y puesto de mando."""

    x_side = 1.05
    y_front = -2.30
    y_rear = -4.65
    z_floor = 0.82
    z_sill = 1.62
    z_window_top = 2.72
    z_wall_top = 2.98
    wall_thickness = 0.14
    wall_height = z_wall_top - z_floor
    lower_height = z_sill - z_floor
    window_height = z_window_top - z_sill
    header_height = z_wall_top - z_window_top
    wall_center_z = (z_floor + z_wall_top) * 0.5
    window_center_z = (z_sill + z_window_top) * 0.5

    front = make_combined_boxes(
        "WheelhouseFrontFrame",
        [
            ((0.0, y_front, (z_floor + z_sill) * 0.5), (2.10, wall_thickness, lower_height), (0.0, 0.0, 0.0)),
            ((0.0, y_front, (z_window_top + z_wall_top) * 0.5), (2.10, wall_thickness, header_height), (0.0, 0.0, 0.0)),
            ((-0.985, y_front, window_center_z), (0.13, wall_thickness, window_height), (0.0, 0.0, 0.0)),
            ((0.0, y_front, window_center_z), (0.09, wall_thickness, window_height), (0.0, 0.0, 0.0)),
            ((0.985, y_front, window_center_z), (0.13, wall_thickness, window_height), (0.0, 0.0, 0.0)),
        ],
        cabin_mat,
        bevel=0.018,
    )

    side_objects: list[bpy.types.Object] = []
    cabin_length = y_front - y_rear
    for side, suffix in ((-1.0, "Port"), (1.0, "Starboard")):
        side_objects.append(
            make_combined_boxes(
                f"Wheelhouse{suffix}Frame",
                [
                    ((side * x_side, (y_front + y_rear) * 0.5, (z_floor + z_sill) * 0.5), (wall_thickness, cabin_length, lower_height), (0.0, 0.0, 0.0)),
                    ((side * x_side, (y_front + y_rear) * 0.5, (z_window_top + z_wall_top) * 0.5), (wall_thickness, cabin_length, header_height), (0.0, 0.0, 0.0)),
                    ((side * x_side, y_front - 0.065, window_center_z), (wall_thickness, 0.13, window_height), (0.0, 0.0, 0.0)),
                    ((side * x_side, (y_front + y_rear) * 0.5, window_center_z), (wall_thickness, 0.10, window_height), (0.0, 0.0, 0.0)),
                    ((side * x_side, y_rear + 0.065, window_center_z), (wall_thickness, 0.13, window_height), (0.0, 0.0, 0.0)),
                ],
                cabin_mat,
                bevel=0.018,
            )
        )

    # Dos jambas de 55 cm y un dintel dejan una entrada centrada de 1 x 2 m.
    rear = make_combined_boxes(
        "WheelhouseRearFrame",
        [
            ((-0.775, y_rear, wall_center_z), (0.55, wall_thickness, wall_height), (0.0, 0.0, 0.0)),
            ((0.775, y_rear, wall_center_z), (0.55, wall_thickness, wall_height), (0.0, 0.0, 0.0)),
            ((0.0, y_rear, 2.90), (1.00, wall_thickness, 0.16), (0.0, 0.0, 0.0)),
        ],
        cabin_mat,
        bevel=0.018,
    )
    roof = make_box("WheelhouseRoof", (0.0, (y_front + y_rear) * 0.5, 3.07), (2.42, 2.65, 0.18), roof_mat, bevel=0.07)

    windows: list[bpy.types.Object] = []
    for x in (-0.515, 0.515):
        windows.append(
            make_box(
                "FrontWindowPort" if x < 0 else "FrontWindowStarboard",
                (x, y_front + 0.082, window_center_z),
                (0.88, 0.025, 1.03),
                glass_mat,
                bevel=0.025,
            )
        )
    for side, suffix in ((-1.0, "Port"), (1.0, "Starboard")):
        for y, number in ((-2.89, "Forward"), (-4.06, "Aft")):
            windows.append(
                make_box(
                    f"SideWindow{suffix}{number}",
                    (side * 1.122, y, window_center_z),
                    (0.025, 1.02, 1.03),
                    glass_mat,
                    bevel=0.025,
                )
            )

    # Hoja corrediza recogida contra estribor. Es visual y no ocupa el vano.
    door = make_box("WheelhouseDoorOpen", (0.96, -4.08, 1.82), (0.055, 0.96, 1.96), trim_mat, bevel=0.028)
    door["role"] = "open_sliding_door_no_collision"

    console = make_combined_boxes(
        "HelmConsole",
        [
            ((0.0, -2.68, 1.15), (1.72, 0.48, 0.62), (0.0, 0.0, 0.0)),
            ((0.0, -2.82, 1.51), (1.72, 0.30, 0.18), (math.radians(-10.0), 0.0, 0.0)),
        ],
        cabin_mat,
        bevel=0.035,
    )
    instrument_panel = make_box("InstrumentPanel", (0.0, -3.005, 1.61), (1.48, 0.045, 0.30), trim_mat, bevel=0.025)
    sonar = make_box("SonarDisplay", (-0.48, -3.034, 1.63), (0.36, 0.025, 0.21), glass_mat, bevel=0.018)

    # Aro + radios unidos mantienen el origen justo en el eje: en Godot se
    # podra animar el objeto HelmWheel sin reconstruir el asset.
    wheel_center = (0.25, -3.085, 1.76)
    bpy.ops.mesh.primitive_torus_add(
        major_radius=0.285,
        minor_radius=0.035,
        major_segments=20,
        minor_segments=6,
        location=wheel_center,
        rotation=(math.radians(90.0), 0.0, 0.0),
    )
    wheel = bpy.context.object
    wheel.name = "HelmWheel"
    wheel.data.materials.append(wood_mat)
    bpy.context.view_layer.objects.active = wheel
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    spokes = make_combined_boxes(
        "HelmWheelSpokesTemporary",
        [
            (wheel_center, (0.54, 0.045, 0.045), (0.0, angle, 0.0))
            for angle in (0.0, math.radians(60.0), math.radians(120.0))
        ],
        wood_mat,
        bevel=0.012,
    )
    bpy.ops.object.select_all(action="DESELECT")
    wheel.select_set(True)
    spokes.select_set(True)
    bpy.context.view_layer.objects.active = wheel
    bpy.ops.object.join()
    wheel.name = "HelmWheel"
    wheel["role"] = "animated_helm_with_centered_origin"

    hub = make_cylinder("HelmHub", wheel_center, 0.085, 0.16, metal_mat, vertices=16)
    hub.rotation_euler.x = math.radians(90.0)
    telegraph_base = make_cylinder("EngineTelegraph", (0.72, -2.99, 1.70), 0.075, 0.16, metal_mat, vertices=12)
    telegraph_base.rotation_euler.x = math.radians(90.0)
    telegraph_lever = make_box("EngineTelegraphLever", (0.72, -3.08, 1.83), (0.045, 0.045, 0.27), metal_mat, bevel=0.012)

    return [
        front,
        *side_objects,
        rear,
        roof,
        door,
        *windows,
        console,
        instrument_panel,
        sonar,
        wheel,
        hub,
        telegraph_base,
        telegraph_lever,
    ]


def build_hatches(deck_trim_mat) -> list[bpy.types.Object]:
    forward = make_box("HatchHoldForward", (0.0, 2.65, 0.94), (1.55, 1.75, 0.18), deck_trim_mat, bevel=0.05)
    aft = make_box("HatchHoldAft", (0.0, 0.10, 0.94), (1.70, 1.65, 0.18), deck_trim_mat, bevel=0.05)
    engine = make_box("HatchEngine", (0.0, -1.55, 0.93), (1.45, 1.05, 0.16), deck_trim_mat, bevel=0.045)
    return [forward, aft, engine]


def build_trim(trim_mat, metal_mat) -> list[bpy.types.Object]:
    pieces: list[bpy.types.Object] = []
    # Defensas longitudinales segmentadas: siguen la tangente de la manga en
    # vez de atravesar la curva de proa con cajas paralelas al eje.
    spans = [(-5.69, -4.01), (-3.85, -2.06), (-1.90, -0.11), (0.05, 1.90), (2.06, 3.52), (3.66, 4.60)]
    for side, suffix in ((-1.0, "Port"), (1.0, "Starboard")):
        for index, (y0, y1) in enumerate(spans):
            x0 = side * (half_beam_at(y0) + 0.13)
            x1 = side * (half_beam_at(y1) + 0.13)
            dx = x1 - x0
            dy = y1 - y0
            length = math.sqrt(dx * dx + dy * dy)
            center_y = (y0 + y1) * 0.5
            piece = make_box(
                f"RubRail{suffix}_{index + 1:02d}",
                ((x0 + x1) * 0.5, center_y, 0.72 + max(0.0, center_y - 3.25) * 0.07),
                (0.14, length, 0.16),
                trim_mat,
                bevel=0.045,
            )
            # RotZ transforma el eje Y local en la tangente del costado.
            piece.rotation_euler.z = math.atan2(-dx, dy)
            pieces.append(piece)

    mast_foot = make_cylinder("MastFoot", (0.0, -2.05, 1.08), 0.18, 0.42, metal_mat, vertices=12)
    pieces.append(mast_foot)
    return pieces


def add_socket_guides(sockets: dict) -> bpy.types.Collection:
    guides = bpy.data.collections.new("SOCKET_GUIDES_NOT_EXPORTED")
    bpy.context.scene.collection.children.link(guides)
    for name, location in sockets.items():
        guide = bpy.data.objects.new(name, None)
        guide.empty_display_type = "ARROWS"
        guide.empty_display_size = 0.32
        guide.location = location
        guides.objects.link(guide)
    guides.hide_render = True
    return guides


def add_buoyancy_guides(probes: dict) -> bpy.types.Collection:
    """Replica en Blender las posiciones nativas de las sondas de Godot.

    No se exportan. Son un gate visual: si una futura edicion deja una esfera
    fuera del volumen sumergido, hay que corregir la malla o volver a validar
    la fisica, nunca ocultar la contradiccion. Por eso mismo se LEEN del .tscn:
    una guia copiada a mano solo es fiable hasta el primer cambio en Godot.
    """

    guides = bpy.data.collections.new("BUOYANCY_GUIDES_NOT_EXPORTED")
    bpy.context.scene.collection.children.link(guides)
    for name, probe in probes.items():
        guide = bpy.data.objects.new(name, None)
        guide.empty_display_type = "SPHERE"
        guide.empty_display_size = 0.22
        guide.location = probe["location"]
        guide["godot_volume_m3"] = probe["volume"]
        guide["godot_height_m"] = probe["height"]
        guides.objects.link(guide)
    guides.hide_render = True
    return guides


def add_preview_scene(water_mat) -> tuple[bpy.types.Object, bpy.types.Object]:
    preview = bpy.data.collections.new("PREVIEW_NOT_EXPORTED")
    bpy.context.scene.collection.children.link(preview)

    bpy.ops.mesh.primitive_plane_add(size=80.0, location=(0.0, 0.0, WATERLINE_Z))
    water = bpy.context.object
    water.name = "PreviewWater"
    water.data.materials.append(water_mat)
    for collection in list(water.users_collection):
        collection.objects.unlink(water)
    preview.objects.link(water)

    bpy.ops.object.camera_add(location=(11.8, 14.5, 8.2))
    camera = bpy.context.object
    camera.name = "PreviewCamera"
    camera.data.lens = 52.0
    for collection in list(camera.users_collection):
        collection.objects.unlink(camera)
    preview.objects.link(camera)
    look_at(camera, Vector((0.0, 0.3, 0.85)))

    bpy.ops.object.light_add(type="AREA", location=(4.0, 3.0, 12.0))
    key = bpy.context.object
    key.name = "PreviewKey"
    key.data.energy = 1800.0
    key.data.shape = "DISK"
    key.data.size = 7.0
    for collection in list(key.users_collection):
        collection.objects.unlink(key)
    preview.objects.link(key)
    look_at(key, Vector((0.0, 0.0, 0.0)))

    bpy.ops.object.light_add(type="AREA", location=(-8.0, -8.0, 6.0))
    fill = bpy.context.object
    fill.name = "PreviewFill"
    fill.data.energy = 950.0
    fill.data.color = (0.42, 0.62, 1.0)
    fill.data.size = 6.0
    for collection in list(fill.users_collection):
        collection.objects.unlink(fill)
    preview.objects.link(fill)
    look_at(fill, Vector((0.0, 0.0, 0.8)))

    bpy.ops.object.light_add(type="AREA", location=(0.0, -3.75, 2.72))
    cabin_fill = bpy.context.object
    cabin_fill.name = "PreviewCabinFill"
    cabin_fill.data.energy = 420.0
    cabin_fill.data.color = (1.0, 0.72, 0.46)
    cabin_fill.data.size = 1.35
    for collection in list(cabin_fill.users_collection):
        collection.objects.unlink(cabin_fill)
    preview.objects.link(cabin_fill)
    look_at(cabin_fill, Vector((0.0, -3.35, 1.45)))

    return camera, water


def look_at(obj: bpy.types.Object, target: Vector) -> None:
    direction = target - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def configure_scene(root: bpy.types.Object) -> None:
    root["length_m"] = LENGTH
    root["beam_m"] = BEAM
    root["deck_height_m"] = DECK_EDGE_Z
    root["godot_bow_axis"] = "-Z"
    root["source_bow_axis"] = "+Y"
    root["physics_note"] = "Visual only; Godot owns colliders and buoyancy probes"
    for child in list(bpy.context.scene.collection.children["EXPORT"].objects):
        if child != root:
            child.parent = root


def save_and_export(blend_path: Path, glb_path: Path, preview_path: Path, cabin_preview_path: Path) -> None:
    blend_path.parent.mkdir(parents=True, exist_ok=True)
    glb_path.parent.mkdir(parents=True, exist_ok=True)
    preview_path.parent.mkdir(parents=True, exist_ok=True)
    cabin_preview_path.parent.mkdir(parents=True, exist_ok=True)

    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))

    bpy.ops.object.select_all(action="DESELECT")
    export_collection = bpy.context.scene.collection.children["EXPORT"]
    for obj in export_collection.all_objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = bpy.data.objects.get("ModularFishingBoat")
    bpy.ops.export_scene.gltf(
        filepath=str(glb_path),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_cameras=False,
        export_lights=False,
        export_extras=True,
        export_yup=True,
    )

    scene = bpy.context.scene
    scene.camera = bpy.data.objects["PreviewCamera"]
    # Blender 5.1 vuelve a exponer Eevee como ``BLENDER_EEVEE`` en la API.
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1200
    scene.render.resolution_y = 760
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(preview_path)
    scene.render.film_transparent = False
    scene.world.color = (0.025, 0.045, 0.075)
    scene.view_settings.look = "AgX - Medium High Contrast"
    # La primera escritura ocurre antes del export por seguridad; esta segunda
    # conserva cámara y preset de render dentro de la fuente editable.
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
    bpy.ops.render.render(write_still=True)

    # Segunda prueba visual: desde el pasillo de popa, atravesando la abertura
    # real. Si el generador vuelve a cerrar la caseta, esta toma lo delata.
    camera = bpy.data.objects["PreviewCamera"]
    camera.location = (0.0, -5.38, 1.90)
    camera.data.lens = 39.0
    look_at(camera, Vector((0.08, -2.78, 1.68)))
    scene.render.resolution_x = 1000
    scene.render.resolution_y = 760
    scene.render.filepath = str(cabin_preview_path)
    bpy.ops.render.render(write_still=True)

    export_objects = [obj for obj in export_collection.all_objects if obj.type == "MESH"]
    vertices = sum(len(obj.data.vertices) for obj in export_objects)
    triangles = sum(len(poly.vertices) - 2 for obj in export_objects for poly in obj.data.polygons)
    print(f"BOAT_BUILD_OK objects={len(export_objects)} vertices={vertices} triangles_base={triangles}")
    print(f"BLEND={blend_path}")
    print(f"GLB={glb_path}")
    print(f"PREVIEW={preview_path}")
    print(f"CABIN_PREVIEW={cabin_preview_path}")


def main() -> None:
    blend_path, glb_path, preview_path, cabin_preview_path = parse_outputs()
    reset_scene()

    hull_paint = material("M_HullPaint_Red", (0.66, 0.13, 0.085, 1.0), 0.58)
    antifouling = material("M_Antifouling_Dark", (0.035, 0.055, 0.065, 1.0), 0.72)
    deck_mat = material("M_DeckWood_Oak", (0.31, 0.145, 0.052, 1.0), 0.86)
    deck_seam_mat = material("M_DeckWood_Seams", (0.055, 0.022, 0.010, 1.0), 0.92)
    helm_wood_mat = material("M_HelmWood_Varnished", (0.40, 0.16, 0.045, 1.0), 0.58)
    bulwark_mat = material("M_Bulwark_Cream", (0.76, 0.73, 0.61, 1.0), 0.68)
    cabin_mat = material("M_Wheelhouse_Cream", (0.82, 0.79, 0.66, 1.0), 0.61)
    roof_mat = material("M_Roof_Red", (0.43, 0.07, 0.045, 1.0), 0.67)
    glass_mat = material("M_Glass_SmokedBlue", (0.035, 0.115, 0.16, 0.42), 0.22, metallic=0.08)
    trim_mat = material("M_Trim_Dark", (0.045, 0.052, 0.050, 1.0), 0.73)
    metal_mat = material("M_Metal_Galvanized", (0.33, 0.37, 0.38, 1.0), 0.46, metallic=0.72)
    water_mat = material("M_PreviewWater", (0.025, 0.18, 0.27, 1.0), 0.26, metallic=0.15)

    root = bpy.data.objects.new("ModularFishingBoat", None)
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 1.0
    bpy.context.scene.collection.children["EXPORT"].objects.link(root)

    build_hull(hull_paint, antifouling)
    build_transom(hull_paint, antifouling)
    build_deck(deck_mat)
    build_deck_plank_seams(deck_seam_mat)
    build_side_bulwark("BulwarkPort", -1.0, bulwark_mat)
    build_side_bulwark("BulwarkStarboard", 1.0, bulwark_mat)
    # El ancho del espejo se DERIVA de la cubierta: es la manga exterior de la
    # borda en su cuaderna. Escrito a mano se queda corto en cuanto cambia la
    # manga y deja ver la tapa de popa por los costados.
    stern_y = -6.40
    stern_width = 2.0 * (deck_half_beam_at(stern_y) + 0.18)
    make_box("BulwarkStern", (0.0, stern_y, 1.20), (stern_width, 0.16, 0.78), bulwark_mat, bevel=0.035)
    make_box("BulwarkBow", (0.0, 6.45, 1.37), (0.14, 0.10, 1.18), bulwark_mat, bevel=0.015)
    build_cabin(cabin_mat, roof_mat, glass_mat, trim_mat, helm_wood_mat, metal_mat)
    build_hatches(trim_mat)
    build_trim(trim_mat, metal_mat)
    sockets, probes = read_godot_anchors()
    add_socket_guides(sockets)
    add_buoyancy_guides(probes)
    add_preview_scene(water_mat)
    configure_scene(root)
    save_and_export(blend_path, glb_path, preview_path, cabin_preview_path)


if __name__ == "__main__":
    main()
