import bpy
import sys
import os
import glob

argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
IN_DIR = argv[0] if len(argv) > 0 else "assets/fbx"
OUT_DIR = argv[1] if len(argv) > 1 else "assets/models"

os.makedirs(OUT_DIR, exist_ok=True)
os.makedirs(os.path.join(OUT_DIR, "bullets"), exist_ok=True)

fbx_files = glob.glob(os.path.join(IN_DIR, "**", "*.fbx"), recursive=True)

for fbx in fbx_files:
    # Clear scene
    bpy.ops.wm.read_factory_settings(use_empty=True)
    
    # Import FBX
    bpy.ops.import_scene.fbx(filepath=fbx)
    
    # Determine out path
    rel_path = os.path.relpath(fbx, IN_DIR)
    out_path = os.path.join(OUT_DIR, os.path.splitext(rel_path)[0] + ".obj")
    
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    
    # Select all meshes
    bpy.ops.object.select_all(action='DESELECT')
    for obj in bpy.context.scene.objects:
        if obj.type == 'MESH':
            obj.select_set(True)
            bpy.context.view_layer.objects.active = obj
    
    if bpy.context.selected_objects:
        print(f"Exporting: {out_path}")
        bpy.ops.wm.obj_export(
            filepath=out_path,
            export_materials=True,
            export_triangulated_mesh=True,
            export_selected_objects=True
        )
    else:
        print(f"No meshes found in {fbx}")

print("Conversion complete!")
