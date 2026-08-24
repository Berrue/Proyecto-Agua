"""Construye la cania de pescar de Proyecto Agua (fuente editable + GLB).

La caja de primitivas que habia en `fishing_rod.tscn` (dos cilindros y una
esfera) cumplia su papel de bloqueo gris, pero la cania es LO QUE EL JUGADOR
MIRA todo el rato: en primera persona ocupa media pantalla y es el unico objeto
del juego que sale en cuadro en cada estado. Este script la modela de verdad,
con las piezas que un pescador reconoce de un vistazo: puntera naranja que se
afina, anillas escalonadas por debajo, portacarretes cromado y un carrete de
spinning que cuelga bajo la mano.

Convenciones (las mismas que el pez y el barco):

- Blender: la cania corre a lo largo de `+Z` (culata abajo), y el VIENTRE de la
  cania -- carrete y anillas -- mira a `+Y`.
- Godot/glTF: `+Z` pasa a `+Y` (la cania sigue apuntando hacia arriba dentro de
  `RodPivot`) y `+Y` pasa a `-Z`, o sea que el carrete queda por debajo y hacia
  delante, justo donde la camara lo ve al lado del brazo.
- El origen (0,0,0) es el punto de agarre de `RodPivot`, no el centro de la
  malla: asi el GLB entra en la escena sin transform y la punta cae en la Y que
  ya espera `fishing_rod.gd`.

Piezas exportadas y por que se llaman asi (Godot las convierte en nodos con el
MISMO nombre, y hay codigo que las busca):

- `Grip`     -> la empuniadura DELANTERA mas los hilos de las anillas. Es la
                pieza que `FishingRod._apply_tier()` tinta con el color del
                tier. Va delante de la mano a proposito: el brazo del viewmodel
                (capsula de radio 7 cm) se traga todo lo que quede por detras,
                asi que pintar la empuniadura trasera era pintar algo que el
                jugador no ve nunca.
- `RearGrip` -> empuniadura trasera y taco de culata (se ve en tercera persona,
                en el soporte de borda y cuando la cania esta en el suelo).
- `Blank`    -> el cuerpo naranja en dos tramos.
- `Guides`   -> las anillas con sus patas, y la puntera.
- `ReelSeat` -> portacarretes: cuerpo, capuchones y tuerca moleteada.
- `ReelBody` -> pie, columna y cuerpo del carrete.
- `ReelRotor`-> rotor, bobina y arco. Origen EN EL EJE de la bobina, paralelo a
                la cania: Godot puede girarlo al recoger sin tocar la malla.
- `ReelHandle`-> manivela y pomo. Origen en el eje de la manivela (local X).

Uso desde la raiz del proyecto:

    blender --background --factory-startup --python tools/build_fishing_rod.py
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BLEND = REPO_ROOT / "source_assets" / "fishing" / "fishing_rod.blend"
DEFAULT_GLB = REPO_ROOT / "game" / "fishing" / "models" / "cania.glb"
DEFAULT_PREVIEW = REPO_ROOT / "docs" / "images" / "fishing_rod_preview.png"
DEFAULT_DETAIL = REPO_ROOT / "docs" / "images" / "fishing_rod_detalle.png"

# --- El contrato con la escena de Godot -------------------------------------
# La punta tiene que caer donde `RodPivot/Tip` ya la espera: de ahi sale el
# sedal, y moverla cambiaria en silencio el punto de anclaje de la linea.
TIP_Z = 1.54
BUTT_Z = -0.26
# Donde cae la mano sobre el mango (Player.arm_grip). Todo lo que este por
# debajo de esta Z queda DENTRO de la capsula del brazo en primera persona.
HAND_Z = 0.05

# Tramos del cuerpo (z_inicio, z_fin, radio_inicio, radio_fin).
BLANK_LOWER = (0.155, 0.830, 0.0195, 0.0125)
BLANK_UPPER = (0.845, TIP_Z, 0.0122, 0.0042)

# --- El rig del doblez ------------------------------------------------------
# Una cania peleando se CURVA; hasta aqui la nuestra se inclinaba entera, tiesa
# como un palo de escoba. La curva sale de una cadena de huesos que arranca
# donde arranca el cuerpo (el mango, el portacarretes y el carrete son piezas
# rigidas y se quedan fuera del rig a proposito).
#
# Seis huesos: menos se ve como una linea quebrada en la punta, que es
# justamente donde mas se curva; mas es geometria y peso de skinning que nadie
# distingue a esta escala.
BLANK_BONES = 6
# Anillos de vertices a lo largo del cuerpo. El skinning solo puede curvar lo
# que tiene vertices: dos anillos (lo que da un cono) darian una caña doblada
# en dos rectas.
BLANK_RINGS = 18
BLANK_SIDES = 10


def parse_outputs() -> tuple[Path, Path, Path, Path]:
    values = {
        "--blend-output": DEFAULT_BLEND,
        "--glb-output": DEFAULT_GLB,
        "--preview-output": DEFAULT_PREVIEW,
        "--detail-output": DEFAULT_DETAIL,
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
    return (values["--blend-output"], values["--glb-output"],
            values["--preview-output"], values["--detail-output"])


# =============================================================================
#  Utilidades de modelado
# =============================================================================

def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials,
                       bpy.data.cameras, bpy.data.lights):
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


def make_cone(name: str, z0: float, z1: float, r0: float, r1: float, mat,
              vertices: int = 10, offset_y: float = 0.0) -> bpy.types.Object:
    """Tronco de cono a lo largo de Z. La cania entera se construye con esto."""
    depth = z1 - z0
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices, radius1=r0, radius2=r1, depth=depth,
        location=(0.0, offset_y, (z0 + z1) * 0.5),
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    return obj


def make_tube(name: str, z0: float, z1: float, radius_at, mat,
              rings: int = BLANK_RINGS, sides: int = BLANK_SIDES,
              inflate: float = 0.0) -> bpy.types.Object:
    """Tubo a lo largo de Z con anillos intermedios y radio por funcion.

    Existe porque el cuerpo tiene que DOBLARSE: un tronco de cono solo tiene
    vertices en los dos extremos, asi que por muy bien que se pesen los huesos
    solo puede quebrarse, no curvarse. Aqui el radio lo decide `radius_at(z)`,
    de modo que el escalon entre tramos del perfil sale solo.
    """
    bm = bmesh.new()
    loops = []
    for i in range(rings + 1):
        z = z0 + (z1 - z0) * (i / rings)
        r = radius_at(z) + inflate
        loop = [
            bm.verts.new((
                r * math.cos(math.tau * j / sides),
                r * math.sin(math.tau * j / sides),
                z,
            ))
            for j in range(sides)
        ]
        loops.append(loop)
    for i in range(rings):
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


def make_cylinder(name: str, location: tuple[float, float, float], radius: float,
                  depth: float, mat, vertices: int = 10,
                  rotation: tuple[float, float, float] = (0.0, 0.0, 0.0)) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices, radius=radius, depth=depth,
        location=location, rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    return obj


def make_torus(name: str, location: tuple[float, float, float], major: float,
               minor: float, mat, rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
               major_segments: int = 12, minor_segments: int = 5) -> bpy.types.Object:
    bpy.ops.mesh.primitive_torus_add(
        major_segments=major_segments, minor_segments=minor_segments,
        major_radius=major, minor_radius=minor,
        location=location, rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    return obj


def make_box(name: str, location: tuple[float, float, float],
             dimensions: tuple[float, float, float], mat,
             rotation: tuple[float, float, float] = (0.0, 0.0, 0.0)) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    return obj


def make_box_between(name: str, start: tuple[float, float, float],
                     end: tuple[float, float, float], width: float, thickness: float,
                     mat) -> bpy.types.Object:
    a = Vector(start)
    b = Vector(end)
    delta = b - a
    obj = make_box(name, tuple((a + b) * 0.5), (width, delta.length, thickness), mat)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = delta.to_track_quat("Y", "Z")
    return obj


def make_sphere(name: str, location: tuple[float, float, float],
                dimensions: tuple[float, float, float], mat,
                subdivisions: int = 2) -> bpy.types.Object:
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
    objects[0].name = name
    return objects[0]


def set_origin(obj: bpy.types.Object, location: tuple[float, float, float]) -> None:
    bpy.context.scene.cursor.location = location
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR", center="MEDIAN")
    bpy.context.scene.cursor.location = (0.0, 0.0, 0.0)


def blank_radius(z: float) -> float:
    """Radio del cuerpo a una altura dada: lo usan las anillas para saber a que
    distancia del eje empieza su pata (si se cambia el perfil, se mueven solas)."""
    for z0, z1, r0, r1 in (BLANK_LOWER, BLANK_UPPER):
        if z <= z1:
            t = (max(z, z0) - z0) / (z1 - z0)
            return r0 + (r1 - r0) * t
    return BLANK_UPPER[3]


# =============================================================================
#  Las piezas
# =============================================================================

def build_rod(mats: dict) -> list[bpy.types.Object]:
    export: list[bpy.types.Object] = []

    # --- Cuerpo: naranja, con anillos para poder curvarse --------------------
    # El escalon entre tramos es real (una cania de dos piezas se une por un
    # encaje), y ademas rompe la silueta: sin el, un cono de 1.8 m de largo lee
    # como un palo, no como una cania.
    blank_parts = [
        make_tube("BlankTube", BLANK_LOWER[0], TIP_Z, blank_radius, mats["orange"]),
        # El hilo del encaje va EN el cuerpo, no en la empuniadura: tiene que
        # doblarse con el. Rigido se despegaria en cuanto la caña se curva.
        make_tube("WrapFerrule", 0.824, 0.868, blank_radius, mats["eva_dark"],
                  rings=2, inflate=0.0013),
    ]
    blank = join_objects("Blank", blank_parts)
    blank["role"] = "cuerpo_naranja_deformable"
    export.append(blank)

    # --- Empuniadura trasera y culata ---------------------------------------
    rear_parts = [
        make_cylinder("ButtCap", (0.0, 0.0, BUTT_Z + 0.014), 0.0262, 0.028,
                      mats["rubber"], vertices=10),
        make_cone("RearGripA", BUTT_Z + 0.028, -0.130, 0.0265, 0.0302,
                  mats["eva_dark"], vertices=10),
        make_cone("RearGripB", -0.130, -0.022, 0.0302, 0.0262,
                  mats["eva_dark"], vertices=10),
    ]
    rear = join_objects("RearGrip", rear_parts)
    rear["role"] = "empuniadura_trasera_tapada_por_el_brazo_en_primera_persona"
    export.append(rear)

    # --- Portacarretes: donde cae la mano ------------------------------------
    seat_parts = [
        make_cone("SeatBody", -0.022, 0.088, 0.0268, 0.0250, mats["graphite"], vertices=10),
        # Anillo trasero: cierra el mango contra la empuniadura en vez de dejar
        # un corte seco entre dos grises.
        make_torus("SeatRingRear", (0.0, 0.0, -0.020), 0.0270, 0.0035, mats["chrome"]),
        # Capuchon fijo (delante) y movil (detras): las dos mordazas que sujetan
        # el pie del carrete. Son lo que hace que se lea como portacarretes y no
        # como "una parte del palo pintada de gris".
        make_box("SeatHoodFore", (0.0, 0.028, 0.070), (0.030, 0.020, 0.036), mats["chrome"]),
        make_box("SeatHoodRear", (0.0, 0.028, 0.006), (0.030, 0.020, 0.030), mats["chrome"]),
        make_cylinder("SeatNut", (0.0, 0.0, -0.012), 0.0290, 0.024, mats["chrome"], vertices=12),
        make_torus("SeatRingFore", (0.0, 0.0, 0.086), 0.0262, 0.0035, mats["chrome"]),
    ]
    seat = join_objects("ReelSeat", seat_parts)
    seat["role"] = "portacarretes"
    export.append(seat)

    # --- Empuniadura delantera + hilos: LA PIEZA DEL TIER --------------------
    # `FishingRod._apply_tier()` le mete el color del tier a esta malla. Todo lo
    # que va aqui esta POR DELANTE de la mano, que es lo unico que se ve en
    # primera persona: la mejora se nota mirando la cania, sin abrir un menu.
    # Va entera POR DEBAJO de donde arranca el rig del doblez: es una pieza
    # rigida, y si la cruzara se estiraria al curvarse la caña.
    grip_parts = [
        make_cone("ForeGrip", 0.088, 0.158, 0.0262, 0.0225, mats["eva"], vertices=10),
    ]
    grip = join_objects("Grip", grip_parts)
    grip["role"] = "pieza_tintada_por_el_tier"
    export.append(grip)

    # --- Anillas: por debajo, escalonadas ------------------------------------
    # Escalonar de gorda a fina no es adorno: es lo que dice "cania" desde 3 m,
    # y es la unica linea de detalle que sobrevive al low poly.
    guide_specs = [
        (0.330, 0.0190),
        (0.575, 0.0155),
        (0.810, 0.0128),
        (1.020, 0.0108),
        (1.200, 0.0094),
        (1.360, 0.0082),
    ]
    guide_parts: list[bpy.types.Object] = []
    for z, ring_r in guide_specs:
        base_r = blank_radius(z)
        stand = base_r + ring_r + 0.004
        guide_parts.append(make_torus(
            f"GuideRing_{int(z * 1000)}", (0.0, stand, z), ring_r, ring_r * 0.22,
            mats["chrome"], major_segments=10, minor_segments=4,
        ))
        # Pata en V hasta el cuerpo, y el pie tumbado sobre el (el hilo que lo
        # ata queda insinuado por el propio pie: a este tamanio, un hilo aparte
        # seria un pixel).
        for side in (-1.0, 1.0):
            guide_parts.append(make_box_between(
                "GuideLeg",
                (side * ring_r * 0.55, stand - ring_r * 0.6, z),
                (side * 0.0015, base_r * 0.6, z - ring_r * 0.9),
                0.0035, 0.0035, mats["chrome"],
            ))
        guide_parts.append(make_box(
            "GuideFoot", (0.0, base_r * 0.75, z - ring_r * 1.6),
            (0.007, base_r * 0.9, ring_r * 1.5), mats["chrome"],
        ))

    # Puntera: la anilla del extremo, casi en el eje. Es el punto por el que sale
    # el sedal, asi que tiene que quedar pegada a `RodPivot/Tip`.
    tip_r = BLANK_UPPER[3]
    guide_parts.append(make_cylinder("TipCap", (0.0, 0.0, TIP_Z - 0.012), tip_r * 1.25,
                                     0.024, mats["chrome"], vertices=8))
    guide_parts.append(make_torus("TipRing", (0.0, tip_r + 0.0075, TIP_Z - 0.004),
                                  0.0075, 0.0018, mats["chrome"],
                                  major_segments=10, minor_segments=4))
    guides = join_objects("Guides", guide_parts)
    guides["count"] = len(guide_specs)
    guides["role"] = "anillas_y_puntera"
    export.append(guides)

    export.extend(build_reel(mats))
    # El rig va el ultimo: necesita el cuerpo y las anillas ya construidos.
    export.append(build_rig([blank, guides]))
    return export


def build_rig(skinned: list[bpy.types.Object]) -> bpy.types.Object:
    """La cadena de huesos que curva el cuerpo, y los pesos que la reparten.

    Se rigan SOLO el cuerpo y las anillas. Mango, portacarretes y carrete son
    hierro y corcho: se quedan fuera del rig porque una pieza rigida que se
    estira delata el truco antes que cualquier otra cosa.

    Los pesos son una funcion sombrero (cada vertice reparte entre los dos
    huesos mas cercanos, proporcional a la distancia a sus centros). No es
    `ARMATURE_AUTO` a proposito: aqui la geometria la genera este script, asi
    que los pesos se pueden calcular exactos en vez de adivinarlos, y no
    dependen de la version de Blender que le toque a quien regenere el modelo.
    """
    heads = [BLANK_LOWER[0] + (TIP_Z - BLANK_LOWER[0]) * i / BLANK_BONES
             for i in range(BLANK_BONES + 1)]

    bpy.ops.object.armature_add(enter_editmode=False, location=(0.0, 0.0, 0.0))
    arm = bpy.context.object
    arm.name = "CaniaRig"
    arm.data.name = "CaniaRig"
    bpy.ops.object.mode_set(mode="EDIT")
    bones = arm.data.edit_bones
    for bone in list(bones):
        bones.remove(bone)
    previous = None
    for i in range(BLANK_BONES):
        bone = bones.new(f"Cania_{i}")
        bone.head = (0.0, 0.0, heads[i])
        bone.tail = (0.0, 0.0, heads[i + 1])
        bone.roll = 0.0
        if previous is not None:
            bone.parent = previous
            bone.use_connect = True
        previous = bone
    bpy.ops.object.mode_set(mode="OBJECT")

    span = heads[1] - heads[0]
    centers = [(heads[i] + heads[i + 1]) * 0.5 for i in range(BLANK_BONES)]
    for obj in skinned:
        groups = [obj.vertex_groups.new(name=f"Cania_{i}") for i in range(BLANK_BONES)]
        for vertex in obj.data.vertices:
            z = vertex.co.z
            weights = [max(0.0, 1.0 - abs(z - c) / span) for c in centers]
            total = sum(weights)
            if total <= 1e-6:
                # Por debajo del primer hueso o por encima del ultimo: pegado al
                # extremo, sin repartir.
                weights[0 if z < centers[0] else BLANK_BONES - 1] = 1.0
                total = 1.0
            for i, weight in enumerate(weights):
                if weight > 0.0:
                    groups[i].add([vertex.index], weight / total, "REPLACE")
        obj.modifiers.new("Doblez", "ARMATURE").object = arm
        obj.parent = arm
    return arm


def build_reel(mats: dict) -> list[bpy.types.Object]:
    """El carrete de spinning, colgando del portacarretes.

    Dos numeros lo gobiernan y ninguno es estetico:

    - Cuelga 10.5 cm bajo el eje, o sea FUERA del radio de la capsula que hace
      de brazo en primera persona (7 cm). Mas cerca y el antebrazo se lo traga
      justo cuando el jugador esta mirando girar la bobina.
    - La bobina va DELANTE del cuerpo (hacia la punta), que es donde esta en un
      carrete real: asi el sedal sale hacia la primera anilla en linea recta en
      vez de cruzar por encima del cuerpo.
    """
    export: list[bpy.types.Object] = []
    axis_y = 0.105          # centro del cuerpo y de la bobina, bajo la cania
    body_z = 0.008

    body_parts = [
        # Pie: la lengueta que muerden los capuchones del portacarretes.
        make_box("ReelFoot", (0.0, 0.032, 0.040), (0.022, 0.016, 0.090), mats["graphite"]),
        # Columna, inclinada hacia atras como en un carrete real.
        make_box_between("ReelStem", (0.0, 0.040, 0.034), (0.0, axis_y - 0.020, body_z),
                         0.026, 0.030, mats["graphite"]),
        make_sphere("ReelBodyShell", (0.0, axis_y, body_z), (0.050, 0.064, 0.054),
                    mats["graphite"]),
        # Tapa del pinion: el circulo lateral que delata que ahi hay engranajes.
        make_cylinder("ReelSideCover", (-0.026, axis_y, body_z), 0.022, 0.010,
                      mats["chrome"], vertices=12, rotation=(0.0, math.pi / 2.0, 0.0)),
    ]
    body = join_objects("ReelBody", body_parts)
    body["role"] = "cuerpo_del_carrete"
    export.append(body)

    # --- Rotor + bobina: giran sobre el eje de la cania (local Z) ------------
    rotor_z = body_z + 0.030
    rotor_parts = [
        make_cone("Rotor", body_z + 0.014, rotor_z + 0.030, 0.034, 0.038,
                  mats["graphite"], vertices=12, offset_y=axis_y),
        # Faldon, hilo enrollado y nucleo. El claro entre el faldon y el hilo es
        # lo unico que dice "bobina cargada" a esta distancia.
        make_cylinder("SpoolLip", (0.0, axis_y, rotor_z + 0.062), 0.0360, 0.012,
                      mats["chrome"], vertices=14),
        make_cylinder("SpoolLine", (0.0, axis_y, rotor_z + 0.046), 0.0322, 0.026,
                      mats["line"], vertices=14),
        make_cylinder("SpoolCore", (0.0, axis_y, rotor_z + 0.048), 0.0175, 0.044,
                      mats["chrome"], vertices=10),
        # Brazo del rotor y arco (el aro que recoge el sedal).
        make_box_between("RotorArm", (0.031, axis_y - 0.022, rotor_z + 0.004),
                         (0.038, axis_y - 0.004, rotor_z + 0.056), 0.013, 0.013,
                         mats["graphite"]),
        make_torus("Bail", (0.0, axis_y, rotor_z + 0.050), 0.042, 0.0038,
                   mats["chrome"], rotation=(0.0, math.pi / 2.0, 0.0),
                   major_segments=14, minor_segments=4),
    ]
    rotor = join_objects("ReelRotor", rotor_parts)
    set_origin(rotor, (0.0, axis_y, rotor_z))
    rotor["spin_axis"] = "local_z"
    rotor["role"] = "rotor_animable_al_recoger"
    export.append(rotor)

    # --- Manivela: a la izquierda (zurda en el carrete = diestra en la cania) -
    crank_x = -0.034
    handle_parts = [
        make_cylinder("CrankShaft", (crank_x - 0.012, axis_y, body_z), 0.009, 0.028,
                      mats["chrome"], vertices=8, rotation=(0.0, math.pi / 2.0, 0.0)),
        make_box_between("CrankArm", (crank_x - 0.024, axis_y, body_z),
                         (crank_x - 0.030, axis_y + 0.050, body_z), 0.011, 0.011,
                         mats["graphite"]),
        make_cylinder("CrankKnob", (crank_x - 0.046, axis_y + 0.054, body_z), 0.012, 0.034,
                      mats["eva_dark"], vertices=8, rotation=(0.0, math.pi / 2.0, 0.0)),
    ]
    handle = join_objects("ReelHandle", handle_parts)
    set_origin(handle, (crank_x - 0.016, axis_y, body_z))
    handle["spin_axis"] = "local_x"
    handle["role"] = "manivela_animable_al_recoger"
    export.append(handle)
    return export


# =============================================================================
#  Validacion, preview y export
# =============================================================================

def validate(objects: list[bpy.types.Object]) -> None:
    names = {obj.name for obj in objects}
    required = {"Blank", "Grip", "RearGrip", "ReelSeat", "Guides",
                "ReelBody", "ReelRotor", "ReelHandle", "CaniaRig"}
    missing = sorted(required - names)
    if missing:
        raise RuntimeError(f"Faltan piezas obligatorias: {missing}")

    # El rig es el fallo mudo mas caro de este script: si el cuerpo sale sin
    # pesos, Godot lo importa igual, no protesta, y la caña se queda tiesa.
    rig = [obj for obj in objects if obj.name == "CaniaRig"][0]
    if len(rig.data.bones) != BLANK_BONES:
        raise RuntimeError(f"El rig tiene {len(rig.data.bones)} huesos, se esperaban {BLANK_BONES}")
    for pieza in ("Blank", "Guides"):
        obj = [o for o in objects if o.name == pieza][0]
        if not any(m.type == "ARMATURE" and m.object is rig for m in obj.modifiers):
            raise RuntimeError(f"{pieza} no esta enganchada al rig")
        sin_peso = [v.index for v in obj.data.vertices if not v.groups]
        if sin_peso:
            raise RuntimeError(f"{pieza} tiene {len(sin_peso)} vertices sin peso")

    by_name = {obj.name: obj for obj in objects}

    # El contrato con Godot: `Grip` es la malla que tinta el tier, y tintar por
    # surface 0 solo tiene sentido si esa malla lleva UN material.
    grip_slots = len(by_name["Grip"].data.materials)
    if grip_slots != 1:
        raise RuntimeError(f"Grip debe tener 1 material (tiene {grip_slots})")
    corners = [obj.matrix_world @ Vector(c)
               for obj in objects if obj.type == "MESH" for c in obj.bound_box]
    top = max(c.z for c in corners)
    bottom = min(c.z for c in corners)
    if abs(top - TIP_Z) > 0.004:
        raise RuntimeError(f"La punta cae en z={top:.4f}, se esperaba {TIP_Z}")
    if abs(bottom - BUTT_Z) > 0.004:
        raise RuntimeError(f"La culata cae en z={bottom:.4f}, se esperaba {BUTT_Z}")

    # Lo unico que puede salirse hacia +Y es el carrete; si algo mas se fuera,
    # es que una anilla se ha despegado del cuerpo.
    guide_corners = [by_name["Guides"].matrix_world @ Vector(c)
                     for c in by_name["Guides"].bound_box]
    # El borde exterior de la anilla mas gorda (la primera) marca el maximo. Si
    # crece de aqui, la cania deja de leerse como cania y empieza a leerse como
    # una antena con aros.
    guide_reach = max(c.y for c in guide_corners)
    if guide_reach > 0.075:
        raise RuntimeError(f"Alguna anilla se separa demasiado del cuerpo: {guide_reach:.4f} m")

    # El carrete tiene que asomar por fuera de la capsula del brazo (r=0.07) o
    # no se vera nunca en primera persona.
    reel_corners = [by_name["ReelRotor"].matrix_world @ Vector(c)
                    for c in by_name["ReelRotor"].bound_box]
    if max(c.y for c in reel_corners) < 0.080:
        raise RuntimeError("El carrete queda dentro del brazo del viewmodel")


def look_at(obj: bpy.types.Object, target: tuple[float, float, float],
            roll_deg: float = 0.0) -> None:
    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    if roll_deg != 0.0:
        obj.rotation_euler.rotate_axis("Z", math.radians(roll_deg))


def add_preview_scene(backdrop_mat) -> bpy.types.Object:
    """Escenario de lamina: fondo, tres luces y una camara.

    Nada de esto se exporta -- se monta DESPUES del GLB para que no pueda
    colarse en el runtime.
    """
    make_box("PREVIEW_Backdrop", (0.0, 1.9, 0.62), (7.0, 0.04, 5.0), backdrop_mat)

    bpy.ops.object.camera_add(location=(1.55, -2.35, 0.62))
    camera = bpy.context.object
    camera.name = "PREVIEW_Camera"
    camera.data.lens = 50
    # Con roll la cania cruza el encuadre en diagonal: en vertical dejaria el
    # 80% de la lamina vacia y las anillas saldrian del tamanio de un pixel.
    look_at(camera, (0.0, 0.03, 0.62), roll_deg=-28.0)
    bpy.context.scene.camera = camera

    bpy.ops.object.light_add(type="AREA", location=(-1.6, -2.0, 2.4))
    key = bpy.context.object
    key.name = "PREVIEW_Key"
    key.data.energy = 260
    key.data.shape = "DISK"
    key.data.size = 2.4
    look_at(key, (0.0, 0.0, 0.7))

    bpy.ops.object.light_add(type="AREA", location=(2.2, -1.4, 0.1))
    fill = bpy.context.object
    fill.name = "PREVIEW_Fill"
    fill.data.energy = 110
    fill.data.size = 1.8
    look_at(fill, (0.0, 0.05, 0.5))

    # Contra: separa el cuerpo naranja del fondo y enciende los cromados, que
    # sin un reflejo que morder salen grises y planos.
    bpy.ops.object.light_add(type="AREA", location=(-0.4, 1.6, 1.9))
    rim = bpy.context.object
    rim.name = "PREVIEW_Rim"
    rim.data.energy = 180
    rim.data.size = 1.2
    look_at(rim, (0.0, 0.0, 0.7))
    return camera


def render_to(path: Path, camera: bpy.types.Object, location: tuple[float, float, float],
              target: tuple[float, float, float], lens: float, roll_deg: float = 0.0,
              resolution: tuple[int, int] = (1280, 900)) -> None:
    camera.location = location
    camera.data.lens = lens
    look_at(camera, target, roll_deg)
    scene = bpy.context.scene
    scene.render.resolution_x, scene.render.resolution_y = resolution
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def main() -> None:
    blend_output, glb_output, preview_output, detail_output = parse_outputs()
    for path in (blend_output, glb_output, preview_output, detail_output):
        path.parent.mkdir(parents=True, exist_ok=True)

    reset_scene()
    mats = {
        # Naranja de seguridad: se lee contra el mar gris, contra el cielo y
        # contra la cubierta, que son los tres fondos que tiene este juego.
        "orange": material("M_Rod_Blank_Orange", (0.920, 0.190, 0.030, 1.0), 0.38),
        # El EVA de la pieza del tier arranca en el MISMO color que
        # `tier_1_iniciacion.tres`: una cania sin tier asignado (capturas, tests)
        # tiene que salir igual que la de iniciacion, no de otro color.
        "eva": material("M_Rod_Grip_EVA", (0.150, 0.130, 0.110, 1.0), 0.86),
        # La trasera va mas oscura a proposito: contra ella, la delantera (la que
        # cambia con el tier) se lee como otra pieza y no como una mancha de luz.
        "eva_dark": material("M_Rod_Grip_Dark", (0.058, 0.055, 0.050, 1.0), 0.88),
        "rubber": material("M_Rod_ButtRubber", (0.030, 0.030, 0.034, 1.0), 0.94),
        "chrome": material("M_Rod_Chrome", (0.780, 0.800, 0.840, 1.0), 0.20, 0.95),
        "graphite": material("M_Reel_Graphite", (0.052, 0.058, 0.070, 1.0), 0.48, 0.25),
        "line": material("M_Reel_Line", (0.845, 0.840, 0.780, 1.0), 0.70),
        "backdrop": material("M_PREVIEW_Backdrop", (0.030, 0.055, 0.075, 1.0), 0.90),
    }
    export_objects = build_rod(mats)
    validate(export_objects)

    bpy.ops.object.select_all(action="DESELECT")
    for obj in export_objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = export_objects[0]
    bpy.ops.export_scene.gltf(
        filepath=str(glb_output),
        export_format="GLB",
        use_selection=True,
        # OJO: aplicar modificadores al exportar se lleva por delante el
        # skinning (el modificador Armature ES el doblez). Aqui no hace falta:
        # este script no usa ningun otro modificador, la geometria sale ya
        # aplicada de `make_*`.
        export_apply=False,
        export_extras=True,
        export_cameras=False,
        export_lights=False,
    )

    camera = add_preview_scene(mats["backdrop"])
    scene = bpy.context.scene
    # Blender 5.1 vuelve a exponer Eevee como ``BLENDER_EEVEE`` en la API.
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.world.color = (0.020, 0.042, 0.058)
    # "Punchy" y no el contraste medio del resto de laminas: aqui el COLOR es el
    # asunto (naranja de seguridad), y AgX medio se lo come hasta dejarlo salmon.
    scene.view_settings.look = "AgX - Punchy"

    bpy.ops.wm.save_as_mainfile(filepath=str(blend_output))
    render_to(preview_output, camera, (1.50, -3.30, 0.72), (0.0, 0.03, 0.64), 50, -30.0)
    # Segunda lamina: el tercio que el jugador tiene delante de la cara en
    # primera persona (portacarretes, carrete y primera anilla).
    render_to(detail_output, camera, (0.56, -0.74, 0.34), (-0.01, 0.06, 0.13), 52, -12.0,
              (1100, 900))

    meshes = [obj for obj in export_objects if obj.type == "MESH"]
    vertices = sum(len(obj.data.vertices) for obj in meshes)
    triangles = sum(len(poly.vertices) - 2 for obj in meshes for poly in obj.data.polygons)
    print(f"FISHING_ROD_OK meshes={len(meshes)} vertices={vertices} triangles={triangles}")
    for obj in meshes:
        print(f"  {obj.name}: verts={len(obj.data.vertices)} mats={len(obj.data.materials)}")
    print(f"BLEND={blend_output}")
    print(f"GLB={glb_output}")
    print(f"PREVIEW={preview_output}")
    print(f"DETAIL={detail_output}")


if __name__ == "__main__":
    main()
