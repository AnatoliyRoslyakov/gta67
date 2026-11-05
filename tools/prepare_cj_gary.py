"""Prepare the downloaded Sketchfab models for Godot. Run with Blender 4.2 bpy.

Sources and credits are in characters/CREDITS.md. Raw downloads remain local.
"""
import bpy
import math
import os
import sys
from pathlib import Path
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'Assets/Characters'


def load_model(name):
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=str(ASSETS / name / 'source/original.glb'))
    # glTF imports joint-display helper meshes; they are not part of the model.
    for obj in list(bpy.data.objects):
        if obj.type == 'MESH' and not obj.data.materials:
            bpy.data.objects.remove(obj, do_unlink=True)
    objects = [o for o in bpy.context.scene.objects if o.type in {'MESH', 'ARMATURE'}]
    for obj in objects:
        transform = obj.matrix_world.copy()
        obj.parent = None
        obj.matrix_world = transform
    for obj in list(bpy.context.scene.objects):
        if obj.type not in {'MESH', 'ARMATURE'}:
            bpy.data.objects.remove(obj, do_unlink=True)
    bpy.ops.object.select_all(action='SELECT')
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return objects


def export(name):
    bpy.ops.export_scene.gltf(filepath=str(ASSETS / name / (name.lower()+'.glb')),
                              export_format='GLB', export_animations=False,
                              export_yup=True, export_extras=True)
    print('EXPORTED', name, flush=True)


objects = load_model('CJ')
rig = next(o for o in objects if o.type == 'ARMATURE')
rig.name = 'GeneralSkeleton'
names = {'pelvis_02': 'Hips', 'spine lower_011': 'Spine',
         'spine middle_012': 'Chest', 'spine upper_013': 'UpperChest',
         'head neck lower_014': 'Neck', 'head neck upper_015': 'Head'}
for side, indices in [('left', ['03','04','05','06','038','039','040','041','042','043','044','045','046','047']),
                      ('right', ['07','08','09','010','048','049','050','051','052','053','054','055','056','057'])]:
    parts = ['thigh','knee','ankle','toes']
    targets = ['UpperLeg','LowerLeg','Foot','Toes']
    for part, target, index in zip(parts, targets, indices[:4]):
        names[f'leg {side} {part}_{index}'] = side.title()+target
    parts = ['shoulder 1','shoulder 2','elbow','wrist','finger 2a','finger 2b','finger 2c','finger 1a','finger 1b','finger 1c']
    targets = ['Shoulder','UpperArm','LowerArm','Hand','MiddleProximal','MiddleIntermediate','MiddleDistal','ThumbMetacarpal','ThumbProximal','ThumbDistal']
    for part, target, index in zip(parts, targets, indices[4:]):
        names[f'arm {side} {part}_{index}'] = side.title()+target
for old, new in names.items():
    rig.data.bones[old].name = new
    for obj in objects:
        if obj.type == 'MESH' and old in obj.vertex_groups:
            obj.vertex_groups[old].name = new
for obj in objects:
    if obj.type == 'MESH':
        obj.name = 'GEO-CJ-' + obj.data.materials[0].name
        obj.parent = rig
        for mat in obj.data.materials:
            mat.use_backface_culling = False
            if mat.use_nodes:
                p = mat.node_tree.nodes.get('Principled BSDF')
                if p: p.inputs['Roughness'].default_value = 0.85
export('CJ')

objects = load_model('Gary')
rotation = Matrix.Rotation(math.pi/2, 4, 'Z')
for obj in objects:
    obj.data.transform(Matrix.Scale(0.44, 4) @ rotation)
    # Maintain the outline and materials, simplify only the dense smooth surfaces.
    if len(obj.data.vertices) > 2000:
        bpy.context.view_layer.objects.active = obj
        mod = obj.modifiers.new('Game mesh reduction', 'DECIMATE')
        mod.ratio = 0.16
        bpy.ops.object.modifier_apply(modifier=mod.name)
    for polygon in obj.data.polygons: polygon.use_smooth = True
    for mat in obj.data.materials:
        if mat.use_nodes:
            p = mat.node_tree.nodes.get('Principled BSDF')
            if p: p.inputs['Roughness'].default_value = 0.72

def marker(name, location, parent=None):
    obj = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(obj)
    obj.location = location
    obj.parent = parent
    return obj

for side, ids, sign in [('Left', [7,71,73,75], 1), ('Right', [5,65,67,69], -1)]:
    pivot = marker(side+'EyePivot', (sign*0.0935, -0.715, 0.737))
    for index in ids:
        obj = bpy.data.objects[f'Object_{index}']
        # Shorter stems bring the eye tops down to the seated rider's hands.
        if index in [5, 7]:
            for vertex in obj.data.vertices:
                vertex.co.z = 0.737 + (vertex.co.z - 0.737) * 0.65
        else:
            obj.data.transform(Matrix.Translation((0, 0, -0.24)))
        obj.parent = pivot
        obj.matrix_parent_inverse = Matrix.Translation(-pivot.location)
        obj.name = 'GEO-'+side+'Eye-'+str(index)
    # Grip rests on top of each eye, matching the supplied riding reference.
    marker(side+'Grip', (sign*0.10, 0.0, 0.80), pivot)
marker('RideSeat', (0, -0.28, 1.37))
for obj in objects:
    if obj.name.startswith('Object_'): obj.name = 'GEO-Gary-'+obj.name
# Batch static parts and each eye assembly while retaining material slots.
for group in [None, bpy.data.objects['LeftEyePivot'], bpy.data.objects['RightEyePivot']]:
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH' and o.parent == group]
    bpy.ops.object.select_all(action='DESELECT')
    for obj in meshes: obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()
    bpy.context.object.name = 'GEO-GaryBody' if group is None else 'GEO-'+group.name
export('Gary')
sys.stdout.flush()
# The standalone macOS bpy wheel crashes during Python interpreter teardown.
if bpy.app.background and 'blender' not in Path(sys.executable).name.lower(): os._exit(0)
