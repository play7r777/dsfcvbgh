# -*- coding: utf-8 -*-
# convert_fbx_to_obj.py — конвертирует FBX-модели оружия/пуль в OBJ+MTL.
# Запуск headless:
#   blender -b --factory-startup --python convert_fbx_to_obj.py
#
# Читает все .fbx из assets/fbx  (и assets/fbx/bullets)
# Сохраняет .obj + .mtl в assets/models (и assets/models/bullets)

import bpy
import os
import sys

IN_DIR = "assets/fbx"
OUT_DIR = "assets/models"
os.makedirs(OUT_DIR, exist_ok=True)

BULLETS_IN  = os.path.join(IN_DIR,  "bullets")
BULLETS_OUT = os.path.join(OUT_DIR, "bullets")
os.makedirs(BULLETS_OUT, exist_ok=True)


def convert_fbx(src_path: str, dst_dir: str):
    """Импортирует FBX, экспортирует OBJ+MTL в dst_dir, очищает сцену."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=os.path.abspath(src_path))

    name = os.path.splitext(os.path.basename(src_path))[0]
    out_path = os.path.join(dst_dir, name + ".obj")

    bpy.ops.wm.obj_export(
        filepath=os.path.abspath(out_path),
        export_materials=True,
        export_triangulated_mesh=True,
        export_selected_objects=False,   # экспортируем всю сцену
    )
    print(f"[convert] {src_path}  ->  {out_path}")


# Оружие
for fname in sorted(os.listdir(IN_DIR)):
    if fname.lower().endswith(".fbx"):
        convert_fbx(os.path.join(IN_DIR, fname), OUT_DIR)

# Пули
if os.path.isdir(BULLETS_IN):
    for fname in sorted(os.listdir(BULLETS_IN)):
        if fname.lower().endswith(".fbx"):
            convert_fbx(os.path.join(BULLETS_IN, fname), BULLETS_OUT)

print("[convert] DONE ->", os.path.abspath(OUT_DIR))
