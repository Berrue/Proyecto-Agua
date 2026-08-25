"""Construye el balde de cebo de cubierta y su GLB de runtime.

Uso desde la raiz del proyecto:

    blender --background --factory-startup --python tools/build_bait_bucket.py

El balde es MOBILIARIO visible (docs/PESCA.md §5): su nivel ES el contador de
cargas, asi que la forma tiene que leerse desde la altura de los ojos y desde
media cubierta. De ahi las tres decisiones de este generador:

1. **Balde de duelas, no cilindro.** La direccion visual del barco es madera y
   hierro forjado (la bomba de docs/BOMBA_MANUAL.md, la bodega medieval): un
   cilindro gris metalico era el unico plastico a bordo.
2. **El asa va VOLCADA hacia fuera.** Un asa en arco sobre la boca cruza
   justo por delante de lo unico que el jugador viene a mirar — cuanto cebo
   queda —, y encima se hunde en el monton al bajar el nivel. Volcada contra
   la pared exterior deja la boca despejada y sigue leyendose como asa.
3. **El cebo es un MONTON, no un tapon.** Dos piezas separadas: ``BaitFill``
   (la masa que llena hasta el nivel, la que Godot escala) y ``BaitMound``
   (el copete: pellas, sardinas medio enterradas y dos gusanos, la que Godot
   solo posa sobre la superficie). Un solido liso se leia como pintura.

**El calibre viaja en el GLB.** ``BaitGaugeBase`` y ``BaitGaugeRim`` son dos
empties en (radio, 0, altura) del interior util: `cubo_cebo.gd` deriva de ellos
el estrechamiento del balde para que la superficie del cebo toque la duela a
cualquier nivel. Editar el balde aqui mueve el calibre solo, sin una segunda
lista de numeros en Godot (regla "nunca el mismo numero en dos sitios").

El cebo lleva COLOR POR VERTICE deliberadamente claro: Godot tine la masa con
el color del `TipoCebo` (masilla parda, cebo vivo rojizo) multiplicando sobre
el, asi que el moteado sobrevive al tinte en vez de pelearse con el.
"""

from __future__ import annotations

import math
import random
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BLEND = REPO_ROOT / "source_assets" / "props" / "bait_bucket.blend"
DEFAULT_GLB = REPO_ROOT / "game" / "props" / "models" / "bait_bucket.glb"
DEFAULT_PREVIEW = REPO_ROOT / "docs" / "images" / "bait_bucket_preview.png"

# --- El balde -----------------------------------------------------------------
# Se conservan la huella y la altura del cubo viejo (radios 0,15/0,19 y 30 cm):
# el barco ya lo tiene colocado y la Zona de interaccion esta calibrada sobre
# esas medidas.
ALTURA = 0.30
R_BASE = 0.150
R_BOCA = 0.190
ESPESOR = 0.013
N_DUELAS = 14
Z_FONDO = 0.024   # el fondo encaja por encima del pie de las duelas
Z_LLENO = 0.262   # tope util del cebo: dos centimetros de guarda bajo la boca
HOLGURA_CEBO = 0.0015  # el cebo no toca la duela: evita z-fighting
# Circulo en el que cabe el copete. Menos que el radio de la boca util porque
# el monton BAJA con el nivel y abajo el balde es mas estrecho.
RADIO_COPETE = 0.128

# Semilla fija: el balde tiene que salir IDENTICO en cada regeneracion o el
# .blend y el .glb dejarian de ser el mismo objeto entre commits.
SEMILLA = 20260824


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


def reset_scene() -> bpy.types.Collection:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in list(bpy.data.collections):
        bpy.data.collections.remove(collection)
    for datablocks in (bpy.data.meshes, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)
    export = bpy.data.collections.new("EXPORT")
    bpy.context.scene.collection.children.link(export)
    return export


def material(
    name: str,
    rgba: tuple[float, float, float, float],
    roughness: float,
    metallic: float = 0.0,
    vertex_color: bool = False,
) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = rgba
    mat.use_nodes = True
    principled = mat.node_tree.nodes.get("Principled BSDF")
    principled.inputs["Base Color"].default_value = rgba
    principled.inputs["Roughness"].default_value = roughness
    principled.inputs["Metallic"].default_value = metallic
    if vertex_color:
        # Las colas de las sardinas son palas de un solo poligono: sin doble
        # cara desaparecen desde la mitad de los angulos de la cubierta.
        mat.use_backface_culling = False
        # El exportador de glTF solo escribe COLOR_0 si el material LEE el
        # atributo: sin este nodo el moteado del cebo se quedaria en el .blend.
        nodo = mat.node_tree.nodes.new("ShaderNodeVertexColor")
        nodo.layer_name = "Col"
        # Multiplicar (y no sustituir) es el montaje que glTF entiende como
        # baseColorFactor x COLOR_0: asi el moteado sigue siendo relativo al
        # color del cebo en vez de pintarlo de blanco.
        mezcla = mat.node_tree.nodes.new("ShaderNodeMix")
        mezcla.data_type = "RGBA"
        mezcla.blend_type = "MULTIPLY"
        mezcla.inputs["Factor"].default_value = 1.0
        mezcla.inputs[6].default_value = rgba
        mat.node_tree.links.new(nodo.outputs["Color"], mezcla.inputs[7])
        mat.node_tree.links.new(mezcla.outputs[2], principled.inputs["Base Color"])
    return mat


class Malla:
    """Acumulador de geometria con color por vertice.

    Se construye a mano en vez de con `bpy.ops` porque las operaciones de
    edicion dependen del contexto (seleccion, modo, escena activa) y en
    `--background` eso es una fuente de fallos silenciosos: aqui una cara mal
    puesta se ve en el indice, no tres pasos despues.
    """

    def __init__(self) -> None:
        self.vertices: list[tuple[float, float, float]] = []
        self.caras: list[tuple[int, ...]] = []
        self.colores: list[tuple[float, float, float, float]] = []

    def agregar(
        self,
        vertices: list[tuple[float, float, float]],
        caras: list[tuple[int, ...]],
        color: tuple[float, float, float],
        variacion: float = 0.0,
        rng: random.Random | None = None,
    ) -> int:
        base = len(self.vertices)
        for vertice in vertices:
            self.vertices.append(vertice)
            tono = 1.0
            if variacion > 0.0 and rng is not None:
                tono = 1.0 + rng.uniform(-variacion, variacion)
            self.colores.append((
                min(color[0] * tono, 1.0),
                min(color[1] * tono, 1.0),
                min(color[2] * tono, 1.0),
                1.0,
            ))
        for cara in caras:
            self.caras.append(tuple(indice + base for indice in cara))
        return base

    def objeto(
        self,
        nombre: str,
        mat: bpy.types.Material,
        coleccion: bpy.types.Collection,
        padre: bpy.types.Object | None = None,
        origen: tuple[float, float, float] = (0.0, 0.0, 0.0),
        suave: bool = True,
    ) -> bpy.types.Object:
        mesh = bpy.data.meshes.new(f"{nombre}_Mesh")
        mesh.from_pydata(self.vertices, [], self.caras)
        mesh.update()
        # Recalcular normales en vez de vigilar el sentido de giro cara a cara:
        # una cara invertida en un GLB no da error, sale como un agujero.
        editable = bmesh.new()
        editable.from_mesh(mesh)
        bmesh.ops.recalc_face_normals(editable, faces=editable.faces)
        editable.to_mesh(mesh)
        editable.free()
        capa = mesh.color_attributes.new(name="Col", type="FLOAT_COLOR", domain="POINT")
        for indice, color in enumerate(self.colores):
            capa.data[indice].color = color
        mesh.materials.append(mat)
        for poligono in mesh.polygons:
            poligono.use_smooth = suave
        obj = bpy.data.objects.new(nombre, mesh)
        obj.location = origen
        coleccion.objects.link(obj)
        if padre is not None:
            obj.parent = padre
        return obj


# =============================================================================
#  Utilidades de forma
# =============================================================================

def radio_exterior(z: float) -> float:
    """Perfil de la duela. El balde se abre hacia la boca, como uno de verdad."""
    return R_BASE + (R_BOCA - R_BASE) * (z / ALTURA)


def radio_interior(z: float) -> float:
    return radio_exterior(z) - ESPESOR


def anillo(radio: float, z: float, segmentos: int, giro: float = 0.0) -> list[tuple[float, float, float]]:
    return [
        (
            radio * math.cos(giro + 2.0 * math.pi * i / segmentos),
            radio * math.sin(giro + 2.0 * math.pi * i / segmentos),
            z,
        )
        for i in range(segmentos)
    ]


def puente(malla: Malla, base_a: int, base_b: int, segmentos: int, cerrado: bool = True) -> None:
    """Cose dos anillos ya volcados en la malla (mismo numero de segmentos)."""
    tope = segmentos if cerrado else segmentos - 1
    for i in range(tope):
        siguiente = (i + 1) % segmentos
        malla.caras.append((base_a + i, base_a + siguiente, base_b + siguiente, base_b + i))


def tubo(
    malla: Malla,
    puntos: list[Vector],
    radio: float,
    color: tuple[float, float, float],
    segmentos: int = 6,
    cerrar_extremos: bool = True,
    rng: random.Random | None = None,
    variacion: float = 0.0,
) -> None:
    """Barre un circulo a lo largo de una polilinea (asa forjada, gusanos).

    Usa transporte paralelo: si se recalculara la normal en cada punto, un
    tramo casi recto haria girar el perfil 180 grados de golpe y el tubo
    saldria retorcido.
    """
    if len(puntos) < 2:
        return
    tangente = (puntos[1] - puntos[0]).normalized()
    referencia = Vector((0.0, 0.0, 1.0))
    if abs(tangente.dot(referencia)) > 0.9:
        referencia = Vector((1.0, 0.0, 0.0))
    normal = (referencia - tangente * tangente.dot(referencia)).normalized()
    binormal = tangente.cross(normal)

    bases: list[int] = []
    for indice, punto in enumerate(puntos):
        if indice > 0:
            nueva_tangente = (
                puntos[indice + 1] - puntos[indice - 1]
                if indice < len(puntos) - 1
                else puntos[indice] - puntos[indice - 1]
            ).normalized()
            normal = (normal - nueva_tangente * nueva_tangente.dot(normal)).normalized()
            binormal = nueva_tangente.cross(normal)
            tangente = nueva_tangente
        aro = []
        for i in range(segmentos):
            angulo = 2.0 * math.pi * i / segmentos
            desplazado = punto + normal * (radio * math.cos(angulo)) + binormal * (radio * math.sin(angulo))
            aro.append((desplazado.x, desplazado.y, desplazado.z))
        bases.append(malla.agregar(aro, [], color, variacion, rng))

    for indice in range(len(bases) - 1):
        puente(malla, bases[indice], bases[indice + 1], segmentos)

    if cerrar_extremos:
        malla.caras.append(tuple(bases[0] + i for i in range(segmentos - 1, -1, -1)))
        malla.caras.append(tuple(bases[-1] + i for i in range(segmentos)))


def esferoide(
    malla: Malla,
    centro: Vector,
    radios: Vector,
    color: tuple[float, float, float],
    rng: random.Random,
    rugosidad: float = 0.0,
    anillos: int = 5,
    segmentos: int = 8,
    variacion: float = 0.06,
) -> None:
    """Pella de cebo: esfera baja en poligonos con los vertices sacudidos."""
    bases: list[int] = []
    polo_bajo = malla.agregar(
        [(centro.x, centro.y, centro.z - radios.z)], [], color, variacion, rng
    )
    for fila in range(1, anillos):
        phi = math.pi * fila / anillos
        aro = []
        for i in range(segmentos):
            theta = 2.0 * math.pi * i / segmentos
            ruido = 1.0 + rng.uniform(-rugosidad, rugosidad)
            aro.append((
                centro.x + radios.x * math.sin(phi) * math.cos(theta) * ruido,
                centro.y + radios.y * math.sin(phi) * math.sin(theta) * ruido,
                centro.z + radios.z * math.cos(phi) * ruido,
            ))
        bases.append(malla.agregar(aro, [], color, variacion, rng))
    polo_alto = malla.agregar(
        [(centro.x, centro.y, centro.z + radios.z)], [], color, variacion, rng
    )

    for i in range(segmentos):
        siguiente = (i + 1) % segmentos
        malla.caras.append((polo_bajo, bases[-1] + siguiente, bases[-1] + i))
        malla.caras.append((polo_alto, bases[0] + i, bases[0] + siguiente))
    for indice in range(len(bases) - 1):
        puente(malla, bases[indice], bases[indice + 1], segmentos)


def sardina(
    malla: Malla,
    centro: Vector,
    largo: float,
    rumbo: float,
    cabeceo: float,
    lomo: tuple[float, float, float],
    vientre: tuple[float, float, float],
    rng: random.Random,
) -> None:
    """Una sardinita de cebo: cuerpo por cuadernas + cola ahorquillada.

    Es LA pieza que hace legible el monton. Una pella lisa podria ser barro;
    una cola asomando entre las pellas solo puede ser cebo.
    """
    # Perfil (posicion a lo largo, semiancho, semialto) normalizado al largo.
    perfil = (
        (-0.50, 0.02, 0.03),
        (-0.34, 0.09, 0.13),
        (-0.10, 0.12, 0.17),
        (0.16, 0.10, 0.14),
        (0.38, 0.05, 0.07),
    )
    coseno_rumbo, seno_rumbo = math.cos(rumbo), math.sin(rumbo)
    coseno_cabeceo, seno_cabeceo = math.cos(cabeceo), math.sin(cabeceo)

    def situar(u: float, v: float, w: float) -> tuple[float, float, float]:
        # Cabeceo sobre el eje transversal y luego rumbo sobre la vertical.
        x1 = u * coseno_cabeceo - w * seno_cabeceo
        z1 = u * seno_cabeceo + w * coseno_cabeceo
        return (
            centro.x + x1 * coseno_rumbo - v * seno_rumbo,
            centro.y + x1 * seno_rumbo + v * coseno_rumbo,
            centro.z + z1,
        )

    bases: list[int] = []
    for posicion, semiancho, semialto in perfil:
        aro = []
        for i in range(6):
            angulo = 2.0 * math.pi * i / 6
            aro.append(situar(
                posicion * largo,
                semiancho * largo * math.cos(angulo),
                semialto * largo * math.sin(angulo),
            ))
        color = lomo if abs(posicion) < 0.45 else vientre
        bases.append(malla.agregar(aro, [], color, 0.05, rng))

    for indice in range(len(bases) - 1):
        puente(malla, bases[indice], bases[indice + 1], 6)
    morro = malla.agregar([situar(-0.56 * largo, 0.0, 0.0)], [], vientre, 0.04, rng)
    for i in range(6):
        malla.caras.append((morro, bases[0] + (i + 1) % 6, bases[0] + i))

    # Cola: dos palas planas desde el ultimo aro. Sin ella la sardina es un
    # cigarro, y un cigarro no dice "cebo" desde tres metros.
    raiz = situar(0.40 * largo, 0.0, 0.0)
    punta_alta = situar(0.60 * largo, 0.0, 0.22 * largo)
    punta_baja = situar(0.60 * largo, 0.0, -0.22 * largo)
    escote = situar(0.50 * largo, 0.0, 0.0)
    lado_a = situar(0.42 * largo, 0.016 * largo, 0.0)
    lado_b = situar(0.42 * largo, -0.016 * largo, 0.0)
    base_cola = malla.agregar(
        [raiz, punta_alta, escote, punta_baja, lado_a, lado_b], [], vientre, 0.05, rng
    )
    for lado in (4, 5):
        malla.caras.append((base_cola + 0, base_cola + lado, base_cola + 1))
        malla.caras.append((base_cola + 1, base_cola + lado, base_cola + 2))
        malla.caras.append((base_cola + 2, base_cola + lado, base_cola + 3))

    # Dorsal: una cresta corta. El balde se mira DESDE ARRIBA, asi que es la
    # aleta que decide si el copete son peces o pellas con punta.
    base_dorsal = malla.agregar(
        [
            situar(-0.14 * largo, 0.0, 0.15 * largo),
            situar(0.10 * largo, 0.0, 0.12 * largo),
            situar(-0.16 * largo, 0.0, 0.24 * largo),
            situar(0.04 * largo, 0.0, 0.20 * largo),
        ],
        [(0, 1, 3, 2)],
        lomo,
        0.05,
        rng,
    )


# =============================================================================
#  Las piezas
# =============================================================================

def construir_balde(
    coleccion: bpy.types.Collection,
    raiz: bpy.types.Object,
    roble: bpy.types.Material,
    hierro: bpy.types.Material,
    rng: random.Random,
) -> list[bpy.types.Object]:
    duelas = Malla()
    color_duela = (0.62, 0.44, 0.26)
    hueco = math.radians(0.35)  # junta entre duelas: la sombra que las separa
    paso = 2.0 * math.pi / N_DUELAS

    for indice in range(N_DUELAS):
        # Cada duela con su propio grosor y su propio radio: un balde de
        # tonelero no es un torneado, y esa irregularidad es la mitad de la
        # lectura "hecho a mano" a la distancia a la que se juega.
        capricho = rng.uniform(-0.0012, 0.0012)
        espesor = ESPESOR + rng.uniform(-0.001, 0.0015)
        a0 = indice * paso + hueco
        a1 = (indice + 1) * paso - hueco
        vertices: list[tuple[float, float, float]] = []
        for z in (0.0, ALTURA):
            externo = radio_exterior(z) + capricho
            interno = externo - espesor
            for radio in (interno, externo):
                for angulo in (a0, a1):
                    vertices.append((radio * math.cos(angulo), radio * math.sin(angulo), z))
        # 0-3 abajo (int a0, int a1, ext a0, ext a1), 4-7 arriba.
        caras = [
            (0, 1, 5, 4),  # cara interior
            (3, 2, 6, 7),  # cara exterior
            (0, 4, 6, 2),  # canto a0
            (1, 3, 7, 5),  # canto a1
            (0, 2, 3, 1),  # pie
            (4, 5, 7, 6),  # boca
        ]
        duelas.agregar(vertices, caras, color_duela, 0.09, rng)

    # Fondo: un disco encajado por dentro, no una tapa pegada al pie. Se ve al
    # vaciarse el balde y es lo que sostiene la lectura de "queda nada".
    radio_fondo = radio_interior(Z_FONDO) + 0.002
    tabla_baja = duelas.agregar(anillo(radio_fondo, Z_FONDO - 0.014, 12), [], (0.5, 0.35, 0.2), 0.06, rng)
    tabla_alta = duelas.agregar(anillo(radio_fondo, Z_FONDO, 12), [], (0.56, 0.4, 0.24), 0.08, rng)
    puente(duelas, tabla_baja, tabla_alta, 12)
    duelas.caras.append(tuple(tabla_alta + i for i in range(12)))
    duelas.caras.append(tuple(tabla_baja + i for i in range(11, -1, -1)))

    objeto_duelas = duelas.objeto("BucketStaves", roble, coleccion, raiz, suave=False)

    # --- Herrajes: aros, orejas y asa, todo en una malla de hierro ----------
    herrajes = Malla()
    color_hierro = (0.34, 0.35, 0.37)
    for z_aro in (0.045, 0.235):
        circulo = [
            Vector((
                (radio_exterior(z_aro) + 0.004) * math.cos(2.0 * math.pi * i / 18),
                (radio_exterior(z_aro) + 0.004) * math.sin(2.0 * math.pi * i / 18),
                z_aro,
            ))
            for i in range(19)
        ]
        tubo(herrajes, circulo, 0.0065, color_hierro, segmentos=5, cerrar_extremos=False, rng=rng, variacion=0.05)

    # Orejas: dos pletinas clavadas a la duela que sujetan el pasador del asa.
    z_pasador = 0.315
    for signo in (1.0, -1.0):
        x_ext = radio_exterior(ALTURA) + 0.004
        vertices = []
        for z in (0.243, z_pasador + 0.014):
            for x in (radio_exterior(min(z, ALTURA)) - 0.001, x_ext):
                for y in (-0.012, 0.012):
                    vertices.append((signo * x, y, z))
        caras = [
            (0, 1, 3, 2), (4, 6, 7, 5), (0, 2, 6, 4),
            (1, 5, 7, 3), (0, 4, 5, 1), (2, 3, 7, 6),
        ]
        herrajes.agregar(vertices, caras, color_hierro, 0.05, rng)

    # El asa VOLCADA hacia -Y: sale del pasador de una oreja, cae por fuera de
    # la pared y vuelve al otro. Se corrige punto a punto contra la duela
    # porque el balde se abre hacia arriba: un arco puro entraria en la madera.
    x_pasador = radio_exterior(ALTURA) + 0.006
    vuelco = math.radians(102.0)
    puntos_asa: list[Vector] = []
    for paso_asa in range(17):
        theta = math.pi * paso_asa / 16
        punto = Vector((
            x_pasador * math.cos(theta),
            -x_pasador * math.sin(theta) * math.sin(vuelco),
            z_pasador + x_pasador * math.sin(theta) * math.cos(vuelco),
        ))
        radial = math.hypot(punto.x, punto.y)
        if 0.0 <= punto.z <= ALTURA and radial > 1e-4:
            minimo = radio_exterior(punto.z) + 0.010
            if radial < minimo:
                factor = minimo / radial
                punto.x *= factor
                punto.y *= factor
        puntos_asa.append(punto)
    tubo(herrajes, puntos_asa, 0.0075, color_hierro, segmentos=5, rng=rng, variacion=0.04)

    objeto_herrajes = herrajes.objeto("BucketIron", hierro, coleccion, raiz)
    return [objeto_duelas, objeto_herrajes]


def construir_cebo(
    coleccion: bpy.types.Collection,
    raiz: bpy.types.Object,
    mat_cebo: bpy.types.Material,
    rng: random.Random,
) -> list[bpy.types.Object]:
    segmentos = 16
    r_base = radio_interior(Z_FONDO) - HOLGURA_CEBO
    r_boca = radio_interior(Z_LLENO) - HOLGURA_CEBO
    altura_util = Z_LLENO - Z_FONDO

    # --- La masa (BaitFill) -------------------------------------------------
    # Origen en el FONDO del balde: Godot la escala en Y y tiene que crecer
    # hacia arriba, no desde el centro (el cebo se posa, no levita).
    relleno = Malla()
    base_baja = relleno.agregar(anillo(r_base, 0.0, segmentos), [], (0.55, 0.52, 0.48), 0.05, rng)
    base_alta = relleno.agregar(
        [
            (
                r_boca * math.cos(2.0 * math.pi * i / segmentos),
                r_boca * math.sin(2.0 * math.pi * i / segmentos),
                altura_util - 0.004 + rng.uniform(-0.0025, 0.0025),
            )
            for i in range(segmentos)
        ],
        [],
        (0.80, 0.78, 0.74),
        0.07,
        rng,
    )
    puente(relleno, base_baja, base_alta, segmentos)
    relleno.caras.append(tuple(base_baja + i for i in range(segmentos - 1, -1, -1)))

    # La superficie no es un disco: se hunde un poco hacia el centro (masa
    # cansada) y se sacude vertice a vertice. Una tapa plana es lo que hacia
    # que el cubo viejo pareciera un bote de pintura.
    aros_superficie: list[int] = [base_alta]
    for fraccion in (0.66, 0.33):
        aros_superficie.append(relleno.agregar(
            [
                (
                    r_boca * fraccion * math.cos(2.0 * math.pi * i / segmentos),
                    r_boca * fraccion * math.sin(2.0 * math.pi * i / segmentos),
                    altura_util - 0.004 - 0.006 * (1.0 - fraccion) + rng.uniform(-0.004, 0.004),
                )
                for i in range(segmentos)
            ],
            [],
            (0.92, 0.90, 0.86),
            0.08,
            rng,
        ))
    for indice in range(len(aros_superficie) - 1):
        puente(relleno, aros_superficie[indice], aros_superficie[indice + 1], segmentos)
    centro = relleno.agregar([(0.0, 0.0, altura_util - 0.013)], [], (0.95, 0.93, 0.9), 0.05, rng)
    for i in range(segmentos):
        relleno.caras.append((centro, aros_superficie[-1] + i, aros_superficie[-1] + (i + 1) % segmentos))

    objeto_relleno = relleno.objeto(
        "BaitFill", mat_cebo, coleccion, raiz, origen=(0.0, 0.0, Z_FONDO)
    )

    # --- El copete (BaitMound) ---------------------------------------------
    # Origen en el PLANO DE LA SUPERFICIE: Godot solo lo posa a la altura que
    # marque el nivel. Todo lo que baja de z=0 queda enterrado en la masa.
    monton = Malla()
    # Las pellas son la CAMA del copete: bajas y anchas. Cuando eran domos
    # altos se comian las sardinas y todo el monton volvia a leerse como una
    # bola de masa, que es justo lo que habia que quitar.
    pella = (0.88, 0.83, 0.74)
    for x, y, z, rx, ry, rz in (
        (0.014, 0.010, 0.004, 0.062, 0.056, 0.021),
        (-0.052, 0.034, -0.004, 0.044, 0.040, 0.016),
        (0.040, -0.056, -0.006, 0.038, 0.042, 0.014),
    ):
        esferoide(monton, Vector((x, y, z)), Vector((rx, ry, rz)), pella, rng, rugosidad=0.18)

    # Lomo OSCURO contra vientre claro: el contraste es lo unico que separa una
    # sardina de una pella cuando las dos se tinen del mismo color de cebo.
    lomo = (0.30, 0.35, 0.44)
    vientre = (0.88, 0.85, 0.80)
    for x, y, z, largo, rumbo, cabeceo in (
        (0.004, 0.026, 0.032, 0.098, 0.55, 0.10),
        (-0.050, -0.020, 0.020, 0.086, 2.35, -0.08),
        (0.050, -0.030, 0.021, 0.090, -0.70, 0.18),
        (-0.020, -0.062, 0.013, 0.078, 1.20, -0.16),
        # La que se apoya en la duela y asoma la cola: es la silueta que dice
        # "hay cebo" desde el otro extremo de la cubierta.
        (0.062, 0.050, 0.026, 0.094, 2.05, 0.32),
    ):
        sardina(monton, Vector((x, y, z)), largo, rumbo, cabeceo, lomo, vientre, rng)

    # Dos gusanos: la unica forma alargada y BLANDA del monton. Con el cebo
    # vivo (tinte rojizo) son ellos los que venden que aquello se mueve.
    gusano = (0.78, 0.55, 0.50)
    for inicio, giro, longitud in ((Vector((-0.070, 0.052, 0.012)), 0.9, 0.11),
                                   (Vector((0.030, -0.070, 0.010)), -2.1, 0.09)):
        puntos = []
        for paso_gusano in range(9):
            t = paso_gusano / 8.0
            angulo = giro + 3.4 * t
            punto = Vector((
                inicio.x + longitud * t * math.cos(angulo),
                inicio.y + longitud * t * math.sin(angulo),
                inicio.z + 0.020 * math.sin(math.pi * t) - 0.004 * t,
            ))
            # El copete entero se escala con el nivel: si un gusano se sale del
            # circulo util, a media carga asoma por la duela.
            radial = math.hypot(punto.x, punto.y)
            if radial > RADIO_COPETE:
                punto.x *= RADIO_COPETE / radial
                punto.y *= RADIO_COPETE / radial
            puntos.append(punto)
        tubo(monton, puntos, 0.0055, gusano, segmentos=5, rng=rng, variacion=0.05)

    objeto_monton = monton.objeto(
        "BaitMound", mat_cebo, coleccion, raiz, origen=(0.0, 0.0, Z_LLENO)
    )
    return [objeto_relleno, objeto_monton]


def construir_calibre(
    coleccion: bpy.types.Collection, raiz: bpy.types.Object
) -> list[bpy.types.Object]:
    """El calibre que Godot lee: (radio, altura) del fondo y de la boca util."""
    calibres = []
    for nombre, radio, z in (
        ("BaitGaugeBase", radio_interior(Z_FONDO) - HOLGURA_CEBO, Z_FONDO),
        ("BaitGaugeRim", radio_interior(Z_LLENO) - HOLGURA_CEBO, Z_LLENO),
    ):
        empty = bpy.data.objects.new(nombre, None)
        empty.empty_display_type = "PLAIN_AXES"
        empty.empty_display_size = 0.02
        empty.location = (radio, 0.0, z)
        coleccion.objects.link(empty)
        empty.parent = raiz
        calibres.append(empty)
    return calibres


def build_asset() -> list[bpy.types.Object]:
    coleccion = bpy.data.collections["EXPORT"]
    rng = random.Random(SEMILLA)

    raiz = bpy.data.objects.new("BaitBucket", None)
    raiz.empty_display_size = 0.05
    coleccion.objects.link(raiz)

    roble = material("M_Oak_Stave", (0.185, 0.082, 0.028, 1.0), 0.90)
    hierro = material("M_Forged_Iron", (0.030, 0.036, 0.040, 1.0), 0.80, 0.55)
    # El color base del cebo es CLARO a proposito: en Godot se multiplica por el
    # color del TipoCebo, asi que el material tiene que ser un lienzo, no una
    # opinion. La masilla parda y el cebo vivo rojizo salen del .tres.
    mat_cebo = material("M_Bait", (0.84, 0.78, 0.66, 1.0), 0.74, vertex_color=True)

    objetos = [raiz]
    objetos += construir_balde(coleccion, raiz, roble, hierro, rng)
    objetos += construir_cebo(coleccion, raiz, mat_cebo, rng)
    objetos += construir_calibre(coleccion, raiz)
    return objetos


def validate_asset(objetos: list[bpy.types.Object]) -> None:
    # Sin esto las matrices de mundo siguen en identidad (los objetos se acaban
    # de crear por API, no por operador) y las comprobaciones medirian el
    # espacio local: el copete daria "por debajo de la cubierta" siempre.
    bpy.context.view_layer.update()

    nombres = {obj.name for obj in objetos}
    requeridos = {
        "BaitBucket", "BucketStaves", "BucketIron",
        "BaitFill", "BaitMound", "BaitGaugeBase", "BaitGaugeRim",
    }
    faltan = sorted(requeridos - nombres)
    if faltan:
        raise RuntimeError(f"Faltan piezas obligatorias: {faltan}")

    mallas = [obj for obj in objetos if obj.type == "MESH"]
    esquinas = [obj.matrix_world @ Vector(c) for obj in mallas for c in obj.bound_box]
    if abs(min(esquina.z for esquina in esquinas)) > 0.002:
        raise RuntimeError("El balde no apoya en Z=0")
    huella = max(
        max(esquina.x for esquina in esquinas) - min(esquina.x for esquina in esquinas),
        max(esquina.y for esquina in esquinas) - min(esquina.y for esquina in esquinas),
    )
    if huella > 0.46:
        raise RuntimeError(f"Huella excedida: {huella:.3f} m (la Zona mide 0,35 de radio)")

    # El cebo NO puede asomar por fuera de la duela a ningun nivel: es el fallo
    # que tenia el cubo viejo (el tapon se escalaba en Y con el radio de la
    # boca y sacaba un anillo por la pared al bajar el nivel).
    relleno = next(obj for obj in objetos if obj.name == "BaitFill")
    for vertice in relleno.data.vertices:
        mundo = relleno.matrix_world @ vertice.co
        radial = math.hypot(mundo.x, mundo.y)
        if radial > radio_interior(mundo.z) + 1e-4:
            raise RuntimeError(f"BaitFill asoma por la duela en z={mundo.z:.3f}")

    monton = next(obj for obj in objetos if obj.name == "BaitMound")
    radio_monton = max(
        math.hypot(vertice.co.x, vertice.co.y) for vertice in monton.data.vertices
    )
    if radio_monton > RADIO_COPETE + 0.006:
        raise RuntimeError(f"El copete se sale del circulo util: radio {radio_monton:.3f} m")


def add_preview_scene() -> None:
    """Tabla, luz y camara SOLO para el render de documentacion."""
    madera = material("M_PREVIEW_Deck", (0.24, 0.105, 0.035, 1.0), 0.88)
    bpy.ops.mesh.primitive_plane_add(size=2.0, location=(0.0, 0.0, 0.0))
    bpy.context.object.name = "PREVIEW_Deck"
    bpy.context.object.data.materials.append(madera)

    bpy.ops.object.light_add(type="AREA", location=(0.55, -0.75, 1.05))
    key = bpy.context.object
    key.data.energy = 110.0
    key.data.size = 1.2
    key.rotation_euler = (math.radians(38.0), 0.0, math.radians(38.0))

    bpy.ops.object.light_add(type="AREA", location=(-0.9, 0.6, 0.6))
    fill = bpy.context.object
    fill.data.energy = 28.0
    fill.data.size = 1.6
    fill.rotation_euler = (math.radians(66.0), 0.0, math.radians(-140.0))

    bpy.ops.object.camera_add(location=(0.62, -0.70, 0.62))
    camara = bpy.context.object
    camara.data.lens = 52.0
    direccion = Vector((0.0, 0.0, 0.15)) - camara.location
    camara.rotation_euler = direccion.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = camara


def elegir_motor(scene: bpy.types.Scene) -> None:
    for motor in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE", "BLENDER_WORKBENCH"):
        try:
            scene.render.engine = motor
            return
        except TypeError:
            continue


def exportar_glb(objetos: list[bpy.types.Object], destino: Path) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objetos:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objetos[0]
    argumentos = dict(
        filepath=str(destino),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_extras=True,
        export_cameras=False,
        export_lights=False,
    )
    try:
        bpy.ops.export_scene.gltf(export_vertex_color="MATERIAL", **argumentos)
    except TypeError:
        # Blender viejo: el color por vertice se exportaba con otro nombre.
        bpy.ops.export_scene.gltf(**argumentos)


def main() -> None:
    blend_output, glb_output, preview_output = parse_outputs()
    for path in (blend_output, glb_output, preview_output):
        path.parent.mkdir(parents=True, exist_ok=True)

    reset_scene()
    objetos = build_asset()
    validate_asset(objetos)
    exportar_glb(objetos, glb_output)

    add_preview_scene()
    scene = bpy.context.scene
    elegir_motor(scene)
    scene.render.resolution_x = 900
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(preview_output)
    scene.render.film_transparent = False
    scene.world.color = (0.018, 0.027, 0.032)
    try:
        scene.view_settings.look = "AgX - Medium High Contrast"
    except TypeError:
        pass

    bpy.ops.wm.save_as_mainfile(filepath=str(blend_output))
    bpy.ops.render.render(write_still=True)

    mallas = [obj for obj in objetos if obj.type == "MESH"]
    vertices = sum(len(obj.data.vertices) for obj in mallas)
    triangulos = sum(len(poly.vertices) - 2 for obj in mallas for poly in obj.data.polygons)
    print(f"BAIT_BUCKET_OK meshes={len(mallas)} vertices={vertices} triangles={triangulos}")
    print(f"BLEND={blend_output}")
    print(f"GLB={glb_output}")
    print(f"PREVIEW={preview_output}")


if __name__ == "__main__":
    main()
