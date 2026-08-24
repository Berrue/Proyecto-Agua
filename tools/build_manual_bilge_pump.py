"""Genera la bomba de achique manual modular de Proyecto Agua.

Uso:
    blender --background --factory-startup --python tools/build_manual_bilge_pump.py

El activo queda deliberadamente separado del barco. Blender conserva las piezas
visuales editables y Godot podra instanciar/animar la palanca, la aguja y el
cabezal de aspiracion sin volver a modelar la bomba.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BLEND = REPO_ROOT / "source_assets" / "boat" / "equipment" / "manual_bilge_pump.blend"
DEFAULT_GLB = REPO_ROOT / "game" / "boat" / "equipment" / "models" / "manual_bilge_pump.glb"
DEFAULT_PREVIEW = REPO_ROOT / "docs" / "images" / "manual_bilge_pump_preview.png"


def parse_outputs() -> tuple[Path, Path, Path]:
    values = {
        "--blend-output": DEFAULT_BLEND,
        "--glb-output": DEFAULT_GLB,
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
    return values["--blend-output"], values["--glb-output"], values["--preview-output"]


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)


def material(name: str, rgba: tuple[float, float, float, float], roughness: float, metallic: float = 0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = rgba
    mat.use_nodes = True
    principled = mat.node_tree.nodes.get("Principled BSDF")
    principled.inputs["Base Color"].default_value = rgba
    principled.inputs["Roughness"].default_value = roughness
    principled.inputs["Metallic"].default_value = metallic
    return mat


def add_bevel(obj: bpy.types.Object, width: float, segments: int = 1) -> None:
    modifier = obj.modifiers.new("EdgeSoftening", "BEVEL")
    modifier.width = width
    modifier.segments = segments


def make_box(
    name: str,
    location: tuple[float, float, float],
    dimensions: tuple[float, float, float],
    mat,
    bevel: float = 0.0,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    if bevel > 0.0:
        add_bevel(obj, bevel)
    return obj


def make_cylinder(
    name: str,
    location: tuple[float, float, float],
    radius: float,
    depth: float,
    mat,
    vertices: int = 12,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
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
    obj.data.materials.append(mat)
    return obj


def make_torus(
    name: str,
    location: tuple[float, float, float],
    major_radius: float,
    minor_radius: float,
    mat,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
    major_segments: int = 16,
    minor_segments: int = 6,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_torus_add(
        major_segments=major_segments,
        minor_segments=minor_segments,
        major_radius=major_radius,
        minor_radius=minor_radius,
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    return obj


def make_box_between(
    name: str,
    start: tuple[float, float, float],
    end: tuple[float, float, float],
    thickness: float,
    mat,
    bevel: float = 0.0,
) -> bpy.types.Object:
    a = Vector(start)
    b = Vector(end)
    delta = b - a
    obj = make_box(name, tuple((a + b) * 0.5), (thickness, delta.length, thickness), mat, bevel)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = delta.to_track_quat("Y", "Z")
    return obj


def set_origin(obj: bpy.types.Object, location: tuple[float, float, float]) -> None:
    bpy.context.scene.cursor.location = location
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR", center="MEDIAN")


def join_objects(name: str, objects: list[bpy.types.Object]) -> bpy.types.Object:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    objects[0].name = name
    return objects[0]


def make_marker(name: str, location: tuple[float, float, float], role: str) -> bpy.types.Object:
    marker = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(marker)
    marker.location = location
    marker.empty_display_type = "ARROWS"
    marker.empty_display_size = 0.065
    marker["role"] = role
    return marker


def build_asset() -> list[bpy.types.Object]:
    # La referencia es la bomba de la nave medieval de Newport: tubo, base y
    # lanza de madera, valvulas de cuero y strum box de cesteria. La manguera
    # movil es una licencia jugable, pero se expresa con cuero, canamo y brea.
    elm = material("M_Elm_Adzed", (0.24, 0.105, 0.030, 1.0), 0.88)
    dark_oak = material("M_Oak_Dark", (0.145, 0.052, 0.014, 1.0), 0.92)
    ash = material("M_Ash_Lever", (0.46, 0.245, 0.070, 1.0), 0.84)
    forged_iron = material("M_Forged_Iron", (0.025, 0.033, 0.037, 1.0), 0.82, 0.58)
    leather = material("M_Tarred_Leather", (0.105, 0.026, 0.012, 1.0), 0.86)
    worn_leather = material("M_Worn_Leather", (0.052, 0.009, 0.004, 1.0), 0.94)
    hemp = material("M_Hemp_Rope", (0.43, 0.285, 0.105, 1.0), 1.0)
    wicker = material("M_Willow_Wicker", (0.39, 0.205, 0.055, 1.0), 0.96)
    bone = material("M_Bone_Cadence", (0.69, 0.61, 0.40, 1.0), 0.82)
    ochre = material("M_Red_Ochre", (0.44, 0.055, 0.018, 1.0), 0.90)
    pitch = material("M_Pitch_Seam", (0.018, 0.010, 0.006, 1.0), 0.98)

    export_objects: list[bpy.types.Object] = []

    base_parts = [
        make_box("BaseTimber", (-0.22, 0.0, 0.045), (0.14, 0.68, 0.09), dark_oak, bevel=0.018),
        make_box("BaseTimber", (0.22, 0.0, 0.045), (0.14, 0.68, 0.09), dark_oak, bevel=0.018),
        make_box("BaseTimber", (0.0, -0.26, 0.088), (0.58, 0.12, 0.075), elm, bevel=0.014),
        make_box("BaseTimber", (0.0, 0.26, 0.088), (0.58, 0.12, 0.075), elm, bevel=0.014),
    ]
    base = join_objects("PumpBase", base_parts)
    base["mount_plane_z"] = 0.0
    export_objects.append(base)

    nails = []
    for x in (-0.245, 0.245):
        for y in (-0.265, 0.265):
            nail = make_cylinder("ForgedNail", (x, y, 0.137), 0.027, 0.025, forged_iron, vertices=4)
            nails.append(nail)
    export_objects.append(join_objects("ForgedFasteners", nails))

    body = make_cylinder("PumpBody", (0.0, 0.0, 0.48), 0.158, 0.76, elm, vertices=8)
    body["role"] = "hollow_elm_pump_trunk"
    export_objects.append(body)

    hoops = []
    for z in (0.18, 0.50, 0.80):
        hoop = make_torus("IronHoop", (0.0, 0.0, z), 0.160, 0.018, forged_iron, major_segments=8, minor_segments=4)
        hoop.rotation_euler.z = math.radians(3.0 if z == 0.50 else -2.0)
        hoops.append(hoop)
    export_objects.append(join_objects("IronHoops", hoops))

    packing = make_cylinder("LeatherTopPacking", (0.0, 0.0, 0.875), 0.132, 0.055, worn_leather, vertices=8)
    packing["role"] = "replaceable_leather_piston_seal"
    export_objects.append(packing)

    pivot = (0.0, 0.0, 0.91)
    pivot_housing = make_cylinder(
        "LeverPivotHousing", pivot, 0.075, 0.27, forged_iron,
        vertices=8, rotation=(0.0, math.pi / 2.0, 0.0)
    )
    pivot_housing["role"] = "forged_pin_and_wedge"
    export_objects.append(pivot_housing)
    spear = make_cylinder("PumpSpear", (0.0, 0.0, 0.77), 0.026, 0.28, ash, vertices=8)
    spear["role"] = "wooden_pump_spear_with_leather_valve_below"
    export_objects.append(spear)

    lever_end = (0.0, 0.49, 1.23)
    lever = make_box_between("LeverArm", pivot, lever_end, 0.072, ash, bevel=0.015)
    set_origin(lever, pivot)
    lever["pivot_axis"] = "local_x"
    lever["role"] = "animated_two_position_lever"
    export_objects.append(lever)

    grip_parts = [
        make_cylinder(
            "GripWood", lever_end, 0.052, 0.30, dark_oak,
            vertices=8, rotation=(0.0, math.pi / 2.0, 0.0)
        )
    ]
    for x in (-0.105, -0.035, 0.035, 0.105):
        grip_parts.append(make_torus(
            "GripLeatherWrap", (x, lever_end[1], lever_end[2]),
            0.053, 0.006, worn_leather,
            rotation=(0.0, math.pi / 2.0, 0.0),
            major_segments=8, minor_segments=4,
        ))
    grip = join_objects("LeverGrip", grip_parts)
    set_origin(grip, lever_end)
    grip.parent = lever
    grip.matrix_parent_inverse = lever.matrix_world.inverted()
    grip["role"] = "carved_oak_handle_with_leather_wraps"
    export_objects.append(grip)

    # Testigo de cadencia: dos guías talladas forman una pequeña escalera
    # abierta. Una pesa de hueso sube entre ellas y golpea tres muescas; se lee
    # como carpintería naval, no como un panel o un Bourdon de 1849.
    rack_parts = [
        make_box("CadenceRail", (0.165, 0.162, 0.69), (0.022, 0.035, 0.33), dark_oak, bevel=0.007),
        make_box("CadenceRail", (0.245, 0.162, 0.69), (0.022, 0.035, 0.33), dark_oak, bevel=0.007),
        make_box("CadenceRail", (0.205, 0.162, 0.535), (0.105, 0.035, 0.025), dark_oak, bevel=0.006),
        make_box("CadenceRail", (0.205, 0.162, 0.845), (0.105, 0.035, 0.025), dark_oak, bevel=0.006),
    ]
    rack = join_objects("CadenceRack", rack_parts)
    rack["display"] = "carved_gravity_cadence_indicator"
    export_objects.append(rack)
    marks = [
        make_box("CadenceMark", (0.205, 0.185, 0.595), (0.075, 0.014, 0.018), forged_iron, bevel=0.002),
        make_box("CadenceMark", (0.205, 0.187, 0.690), (0.088, 0.018, 0.026), bone, bevel=0.003),
        make_box("CadenceMark", (0.205, 0.185, 0.790), (0.075, 0.014, 0.018), ochre, bevel=0.002),
    ]
    export_objects.append(join_objects("CadenceMarks", marks))
    tongue_center = (0.205, 0.213, 0.69)
    tongue_parts = [
        make_cylinder("CadenceBoneWeight", tongue_center, 0.028, 0.075, bone, vertices=8),
        make_torus(
            "CadenceWeightRing", (tongue_center[0], tongue_center[1], tongue_center[2] + 0.018),
            0.029, 0.005, forged_iron, major_segments=8, minor_segments=4,
        ),
    ]
    tongue = join_objects("CadenceTongue", tongue_parts)
    set_origin(tongue, tongue_center)
    tongue["pivot_axis"] = "local_z_translation"
    tongue["role"] = "animated_cadence_weight"
    export_objects.append(tongue)

    # Licencia medieval verosimil: espiga de madera, cuero embreado y ligadura,
    # nunca racor roscado o galvanizado.
    intake_parts = [
        make_cylinder("IntakePart", (-0.205, 0.0, 0.245), 0.067, 0.16, dark_oak, vertices=8, rotation=(0.0, math.pi / 2.0, 0.0)),
        make_cylinder("IntakePart", (-0.292, 0.0, 0.245), 0.073, 0.050, leather, vertices=8, rotation=(0.0, math.pi / 2.0, 0.0)),
        make_cylinder("IntakePart", (-0.323, 0.0, 0.245), 0.064, 0.018, hemp, vertices=8, rotation=(0.0, math.pi / 2.0, 0.0)),
    ]
    intake = join_objects("IntakeCoupling", intake_parts)
    intake["connector_diameter_m"] = 0.055
    intake["construction"] = "wood_leather_hemp"
    export_objects.append(intake)

    # La descarga es una canaleta tallada (dale), no un codo industrial.
    discharge_parts = [
        make_box_between("DalePart", (0.10, 0.0, 0.58), (0.305, 0.055, 0.61), 0.105, dark_oak, bevel=0.012),
        make_box("DaleMouth", (0.312, 0.058, 0.612), (0.014, 0.080, 0.070), pitch, bevel=0.002),
        make_box("DaleIronBand", (0.255, 0.043, 0.602), (0.025, 0.120, 0.125), forged_iron, bevel=0.004),
    ]
    discharge = join_objects("DischargeDale", discharge_parts)
    discharge["role"] = "fixed_overboard_discharge"
    export_objects.append(discharge)

    # Estacas y travesano del rollo, unidos como lo haria el carpintero naval.
    cradle_parts = [
        make_box("CradlePeg", (-0.24, -0.245, 0.37), (0.045, 0.050, 0.50), dark_oak, bevel=0.010),
        make_box("CradlePeg", (0.24, -0.245, 0.37), (0.045, 0.050, 0.50), dark_oak, bevel=0.010),
        make_box("CradleBar", (0.0, -0.245, 0.57), (0.51, 0.050, 0.055), ash, bevel=0.010),
        make_cylinder("CradleLashing", (-0.24, -0.245, 0.55), 0.034, 0.065, hemp, vertices=8),
        make_cylinder("CradleLashing", (0.24, -0.245, 0.55), 0.034, 0.065, hemp, vertices=8),
    ]
    export_objects.append(join_objects("HoseCradle", cradle_parts))

    coils: list[bpy.types.Object] = []
    for y in (-0.285, -0.245, -0.205):
        coils.append(make_torus("LeatherHoseLoop", (0.0, y, 0.36), 0.205, 0.0275, leather, rotation=(math.pi / 2.0, 0.0, 0.0), major_segments=16, minor_segments=6))
        coils.append(make_torus("HempBinding", (0.0, y - 0.017, 0.36), 0.205, 0.0065, hemp, rotation=(math.pi / 2.0, 0.0, 0.0), major_segments=16, minor_segments=4))
        coils.append(make_torus("HempBinding", (0.0, y + 0.017, 0.36), 0.205, 0.0065, hemp, rotation=(math.pi / 2.0, 0.0, 0.0), major_segments=16, minor_segments=4))
    hose_coil = join_objects("HoseCoil", coils)
    hose_coil["hose_outer_diameter_m"] = 0.055
    hose_coil["usable_length_m"] = 6.8
    hose_coil["role"] = "stored_tarred_leather_hose"
    export_objects.append(hose_coil)

    # Cesta-colador inspirada en el strum box de Newport: mimbre, peso oscuro
    # interior y asa de canamo. El vacio entre varillas es geometria real.
    head_parts: list[bpy.types.Object] = []
    for z in (0.235, 0.325, 0.415):
        mat = forged_iron if z == 0.235 else wicker
        head_parts.append(make_torus("BasketHoop", (0.20, -0.27, z), 0.082, 0.012, mat, major_segments=10, minor_segments=4))
    for angle_deg in range(0, 360, 45):
        angle = math.radians(angle_deg)
        slat = make_box(
            "WickerSlat",
            (0.20 + math.cos(angle) * 0.077, -0.27 + math.sin(angle) * 0.077, 0.325),
            (0.014, 0.014, 0.19), wicker, bevel=0.003,
        )
        slat.rotation_euler.z = angle
        head_parts.append(slat)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.060, location=(0.20, -0.27, 0.285))
    ballast = bpy.context.object
    ballast.name = "StoneBallast"
    ballast.data.materials.append(forged_iron)
    head_parts.append(ballast)
    head_parts.extend(
        [
            make_cylinder("BasketNeck", (0.20, -0.27, 0.455), 0.052, 0.085, dark_oak, vertices=8),
            make_cylinder("BasketLashing", (0.20, -0.27, 0.487), 0.060, 0.030, hemp, vertices=8),
            make_torus("RopeHandle", (0.20, -0.27, 0.515), 0.068, 0.012, hemp, rotation=(math.pi / 2.0, 0.0, 0.0), major_segments=10, minor_segments=4),
        ]
    )
    head = join_objects("IntakeHead", head_parts)
    head_grip = (0.20, -0.27, 0.583)
    set_origin(head, head_grip)
    head["role"] = "grabbable_wicker_strum_box"
    head["grip_uses_hands"] = 1
    export_objects.append(head)

    # Anclajes de arte exportados. Godot podra obtener posiciones estables sin
    # deducirlas del AABB o de vertices que cambien durante una iteracion visual.
    export_objects.extend(
        [
            make_marker("HoseAnchorArt", (-0.332, 0.0, 0.245), "fixed_hose_start"),
            make_marker("LeverPivotArt", pivot, "lever_rotation_pivot"),
            make_marker("CadencePivotArt", tongue_center, "cadence_weight_translation_origin"),
            make_marker("DischargeSocketArt", (0.318, 0.085, 0.612), "water_discharge_fx_socket"),
        ]
    )

    # Metadata de contrato, visible desde Blender y conservada por glTF extras.
    base["asset_id"] = "manual_bilge_pump_medieval_v2"
    base["footprint_x_m"] = 0.70
    base["footprint_y_m"] = 1.00
    base["operator_facing_axis"] = "+Y"
    base["historical_basis"] = "Newport medieval ship burr pump, c. 1450s"
    base["gameplay_license"] = "movable reinforced leather suction hose"
    base["not_instanced_on_boat"] = True
    return export_objects


def look_at(obj: bpy.types.Object, target: tuple[float, float, float]) -> None:
    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def add_preview_scene(deck_mat) -> tuple[bpy.types.Object, bpy.types.Object, bpy.types.Object]:
    ground = make_box("PREVIEW_Deck", (0.0, 0.0, -0.035), (2.2, 2.2, 0.07), deck_mat, bevel=0.018)
    ground.hide_render = False

    bpy.ops.object.camera_add(location=(2.05, 2.60, 1.68))
    camera = bpy.context.object
    camera.name = "PREVIEW_Camera"
    camera.data.lens = 60
    look_at(camera, (0.0, 0.0, 0.56))
    bpy.context.scene.camera = camera

    bpy.ops.object.light_add(type="AREA", location=(-1.5, 1.8, 2.8))
    key = bpy.context.object
    key.name = "PREVIEW_Key"
    key.data.energy = 800
    key.data.shape = "DISK"
    key.data.size = 2.0
    look_at(key, (0.0, 0.0, 0.55))

    bpy.ops.object.light_add(type="AREA", location=(1.8, -1.2, 1.5))
    fill = bpy.context.object
    fill.name = "PREVIEW_Fill"
    fill.data.energy = 500
    fill.data.size = 1.5
    look_at(fill, (0.0, 0.0, 0.5))
    return ground, camera, key


def validate_asset(objects: list[bpy.types.Object]) -> None:
    required = {
        "PumpBase",
        "PumpBody",
        "IronHoops",
        "LeverArm",
        "LeverGrip",
        "PumpSpear",
        "CadenceRack",
        "CadenceTongue",
        "IntakeCoupling",
        "DischargeDale",
        "HoseCradle",
        "HoseCoil",
        "IntakeHead",
    }
    names = {obj.name for obj in objects}
    missing = sorted(required - names)
    if missing:
        raise RuntimeError(f"Faltan piezas obligatorias: {missing}")

    meshes = [obj for obj in objects if obj.type == "MESH"]
    if abs(min(corner.z for corner in [obj.matrix_world @ Vector(c) for obj in meshes for c in obj.bound_box])) > 0.002:
        raise RuntimeError("La geometria no apoya exactamente en Z=0")

    xs = [corner.x for obj in meshes for corner in [obj.matrix_world @ Vector(c) for c in obj.bound_box]]
    ys = [corner.y for obj in meshes for corner in [obj.matrix_world @ Vector(c) for c in obj.bound_box]]
    if max(xs) - min(xs) > 0.70 + 1e-3:
        extremes = []
        for obj in meshes:
            world_corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
            extremes.append((obj.name, min(c.x for c in world_corners), max(c.x for c in world_corners)))
        raise RuntimeError(
            f"Huella X excedida: {max(xs) - min(xs):.3f} m; "
            f"extremos={sorted(extremes, key=lambda item: item[2] - item[1], reverse=True)[:5]}"
        )
    if max(ys) - min(ys) > 1.00 + 1e-3:
        raise RuntimeError(f"Huella Y excedida: {max(ys) - min(ys):.3f} m")

    for name in ("LeverArm", "CadenceTongue", "IntakeHead"):
        if objects[[obj.name for obj in objects].index(name)].type != "MESH":
            raise RuntimeError(f"{name} debe seguir siendo una malla manipulable")


def main() -> None:
    blend_output, glb_output, preview_output = parse_outputs()
    for path in (blend_output, glb_output, preview_output):
        path.parent.mkdir(parents=True, exist_ok=True)

    reset_scene()
    export_objects = build_asset()
    validate_asset(export_objects)

    # Exportar solo el equipo. Camara, luces y cubierta de presentacion se
    # agregan despues, de modo que nunca contaminan el GLB de runtime.
    bpy.ops.object.select_all(action="DESELECT")
    for obj in export_objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = export_objects[0]
    bpy.ops.export_scene.gltf(
        filepath=str(glb_output),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_extras=True,
        export_cameras=False,
        export_lights=False,
    )

    deck_mat = material("M_PREVIEW_DeckWood", (0.24, 0.105, 0.035, 1.0), 0.88)
    add_preview_scene(deck_mat)

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(preview_output)
    scene.render.film_transparent = False
    scene.world.color = (0.018, 0.027, 0.032)
    scene.view_settings.look = "AgX - Medium High Contrast"

    bpy.ops.wm.save_as_mainfile(filepath=str(blend_output))
    bpy.ops.render.render(write_still=True)

    mesh_count = len(export_objects)
    vertex_count = sum(len(obj.data.vertices) for obj in export_objects if obj.type == "MESH")
    triangle_count = sum(len(poly.vertices) - 2 for obj in export_objects if obj.type == "MESH" for poly in obj.data.polygons)
    print(f"MANUAL_BILGE_PUMP_OK meshes={mesh_count} vertices={vertex_count} triangles={triangle_count}")
    print(f"BLEND={blend_output}")
    print(f"GLB={glb_output}")
    print(f"PREVIEW={preview_output}")


if __name__ == "__main__":
    main()
