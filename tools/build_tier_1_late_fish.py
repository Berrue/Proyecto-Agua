"""Construye Boqueron, Faneca y Sargo como tanda de aprobacion.

Estos tres peces completan el tier 1, pero no se escriben en ``game/``: los GLB
quedan bajo ``source_assets/`` hasta que el usuario apruebe las siluetas. Reusa
el vocabulario geometrico de los peces comunes, incluida la raiz facetada y
hundida de las aletas pectorales.

Uso desde la raiz del proyecto:

    blender --background --factory-startup --python-exit-code 1 \
        --python tools/build_tier_1_late_fish.py
"""

from __future__ import annotations

import json
import math
import struct
import sys
from pathlib import Path

import bpy
from mathutils import Vector


TOOLS_DIR = Path(__file__).resolve().parent
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

import build_common_fish as common


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BLEND = REPO_ROOT / "source_assets" / "fish" / "tier_1_late" / "tier_1_late_fish.blend"
DEFAULT_GLB_DIR = REPO_ROOT / "source_assets" / "fish" / "tier_1_late" / "staged_glb"
DEFAULT_PREVIEW = REPO_ROOT / "docs" / "images" / "tier_1_late_fish_preview.png"
DEFAULT_ATTACHMENT_PREVIEW = (
    REPO_ROOT / "docs" / "images" / "tier_1_late_fish_attachments.png"
)
TRIANGLE_BUDGET = 280


def parse_outputs() -> tuple[Path, Path, Path, Path]:
    values = {
        "--blend-output": DEFAULT_BLEND,
        "--glb-dir": DEFAULT_GLB_DIR,
        "--preview-output": DEFAULT_PREVIEW,
        "--attachment-preview-output": DEFAULT_ATTACHMENT_PREVIEW,
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
        values["--glb-dir"],
        values["--preview-output"],
        values["--attachment-preview-output"],
    )


def body_surface_x(
    length: float,
    half_width: float,
    half_height: float,
    profile: tuple[tuple[float, float, float, float], ...],
    y: float,
    z: float,
) -> float:
    """Proyecta un punto YZ sobre la cuaderna eliptica interpolada del cuerpo."""
    anchors = [(length * 0.49, 0.0, 0.0, 0.0)]
    anchors.extend((length * yf, wf, hf, zf) for yf, wf, hf, zf in profile)
    anchors.append((length * profile[-1][0] - 0.006, 0.0, 0.0, 0.0))

    upper = anchors[0]
    lower = anchors[1]
    for index in range(len(anchors) - 1):
        candidate_upper = anchors[index]
        candidate_lower = anchors[index + 1]
        if candidate_upper[0] >= y >= candidate_lower[0]:
            upper = candidate_upper
            lower = candidate_lower
            break
    span = max(upper[0] - lower[0], 1e-6)
    factor = max(0.0, min(1.0, (upper[0] - y) / span))
    width_factor = upper[1] + (lower[1] - upper[1]) * factor
    height_factor = upper[2] + (lower[2] - upper[2]) * factor
    z_factor = upper[3] + (lower[3] - upper[3]) * factor
    radius_z = max(half_height * height_factor, 1e-6)
    normalized_z = (z - half_height * z_factor) / radius_z
    radial = math.sqrt(max(0.0, 1.0 - normalized_z * normalized_z))
    return half_width * width_factor * radial


def curved_quad_patch_pair(
    name: str,
    root: bpy.types.Object,
    length: float,
    half_width: float,
    half_height: float,
    profile: tuple[tuple[float, float, float, float], ...],
    corners_yz: tuple[
        tuple[float, float],
        tuple[float, float],
        tuple[float, float],
        tuple[float, float],
    ],
    u_steps: int,
    v_steps: int,
    mat: bpy.types.Material,
) -> None:
    """Tesela una marca sobre la curva; nunca deja una placa plana flotando."""
    front_top, rear_top, rear_bottom, front_bottom = corners_yz
    for side in (-1.0, 1.0):
        vertices: list[tuple[float, float, float]] = []
        for u_index in range(u_steps + 1):
            u = float(u_index) / float(u_steps)
            top_y = front_top[0] + (rear_top[0] - front_top[0]) * u
            top_z = front_top[1] + (rear_top[1] - front_top[1]) * u
            bottom_y = front_bottom[0] + (rear_bottom[0] - front_bottom[0]) * u
            bottom_z = front_bottom[1] + (rear_bottom[1] - front_bottom[1]) * u
            for v_index in range(v_steps + 1):
                v = float(v_index) / float(v_steps)
                y = top_y + (bottom_y - top_y) * v
                z = top_z + (bottom_z - top_z) * v
                x = body_surface_x(length, half_width, half_height, profile, y, z)
                vertices.append((side * (x + 0.0012), y, z))

        faces: list[tuple[int, ...]] = []
        row = v_steps + 1
        for u_index in range(u_steps):
            for v_index in range(v_steps):
                a = u_index * row + v_index
                b = (u_index + 1) * row + v_index
                c = b + 1
                d = a + 1
                faces.append((a, b, c, d) if side > 0.0 else (a, d, c, b))
        common.mesh_object(
            f"{root.name}_{name}_{'R' if side > 0 else 'L'}",
            vertices,
            faces,
            [mat],
            root,
        )


def curved_oval_patch_pair(
    name: str,
    root: bpy.types.Object,
    length: float,
    half_width: float,
    half_height: float,
    profile: tuple[tuple[float, float, float, float], ...],
    center_y: float,
    center_z: float,
    radius_y: float,
    radius_z: float,
    mat: bpy.types.Material,
    segments: int = 8,
) -> None:
    for side in (-1.0, 1.0):
        center_x = body_surface_x(
            length, half_width, half_height, profile, center_y, center_z
        )
        vertices = [(side * (center_x + 0.0012), center_y, center_z)]
        for index in range(segments):
            angle = math.tau * float(index) / float(segments)
            y = center_y + math.cos(angle) * radius_y
            z = center_z + math.sin(angle) * radius_z
            x = body_surface_x(length, half_width, half_height, profile, y, z)
            vertices.append((side * (x + 0.0012), y, z))
        faces: list[tuple[int, ...]] = []
        for index in range(segments):
            current = 1 + index
            following = 1 + (index + 1) % segments
            faces.append(
                (0, current, following) if side > 0.0 else (0, following, current)
            )
        common.mesh_object(
            f"{root.name}_{name}_{'R' if side > 0 else 'L'}",
            vertices,
            faces,
            [mat],
            root,
        )


def staged_root(
    export: bpy.types.Collection,
    name: str,
    weight: float,
    min_fury: float,
) -> bpy.types.Object:
    root = common.make_root(export, name, weight)
    root["tier"] = 1
    root["min_fury"] = min_fury
    root["approval_state"] = "staged_not_integrated"
    return root


def build_boqueron(
    export: bpy.types.Collection,
    mats: dict[str, bpy.types.Material],
) -> bpy.types.Object:
    root = staged_root(export, "Boqueron", 1.0, 1.5)
    length = 0.42
    width = 0.043
    height = 0.068
    profile = (
        (0.39, 0.38, 0.45, 0.00),
        (0.28, 0.78, 0.80, 0.00),
        (0.08, 1.00, 1.00, 0.01),
        (-0.16, 0.78, 0.70, -0.01),
        (-0.33, 0.25, 0.22, 0.00),
    )
    common.body_mesh(
        "BoqueronBody",
        root,
        length,
        width,
        height,
        profile,
        mats["boqueron_back"],
        mats["boqueron_side"],
        mats["belly"],
    )
    # La cola empieza por delante de la ultima cuaderna: la costura queda dentro
    # del pedunculo y no puede leerse como una pieza apoyada.
    common.extruded_side_polygon(
        "BoqueronTail",
        root,
        [
            (-0.125, 0.010),
            (-0.210, 0.092),
            (-0.192, 0.020),
            (-0.178, 0.000),
            (-0.192, -0.020),
            (-0.210, -0.092),
            (-0.125, -0.010),
        ],
        0.008,
        mats["boqueron_back"],
    )
    common.extruded_side_polygon(
        "BoqueronDorsal",
        root,
        [(0.035, 0.032), (-0.015, 0.122), (-0.100, 0.030)],
        0.005,
        mats["boqueron_back"],
    )
    common.extruded_side_polygon(
        "BoqueronAnal",
        root,
        [(-0.045, -0.025), (-0.092, -0.082), (-0.132, -0.022)],
        0.004,
        mats["boqueron_back"],
    )
    common.pectoral_fins(
        root,
        0.105,
        0.003,
        width * 0.90,
        0.045,
        0.070,
        mats["boqueron_stripe"],
    )
    common.eye_discs(
        root,
        0.145,
        0.020,
        width * 0.86,
        0.017,
        mats["eye_gold"],
        mats["dark"],
    )
    common.gill_slits(root, 0.108, height, width * 0.94, mats["dark"])
    curved_quad_patch_pair(
        "BlueStripe",
        root,
        length,
        width,
        height,
        profile,
        ((0.118, 0.025), (-0.122, 0.011), (-0.132, -0.003), (0.105, 0.012)),
        4,
        1,
        mats["boqueron_stripe"],
    )
    # Boca larga y baja: la lectura que separa al boqueron de una sardina chica.
    curved_quad_patch_pair(
        "Mouth",
        root,
        length,
        width,
        height,
        profile,
        ((0.202, -0.006), (0.143, -0.016), (0.108, -0.026), (0.180, -0.024)),
        4,
        1,
        mats["dark"],
    )
    common.join_species(root)
    return root


def build_faneca(
    export: bpy.types.Collection,
    mats: dict[str, bpy.types.Material],
) -> bpy.types.Object:
    root = staged_root(export, "Faneca", 2.0, 1.5)
    length = 0.48
    width = 0.062
    height = 0.105
    profile = (
        (0.38, 0.62, 0.68, 0.00),
        (0.25, 0.96, 0.98, 0.02),
        (0.05, 1.00, 1.00, 0.01),
        (-0.17, 0.80, 0.78, -0.01),
        (-0.34, 0.34, 0.30, 0.00),
    )
    common.body_mesh(
        "FanecaBody",
        root,
        length,
        width,
        height,
        profile,
        mats["faneca_back"],
        mats["faneca_side"],
        mats["belly"],
    )
    common.extruded_side_polygon(
        "FanecaTail",
        root,
        [
            (-0.150, 0.018),
            (-0.232, 0.092),
            (-0.252, 0.055),
            (-0.258, 0.000),
            (-0.252, -0.055),
            (-0.232, -0.092),
            (-0.150, -0.018),
        ],
        0.011,
        mats["faneca_fin"],
    )
    # Tres dorsales y dos anales: se reconocen antes que el color. Todas las
    # bases penetran el lomo o vientre, no descansan sobre la tangente.
    for suffix, points in (
        ("Dorsal1", [(0.145, 0.052), (0.105, 0.178), (0.040, 0.050)]),
        ("Dorsal2", [(0.035, 0.050), (-0.010, 0.163), (-0.075, 0.046)]),
        ("Dorsal3", [(-0.082, 0.043), (-0.125, 0.135), (-0.175, 0.037)]),
        ("Anal1", [(0.015, -0.048), (-0.038, -0.132), (-0.095, -0.043)]),
        ("Anal2", [(-0.098, -0.040), (-0.137, -0.112), (-0.180, -0.034)]),
    ):
        common.extruded_side_polygon(
            f"Faneca{suffix}",
            root,
            points,
            0.005,
            mats["faneca_fin"],
        )
    common.pectoral_fins(
        root,
        0.125,
        0.008,
        width * 0.90,
        0.065,
        0.098,
        mats["faneca_fin"],
    )
    common.eye_discs(
        root,
        0.168,
        0.034,
        width * 0.88,
        0.019,
        mats["eye_gold"],
        mats["dark"],
    )
    common.gill_slits(root, 0.127, height, width * 0.95, mats["dark"])
    # La barbilla nace dentro de la mandibula; el primer y ultimo punto quedan
    # ocultos por el volumen de la cabeza.
    common.extruded_side_polygon(
        "FanecaBarbel",
        root,
        [(0.170, -0.052), (0.154, -0.123), (0.139, -0.056)],
        0.008,
        mats["faneca_fin"],
    )
    curved_quad_patch_pair(
        "LateralLine",
        root,
        length,
        width,
        height,
        profile,
        ((0.122, 0.035), (-0.150, 0.010), (-0.160, -0.003), (0.105, 0.022)),
        4,
        1,
        mats["faneca_fin"],
    )
    for index, (center_y, center_z) in enumerate(
        ((0.065, 0.067), (-0.005, 0.047), (-0.075, 0.020))
    ):
        curved_oval_patch_pair(
            f"Mottle{index}",
            root,
            length,
            width,
            height,
            profile,
            center_y,
            center_z,
            0.018,
            0.012,
            mats["faneca_back"],
            6,
        )
    common.join_species(root)
    return root


def build_sargo(
    export: bpy.types.Collection,
    mats: dict[str, bpy.types.Material],
) -> bpy.types.Object:
    root = staged_root(export, "Sargo", 4.0, 2.0)
    length = 0.53
    width = 0.075
    height = 0.155
    profile = (
        (0.36, 0.62, 0.72, 0.01),
        (0.24, 0.94, 0.98, 0.02),
        (0.05, 1.00, 1.00, 0.01),
        (-0.16, 0.88, 0.90, 0.00),
        (-0.33, 0.32, 0.34, 0.00),
    )
    common.body_mesh(
        "SargoBody",
        root,
        length,
        width,
        height,
        profile,
        mats["sargo_back"],
        mats["sargo_side"],
        mats["belly"],
    )
    common.extruded_side_polygon(
        "SargoTail",
        root,
        [
            (-0.165, 0.020),
            (-0.285, 0.155),
            (-0.258, 0.038),
            (-0.232, 0.000),
            (-0.258, -0.038),
            (-0.285, -0.155),
            (-0.165, -0.020),
        ],
        0.013,
        mats["sargo_fin"],
    )
    common.extruded_side_polygon(
        "SargoSpinyDorsal",
        root,
        [
            (0.185, 0.078),
            (0.150, 0.218),
            (0.108, 0.145),
            (0.075, 0.226),
            (0.030, 0.150),
            (-0.005, 0.205),
            (-0.045, 0.085),
        ],
        0.007,
        mats["sargo_back"],
    )
    common.extruded_side_polygon(
        "SargoSoftDorsal",
        root,
        [(-0.048, 0.082), (-0.085, 0.176), (-0.155, 0.070), (-0.170, 0.065)],
        0.007,
        mats["sargo_fin"],
    )
    common.extruded_side_polygon(
        "SargoAnal",
        root,
        [(0.015, -0.075), (-0.040, -0.176), (-0.145, -0.067), (-0.160, -0.060)],
        0.006,
        mats["sargo_fin"],
    )
    common.pectoral_fins(
        root,
        0.145,
        0.012,
        width * 0.90,
        0.095,
        0.145,
        mats["sargo_fin"],
    )
    common.eye_discs(
        root,
        0.192,
        0.048,
        width * 0.88,
        0.020,
        mats["eye_gold"],
        mats["dark"],
    )
    common.gill_slits(root, 0.148, height, width * 0.95, mats["dark"])
    # Cinco barras grandes y una mancha caudal hacen que el sargo se lea incluso
    # cuando el rigidbody rueda lejos de la camara.
    for index, center_y in enumerate((0.125, 0.070, 0.012, -0.050, -0.112)):
        top = 0.110 - abs(center_y) * 0.12
        bottom = -0.105 + abs(center_y) * 0.10
        curved_quad_patch_pair(
            f"Band{index}",
            root,
            length,
            width,
            height,
            profile,
            (
                (center_y + 0.014, top),
                (center_y - 0.006, top + 0.010),
                (center_y - 0.018, bottom),
                (center_y + 0.005, bottom - 0.008),
            ),
            1,
            2,
            mats["dark"],
        )
    curved_oval_patch_pair(
        "CaudalSpot",
        root,
        length,
        width,
        height,
        profile,
        -0.145,
        0.012,
        0.027,
        0.045,
        mats["dark"],
    )
    common.join_species(root)
    return root


def mesh_stats(root: bpy.types.Object) -> tuple[int, int, Vector]:
    meshes = [child for child in root.children_recursive if child.type == "MESH"]
    if len(meshes) != 1:
        raise RuntimeError(f"{root.name}: se esperaba una malla, hay {len(meshes)}")
    mesh = meshes[0].data
    triangles = sum(len(polygon.vertices) - 2 for polygon in mesh.polygons)
    if triangles > TRIANGLE_BUDGET:
        raise RuntimeError(
            f"{root.name}: {triangles} triangulos supera el presupuesto {TRIANGLE_BUDGET}"
        )
    coords = [vertex.co for vertex in mesh.vertices]
    minimum = Vector((min(v.x for v in coords), min(v.y for v in coords), min(v.z for v in coords)))
    maximum = Vector((max(v.x for v in coords), max(v.y for v in coords), max(v.z for v in coords)))
    size = maximum - minimum
    if size.y <= size.x or size.y <= size.z:
        raise RuntimeError(f"{root.name}: orientacion inesperada, AABB={tuple(size)}")
    return len(mesh.vertices), triangles, size


def glb_json(path: Path) -> dict:
    data = path.read_bytes()
    if len(data) < 20 or data[:4] != b"glTF":
        raise RuntimeError(f"{path.name}: cabecera GLB invalida")
    _magic, version, total_length = struct.unpack_from("<4sII", data, 0)
    if version != 2 or total_length != len(data):
        raise RuntimeError(f"{path.name}: version o longitud GLB invalida")
    json_length, chunk_type = struct.unpack_from("<II", data, 12)
    if chunk_type != 0x4E4F534A:
        raise RuntimeError(f"{path.name}: el primer chunk no es JSON")
    return json.loads(data[20 : 20 + json_length].decode("utf-8").rstrip(" \t\r\n\x00"))


def validate_glb(path: Path) -> None:
    document = glb_json(path)
    if len(document.get("meshes", [])) != 1:
        raise RuntimeError(f"{path.name}: no contiene exactamente una malla")
    forbidden = ("animations", "skins", "cameras", "images", "textures")
    present = [key for key in forbidden if document.get(key)]
    if present:
        raise RuntimeError(f"{path.name}: datos prohibidos en staging: {present}")
    extensions = document.get("extensions", {})
    if "KHR_lights_punctual" in extensions:
        raise RuntimeError(f"{path.name}: exporto luces por accidente")
    primitive_count = sum(
        len(mesh.get("primitives", [])) for mesh in document.get("meshes", [])
    )
    if primitive_count < 3 or primitive_count > 6:
        raise RuntimeError(f"{path.name}: {primitive_count} bloques de material")
    if path.stat().st_size > 100_000:
        raise RuntimeError(f"{path.name}: pesa mas de 100 KB")


def configure_render(scene: bpy.types.Scene) -> None:
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.world.color = (0.012, 0.027, 0.043)
    scene.view_settings.look = "AgX - Medium High Contrast"


def save_export_and_render(
    blend_path: Path,
    glb_dir: Path,
    preview_path: Path,
    attachment_preview_path: Path,
    roots: list[bpy.types.Object],
    camera: bpy.types.Object,
) -> None:
    for path in (blend_path.parent, glb_dir, preview_path.parent, attachment_preview_path.parent):
        path.mkdir(parents=True, exist_ok=True)

    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
    for root in roots:
        common.export_species(root, glb_dir / f"{root.name.lower()}.glb")

    scene = bpy.context.scene
    scene.camera = camera
    configure_render(scene)
    scene.render.filepath = str(preview_path)
    bpy.ops.render.render(write_still=True)

    # El perfil compara siluetas; esta segunda vista abre el angulo para que la
    # extension de las pectorales y su raiz hundida se puedan juzgar.
    side_location = camera.location.copy()
    side_rotation = camera.rotation_euler.copy()
    side_scale = camera.data.ortho_scale
    camera.location = (3.15, -1.45, 1.35)
    camera.data.ortho_scale = 2.55
    common.look_at(camera, Vector((0.0, 0.0, 0.27)))
    scene.render.filepath = str(attachment_preview_path)
    bpy.ops.render.render(write_still=True)
    camera.location = side_location
    camera.rotation_euler = side_rotation
    camera.data.ortho_scale = side_scale
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))

    for root in roots:
        vertices, triangles, size = mesh_stats(root)
        path = glb_dir / f"{root.name.lower()}.glb"
        validate_glb(path)
        print(
            "FISH "
            f"{root.name}: meshes=1 vertices={vertices} triangles={triangles} "
            f"aabb=({size.x:.3f},{size.y:.3f},{size.z:.3f}) bytes={path.stat().st_size}"
        )
    print("TIER_1_LATE_FISH_BUILD_OK")
    print(f"BLEND={blend_path}")
    print(f"STAGED_GLB_DIR={glb_dir}")
    print(f"PREVIEW={preview_path}")
    print(f"ATTACHMENTS={attachment_preview_path}")


def main() -> None:
    blend_path, glb_dir, preview_path, attachment_preview_path = parse_outputs()
    export = common.reset_scene()
    mats = {
        "boqueron_back": common.material("M_Boqueron_Back", (0.10, 0.25, 0.28, 1.0)),
        "boqueron_side": common.material("M_Boqueron_Silver", (0.72, 0.76, 0.68, 1.0), 0.78),
        "boqueron_stripe": common.material("M_Boqueron_Stripe", (0.08, 0.30, 0.38, 1.0), 0.82),
        "faneca_back": common.material("M_Faneca_Back", (0.24, 0.19, 0.12, 1.0)),
        "faneca_side": common.material("M_Faneca_Side", (0.60, 0.52, 0.40, 1.0), 0.84),
        "faneca_fin": common.material("M_Faneca_Fin", (0.55, 0.38, 0.18, 1.0), 0.86),
        "sargo_back": common.material("M_Sargo_Back", (0.22, 0.25, 0.27, 1.0)),
        "sargo_side": common.material("M_Sargo_Silver", (0.62, 0.62, 0.66, 1.0), 0.78),
        "sargo_fin": common.material("M_Sargo_Fin", (0.32, 0.38, 0.39, 1.0), 0.88),
        "belly": common.material("M_Tier1Late_Belly", (0.80, 0.79, 0.69, 1.0), 0.90),
        "eye_gold": common.material("M_Tier1Late_Eye", (0.86, 0.70, 0.28, 1.0), 0.72),
        "dark": common.material("M_Tier1Late_Dark", (0.018, 0.026, 0.028, 1.0), 0.92),
        "floor": common.material("M_Tier1Late_PreviewFloor", (0.008, 0.025, 0.032, 1.0), 0.80),
    }
    roots = [
        build_boqueron(export, mats),
        build_faneca(export, mats),
        build_sargo(export, mats),
    ]
    camera = common.add_preview_scene(roots, mats["floor"])
    save_export_and_render(
        blend_path,
        glb_dir,
        preview_path,
        attachment_preview_path,
        roots,
        camera,
    )


if __name__ == "__main__":
    main()
