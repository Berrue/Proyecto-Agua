"""Construye los tres peces comunes editables y sus GLB de runtime.

El tier bajo aparece durante la mayor parte de una salida, asi que sus siluetas
deben distinguirse desde la cubierta sin recurrir a texturas finas. La fuente
usa geometria low-poly y bloques de material planos; Godot conserva la colision,
la masa y la flotabilidad en ``game/fishing/fish.tscn``.

Uso desde la raiz del proyecto:

    blender --background --factory-startup --python tools/build_common_fish.py
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BLEND = REPO_ROOT / "source_assets" / "fish" / "common_fish.blend"
DEFAULT_GLB_DIR = REPO_ROOT / "game" / "fishing" / "models"
DEFAULT_PREVIEW = REPO_ROOT / "docs" / "images" / "common_fish_preview.png"


def parse_outputs() -> tuple[Path, Path, Path]:
    values = {
        "--blend-output": DEFAULT_BLEND,
        "--glb-dir": DEFAULT_GLB_DIR,
        "--preview-output": DEFAULT_PREVIEW,
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
    return values["--blend-output"], values["--glb-dir"], values["--preview-output"]


def reset_scene() -> bpy.types.Collection:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in list(bpy.data.collections):
        bpy.data.collections.remove(collection)
    export = bpy.data.collections.new("EXPORT")
    bpy.context.scene.collection.children.link(export)
    return export


def material(
    name: str,
    rgba: tuple[float, float, float, float],
    roughness: float = 0.88,
) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = rgba
    mat.use_nodes = True
    mat.use_backface_culling = False
    principled = mat.node_tree.nodes.get("Principled BSDF")
    principled.inputs["Base Color"].default_value = rgba
    principled.inputs["Roughness"].default_value = roughness
    principled.inputs["Metallic"].default_value = 0.0
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
    parent: bpy.types.Object,
    material_indices: list[int] | None = None,
) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    recalculate_normals(mesh)
    obj = bpy.data.objects.new(name, mesh)
    parent.users_collection[0].objects.link(obj)
    obj.parent = parent
    for mat in materials:
        mesh.materials.append(mat)
    for index, polygon in enumerate(mesh.polygons):
        polygon.use_smooth = False
        if material_indices is not None and index < len(material_indices):
            polygon.material_index = material_indices[index]
    return obj


def body_mesh(
    name: str,
    root: bpy.types.Object,
    length: float,
    half_width: float,
    half_height: float,
    profile: tuple[tuple[float, float, float, float], ...],
    dorsal: bpy.types.Material,
    flank: bpy.types.Material,
    belly: bpy.types.Material,
) -> bpy.types.Object:
    """Cuerpo por cuadernas: X=espesor, Y+=hocico, Z=arriba."""
    segments = 8
    nose_y = length * 0.49
    vertices: list[tuple[float, float, float]] = [(0.0, nose_y, 0.0)]
    for y_factor, width_factor, height_factor, z_factor in profile:
        for segment in range(segments):
            angle = math.tau * float(segment) / float(segments)
            vertices.append(
                (
                    math.cos(angle) * half_width * width_factor,
                    length * y_factor,
                    math.sin(angle) * half_height * height_factor + half_height * z_factor,
                )
            )
    tail_index = len(vertices)
    tail_y = length * profile[-1][0]
    vertices.append((0.0, tail_y - 0.006, 0.0))

    faces: list[tuple[int, ...]] = []
    indices: list[int] = []

    def face_material(face: tuple[int, ...]) -> int:
        average_z = sum(vertices[index][2] for index in face) / float(len(face))
        if average_z > half_height * 0.34:
            return 0
        if average_z < -half_height * 0.35:
            return 2
        return 1

    for segment in range(segments):
        face = (0, 1 + (segment + 1) % segments, 1 + segment)
        faces.append(face)
        indices.append(face_material(face))

    for ring in range(len(profile) - 1):
        start_a = 1 + ring * segments
        start_b = start_a + segments
        for segment in range(segments):
            face = (
                start_a + segment,
                start_a + (segment + 1) % segments,
                start_b + (segment + 1) % segments,
                start_b + segment,
            )
            faces.append(face)
            indices.append(face_material(face))

    last_start = 1 + (len(profile) - 1) * segments
    for segment in range(segments):
        face = (last_start + segment, last_start + (segment + 1) % segments, tail_index)
        faces.append(face)
        indices.append(face_material(face))
    return mesh_object(name, vertices, faces, [dorsal, flank, belly], root, indices)


def extruded_side_polygon(
    name: str,
    root: bpy.types.Object,
    points_yz: list[tuple[float, float]],
    half_thickness: float,
    mat: bpy.types.Material,
) -> bpy.types.Object:
    vertices = [(-half_thickness, y, z) for y, z in points_yz]
    vertices.extend((half_thickness, y, z) for y, z in points_yz)
    count = len(points_yz)
    faces: list[tuple[int, ...]] = [tuple(range(count - 1, -1, -1)), tuple(range(count, count * 2))]
    for index in range(count):
        nxt = (index + 1) % count
        faces.append((index, nxt, count + nxt, count + index))
    return mesh_object(name, vertices, faces, [mat], root)


def flat_side_patch(
    name: str,
    root: bpy.types.Object,
    side_x: float,
    points_yz: list[tuple[float, float]],
    mat: bpy.types.Material,
) -> bpy.types.Object:
    vertices = [(side_x, y, z) for y, z in points_yz]
    face = tuple(range(len(points_yz))) if side_x > 0.0 else tuple(range(len(points_yz) - 1, -1, -1))
    return mesh_object(name, vertices, [face], [mat], root)


def eye_discs(
    root: bpy.types.Object,
    y: float,
    z: float,
    side_x: float,
    radius: float,
    iris: bpy.types.Material,
    pupil: bpy.types.Material,
) -> None:
    for side in (-1.0, 1.0):
        for suffix, disc_radius, mat, offset in (
            ("Iris", radius, iris, 0.0015),
            ("Pupil", radius * 0.48, pupil, 0.0028),
        ):
            points: list[tuple[float, float]] = []
            for index in range(8):
                angle = math.tau * float(index) / 8.0
                points.append((y + math.cos(angle) * disc_radius, z + math.sin(angle) * disc_radius))
            flat_side_patch(
                f"{root.name}_{suffix}_{'R' if side > 0 else 'L'}",
                root,
                side * (side_x + offset),
                points,
                mat,
            )


def gill_slits(
    root: bpy.types.Object,
    y: float,
    half_height: float,
    side_x: float,
    mat: bpy.types.Material,
) -> None:
    points = [
        (y + 0.006, half_height * 0.45),
        (y - 0.010, half_height * 0.40),
        (y - 0.022, -half_height * 0.34),
        (y - 0.010, -half_height * 0.30),
    ]
    for side in (-1.0, 1.0):
        flat_side_patch(f"{root.name}_Gill_{side:+.0f}", root, side * side_x, points, mat)


def pectoral_fins(
    root: bpy.types.Object,
    y: float,
    z: float,
    side_x: float,
    reach: float,
    length: float,
    mat: bpy.types.Material,
) -> None:
    """Aletas laterales con una raiz facetada que se pierde dentro del cuerpo.

    Una sola cara triangular apoyada sobre un elipsoide deja dos puntas
    tangenciales visibles: parecen flotar aunque geometricamente se toquen. Esta
    hoja usa tres puntos de raiz en arco, todos hundidos en el volumen, y un
    pequeño espesor. La interseccion oculta el borde y la union se lee continua.
    """
    for side in (-1.0, 1.0):
        outline = [
            (side * side_x * 0.72, y + length * 0.25, z + 0.008),
            (side * side_x * 0.58, y + length * 0.02, z + 0.002),
            (side * side_x * 0.70, y - length * 0.23, z - 0.008),
            (side * (side_x + reach), y - length, z - 0.030),
            (side * (side_x + reach * 0.30), y - length * 0.38, z - 0.004),
        ]
        half_thickness = 0.0035
        vertices = [(x, py, pz - half_thickness) for x, py, pz in outline]
        vertices.extend((x, py, pz + half_thickness) for x, py, pz in outline)
        count = len(outline)
        faces: list[tuple[int, ...]] = [
            tuple(range(count - 1, -1, -1)),
            tuple(range(count, count * 2)),
        ]
        for index in range(count):
            nxt = (index + 1) % count
            faces.append((index, nxt, count + nxt, count + index))
        mesh_object(f"{root.name}_Pectoral_{side:+.0f}", vertices, faces, [mat], root)


def join_species(root: bpy.types.Object) -> bpy.types.Object:
    meshes = [child for child in root.children_recursive if child.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()
    joined = bpy.context.object
    joined.name = f"{root.name}_Mesh"
    bpy.ops.object.material_slot_remove_unused()
    for polygon in joined.data.polygons:
        polygon.use_smooth = False
    return joined


def make_root(export: bpy.types.Collection, name: str, weight: float) -> bpy.types.Object:
    root = bpy.data.objects.new(name, None)
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 0.12
    root["species_name"] = name
    root["tier"] = "A"
    root["base_weight_kg"] = weight
    root["source_forward_axis"] = "+Y"
    root["godot_forward_axis"] = "-Z"
    export.objects.link(root)
    return root


def build_sardina(export: bpy.types.Collection, mats: dict[str, bpy.types.Material]) -> bpy.types.Object:
    root = make_root(export, "Sardina", 2.0)
    length = 0.48
    width = 0.052
    height = 0.082
    profile = (
        (0.37, 0.50, 0.56, 0.00),
        (0.21, 0.92, 0.90, 0.01),
        (-0.02, 1.00, 1.00, 0.00),
        (-0.23, 0.70, 0.67, -0.01),
        (-0.33, 0.28, 0.28, 0.00),
    )
    body_mesh("SardinaBody", root, length, width, height, profile, mats["sardina_back"], mats["sardina_side"], mats["belly"])
    extruded_side_polygon(
        "SardinaTail",
        root,
        [(-0.146, 0.012), (-0.240, 0.112), (-0.220, 0.020), (-0.205, 0.000), (-0.220, -0.020), (-0.240, -0.112), (-0.146, -0.012)],
        0.010,
        mats["sardina_back"],
    )
    extruded_side_polygon("SardinaDorsal", root, [(0.035, 0.040), (-0.030, 0.148), (-0.105, 0.035)], 0.006, mats["sardina_back"])
    extruded_side_polygon("SardinaAnal", root, [(-0.070, -0.030), (-0.112, -0.105), (-0.150, -0.028)], 0.005, mats["sardina_back"])
    pectoral_fins(root, 0.105, 0.010, width * 0.88, 0.055, 0.075, mats["sardina_back"])
    eye_discs(root, 0.165, 0.022, width * 0.88, 0.016, mats["eye_gold"], mats["dark"])
    gill_slits(root, 0.118, height, width * 0.95, mats["dark"])
    join_species(root)
    return root


def build_caballa(export: bpy.types.Collection, mats: dict[str, bpy.types.Material]) -> bpy.types.Object:
    root = make_root(export, "Caballa", 3.0)
    length = 0.54
    width = 0.067
    height = 0.098
    profile = (
        (0.37, 0.48, 0.52, 0.00),
        (0.22, 0.90, 0.88, 0.01),
        (-0.01, 1.00, 1.00, 0.01),
        (-0.22, 0.77, 0.72, -0.01),
        (-0.34, 0.27, 0.28, 0.00),
    )
    body_mesh("CaballaBody", root, length, width, height, profile, mats["caballa_back"], mats["caballa_side"], mats["belly"])
    extruded_side_polygon(
        "CaballaTail",
        root,
        [(-0.170, 0.014), (-0.270, 0.138), (-0.248, 0.028), (-0.226, 0.000), (-0.248, -0.028), (-0.270, -0.138), (-0.170, -0.014)],
        0.012,
        mats["caballa_back"],
    )
    extruded_side_polygon("CaballaDorsal1", root, [(0.082, 0.045), (0.024, 0.174), (-0.052, 0.043)], 0.007, mats["caballa_back"])
    extruded_side_polygon("CaballaDorsal2", root, [(-0.080, 0.036), (-0.126, 0.132), (-0.177, 0.032)], 0.006, mats["caballa_back"])
    extruded_side_polygon("CaballaAnal", root, [(-0.085, -0.035), (-0.132, -0.121), (-0.178, -0.030)], 0.006, mats["caballa_back"])
    for index, y in enumerate((-0.185, -0.214)):
        extruded_side_polygon(f"CaballaFinletTop{index}", root, [(y + 0.010, 0.018), (y, 0.071), (y - 0.012, 0.016)], 0.004, mats["caballa_back"])
        extruded_side_polygon(f"CaballaFinletBottom{index}", root, [(y + 0.010, -0.018), (y, -0.068), (y - 0.012, -0.016)], 0.004, mats["caballa_back"])
    pectoral_fins(root, 0.120, 0.012, width * 0.90, 0.068, 0.090, mats["caballa_back"])
    eye_discs(root, 0.190, 0.027, width * 0.88, 0.017, mats["eye_gold"], mats["dark"])
    gill_slits(root, 0.135, height, width * 0.95, mats["dark"])
    for side in (-1.0, 1.0):
        x = side * width * 0.94
        for index, y in enumerate((0.085, 0.035, -0.015, -0.065, -0.115)):
            flat_side_patch(
                f"CaballaStripe_{side:+.0f}_{index}",
                root,
                x,
                [(y + 0.018, 0.077), (y + 0.005, 0.092), (y - 0.032, 0.022), (y - 0.019, 0.020)],
                mats["dark"],
            )
    join_species(root)
    return root


def build_jurel(export: bpy.types.Collection, mats: dict[str, bpy.types.Material]) -> bpy.types.Object:
    root = make_root(export, "Jurel", 4.0)
    length = 0.56
    width = 0.071
    height = 0.132
    profile = (
        (0.38, 0.62, 0.68, 0.01),
        (0.24, 0.96, 0.94, 0.02),
        (0.05, 1.00, 1.00, 0.01),
        (-0.16, 0.80, 0.82, -0.01),
        (-0.32, 0.25, 0.25, 0.00),
    )
    body_mesh("JurelBody", root, length, width, height, profile, mats["jurel_back"], mats["jurel_side"], mats["belly"])
    extruded_side_polygon(
        "JurelTail",
        root,
        [(-0.163, 0.016), (-0.280, 0.158), (-0.250, 0.032), (-0.222, 0.000), (-0.250, -0.032), (-0.280, -0.158), (-0.163, -0.016)],
        0.013,
        mats["jurel_gold"],
    )
    extruded_side_polygon("JurelDorsal", root, [(0.115, 0.055), (0.068, 0.218), (-0.065, 0.060), (-0.145, 0.045)], 0.007, mats["jurel_back"])
    extruded_side_polygon("JurelAnal", root, [(-0.012, -0.055), (-0.070, -0.181), (-0.154, -0.043)], 0.006, mats["jurel_gold"])
    pectoral_fins(root, 0.135, 0.016, width * 0.90, 0.105, 0.155, mats["jurel_gold"])
    eye_discs(root, 0.196, 0.040, width * 0.88, 0.021, mats["eye_gold"], mats["dark"])
    gill_slits(root, 0.138, height, width * 0.96, mats["dark"])
    for side in (-1.0, 1.0):
        x = side * width * 0.97
        flat_side_patch(
            f"JurelLateralLine_{side:+.0f}",
            root,
            x,
            [(0.137, 0.005), (0.132, 0.020), (-0.153, 0.008), (-0.160, -0.006)],
            mats["jurel_gold"],
        )
        # Mancha opercular grande: legible a distancia y propia de la silueta.
        points: list[tuple[float, float]] = []
        for index in range(8):
            angle = math.tau * float(index) / 8.0
            points.append((0.124 + math.cos(angle) * 0.019, 0.046 + math.sin(angle) * 0.019))
        flat_side_patch(f"JurelSpot_{side:+.0f}", root, x + side * 0.001, points, mats["dark"])
    join_species(root)
    return root


def add_preview_scene(roots: list[bpy.types.Object], floor_mat: bpy.types.Material) -> bpy.types.Object:
    preview = bpy.data.collections.new("PREVIEW_NOT_EXPORTED")
    bpy.context.scene.collection.children.link(preview)

    # La camara mira casi a lo largo de X: separar sobre Y convierte la lamina
    # en tres perfiles comparables y evita que las colas queden recortadas.
    for root, y in zip(roots, (-0.72, 0.0, 0.74)):
        root.location = (0.0, y, 0.28)
        root.rotation_euler.z = math.radians(-8.0 if y < 0.0 else (8.0 if y > 0.0 else 0.0))

    bpy.ops.mesh.primitive_plane_add(size=8.0, location=(0.0, 0.0, 0.0))
    floor = bpy.context.object
    floor.name = "PreviewFloor"
    floor.data.materials.append(floor_mat)
    for collection in list(floor.users_collection):
        collection.objects.unlink(floor)
    preview.objects.link(floor)

    bpy.ops.object.camera_add(location=(3.25, -0.10, 1.45))
    camera = bpy.context.object
    camera.name = "PreviewCamera"
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 2.40
    for collection in list(camera.users_collection):
        collection.objects.unlink(camera)
    preview.objects.link(camera)
    look_at(camera, Vector((0.0, 0.0, 0.28)))

    for name, location, energy, size, color in (
        ("Key", (2.2, -1.8, 4.8), 780.0, 4.0, (1.0, 0.82, 0.66)),
        ("Fill", (-3.2, -0.5, 2.8), 520.0, 3.5, (0.34, 0.58, 1.0)),
        ("Rim", (0.0, 3.2, 3.6), 680.0, 3.0, (0.38, 0.84, 1.0)),
    ):
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.name = f"Preview{name}"
        light.data.energy = energy
        light.data.shape = "DISK"
        light.data.size = size
        light.data.color = color
        for collection in list(light.users_collection):
            collection.objects.unlink(light)
        preview.objects.link(light)
        look_at(light, Vector((0.0, 0.0, 0.28)))
    return camera


def look_at(obj: bpy.types.Object, target: Vector) -> None:
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def export_species(root: bpy.types.Object, glb_path: Path) -> None:
    saved_location = root.location.copy()
    saved_rotation = root.rotation_euler.copy()
    root.location = (0.0, 0.0, 0.0)
    root.rotation_euler = (0.0, 0.0, 0.0)
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for child in root.children_recursive:
        child.select_set(True)
    bpy.context.view_layer.objects.active = root
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
    root.location = saved_location
    root.rotation_euler = saved_rotation
    bpy.context.view_layer.update()


def save_export_and_render(
    blend_path: Path,
    glb_dir: Path,
    preview_path: Path,
    roots: list[bpy.types.Object],
    camera: bpy.types.Object,
) -> None:
    blend_path.parent.mkdir(parents=True, exist_ok=True)
    glb_dir.mkdir(parents=True, exist_ok=True)
    preview_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))

    for root in roots:
        export_species(root, glb_dir / f"{root.name.lower()}.glb")

    scene = bpy.context.scene
    scene.camera = camera
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(preview_path)
    scene.render.film_transparent = False
    scene.world.color = (0.012, 0.027, 0.043)
    scene.view_settings.look = "AgX - Medium High Contrast"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
    bpy.ops.render.render(write_still=True)

    for root in roots:
        meshes = [child for child in root.children_recursive if child.type == "MESH"]
        vertices = sum(len(obj.data.vertices) for obj in meshes)
        triangles = sum(len(poly.vertices) - 2 for obj in meshes for poly in obj.data.polygons)
        print(f"FISH {root.name}: meshes={len(meshes)} vertices={vertices} triangles={triangles}")
    print("COMMON_FISH_BUILD_OK")
    print(f"BLEND={blend_path}")
    print(f"GLB_DIR={glb_dir}")
    print(f"PREVIEW={preview_path}")


def main() -> None:
    blend_path, glb_dir, preview_path = parse_outputs()
    export = reset_scene()
    mats = {
        "sardina_back": material("M_Sardina_Back", (0.20, 0.34, 0.40, 1.0)),
        "sardina_side": material("M_Sardina_Silver", (0.60, 0.72, 0.76, 1.0), 0.78),
        "caballa_back": material("M_Caballa_Back", (0.08, 0.24, 0.28, 1.0)),
        "caballa_side": material("M_Caballa_Side", (0.27, 0.50, 0.52, 1.0), 0.80),
        "jurel_back": material("M_Jurel_Back", (0.20, 0.32, 0.31, 1.0)),
        "jurel_side": material("M_Jurel_Side", (0.48, 0.58, 0.55, 1.0), 0.82),
        "jurel_gold": material("M_Jurel_Gold", (0.78, 0.55, 0.14, 1.0), 0.84),
        "belly": material("M_Common_Belly", (0.78, 0.80, 0.73, 1.0), 0.90),
        "eye_gold": material("M_Common_Eye", (0.86, 0.72, 0.32, 1.0), 0.72),
        "dark": material("M_Common_Dark", (0.018, 0.028, 0.030, 1.0), 0.92),
        "floor": material("M_Preview_Floor", (0.008, 0.025, 0.032, 1.0), 0.80),
    }
    roots = [build_sardina(export, mats), build_caballa(export, mats), build_jurel(export, mats)]
    camera = add_preview_scene(roots, mats["floor"])
    save_export_and_render(blend_path, glb_dir, preview_path, roots, camera)


if __name__ == "__main__":
    main()
