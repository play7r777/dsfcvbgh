# -*- coding: utf-8 -*-
# ============================================================================
# build_assets.py — процедурная генерация 3D-моделей Frontline Arena.
# Запуск headless:
#   blender -b --factory-startup --python tools/blender/build_assets.py -- assets/fbx
#
# Создаёт:
#   assets/fbx/<Weapon>.fbx          — модели оружия с ригом и анимацией
#                                      перезарядки (кости Root/Mag/Bolt)
#   assets/fbx/bullets/<Bullet>.fbx  — модели пуль/снарядов
#
# Конвенция: ствол вдоль +X, вверх +Z, размеры в условных «стадах» Roblox.
# Анимация называется "<Weapon>_Reload" и длится столько же, сколько
# ReloadTime из WeaponConfig (30 fps).
# ============================================================================

import math
import os
import sys

import bpy

FPS = 30

# ---------------------------------------------------------------------------
# Приём аргументов после "--"
# ---------------------------------------------------------------------------
argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
OUT_DIR = argv[0] if argv else "assets/fbx"
BULLETS_DIR = os.path.join(OUT_DIR, "bullets")
os.makedirs(BULLETS_DIR, exist_ok=True)

# ---------------------------------------------------------------------------
# Материалы
# ---------------------------------------------------------------------------
def make_mat(name, rgb):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*rgb, 1.0)
    return m

GUNMETAL = DARK = OLIVE = WOOD = TAN = BRASS = STEEL_TIP = SCREEN = RED = None

def init_materials():
    global GUNMETAL, DARK, OLIVE, WOOD, TAN, BRASS, STEEL_TIP, SCREEN, RED
    GUNMETAL = make_mat("Gunmetal", (0.16, 0.17, 0.19))
    DARK = make_mat("Dark", (0.09, 0.10, 0.10))
    OLIVE = make_mat("Olive", (0.29, 0.32, 0.22))
    WOOD = make_mat("Wood", (0.38, 0.27, 0.16))
    TAN = make_mat("Tan", (0.55, 0.49, 0.35))
    BRASS = make_mat("Brass", (0.72, 0.55, 0.25))
    STEEL_TIP = make_mat("SteelTip", (0.45, 0.47, 0.50))
    SCREEN = make_mat("Screen", (0.25, 0.62, 0.78))
    RED = make_mat("SignalRed", (0.75, 0.20, 0.14))

# ---------------------------------------------------------------------------
# Строительные блоки
# ---------------------------------------------------------------------------
def box(name, size, loc, mat, rot=(0, 0, 0), bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    o.scale = (size[0], size[1], size[2])
    bpy.ops.object.transform_apply(scale=True)
    if mat:
        o.data.materials.append(mat)
    if bevel > 0:
        mod = o.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return o

def cyl(name, radius, depth, loc, mat, rot=(0, 0, 0), vertices=12):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    if mat:
        o.data.materials.append(mat)
    return o

def cone(name, r1, r2, depth, loc, mat, rot=(0, 0, 0), vertices=12):
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=r1, radius2=r2, depth=depth, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    if mat:
        o.data.materials.append(mat)
    return o

# поворот «цилиндр вдоль +X» (ствол)
ROT_X = (0, math.radians(90), 0)

# ---------------------------------------------------------------------------
# Риг и анимация перезарядки
# ---------------------------------------------------------------------------
def make_rig(name, mag_loc, bolt_loc):
    """Кости: Root (в центре), Mag (смотрит вниз -Z), Bolt (смотрит назад -X).
    Локальная +Y кости = направление кости => Mag двигается 'вниз', Bolt 'назад'."""
    arm = bpy.data.armatures.new(name)
    rig = bpy.data.objects.new(name, arm)
    bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    root = arm.edit_bones.new("Root")
    root.head = (0, 0, 0)
    root.tail = (0, 0, 0.1)
    mag = arm.edit_bones.new("Mag")
    mag.head = mag_loc
    mag.tail = (mag_loc[0], mag_loc[1], mag_loc[2] - 0.05)
    mag.parent = root
    bolt = arm.edit_bones.new("Bolt")
    bolt.head = bolt_loc
    bolt.tail = (bolt_loc[0] - 0.05, bolt_loc[1], bolt_loc[2])
    bolt.parent = root
    bpy.ops.object.mode_set(mode="OBJECT")
    rig.select_set(False)
    return rig

def bone_parent(obj, rig, bone_name):
    mw = obj.matrix_world.copy()
    obj.parent = rig
    obj.parent_type = "BONE"
    obj.parent_bone = bone_name
    obj.matrix_world = mw

def reload_anim(rig, weapon_name, reload_seconds, mag_travel=0.24, bolt_travel=0.14, has_bolt=True):
    """Ключи: магазин/боевая часть вниз-наружу и обратно, затвор назад-вперёд.
    В pose-пространстве +Y кости — вдоль её направления."""
    total = max(12, int(round(reload_seconds * FPS)))
    scene = bpy.context.scene
    scene.frame_start = 1
    scene.frame_end = total
    scene.render.fps = FPS

    rig.animation_data_create()
    act = bpy.data.actions.new(weapon_name + "_Reload")
    rig.animation_data.action = act

    def key(bone_name, frame, loc):
        pb = rig.pose.bones[bone_name]
        pb.location = loc
        pb.keyframe_insert("location", frame=frame)

    key("Mag", 1, (0, 0, 0))
    key("Mag", max(2, int(total * 0.18)), (0, mag_travel, 0))   # извлечён
    key("Mag", max(3, int(total * 0.50)), (0, mag_travel, 0))   # пауза
    key("Mag", max(4, int(total * 0.68)), (0, 0, 0))            # вставлен
    if has_bolt:
        key("Bolt", 1, (0, 0, 0))
        key("Bolt", max(5, int(total * 0.72)), (0, 0, 0))
        key("Bolt", max(6, int(total * 0.85)), (0, bolt_travel, 0))  # назад
        key("Bolt", total, (0, 0, 0))                                 # вперёд
    else:
        key("Mag", total, (0, 0, 0))

# ---------------------------------------------------------------------------
# Экспорт
# ---------------------------------------------------------------------------
def export_fbx(path, objects, animated=True):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    if objects:
        bpy.context.view_layer.objects.active = objects[0]
    kwargs = dict(
        filepath=path,
        use_selection=True,
        add_leaf_bones=False,
        apply_scale_options="FBX_SCALE_ALL",
    )
    if animated:
        kwargs["bake_anim"] = True
        kwargs["bake_anim_use_all_bones"] = True
        kwargs["bake_anim_force_startend_keying"] = True
    bpy.ops.export_scene.fbx(**kwargs)
    print("[build_assets] wrote", path)

def at(origin, loc):
    return (origin[0] + loc[0], origin[1] + loc[1], origin[2] + loc[2])

# ============================================================================
# ОРУЖИЕ
# ============================================================================
def build_assault_rifle(origin):
    n = "AssaultRifle"
    parts = []
    parts.append(box(n + "_Receiver", (0.55, 0.09, 0.13), at(origin, (0.10, 0, 0.09)), GUNMETAL, bevel=0.01))
    parts.append(box(n + "_Handguard", (0.34, 0.10, 0.11), at(origin, (-0.36, 0, 0.10)), OLIVE, bevel=0.01))
    parts.append(cyl(n + "_Barrel", 0.022, 0.45, at(origin, (-0.62, 0, 0.10)), DARK, ROT_X))
    parts.append(cyl(n + "_Muzzle", 0.032, 0.07, at(origin, (-0.86, 0, 0.10)), GUNMETAL, ROT_X))
    mag = box(n + "_Magazine", (0.09, 0.07, 0.24), at(origin, (0.02, 0, -0.08)), GUNMETAL, rot=(0, math.radians(-8), 0))
    parts.append(mag)
    parts.append(box(n + "_Stock", (0.28, 0.08, 0.12), at(origin, (0.50, 0, 0.07)), OLIVE, bevel=0.01))
    parts.append(box(n + "_Grip", (0.07, 0.07, 0.18), at(origin, (0.22, 0, -0.05)), DARK, rot=(0, math.radians(12), 0)))
    parts.append(box(n + "_SightF", (0.02, 0.03, 0.06), at(origin, (-0.52, 0, 0.19)), DARK))
    parts.append(box(n + "_SightR", (0.04, 0.03, 0.05), at(origin, (0.18, 0, 0.19)), DARK))
    bolt = cyl(n + "_ChargingHandle", 0.015, 0.08, at(origin, (0.12, 0.07, 0.13)), DARK, (math.radians(90), 0, 0))
    parts.append(bolt)
    rig = make_rig(n + "_Rig", at(origin, (0.02, 0, -0.08)), at(origin, (0.12, 0.07, 0.13)))
    bone_parent(mag, rig, "Mag")
    bone_parent(bolt, rig, "Bolt")
    reload_anim(rig, n, 2.3)
    return parts + [rig]

def build_pistol(origin):
    n = "Pistol"
    parts = []
    parts.append(box(n + "_Slide", (0.30, 0.06, 0.07), at(origin, (0.0, 0, 0.06)), GUNMETAL, bevel=0.008))
    parts.append(box(n + "_Frame", (0.26, 0.055, 0.06), at(origin, (0.0, 0, 0.0)), DARK, bevel=0.008))
    mag = box(n + "_Magazine", (0.06, 0.05, 0.16), at(origin, (0.08, 0, -0.09)), GUNMETAL, rot=(0, math.radians(10), 0))
    parts.append(mag)
    parts.append(box(n + "_GripPanel", (0.08, 0.06, 0.16), at(origin, (0.09, 0, -0.08)), OLIVE, rot=(0, math.radians(10), 0)))
    parts.append(cyl(n + "_Muzzle", 0.02, 0.04, at(origin, (-0.17, 0, 0.06)), DARK, ROT_X))
    bolt = box(n + "_Hammer", (0.02, 0.04, 0.05), at(origin, (0.15, 0, 0.06)), DARK)
    parts.append(bolt)
    rig = make_rig(n + "_Rig", at(origin, (0.08, 0, -0.09)), at(origin, (0.15, 0, 0.06)))
    bone_parent(mag, rig, "Mag")
    bone_parent(bolt, rig, "Bolt")
    reload_anim(rig, n, 1.7, mag_travel=0.18, bolt_travel=0.08)
    return parts + [rig]

def build_sniper(origin):
    n = "SniperRifle"
    parts = []
    parts.append(box(n + "_Receiver", (0.70, 0.09, 0.13), at(origin, (0.05, 0, 0.09)), GUNMETAL, bevel=0.01))
    parts.append(cyl(n + "_Barrel", 0.02, 0.85, at(origin, (-0.75, 0, 0.10)), DARK, ROT_X))
    parts.append(cyl(n + "_MuzzleBrake", 0.035, 0.08, at(origin, (-1.16, 0, 0.10)), GUNMETAL, ROT_X))
    parts.append(box(n + "_Stock", (0.45, 0.08, 0.16), at(origin, (0.62, 0, 0.05)), OLIVE, bevel=0.01))
    parts.append(box(n + "_Cheek", (0.18, 0.07, 0.05), at(origin, (0.55, 0, 0.15)), OLIVE))
    parts.append(box(n + "_Grip", (0.07, 0.07, 0.16), at(origin, (0.22, 0, -0.04)), DARK, rot=(0, math.radians(14), 0)))
    mag = box(n + "_Magazine", (0.16, 0.06, 0.13), at(origin, (-0.02, 0, -0.03)), DARK)
    parts.append(mag)
    parts.append(cyl(n + "_ScopeTube", 0.035, 0.30, at(origin, (0.02, 0, 0.22)), DARK, ROT_X))
    parts.append(cyl(n + "_ScopeBell", 0.05, 0.06, at(origin, (-0.15, 0, 0.22)), GUNMETAL, ROT_X))
    parts.append(box(n + "_ScopeMount", (0.16, 0.04, 0.05), at(origin, (0.02, 0, 0.16)), GUNMETAL))
    bolt = cyl(n + "_BoltHandle", 0.014, 0.10, at(origin, (0.12, 0.08, 0.10)), STEEL_TIP, (math.radians(90), 0, 0))
    parts.append(bolt)
    rig = make_rig(n + "_Rig", at(origin, (-0.02, 0, -0.03)), at(origin, (0.12, 0.08, 0.10)))
    bone_parent(mag, rig, "Mag")
    bone_parent(bolt, rig, "Bolt")
    reload_anim(rig, n, 3.4, mag_travel=0.16, bolt_travel=0.10)
    return parts + [rig]

def build_lmg(origin):
    n = "LMG"
    parts = []
    parts.append(box(n + "_Receiver", (0.75, 0.12, 0.17), at(origin, (0.05, 0, 0.10)), GUNMETAL, bevel=0.012))
    parts.append(cyl(n + "_Barrel", 0.026, 0.70, at(origin, (-0.72, 0, 0.11)), DARK, ROT_X))
    parts.append(cyl(n + "_Shroud", 0.05, 0.32, at(origin, (-0.45, 0, 0.11)), OLIVE, ROT_X))
    boxmag = box(n + "_AmmoBox", (0.26, 0.13, 0.20), at(origin, (-0.02, 0, -0.08)), OLIVE, bevel=0.01)
    parts.append(boxmag)
    parts.append(box(n + "_Stock", (0.32, 0.10, 0.14), at(origin, (0.55, 0, 0.08)), DARK, bevel=0.01))
    parts.append(box(n + "_Grip", (0.07, 0.08, 0.18), at(origin, (0.24, 0, -0.06)), DARK, rot=(0, math.radians(12), 0)))
    parts.append(box(n + "_CarryHandle", (0.16, 0.03, 0.05), at(origin, (-0.20, 0, 0.24)), DARK))
    parts.append(box(n + "_BipodL", (0.02, 0.02, 0.24), at(origin, (-0.85, 0.06, -0.06)), DARK, rot=(math.radians(18), 0, 0)))
    parts.append(box(n + "_BipodR", (0.02, 0.02, 0.24), at(origin, (-0.85, -0.06, -0.06)), DARK, rot=(math.radians(-18), 0, 0)))
    bolt = cyl(n + "_ChargingHandle", 0.016, 0.09, at(origin, (0.20, 0.08, 0.12)), DARK, (math.radians(90), 0, 0))
    parts.append(bolt)
    rig = make_rig(n + "_Rig", at(origin, (-0.02, 0, -0.08)), at(origin, (0.20, 0.08, 0.12)))
    bone_parent(boxmag, rig, "Mag")
    bone_parent(bolt, rig, "Bolt")
    reload_anim(rig, n, 5.2, mag_travel=0.22, bolt_travel=0.12)
    return parts + [rig]

def build_rpg(origin):
    n = "RPG"
    parts = []
    parts.append(cyl(n + "_Tube", 0.045, 1.50, at(origin, (0.0, 0, 0.12)), OLIVE, ROT_X))
    parts.append(cone(n + "_RearCone", 0.09, 0.045, 0.18, at(origin, (0.82, 0, 0.12)), DARK, (0, math.radians(-90), 0)))
    warhead = cone(n + "_Warhead", 0.045, 0.10, 0.34, at(origin, (-0.90, 0, 0.12)), TAN, (0, math.radians(-90), 0))
    parts.append(warhead)
    parts.append(box(n + "_Grip", (0.07, 0.07, 0.20), at(origin, (0.10, 0, -0.02)), DARK))
    parts.append(box(n + "_Trigger", (0.05, 0.03, 0.06), at(origin, (0.02, 0, 0.02)), DARK))
    parts.append(box(n + "_Sight", (0.05, 0.03, 0.12), at(origin, (-0.15, 0, 0.22)), DARK))
    bolt = box(n + "_SafetyPin", (0.03, 0.03, 0.06), at(origin, (-0.60, 0, 0.12)), RED)
    parts.append(bolt)
    rig = make_rig(n + "_Rig", at(origin, (-0.90, 0, 0.12)), at(origin, (-0.60, 0, 0.12)))
    bone_parent(warhead, rig, "Mag")  # перезарядка = новая боевая часть
    bone_parent(bolt, rig, "Bolt")
    reload_anim(rig, n, 3.8, mag_travel=0.30, bolt_travel=0.05)
    return parts + [rig]

def build_c4(origin):
    n = "C4Charge"
    parts = [
        box(n + "_Block", (0.22, 0.15, 0.07), at(origin, (0, 0, 0.035)), TAN, bevel=0.015),
        box(n + "_Stripe", (0.22, 0.04, 0.02), at(origin, (0, 0, 0.075)), RED),
    ]
    rig = make_rig(n + "_Rig", at(origin, (0, 0, 0.03)), at(origin, (0, 0, 0.05)))
    reload_anim(rig, n, 0.8, mag_travel=0.0, has_bolt=False)  # без анимации магазина
    return parts + [rig]

def build_detonator(origin):
    n = "Detonator"
    parts = [
        box(n + "_Body", (0.09, 0.16, 0.05), at(origin, (0, 0, 0.025)), DARK, bevel=0.008),
        cyl(n + "_Antenna", 0.008, 0.22, at(origin, (0.03, 0.05, 0.15)), GUNMETAL),
        box(n + "_Button", (0.04, 0.04, 0.02), at(origin, (0, -0.02, 0.06)), RED),
    ]
    rig = make_rig(n + "_Rig", at(origin, (0, 0, 0.02)), at(origin, (0, 0, 0.04)))
    reload_anim(rig, n, 0.8, mag_travel=0.0, has_bolt=False)
    return parts + [rig]

def build_landmine(origin):
    n = "Landmine"
    parts = [
        cyl(n + "_Body", 0.17, 0.07, at(origin, (0, 0, 0.035)), OLIVE, vertices=16),
        cyl(n + "_Cap", 0.06, 0.04, at(origin, (0, 0, 0.08)), DARK, vertices=12),
    ]
    rig = make_rig(n + "_Rig", at(origin, (0, 0, 0.03)), at(origin, (0, 0, 0.05)))
    reload_anim(rig, n, 0.8, mag_travel=0.0, has_bolt=False)
    return parts + [rig]

def build_tablet(origin):
    n = "DroneTablet"
    parts = [
        box(n + "_Body", (0.30, 0.20, 0.02), at(origin, (0, 0, 0.01)), DARK, bevel=0.01),
        box(n + "_Screen", (0.26, 0.16, 0.012), at(origin, (0, 0, 0.02)), SCREEN),
        box(n + "_StickL", (0.03, 0.03, 0.05), at(origin, (-0.10, 0.11, 0.03)), GUNMETAL),
        box(n + "_StickR", (0.03, 0.03, 0.05), at(origin, (0.10, 0.11, 0.03)), GUNMETAL),
    ]
    rig = make_rig(n + "_Rig", at(origin, (0, 0, 0.01)), at(origin, (0, 0, 0.03)))
    reload_anim(rig, n, 0.8, mag_travel=0.0, has_bolt=False)
    return parts + [rig]

# ============================================================================
# ПУЛИ / СНАРЯДЫ (без анимации)
# ============================================================================
def build_bullet(name, case_r, case_d, tip_r, tip_d, origin):
    parts = [
        cyl(name + "_Body", case_r, case_d, at(origin, (0, 0, 0)), BRASS, ROT_X, vertices=10),
        cone(name + "_Tip", tip_r, 0.002, tip_d, at(origin, (-(case_d + tip_d) / 2, 0, 0)), STEEL_TIP, (0, math.radians(-90), 0), vertices=10),
    ]
    return parts

def build_rpg_warhead(origin):
    n = "RPG_Warhead"
    parts = [
        cone(n + "_Nose", 0.09, 0.02, 0.22, at(origin, (-0.21, 0, 0)), TAN, (0, math.radians(-90), 0)),
        cyl(n + "_Body", 0.05, 0.22, at(origin, (0.02, 0, 0)), GUNMETAL, ROT_X),
        cyl(n + "_Stem", 0.02, 0.16, at(origin, (0.20, 0, 0)), DARK, ROT_X),
    ]
    for i in range(4):
        ang = math.radians(i * 90)
        parts.append(box(n + "_Fin" + str(i), (0.10, 0.005, 0.06),
                         at(origin, (0.24, math.cos(ang) * 0.045, math.sin(ang) * 0.045)),
                         DARK, rot=(ang, 0, 0)))
    return parts

# ============================================================================
# СБОРКА ВСЕГО
# ============================================================================
def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    init_materials()

    builders = [
        ("AssaultRifle", build_assault_rifle),
        ("Pistol", build_pistol),
        ("SniperRifle", build_sniper),
        ("LMG", build_lmg),
        ("RPG", build_rpg),
        ("C4Charge", build_c4),
        ("Detonator", build_detonator),
        ("Landmine", build_landmine),
        ("DroneTablet", build_tablet),
    ]

    for i, (name, fn) in enumerate(builders):
        origin = (0, i * 3.0, 0)
        objects = fn(origin)
        export_fbx(os.path.join(OUT_DIR, name + ".fbx"), objects, animated=True)

    bullets = [
        ("B_9x19", 0.009, 0.014, 0.009, 0.012),
        ("B_762x39", 0.008, 0.026, 0.008, 0.016),
        ("B_762x54R", 0.008, 0.034, 0.008, 0.020),
        ("B_338Lapua", 0.009, 0.040, 0.009, 0.026),
    ]
    for j, (name, cr, cd, tr, td) in enumerate(bullets):
        objects = build_bullet(name, cr, cd, tr, td, (0, j * 1.0, 0))
        export_fbx(os.path.join(BULLETS_DIR, name + ".fbx"), objects, animated=False)

    objects = build_rpg_warhead((0, 10.0, 0))
    export_fbx(os.path.join(BULLETS_DIR, "RPG_Warhead.fbx"), objects, animated=False)

    print("[build_assets] DONE ->", os.path.abspath(OUT_DIR))

main()
