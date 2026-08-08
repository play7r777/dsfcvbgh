import bpy
import os

# Create a cube
bpy.ops.mesh.primitive_cube_add(size=2, location=(0, 0, 0))
cube = bpy.context.active_object

# Setup camera
cam_data = bpy.data.cameras.new("Camera")
cam_obj = bpy.data.objects.new("Camera", cam_data)
bpy.context.collection.objects.link(cam_obj)
bpy.context.scene.camera = cam_obj
cam_obj.location = (5, -5, 5)
cam_obj.rotation_euler = (0.785, 0, 0.785) # 45 degrees

# Setup light
light_data = bpy.data.lights.new(name="Light", type='SUN')
light_obj = bpy.data.objects.new(name="Light", object_data=light_data)
bpy.context.collection.objects.link(light_obj)
light_obj.location = (5, 5, 5)

# Render
bpy.context.scene.render.filepath = os.path.abspath("test_render.png")
bpy.ops.render.render(write_still=True)
print("Rendered to:", bpy.context.scene.render.filepath)

# Export OBJ
try:
    bpy.ops.wm.obj_export(filepath=os.path.abspath("test.obj"))
    print("Exported using wm.obj_export")
except Exception as e:
    print("Failed wm.obj_export:", e)
    bpy.ops.export_scene.obj(filepath=os.path.abspath("test.obj"))
    print("Exported using export_scene.obj")

print("Done")
