"""Construye el pescador *soft low-poly* con rig y gestos faciales.

Este generador es deliberadamente autocontenido y no lee ni sobrescribe el
``pescador.glb`` historico. Produce dos assets paralelos:

    source_assets/player/pescador_smooth.blend
    game/player/pescador_smooth.glb

Uso:

    blender --background --factory-startup --python tools/build_pescador_smooth.py

La convencion del modelo es Blender Z-up, mirando -Y. El exportador glTF lo
convierte a Y-up mirando +Z, igual que el pescador original en Godot.
"""

from __future__ import annotations

import json
import math
import os
import struct
import tempfile
from collections.abc import Callable

import bpy
from mathutils import Vector


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.normpath(os.path.join(SCRIPT_DIR, ".."))
BLEND_PATH = os.path.join(PROJECT_ROOT, "source_assets", "player", "pescador_smooth.blend")
GLB_PATH = os.path.join(PROJECT_ROOT, "game", "player", "pescador_smooth.glb")
QA_DIR = os.environ.get(
    "PESCADOR_QA_DIR",
    os.path.join(tempfile.gettempdir(), "pescador_smooth_qa"),
)

ASSET_OBJECTS: list[bpy.types.Object] = []
SKINNED_OBJECTS: list[bpy.types.Object] = []
FACE_OBJECTS: dict[str, bpy.types.Object] = {}
MATERIALS: dict[str, bpy.types.Material] = {}
RIG: bpy.types.Object | None = None


def clean_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (
        bpy.data.meshes,
        bpy.data.curves,
        bpy.data.armatures,
        bpy.data.materials,
        bpy.data.cameras,
        bpy.data.lights,
    ):
        for block in list(datablocks):
            if block.users == 0:
                datablocks.remove(block)


def srgb(hex_color: str) -> tuple[float, float, float, float]:
    raw = hex_color.lstrip("#")
    channels = [int(raw[i : i + 2], 16) / 255.0 for i in (0, 2, 4)]

    def to_linear(value: float) -> float:
        return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4

    return tuple(to_linear(value) for value in channels) + (1.0,)


def material(name: str, color: str, roughness: float = 0.68, metallic: float = 0.0) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = srgb(color)
    mat.use_nodes = True
    principled = mat.node_tree.nodes.get("Principled BSDF")
    principled.inputs["Base Color"].default_value = srgb(color)
    principled.inputs["Roughness"].default_value = roughness
    principled.inputs["Metallic"].default_value = metallic
    MATERIALS[name] = mat
    return mat


def make_materials() -> None:
    # Verdes apagados y calidos: conserva la identidad sin el aspecto plastico
    # lavado del original. Los contrastes oscuros ayudan a leerlo a distancia.
    material("Raincoat", "#47794E", 0.72)
    material("RaincoatDark", "#285235", 0.76)
    material("RaincoatEdge", "#74A26F", 0.68)
    material("Trousers", "#285136", 0.78)
    material("BootRubber", "#111B1F", 0.55)
    material("BootEdge", "#070D0F", 0.50)
    material("Skin", "#D69D78", 0.76)
    material("SkinWarm", "#C88666", 0.78)
    material("BeardSurface", "#625C55", 0.94)
    material("Hat", "#3E7043", 0.78)
    material("HatDark", "#183923", 0.80)
    material("EyeWhite", "#F4F0DF", 0.62)
    material("Ink", "#1B2423", 0.72)
    material("Mouth", "#4B2522", 0.78)
    material("Button", "#E3C47A", 0.58, 0.08)


def register(obj: bpy.types.Object) -> bpy.types.Object:
    if obj not in ASSET_OBJECTS:
        ASSET_OBJECTS.append(obj)
    return obj


def assign_material(obj: bpy.types.Object, mat_name: str) -> None:
    obj.data.materials.append(MATERIALS[mat_name])


def smooth_mesh(obj: bpy.types.Object) -> None:
    for poly in obj.data.polygons:
        poly.use_smooth = True


def apply_modifier(obj: bpy.types.Object, modifier: bpy.types.Modifier) -> None:
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.select_set(False)


def bevel(obj: bpy.types.Object, width: float, segments: int = 2) -> None:
    mod = obj.modifiers.new("Soft bevel", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.limit_method = "ANGLE"
    apply_modifier(obj, mod)
    smooth_mesh(obj)


def subdivide_head_beard_surfaces(obj: bpy.types.Object, cuts: int) -> None:
    """Agrega resolucion solo donde la frontera de la barba necesita curvarse."""
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    for polygon in obj.data.polygons:
        normal = polygon.normal
        polygon.select = normal.y < -0.98 or abs(normal.x) > 0.98 or normal.z < -0.98
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.context.tool_settings.mesh_select_mode = (False, False, True)
    bpy.ops.mesh.subdivide(number_cuts=cuts, smoothness=0.0)
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.quads_convert_to_tris(quad_method="BEAUTY", ngon_method="BEAUTY")
    bpy.ops.object.mode_set(mode="OBJECT")
    obj.select_set(False)
    obj.data.update()


def assign_head_stubble(obj: bpy.types.Object) -> None:
    """Pinta barba corta sobre la propia topologia de HeadMesh."""
    obj.data.materials.append(MATERIALS["BeardSurface"])
    for polygon in obj.data.polygons:
        center = polygon.center
        side_ratio = min(1.0, abs(center.x) / 0.235)
        curved_ratio = side_ratio * side_ratio * (3.0 - 2.0 * side_ratio)
        beard_line = -0.135 + 0.045 * curved_ratio
        on_front = center.y < -0.110 and center.z < beard_line
        depth_ratio = min(1.0, max(0.0, (center.y + 0.135) / 0.270))
        side_line = -0.090 - 0.040 * depth_ratio
        on_jaw_side = abs(center.x) > 0.202 and center.z < side_line
        under_chin = center.z < -0.165 and center.y < 0.080
        if on_front or on_jaw_side or under_chin:
            polygon.material_index = 1


def rounded_cube(
    name: str,
    location: tuple[float, float, float],
    dimensions: tuple[float, float, float],
    mat_name: str,
    bevel_width: float,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    bevel(obj, bevel_width, 2)
    assign_material(obj, mat_name)
    return register(obj)


def low_sphere(
    name: str,
    location: tuple[float, float, float],
    dimensions: tuple[float, float, float],
    mat_name: str,
    segments: int = 16,
    rings: int = 8,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    smooth_mesh(obj)
    assign_material(obj, mat_name)
    return register(obj)


def soft_cylinder(
    name: str,
    location: tuple[float, float, float],
    radius: float,
    depth: float,
    mat_name: str,
    vertices: int = 16,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
    scale: tuple[float, float, float] = (1.0, 1.0, 1.0),
    bevel_width: float = 0.012,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    if bevel_width:
        bevel(obj, bevel_width, 2)
    else:
        smooth_mesh(obj)
    assign_material(obj, mat_name)
    return register(obj)


def soft_cone(
    name: str,
    location: tuple[float, float, float],
    radius_bottom: float,
    radius_top: float,
    depth: float,
    mat_name: str,
    vertices: int = 16,
    scale: tuple[float, float, float] = (1.0, 1.0, 1.0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices,
        radius1=radius_bottom,
        radius2=radius_top,
        depth=depth,
        location=location,
    )
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bevel(obj, 0.015, 2)
    assign_material(obj, mat_name)
    return register(obj)


def make_hat_brim() -> bpy.types.Object:
    """Ala ancha, asimetrica y levemente caida de sombrero de pescador."""
    count = 28
    mid_factor = 0.58
    top_center_z = 1.603
    thickness = 0.038
    vertices: list[tuple[float, float, float]] = []

    # Centros superior e inferior.
    vertices.append((0.0, 0.0, top_center_z))
    vertices.append((0.0, 0.0, top_center_z - thickness))

    def outline(angle: float, factor: float, bottom: bool = False):
        c, s = math.cos(angle), math.sin(angle)
        x = 0.465 * factor * c
        # El frente (-Y) se extiende un poco mas: menos fedora, mas pescador.
        front_extension = 0.030 * factor * max(0.0, -s)
        y = (0.330 * factor + front_extension) * s
        edge = factor ** 1.8
        front = max(0.0, -s)
        back = max(0.0, s)
        side = abs(c)
        z = top_center_z - edge * (0.028 * front + 0.010 * side - 0.004 * back)
        if bottom:
            z -= thickness
        return (x, y, z)

    # top-mid, top-outer, bottom-mid, bottom-outer
    for bottom in (False, True):
        for factor in (mid_factor, 1.0):
            for i in range(count):
                vertices.append(outline(math.tau * i / count, factor, bottom))

    top_mid = 2
    top_outer = top_mid + count
    bottom_mid = top_outer + count
    bottom_outer = bottom_mid + count
    faces: list[tuple[int, ...]] = []
    for i in range(count):
        j = (i + 1) % count
        faces.append((0, top_mid + i, top_mid + j))
        faces.append((top_mid + i, top_outer + i, top_outer + j, top_mid + j))
        faces.append((1, bottom_mid + j, bottom_mid + i))
        faces.append((bottom_mid + j, bottom_outer + j, bottom_outer + i, bottom_mid + i))
        faces.append((top_outer + i, bottom_outer + i, bottom_outer + j, top_outer + j))
    brim = mesh_object("HatBrim", vertices, faces, "Hat", smooth=True)
    brim.data.materials.append(MATERIALS["HatDark"])
    # La cara inferior y el borde ganan contraste sin sumar otra pieza flotante.
    for index, polygon in enumerate(brim.data.polygons):
        if index % 5 in {2, 3, 4}:
            polygon.material_index = 1
    return brim


def mesh_object(
    name: str,
    vertices: list[tuple[float, float, float]],
    faces: list[tuple[int, ...]],
    mat_name: str,
    smooth: bool = True,
) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(f"{name}Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update(calc_edges=True)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    assign_material(obj, mat_name)
    if smooth:
        smooth_mesh(obj)
    return register(obj)


def face_plate(
    name: str,
    location: tuple[float, float, float],
    half_width: float,
    half_height: float,
    thickness: float,
    mat_name: str,
    segments: int = 16,
    profile_power: float = 1.0,
) -> bpy.types.Object:
    """Placa facial fina; profile_power > 1 afila los extremos del ovalo."""
    boundary: list[tuple[float, float]] = []
    for i in range(segments):
        angle = math.tau * i / segments
        c, s = math.cos(angle), math.sin(angle)
        z = half_height * math.copysign(abs(s) ** profile_power, s)
        boundary.append((half_width * c, z))
    front_y, back_y = -thickness / 2.0, thickness / 2.0
    vertices = [(0.0, front_y, 0.0)] + [(x, front_y, z) for x, z in boundary]
    vertices += [(0.0, back_y, 0.0)] + [(x, back_y, z) for x, z in boundary]
    faces: list[tuple[int, ...]] = []
    front_center = 0
    back_center = segments + 1
    for i in range(segments):
        j = (i + 1) % segments
        faces.append((front_center, 1 + j, 1 + i))
        faces.append((back_center, back_center + 1 + i, back_center + 1 + j))
        faces.append((1 + i, 1 + j, back_center + 1 + j, back_center + 1 + i))
    obj = mesh_object(name, vertices, faces, mat_name)
    obj.location = location
    bpy.context.view_layer.update()
    return obj


def superellipse_ring(hx: float, hy: float, z: float, count: int = 20, power: float = 3.4):
    points = []
    exponent = 2.0 / power
    for i in range(count):
        angle = math.tau * i / count
        c, s = math.cos(angle), math.sin(angle)
        x = hx * math.copysign(abs(c) ** exponent, c)
        y = hy * math.copysign(abs(s) ** exponent, s)
        points.append((x, y, z))
    return points


def make_raincoat() -> bpy.types.Object:
    rings = [
        (0.345, 0.188, 0.52),
        (0.350, 0.190, 0.57),
        (0.330, 0.185, 0.72),
        (0.307, 0.178, 0.88),
        (0.286, 0.170, 1.02),
        (0.270, 0.162, 1.13),
        (0.252, 0.152, 1.17),
    ]
    count = 20
    vertices: list[tuple[float, float, float]] = []
    for hx, hy, z in rings:
        vertices.extend(superellipse_ring(hx, hy, z, count))
    faces: list[tuple[int, ...]] = []
    for ring in range(len(rings) - 1):
        base = ring * count
        nxt = (ring + 1) * count
        for i in range(count):
            j = (i + 1) % count
            faces.append((base + i, base + j, nxt + j, nxt + i))
    bottom_center = len(vertices)
    vertices.append((0.0, 0.0, rings[0][2]))
    top_center = len(vertices)
    vertices.append((0.0, 0.0, rings[-1][2]))
    for i in range(count):
        j = (i + 1) % count
        faces.append((bottom_center, j, i))
        top = (len(rings) - 1) * count
        faces.append((top_center, top + i, top + j))
    return mesh_object("RaincoatBody", vertices, faces, "Raincoat")


def make_tube_x(name: str, side: int) -> bpy.types.Object:
    # side=-1: derecha anatomica; side=+1: izquierda anatomica.
    xs = [0.225, 0.285, 0.355, 0.425, 0.485, 0.545, 0.605, 0.655]
    radii = [0.108, 0.111, 0.107, 0.102, 0.100, 0.096, 0.090, 0.083]
    ring_count = 12
    vertices: list[tuple[float, float, float]] = []
    for x, radius in zip(xs, radii):
        for i in range(ring_count):
            a = math.tau * i / ring_count
            vertices.append((side * x, radius * math.cos(a), 1.095 + radius * math.sin(a)))
    faces: list[tuple[int, ...]] = []
    for ring in range(len(xs) - 1):
        base = ring * ring_count
        nxt = (ring + 1) * ring_count
        for i in range(ring_count):
            j = (i + 1) % ring_count
            # Invierte el winding de un lado para mantener normales consistentes.
            quad = (base + i, base + j, nxt + j, nxt + i)
            faces.append(quad if side > 0 else tuple(reversed(quad)))
    for end, reverse in ((0, side > 0), ((len(xs) - 1) * ring_count, side < 0)):
        cap = tuple(end + i for i in range(ring_count))
        faces.append(tuple(reversed(cap)) if reverse else cap)
    return mesh_object(name, vertices, faces, "Raincoat")


def make_leg(name: str, x: float) -> bpy.types.Object:
    rings = [
        (0.132, 0.125, 0.60),
        (0.134, 0.126, 0.51),
        (0.125, 0.120, 0.41),
        (0.118, 0.113, 0.32),
        (0.112, 0.108, 0.25),
    ]
    count = 12
    vertices: list[tuple[float, float, float]] = []
    for hx, hy, z in rings:
        for i in range(count):
            a = math.tau * i / count
            vertices.append((x + hx * math.cos(a), hy * math.sin(a), z))
    faces: list[tuple[int, ...]] = []
    for ring in range(len(rings) - 1):
        for i in range(count):
            j = (i + 1) % count
            a = ring * count
            b = (ring + 1) * count
            faces.append((a + i, a + j, b + j, b + i))
    faces.append(tuple(reversed(tuple(range(count)))))
    top = (len(rings) - 1) * count
    faces.append(tuple(top + i for i in range(count)))
    return mesh_object(name, vertices, faces, "Trousers")


def create_armature() -> bpy.types.Object:
    global RIG
    armature = bpy.data.armatures.new("PescadorSmoothArmature")
    rig = bpy.data.objects.new("PescadorSmoothRig", armature)
    bpy.context.scene.collection.objects.link(rig)
    register(rig)
    rig.show_in_front = True
    rig["asset_version"] = "pescador_smooth_v1"
    rig["godot_forward"] = "+Z after glTF conversion"
    rig["facial_system"] = "Morph targets; facial gestures never rotate Head"
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")

    specs = {
        "Root": ((0, 0, 0.00), (0, 0, 0.10), None),
        "Hips": ((0, 0, 0.56), (0, 0, 0.70), "Root"),
        "Spine": ((0, 0, 0.68), (0, 0, 0.88), "Hips"),
        "Chest": ((0, 0, 0.86), (0, 0, 1.04), "Spine"),
        "UpperChest": ((0, 0, 1.02), (0, 0, 1.15), "Chest"),
        "Neck": ((0, 0, 1.14), (0, 0, 1.24), "UpperChest"),
        "Head": ((0, 0, 1.23), (0, 0, 1.55), "Neck"),
        "barba": ((0, -0.02, 1.37), (0, -0.02, 1.13), "Head"),
        "sombrero": ((0, 0, 1.56), (0, 0, 1.79), "Head"),
        "RightShoulder": ((-0.10, 0, 1.105), (-0.235, 0, 1.105), "UpperChest"),
        "RightUpperArm": ((-0.235, 0, 1.095), (-0.435, 0, 1.095), "RightShoulder"),
        "RightLowerArm": ((-0.435, 0, 1.095), (-0.625, 0, 1.095), "RightUpperArm"),
        "RightHand": ((-0.625, 0, 1.095), (-0.765, 0, 1.095), "RightLowerArm"),
        "LeftShoulder": ((0.10, 0, 1.105), (0.235, 0, 1.105), "UpperChest"),
        "LeftUpperArm": ((0.235, 0, 1.095), (0.435, 0, 1.095), "LeftShoulder"),
        "LeftLowerArm": ((0.435, 0, 1.095), (0.625, 0, 1.095), "LeftUpperArm"),
        "LeftHand": ((0.625, 0, 1.095), (0.765, 0, 1.095), "LeftLowerArm"),
        "RightUpperLeg": ((-0.155, 0, 0.59), (-0.155, 0, 0.395), "Hips"),
        "RightLowerLeg": ((-0.155, 0, 0.395), (-0.155, 0, 0.165), "RightUpperLeg"),
        "RightFoot": ((-0.155, 0, 0.165), (-0.155, -0.185, 0.135), "RightLowerLeg"),
        "LeftUpperLeg": ((0.155, 0, 0.59), (0.155, 0, 0.395), "Hips"),
        "LeftLowerLeg": ((0.155, 0, 0.395), (0.155, 0, 0.165), "LeftUpperLeg"),
        "LeftFoot": ((0.155, 0, 0.165), (0.155, -0.185, 0.135), "LeftLowerLeg"),
    }
    bones = {}
    for name, (head, tail, _parent) in specs.items():
        bone = armature.edit_bones.new(name)
        bone.head = head
        bone.tail = tail
        bone.use_deform = name not in {"Root"}
        bones[name] = bone
    for name, (_head, _tail, parent_name) in specs.items():
        if parent_name:
            bones[name].parent = bones[parent_name]
    bpy.ops.object.mode_set(mode="OBJECT")
    rig.select_set(False)
    RIG = rig
    return rig


def normalized(weights: dict[str, float]) -> dict[str, float]:
    clean = {name: max(0.0, value) for name, value in weights.items() if value > 1e-6}
    total = sum(clean.values())
    return {name: value / total for name, value in clean.items()}


def blend(a: str, b: str, t: float) -> dict[str, float]:
    t = min(1.0, max(0.0, t))
    return normalized({a: 1.0 - t, b: t})


def skin_object(
    obj: bpy.types.Object,
    weight_function: Callable[[Vector], dict[str, float]],
) -> None:
    assert RIG is not None
    world = obj.matrix_world.copy()
    obj.parent = RIG
    obj.matrix_world = world
    modifier = obj.modifiers.new("Smooth humanoid skin", "ARMATURE")
    modifier.object = RIG
    modifier.use_deform_preserve_volume = True
    used_groups: dict[str, bpy.types.VertexGroup] = {}
    for vertex in obj.data.vertices:
        world_co = obj.matrix_world @ vertex.co
        weights = normalized(weight_function(world_co))
        if not weights:
            raise RuntimeError(f"Vertice sin peso en {obj.name}: {vertex.index}")
        for bone_name, value in weights.items():
            group = used_groups.get(bone_name)
            if group is None:
                group = obj.vertex_groups.get(bone_name) or obj.vertex_groups.new(name=bone_name)
                used_groups[bone_name] = group
            group.add([vertex.index], value, "REPLACE")
    SKINNED_OBJECTS.append(obj)


def constant_weight(bone_name: str):
    return lambda _co: {bone_name: 1.0}


def coat_weights(co: Vector) -> dict[str, float]:
    z = co.z
    if z <= 0.62:
        return {"Hips": 1.0}
    if z < 0.78:
        return blend("Hips", "Spine", (z - 0.62) / 0.16)
    if z < 0.96:
        return blend("Spine", "Chest", (z - 0.78) / 0.18)
    return blend("Chest", "UpperChest", (z - 0.96) / 0.21)


def arm_weights(co: Vector) -> dict[str, float]:
    s = abs(co.x)
    prefix = "Right" if co.x < 0 else "Left"
    if s < 0.37:
        return {f"{prefix}UpperArm": 1.0}
    if s < 0.49:
        return blend(f"{prefix}UpperArm", f"{prefix}LowerArm", (s - 0.37) / 0.12)
    if s < 0.58:
        return {f"{prefix}LowerArm": 1.0}
    return blend(f"{prefix}LowerArm", f"{prefix}Hand", (s - 0.58) / 0.10)


def leg_weights(side_name: str):
    def chooser(co: Vector) -> dict[str, float]:
        if co.z > 0.45:
            return {f"{side_name}UpperLeg": 1.0}
        if co.z > 0.34:
            return blend(
                f"{side_name}LowerLeg",
                f"{side_name}UpperLeg",
                (co.z - 0.34) / 0.11,
            )
        return {f"{side_name}LowerLeg": 1.0}

    return chooser


def add_basis_and_shape(obj: bpy.types.Object, name: str, transform) -> bpy.types.ShapeKey:
    if obj.data.shape_keys is None:
        obj.shape_key_add(name="Basis")
    key = obj.shape_key_add(name=name)
    for index, point in enumerate(key.data):
        point.co = transform(obj.data.vertices[index].co.copy())
    key.value = 0.0
    return key


def add_eye_shapes(obj: bpy.types.Object, blink_name: str) -> None:
    add_basis_and_shape(
        obj,
        blink_name,
        lambda co: Vector((co.x, co.y, co.z * 0.08)),
    )


def add_pupil_shapes(obj: bpy.types.Object, blink_name: str) -> None:
    for name, dx, dz in (
        ("look_left", 0.013, 0.0),
        ("look_right", -0.013, 0.0),
        ("look_up", 0.0, 0.010),
        ("look_down", 0.0, -0.009),
    ):
        add_basis_and_shape(obj, name, lambda co, dx=dx, dz=dz: Vector((co.x + dx, co.y, co.z + dz)))
    add_basis_and_shape(obj, blink_name, lambda co: Vector((co.x, co.y, co.z * 0.06)))


def add_brow_shapes(obj: bpy.types.Object, anatomical_side: str) -> None:
    inner_sign = -1.0 if anatomical_side == "L" else 1.0

    def tense(co: Vector) -> Vector:
        inner = max(0.0, min(1.0, inner_sign * co.x / 0.075 + 0.5))
        co.z += 0.010 - 0.034 * inner
        return co

    def effort(co: Vector) -> Vector:
        inner = max(0.0, min(1.0, inner_sign * co.x / 0.075 + 0.5))
        co.z += 0.025 + 0.010 * inner
        return co

    add_basis_and_shape(obj, "tense", tense)
    add_basis_and_shape(obj, "effort", effort)


def make_mouth() -> bpy.types.Object:
    # El MeshInstance no se llama `Mouth` a proposito. Godot hornea los
    # vertices skineados en coordenadas del modelo y deja el nodo con origen
    # (0, 0, 0); PlayerFaceAnimator reserva el alias `Mouth` para su fallback
    # transform-based y escalaria esta malla alrededor del origen global. El
    # alias estable se exporta como Empty y esta malla usa solo sus morphs.
    basis_width = 0.056
    basis_height = 0.0045
    mouth = face_plate(
        "FaceMouthMesh",
        (0.0, -0.179, 1.292),
        basis_width,
        basis_height,
        0.005,
        "Mouth",
        16,
        1.20,
    )

    def morph(co: Vector, style: str) -> Vector:
        if abs(co.x) < 1e-7 and abs(co.z) < 1e-7:
            return co
        angle = math.atan2(co.z / basis_height, co.x / basis_width)
        c, s = math.cos(angle), math.sin(angle)
        if style == "smile":
            x = 0.058 * c
            z = 0.0045 * s + 0.015 * (abs(c) ** 1.7) - 0.006
        elif style == "tense":
            x = 0.063 * c
            z = 0.0035 * math.copysign(abs(s) ** 1.2, s)
        elif style == "talk":
            x = 0.026 * c
            z = 0.011 * s
        else:  # effort
            x = 0.049 * c
            z = 0.007 * math.copysign(abs(s) ** 1.1, s) - 0.004 * c
        return Vector((x, co.y, z))

    for style in ("smile", "tense", "talk", "effort"):
        add_basis_and_shape(mouth, style, lambda co, style=style: morph(co, style))
    return mouth


def create_face() -> None:
    assert RIG is not None
    # Nodos estables para el controlador facial. FaceEyes es ademas un punto
    # de busqueda semantico aunque las piezas reales estan skineadas a Head.
    controls = bpy.data.objects.new("FaceControls", None)
    bpy.context.scene.collection.objects.link(controls)
    register(controls)
    controls["channels"] = "blink_L blink_R look_left look_right look_up look_down smile tense talk effort"
    face_eyes = bpy.data.objects.new("FaceEyes", None)
    bpy.context.scene.collection.objects.link(face_eyes)
    face_eyes.parent = controls
    register(face_eyes)

    mouth_alias = bpy.data.objects.new("Mouth", None)
    bpy.context.scene.collection.objects.link(mouth_alias)
    mouth_alias.parent = controls
    mouth_alias["morph_mesh"] = "FaceMouthMesh"
    register(mouth_alias)

    eye_specs = {
        "Eye_R": (-0.095, "blink_R", "R"),
        "Eye_L": (0.095, "blink_L", "L"),
    }
    for name, (x, blink_name, side) in eye_specs.items():
        eye = face_plate(name, (x, -0.177, 1.435), 0.047, 0.021, 0.006, "EyeWhite", 16, 1.35)
        add_eye_shapes(eye, blink_name)
        skin_object(eye, constant_weight("Head"))
        FACE_OBJECTS[name] = eye

        pupil_name = f"Pupil_{side}"
        pupil = face_plate(pupil_name, (x, -0.184, 1.435), 0.0085, 0.011, 0.004, "Ink", 12, 1.0)
        add_pupil_shapes(pupil, blink_name)
        skin_object(pupil, constant_weight("Head"))
        FACE_OBJECTS[pupil_name] = pupil

        brow_name = f"Brow_{side}"
        brow = rounded_cube(
            brow_name,
            (x, -0.181, 1.495),
            (0.130, 0.012, 0.018),
            "Ink",
            0.005,
            rotation=(0.0, math.radians(3.0 if side == "L" else -3.0), 0.0),
        )
        add_brow_shapes(brow, side)
        skin_object(brow, constant_weight("Head"))
        FACE_OBJECTS[brow_name] = brow

    mouth = make_mouth()
    skin_object(mouth, constant_weight("Head"))
    FACE_OBJECTS["Mouth"] = mouth


def build_character() -> None:
    create_armature()

    raincoat = make_raincoat()
    skin_object(raincoat, coat_weights)

    # Cuello y cuello del impermeable ocultan cualquier costura en los hombros.
    neck = soft_cylinder("NeckMesh", (0, 0, 1.175), 0.105, 0.12, "Skin", 16, bevel_width=0.014)
    skin_object(neck, constant_weight("Neck"))
    bpy.ops.mesh.primitive_torus_add(
        major_radius=0.155,
        minor_radius=0.027,
        major_segments=20,
        minor_segments=6,
        location=(0, 0, 1.145),
    )
    collar = bpy.context.object
    collar.name = "RaincoatCollar"
    collar.scale.y = 0.78
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    smooth_mesh(collar)
    assign_material(collar, "RaincoatDark")
    register(collar)
    skin_object(collar, constant_weight("UpperChest"))

    for side, suffix in ((-1, "R"), (1, "L")):
        arm = make_tube_x(f"Arm_{suffix}", side)
        skin_object(arm, arm_weights)

        cuff_x = side * 0.625
        cuff = soft_cylinder(
            f"Cuff_{suffix}",
            (cuff_x, 0, 1.095),
            0.095,
            0.070,
            "RaincoatDark",
            16,
            rotation=(0, math.radians(90), 0),
            scale=(1.0, 1.0, 1.0),
            bevel_width=0.012,
        )
        skin_object(cuff, arm_weights)

        # Nombres historicos conservados para player.gd: _L vive en -X y es
        # la mano derecha anatomica, como en el pescador original.
        hand_name = "palma_L" if side < 0 else "palma_R"
        hand_bone = "RightHand" if side < 0 else "LeftHand"
        hand = low_sphere(hand_name, (side * 0.735, -0.004, 1.095), (0.188, 0.170, 0.190), "Skin", 16, 8)
        skin_object(hand, constant_weight(hand_bone))
        thumb = low_sphere(
            f"Thumb_{suffix}",
            (side * 0.715, -0.078, 1.065),
            (0.085, 0.080, 0.095),
            "SkinWarm",
            12,
            6,
        )
        skin_object(thumb, constant_weight(hand_bone))

    right_leg = make_leg("Leg_R", -0.155)
    skin_object(right_leg, leg_weights("Right"))
    left_leg = make_leg("Leg_L", 0.155)
    skin_object(left_leg, leg_weights("Left"))

    for x, side_name, suffix in ((-0.155, "Right", "R"), (0.155, "Left", "L")):
        shaft = rounded_cube(
            f"BootShaft_{suffix}",
            (x, 0.010, 0.235),
            (0.248, 0.245, 0.265),
            "BootRubber",
            0.040,
        )
        skin_object(shaft, constant_weight(f"{side_name}LowerLeg"))
        rim = soft_cylinder(
            f"BootRim_{suffix}",
            (x, 0.005, 0.345),
            0.132,
            0.050,
            "BootEdge",
            16,
            scale=(1.0, 0.92, 1.0),
            bevel_width=0.012,
        )
        skin_object(rim, constant_weight(f"{side_name}LowerLeg"))
        foot = rounded_cube(
            f"BootFoot_{suffix}",
            (x, -0.075, 0.105),
            (0.255, 0.365, 0.185),
            "BootRubber",
            0.045,
        )
        skin_object(foot, constant_weight(f"{side_name}Foot"))
        sole = rounded_cube(
            f"BootSole_{suffix}",
            (x, -0.080, 0.025),
            (0.270, 0.385, 0.045),
            "BootEdge",
            0.015,
        )
        skin_object(sole, constant_weight(f"{side_name}Foot"))

    head = rounded_cube("HeadMesh", (0, 0, 1.395), (0.475, 0.345, 0.415), "Skin", 0.080)
    subdivide_head_beard_surfaces(head, 23)
    assign_head_stubble(head)
    skin_object(head, constant_weight("Head"))
    for x, suffix in ((-0.245, "R"), (0.245, "L")):
        ear = low_sphere(f"Ear_{suffix}", (x, -0.002, 1.390), (0.078, 0.060, 0.115), "SkinWarm", 12, 6)
        skin_object(ear, constant_weight("Head"))
    nose = low_sphere("Nose", (0, -0.205, 1.365), (0.095, 0.080, 0.115), "SkinWarm", 12, 6)
    skin_object(nose, constant_weight("Head"))

    brim = make_hat_brim()
    skin_object(brim, constant_weight("sombrero"))
    crown = soft_cone("HatCrown", (0, 0.025, 1.735), 0.300, 0.215, 0.260, "Hat", 20, (1.0, 0.78, 1.0))
    skin_object(crown, constant_weight("sombrero"))
    band = soft_cylinder(
        "HatBand",
        (0, 0.020, 1.630),
        0.288,
        0.055,
        "HatDark",
        20,
        scale=(1.0, 0.78, 1.0),
        bevel_width=0.008,
    )
    skin_object(band, constant_weight("sombrero"))

    for index, z in enumerate((0.935, 0.785, 0.635), 1):
        button = soft_cylinder(
            f"Button_{index}",
            (0, -0.187, z),
            0.027,
            0.020,
            "Button",
            12,
            rotation=(math.radians(90), 0, 0),
            bevel_width=0.006,
        )
        skin_object(button, coat_weights)

    create_face()


def add_shape_animation(
    obj_name: str,
    clip_name: str,
    channels: dict[str, list[tuple[int, float]]],
) -> None:
    obj = FACE_OBJECTS[obj_name]
    keys = obj.data.shape_keys
    if keys is None:
        raise RuntimeError(f"{obj_name} no tiene shape keys")
    keys.animation_data_create()
    action = bpy.data.actions.new(f"{clip_name}__{obj_name}")
    action.use_fake_user = True
    keys.animation_data.action = action
    for channel_name, keyframes in channels.items():
        block = keys.key_blocks[channel_name]
        for frame, value in keyframes:
            block.value = value
            block.keyframe_insert(data_path="value", frame=frame, group="Face")
    keys.animation_data.action = None
    track = keys.animation_data.nla_tracks.new()
    track.name = clip_name
    track.strips.new(clip_name, min(frame for frames in channels.values() for frame, _ in frames), action)


def create_face_animations() -> None:
    add_shape_animation("Eye_L", "Face_Blink", {"blink_L": [(1, 0), (4, 1), (7, 0)]})
    add_shape_animation("Eye_R", "Face_Blink", {"blink_R": [(1, 0), (4, 1), (7, 0)]})
    add_shape_animation("Pupil_L", "Face_Blink", {"blink_L": [(1, 0), (4, 1), (7, 0)]})
    add_shape_animation("Pupil_R", "Face_Blink", {"blink_R": [(1, 0), (4, 1), (7, 0)]})

    add_shape_animation("Mouth", "Face_Smile", {"smile": [(1, 0), (6, 1), (24, 1), (30, 0)]})
    add_shape_animation("Mouth", "Face_Talk", {"talk": [(1, 0), (4, 1), (8, 0.15), (12, 0.8), (16, 0), (20, 1), (24, 0)]})
    add_shape_animation("Mouth", "Face_Tense", {"tense": [(1, 0), (6, 1), (24, 1), (30, 0)]})
    add_shape_animation("Brow_L", "Face_Tense", {"tense": [(1, 0), (6, 1), (24, 1), (30, 0)]})
    add_shape_animation("Brow_R", "Face_Tense", {"tense": [(1, 0), (6, 1), (24, 1), (30, 0)]})
    add_shape_animation("Mouth", "Face_Effort", {"effort": [(1, 0), (5, 1), (20, 1), (26, 0)]})
    add_shape_animation("Brow_L", "Face_Effort", {"effort": [(1, 0), (5, 1), (20, 1), (26, 0)]})
    add_shape_animation("Brow_R", "Face_Effort", {"effort": [(1, 0), (5, 0.72), (20, 0.72), (26, 0)]})

    look_cycle = {
        "look_left": [(1, 0), (6, 1), (11, 0)],
        "look_right": [(11, 0), (16, 1), (21, 0)],
        "look_up": [(21, 0), (26, 1), (31, 0)],
        "look_down": [(31, 0), (36, 1), (41, 0)],
    }
    add_shape_animation("Pupil_L", "Face_Look", look_cycle)
    add_shape_animation("Pupil_R", "Face_Look", look_cycle)


def zero_face() -> None:
    for obj in FACE_OBJECTS.values():
        keys = obj.data.shape_keys
        if keys:
            for block in keys.key_blocks:
                if block.name != "Basis":
                    block.value = 0.0
    bpy.context.scene.frame_set(1)


def set_face(values: dict[tuple[str, str], float]) -> None:
    zero_face()
    for (obj_name, shape_name), value in values.items():
        FACE_OBJECTS[obj_name].data.shape_keys.key_blocks[shape_name].value = value
    bpy.context.view_layer.update()


def point_camera(camera: bpy.types.Object, target: tuple[float, float, float]) -> None:
    direction = Vector(target) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def render_qa() -> list[str]:
    os.makedirs(QA_DIR, exist_ok=True)
    scene = bpy.context.scene
    # En Blender 5.1 Eevee vuelve a exponerse como BLENDER_EEVEE.
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 640
    scene.render.resolution_y = 640
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.world.color = (0.025, 0.032, 0.035)
    scene.view_settings.look = "AgX - Medium High Contrast"

    bpy.ops.object.camera_add(location=(0, -4.5, 1.05))
    camera = bpy.context.object
    camera.name = "QA_Camera"
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 2.15
    scene.camera = camera

    def area(name, location, energy, size, color):
        data = bpy.data.lights.new(name, "AREA")
        data.energy = energy
        data.shape = "DISK"
        data.size = size
        data.color = color
        obj = bpy.data.objects.new(name, data)
        scene.collection.objects.link(obj)
        obj.location = location
        point_camera(obj, (0, 0, 1.0))
        return obj

    qa_objects = [camera]
    qa_objects.append(area("QA_Key", (-2.3, -3.5, 3.5), 720, 4.0, (1.0, 0.82, 0.68)))
    qa_objects.append(area("QA_Fill", (2.6, -1.8, 2.4), 520, 3.5, (0.62, 0.80, 1.0)))
    qa_objects.append(area("QA_Rim", (0.5, 2.0, 3.3), 820, 3.0, (0.62, 1.0, 0.78)))

    bpy.ops.mesh.primitive_plane_add(size=8, location=(0, 0, -0.006))
    floor = bpy.context.object
    floor.name = "QA_Floor"
    floor_mat = material("QA_FloorMat", "#172023", 0.92)
    floor.data.materials.append(floor_mat)
    qa_objects.append(floor)

    outputs: list[str] = []

    def render(name, location, target, ortho=2.15):
        camera.location = location
        camera.data.ortho_scale = ortho
        point_camera(camera, target)
        path = os.path.join(QA_DIR, f"{name}.png")
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        outputs.append(path)

    set_face({})
    render("01_front", (0, -4.5, 1.05), (0, 0, 0.95))
    render("02_side", (-4.5, 0, 1.05), (0, 0, 0.95))
    render("03_three_quarter", (-3.1, -3.1, 1.15), (0, 0, 0.98))
    render("04_head_close", (0, -3.6, 1.43), (0, 0, 1.43), 0.78)

    expression_settings = {
        "05_smile": {("Mouth", "smile"): 1.0},
        "06_talk": {("Mouth", "talk"): 1.0},
        "07_effort": {("Mouth", "effort"): 1.0, ("Brow_L", "effort"): 1.0, ("Brow_R", "effort"): 0.72},
        "08_tense": {("Mouth", "tense"): 1.0, ("Brow_L", "tense"): 1.0, ("Brow_R", "tense"): 1.0},
        "09_blink": {
            ("Eye_L", "blink_L"): 1.0,
            ("Eye_R", "blink_R"): 1.0,
            ("Pupil_L", "blink_L"): 1.0,
            ("Pupil_R", "blink_R"): 1.0,
        },
        "10_look_left": {("Pupil_L", "look_left"): 1.0, ("Pupil_R", "look_left"): 1.0},
    }
    for name, settings in expression_settings.items():
        set_face(settings)
        render(name, (0, -3.6, 1.43), (0, 0, 1.43), 0.78)
    zero_face()

    # Prueba explicita del skin: hombros, codos, cadera, rodilla y tobillo
    # flexionados. No se guarda como clip ni llega al GLB.
    assert RIG is not None
    pose_values = {
        "RightUpperArm": (-34, 0, 7),
        "LeftUpperArm": (-34, 0, -7),
        "RightLowerArm": (-48, 0, 0),
        "LeftLowerArm": (-48, 0, 0),
        "RightHand": (12, 0, 0),
        "LeftHand": (12, 0, 0),
        "RightUpperLeg": (18, 0, 0),
        "RightLowerLeg": (-32, 0, 0),
        "RightFoot": (13, 0, 0),
        "LeftUpperLeg": (-8, 0, 0),
    }
    for bone_name, degrees in pose_values.items():
        pose_bone = RIG.pose.bones[bone_name]
        pose_bone.rotation_mode = "XYZ"
        pose_bone.rotation_euler = tuple(math.radians(value) for value in degrees)
    bpy.context.view_layer.update()
    render("11_joint_pose", (-3.1, -3.1, 1.15), (0, 0, 0.95))
    for pose_bone in RIG.pose.bones:
        pose_bone.matrix_basis.identity()
    bpy.context.view_layer.update()

    for obj in qa_objects:
        bpy.data.objects.remove(obj, do_unlink=True)
    if floor_mat.users == 0:
        bpy.data.materials.remove(floor_mat)
        MATERIALS.pop("QA_FloorMat", None)
    return outputs


def validate_before_export() -> dict[str, object]:
    armatures = [obj for obj in ASSET_OBJECTS if obj.type == "ARMATURE"]
    if len(armatures) != 1:
        raise RuntimeError(f"Se esperaba un armature; hay {len(armatures)}")
    required_bones = {
        "Root", "Hips", "Spine", "Chest", "UpperChest", "Neck", "Head",
        "RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
        "LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
        "RightUpperLeg", "RightLowerLeg", "RightFoot",
        "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
    }
    present_bones = set(armatures[0].data.bones.keys())
    missing = required_bones - present_bones
    if missing:
        raise RuntimeError(f"Faltan huesos humanoides: {sorted(missing)}")
    object_names = {obj.name for obj in ASSET_OBJECTS}
    for required_name in ("palma_R", "palma_L", "FaceEyes", "Eye_L", "Eye_R", "Pupil_L", "Pupil_R", "Brow_L", "Brow_R", "Mouth"):
        if required_name not in object_names:
            raise RuntimeError(f"Falta nodo estable: {required_name}")
    if "Beard" in object_names:
        raise RuntimeError("La barba volumetrica no debe existir")
    head = next(obj for obj in ASSET_OBJECTS if obj.name == "HeadMesh")
    beard_polygons = sum(1 for polygon in head.data.polygons if polygon.material_index == 1)
    if len(head.data.materials) < 2 or beard_polygons == 0:
        raise RuntimeError("HeadMesh no contiene la barba gris superficial")
    expected_shapes = {
        "Eye_L": {"blink_L"},
        "Eye_R": {"blink_R"},
        "Pupil_L": {"blink_L", "look_left", "look_right", "look_up", "look_down"},
        "Pupil_R": {"blink_R", "look_left", "look_right", "look_up", "look_down"},
        "Brow_L": {"tense", "effort"},
        "Brow_R": {"tense", "effort"},
        "Mouth": {"smile", "tense", "talk", "effort"},
    }
    for obj_name, expected in expected_shapes.items():
        keys = FACE_OBJECTS[obj_name].data.shape_keys
        actual = set(keys.key_blocks.keys()) - {"Basis"}
        if not expected.issubset(actual):
            raise RuntimeError(f"Morphs incompletos en {obj_name}: {sorted(expected - actual)}")
    for obj in SKINNED_OBJECTS:
        for vertex in obj.data.vertices:
            total = sum(group.weight for group in vertex.groups)
            if total < 0.999 or total > 1.001:
                raise RuntimeError(f"Pesos no normalizados: {obj.name}[{vertex.index}]={total}")
    mesh_objects = [obj for obj in ASSET_OBJECTS if obj.type == "MESH"]
    triangles = sum(sum(len(poly.vertices) - 2 for poly in obj.data.polygons) for obj in mesh_objects)
    vertices = sum(len(obj.data.vertices) for obj in mesh_objects)
    return {
        "armatures": 1,
        "bones": len(present_bones),
        "mesh_objects": len(mesh_objects),
        "vertices": vertices,
        "triangles": triangles,
        "skinned_meshes": len(SKINNED_OBJECTS),
        "facial_nodes": sorted(FACE_OBJECTS),
    }


def select_asset() -> None:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in ASSET_OBJECTS:
        if obj.name in bpy.context.scene.objects:
            obj.select_set(True)
    assert RIG is not None
    bpy.context.view_layer.objects.active = RIG


def export_glb() -> None:
    os.makedirs(os.path.dirname(GLB_PATH), exist_ok=True)
    select_asset()
    result = bpy.ops.export_scene.gltf(
        filepath=GLB_PATH,
        check_existing=False,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=False,
        export_extras=True,
        export_cameras=False,
        export_lights=False,
        export_materials="EXPORT",
        export_skins=True,
        export_all_influences=False,
        export_influence_nb=4,
        export_def_bones=True,
        export_leaf_bone=False,
        export_armature_object_remove=False,
        export_morph=True,
        export_morph_normal=False,
        export_morph_tangent=False,
        export_morph_animation=True,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_nla_strips=True,
        export_merge_animation="NLA_TRACK",
        export_force_sampling=False,
        export_frame_range=False,
        export_optimize_animation_size=True,
    )
    if "FINISHED" not in result:
        raise RuntimeError(f"Fallo export glTF: {result}")


def glb_manifest() -> dict[str, object]:
    raw = open(GLB_PATH, "rb").read()
    magic, version, _length = struct.unpack("<III", raw[:12])
    if magic != 0x46546C67 or version != 2:
        raise RuntimeError("El resultado no es GLB v2")
    chunk_length, chunk_type = struct.unpack("<II", raw[12:20])
    if chunk_type != 0x4E4F534A:
        raise RuntimeError("Primer chunk GLB no es JSON")
    gltf = json.loads(raw[20 : 20 + chunk_length].decode("utf-8"))
    skins = gltf.get("skins", [])
    if len(skins) != 1:
        raise RuntimeError(f"El GLB debe tener un skin; tiene {len(skins)}")
    animations = [anim.get("name", "") for anim in gltf.get("animations", [])]
    required_clips = {"Face_Blink", "Face_Smile", "Face_Talk", "Face_Tense", "Face_Effort", "Face_Look"}
    missing_clips = required_clips - set(animations)
    if missing_clips:
        raise RuntimeError(f"Faltan clips faciales exportados: {sorted(missing_clips)}; hay {animations}")
    node_names = {node.get("name") for node in gltf.get("nodes", [])}
    required_nodes = {"palma_R", "palma_L", "FaceEyes", "Mouth", "FaceMouthMesh"}
    if not required_nodes.issubset(node_names):
        raise RuntimeError(f"Faltan nodos GLB: {sorted(required_nodes - node_names)}")
    required_bones = {
        "Root", "Hips", "Spine", "Chest", "UpperChest", "Neck", "Head",
        "RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
        "LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
        "RightUpperLeg", "RightLowerLeg", "RightFoot",
        "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
    }
    if not required_bones.issubset(node_names):
        raise RuntimeError(f"Faltan huesos nombrados en GLB: {sorted(required_bones - node_names)}")
    morph_targets: set[str] = set()
    for mesh in gltf.get("meshes", []):
        morph_targets.update(mesh.get("extras", {}).get("targetNames", []))
    required_morphs = {
        "blink_L", "blink_R", "look_left", "look_right", "look_up", "look_down",
        "smile", "tense", "talk", "effort",
    }
    if not required_morphs.issubset(morph_targets):
        raise RuntimeError(f"Faltan morph targets GLB: {sorted(required_morphs - morph_targets)}")
    return {
        "bytes": len(raw),
        "nodes": len(gltf.get("nodes", [])),
        "meshes": len(gltf.get("meshes", [])),
        "skins": len(skins),
        "joints": len(skins[0].get("joints", [])),
        "animations": animations,
        "morph_targets": sorted(morph_targets),
    }


def mute_nla_for_clean_blend() -> None:
    for obj in FACE_OBJECTS.values():
        keys = obj.data.shape_keys
        if keys and keys.animation_data:
            for track in keys.animation_data.nla_tracks:
                track.mute = True
    zero_face()


def save_blend() -> None:
    os.makedirs(os.path.dirname(BLEND_PATH), exist_ok=True)
    bpy.context.scene.tool_settings.transform_pivot_point = "MEDIAN_POINT"
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = 41
    bpy.context.scene.render.fps = 30
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH, check_existing=False)


def main() -> None:
    clean_scene()
    make_materials()
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    build_character()
    stats = validate_before_export()
    qa_files = render_qa()
    create_face_animations()
    export_glb()
    exported = glb_manifest()
    mute_nla_for_clean_blend()
    save_blend()
    print("PESCADOR_SMOOTH_BUILD_OK")
    print("BLEND=" + BLEND_PATH)
    print("GLB=" + GLB_PATH)
    print("QA_DIR=" + QA_DIR)
    print("STATS=" + json.dumps(stats, sort_keys=True))
    print("GLB_MANIFEST=" + json.dumps(exported, sort_keys=True))
    print("QA_FILES=" + json.dumps(qa_files))


if __name__ == "__main__":
    main()
