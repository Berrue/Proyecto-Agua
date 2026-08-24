"""Aplica la receta de retarget a los clips de Mixamo ya copiados al proyecto.

    python tools/import_clip.py                 # todos los .fbx de la carpeta
    python tools/import_clip.py walk idle

Escribe el bloque `_subresources` del `.import` y deja el clip horneado como
`<nombre>_retargeted.res`, que es lo que consume el juego: un archivo de verdad,
inmune a que otra instancia de Godot regenere el `.import`.

Despues hay que reimportar:
    "C:/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe" --headless --import --path .

Ver docs/RIG.md para el porque de cada opcion, y sobre todo de las que NO estan:
`remove_tracks/except_bone_transform` borra TODAS las pistas del clip.
"""
import io
import os
import sys

DIR = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)),
	"..", "game", "player", "animations"))
BONE_MAP = "res://game/player/animations/mixamo_bonemap.tres"
ANIM = "mixamo_com"   # Mixamo siempre nombra asi su unica animacion


def bloque(nombre):
	return [
		'_subresources={',
		'"animations": {',
		'"%s": {' % ANIM,
		'"save_to_file/enabled": true,',
		'"save_to_file/keep_custom_tracks": false,',
		'"save_to_file/path": "res://game/player/animations/%s_retargeted.res",' % nombre,
		'"settings/loop_mode": 1',
		'}',
		'},',
		'"nodes": {',
		'"PATH:Skeleton3D": {',
		'"retarget/bone_map": Resource("%s"),' % BONE_MAP,
		'"retarget/remove_tracks/unimportant_positions": true,',
		'"retarget/remove_tracks/unmapped_bones": true,',
		'"retarget/rest_fixer/normalize_position_tracks": true,',
		'"retarget/rest_fixer/overwrite_axis": true',
		'}',
		'}',
		'}',
	]


def parchear(nombre):
	ruta = os.path.join(DIR, nombre + ".fbx.import")
	if not os.path.exists(ruta):
		print("  %-14s SIN .import (corre --import primero)" % nombre)
		return False
	lineas = io.open(ruta, encoding="utf-8").read().split("\n")
	salida = []
	profundidad = 0
	hecho = False
	tiene_fbx = False
	for linea in lineas:
		if profundidad > 0:
			# Saltando el bloque viejo: hay que CONTAR llaves. El dict lleva
			# cierres a columna 0 en cada nivel, y asumir que el primer "}"
			# cerraba todo me comio la clave fbx/importer una vez.
			profundidad += linea.count("{") - linea.count("}")
			continue
		if linea.strip() == "_subresources={}":
			salida.extend(bloque(nombre))
			hecho = True
			continue
		if linea.strip() == "_subresources={":
			profundidad = 1
			salida.extend(bloque(nombre))
			hecho = True
			continue
		if linea.startswith("fbx/importer="):
			# 0 = ufbx nativo. Con 1 llama a FBX2glTF, que no esta instalado
			# ("Could not create child process") y el import muere.
			salida.append("fbx/importer=0")
			tiene_fbx = True
			continue
		salida.append(linea)
	if not hecho:
		print("  %-14s no encontre _subresources" % nombre)
		return False
	if not tiene_fbx:
		salida.append("fbx/importer=0")
	io.open(ruta, "w", encoding="utf-8", newline="\n").write("\n".join(salida))
	print("  %-14s receta aplicada" % nombre)
	return True


def main():
	nombres = sys.argv[1:]
	if not nombres:
		nombres = sorted(f[:-4] for f in os.listdir(DIR) if f.endswith(".fbx"))
	print("clips:", ", ".join(nombres))
	ok = sum(1 for n in nombres if parchear(n))
	print("%d/%d listos" % (ok, len(nombres)))
	return 0 if ok == len(nombres) else 1


if __name__ == "__main__":
	sys.exit(main())
