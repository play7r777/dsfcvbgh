import bpy
import math
import os

OUT_DIR = "assets/models/map"
os.makedirs(OUT_DIR, exist_ok=True)

# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------
def get_mat(name, rgb):
    if name in bpy.data.materials:
        return bpy.data.materials[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get('Principled BSDF')
    if bsdf:
        bsdf.inputs['Base Color'].default_value = (*rgb, 1.0)
        bsdf.inputs['Roughness'].default_value = 0.8
    # Also set viewport color
    m.diffuse_color = (*rgb, 1.0)
    return m

# ---------------------------------------------------------------------------
# Builders
# ---------------------------------------------------------------------------
def build_tree(name, loc):
    bpy.ops.mesh.primitive_cylinder_add(radius=0.6, depth=5, location=(loc[0], loc[1], loc[2] + 2.5))
    trunk = bpy.context.active_object
    trunk.data.materials.append(MAT_WOOD)
    
    leaves = []
    for i in range(3):
        bpy.ops.mesh.primitive_ico_sphere_add(radius=2.5 - i*0.4, subdivisions=2, 
            location=(loc[0], loc[1], loc[2] + 5 + i*1.8))
        leaf = bpy.context.active_object
        leaf.data.materials.append(MAT_LEAVES)
        leaves.append(leaf)
    return [trunk] + leaves

def build_bush(name, loc):
    bpy.ops.mesh.primitive_ico_sphere_add(radius=1.5, subdivisions=2, location=(loc[0], loc[1], loc[2] + 1.0))
    bush1 = bpy.context.active_object
    bush1.data.materials.append(MAT_LEAVES)
    
    bpy.ops.mesh.primitive_ico_sphere_add(radius=1.0, subdivisions=2, location=(loc[0]+1.2, loc[1]+0.8, loc[2] + 0.6))
    bush2 = bpy.context.active_object
    bush2.data.materials.append(MAT_LEAVES)
    return [bush1, bush2]

def build_house(name, loc):
    # Base (Width: 10, Depth: 8, Height: 6)
    bpy.ops.mesh.primitive_cube_add(size=1, location=(loc[0], loc[1], loc[2] + 3))
    base = bpy.context.active_object
    base.scale = (10, 8, 6)
    bpy.ops.object.transform_apply(scale=True)
    base.data.materials.append(MAT_CONCRETE)
    
    # Roof (Pyramid on top)
    bpy.ops.mesh.primitive_cone_add(radius1=7, radius2=0, depth=4, vertices=4, 
        location=(loc[0], loc[1], loc[2] + 8))
    roof = bpy.context.active_object
    roof.rotation_euler = (0, 0, math.radians(45))
    roof.scale = (1, 0.8, 1)
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    roof.data.materials.append(MAT_ROOF)
    
    # Door (Width: 1.5, Depth: 0.2, Height: 3)
    bpy.ops.mesh.primitive_cube_add(size=1, location=(loc[0], loc[1] - 4.1, loc[2] + 1.5))
    door = bpy.context.active_object
    door.scale = (1.5, 0.2, 3)
    bpy.ops.object.transform_apply(scale=True)
    door.data.materials.append(MAT_WOOD)
    
    # Window
    bpy.ops.mesh.primitive_cube_add(size=1, location=(loc[0] - 2.5, loc[1] - 4.1, loc[2] + 2.5))
    window = bpy.context.active_object
    window.scale = (2, 0.2, 1.5)
    bpy.ops.object.transform_apply(scale=True)
    window.data.materials.append(MAT_WINDOW)
    
    return [base, roof, door, window]

def build_trench(name, loc):
    parts = []
    
    # Floor
    bpy.ops.mesh.primitive_cube_add(size=1, location=(loc[0], loc[1], loc[2] + 0.5))
    floor = bpy.context.active_object
    floor.scale = (3, 8, 1)
    bpy.ops.object.transform_apply(scale=True)
    floor.data.materials.append(MAT_DIRT)
    parts.append(floor)
    
    # Wall Left
    bpy.ops.mesh.primitive_cube_add(size=1, location=(loc[0] - 1.5, loc[1], loc[2] + 2.5))
    wl = bpy.context.active_object
    wl.scale = (0.5, 8, 3)
    bpy.ops.object.transform_apply(scale=True)
    wl.data.materials.append(MAT_DIRT)
    parts.append(wl)
    
    # Wall Right
    bpy.ops.mesh.primitive_cube_add(size=1, location=(loc[0] + 1.5, loc[1], loc[2] + 2.5))
    wr = bpy.context.active_object
    wr.scale = (0.5, 8, 3)
    bpy.ops.object.transform_apply(scale=True)
    wr.data.materials.append(MAT_DIRT)
    parts.append(wr)
    
    # Sandbags
    for i in range(7):
        bpy.ops.mesh.primitive_cube_add(size=1, location=(loc[0] - 1.5, loc[1] - 3.5 + i*1.1, loc[2] + 4.2))
        sb = bpy.context.active_object
        sb.scale = (0.8, 1, 0.4)
        bpy.ops.object.transform_apply(scale=True)
        sb.data.materials.append(MAT_SANDBAG)
        parts.append(sb)
        
    return parts

# ---------------------------------------------------------------------------
# Setup and Render
# ---------------------------------------------------------------------------
def setup_scene():
    # Setup camera
    cam_data = bpy.data.cameras.new("Camera")
    cam_obj = bpy.data.objects.new("Camera", cam_data)
    bpy.context.collection.objects.link(cam_obj)
    bpy.context.scene.camera = cam_obj
    cam_obj.location = (0, -35, 25)
    cam_obj.rotation_euler = (math.radians(60), 0, 0)
    
    # Setup light
    light_data = bpy.data.lights.new(name="Sun", type='SUN')
    light_data.energy = 5
    light_obj = bpy.data.objects.new(name="Sun", object_data=light_data)
    bpy.context.collection.objects.link(light_obj)
    light_obj.rotation_euler = (math.radians(45), math.radians(30), 0)
    
    # Add Ground Plane for render
    bpy.ops.mesh.primitive_plane_add(size=100, location=(0, 0, 0))
    ground = bpy.context.active_object
    ground.data.materials.append(get_mat("Map_Ground", (0.2, 0.3, 0.15)))

def export_and_render():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    
    global MAT_WOOD, MAT_LEAVES, MAT_DIRT, MAT_STONE, MAT_SANDBAG, MAT_CONCRETE, MAT_ROOF, MAT_WINDOW
    MAT_WOOD = get_mat("Map_Wood", (0.35, 0.25, 0.15))
    MAT_LEAVES = get_mat("Map_Leaves", (0.1, 0.4, 0.1))
    MAT_DIRT = get_mat("Map_Dirt", (0.4, 0.3, 0.2))
    MAT_STONE = get_mat("Map_Stone", (0.5, 0.5, 0.5))
    MAT_SANDBAG = get_mat("Map_Sandbag", (0.6, 0.55, 0.45))
    MAT_CONCRETE = get_mat("Map_Concrete", (0.7, 0.7, 0.7))
    MAT_ROOF = get_mat("Map_Roof", (0.6, 0.2, 0.2))
    MAT_WINDOW = get_mat("Map_Window", (0.5, 0.8, 0.9))
    
    setup_scene()
    
    # Build models grouped closer to center for render framing
    house_objs = build_house("House", (-12, 5, 0))
    tree_objs = build_tree("Tree", (10, 8, 0))
    bush_objs = build_bush("Bush", (8, 2, 0))
    trench_objs = build_trench("Trench", (0, -10, 0))
    
    # Render
    bpy.context.scene.render.engine = 'CYCLES' if bpy.app.version[0] >= 3 else 'BLENDER_EEVEE'
    bpy.context.scene.render.filepath = os.path.abspath("map_render.png")
    bpy.ops.render.render(write_still=True)
    print("Render saved to map_render.png")
    
    # Function to export individual groups
    def export_group(objs, name):
        bpy.ops.object.select_all(action='DESELECT')
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        
        path = os.path.join(OUT_DIR, f"{name}.obj")
        bpy.ops.wm.obj_export(
            filepath=os.path.abspath(path),
            export_materials=True,
            export_triangulated_mesh=True,
            export_selected_objects=True
        )
        print(f"Exported {name}.obj")
        
    export_group(tree_objs, "Tree")
    export_group(bush_objs, "Bush")
    export_group(house_objs, "House")
    export_group(trench_objs, "Trench")

export_and_render()
