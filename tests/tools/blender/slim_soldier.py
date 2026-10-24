## Slim the Sketchfab soldier for the game: drop the stray sphere, join the
## meshes, decimate to a triangle budget, shrink textures, write grey
## (friendly) and subdued (enemy) albedo variants, export a skinned .glb.
import bpy, sys, os, bmesh
argv = sys.argv[sys.argv.index("--") + 1:]
src, outdir, budget, tex = argv[0], argv[1], int(argv[2]), int(argv[3])
os.makedirs(outdir, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
for o in list(bpy.data.objects):
    if o.type == 'MESH' and (o.name == 'Icosphere' or not o.data.materials):
        bpy.data.objects.remove(o, do_unlink=True)
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
# eyes sit behind the glasses and mask: not worth their triangles
for o in list(meshes):
    if o.data.materials[0].name == 'Mark_Eye':
        bpy.data.objects.remove(o, do_unlink=True)
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)
total = sum(tris(o) for o in meshes)
print("before", total)
# Decimate: big meshes harder (the helmet alone is 26k).
for o in meshes:
    t = tris(o)
    share = budget * (t / total) ** 0.75 / sum((tris(m) / total) ** 0.75 for m in meshes)
    ratio = min(1.0, max(0.05, share / t))
    if ratio < 0.99:
        m = o.modifiers.new("dec", 'DECIMATE')
        m.ratio = ratio
        m.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = o
        # apply decimate before the armature modifier
        bpy.ops.object.modifier_move_to_index(modifier="dec", index=0)
        bpy.ops.object.modifier_apply(modifier="dec")
print("after", sum(tris(o) for o in meshes))
# join into one mesh (one node; surfaces stay per material)
bpy.ops.object.select_all(action='DESELECT')
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.join()
body = bpy.context.view_layer.objects.active
body.name = "Body"
# Bake the idle pose (the file's real standing pose) in as the rest pose:
# freeze the posed mesh shape, then make the pose the armature's rest.
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
bpy.context.scene.frame_set(0)
bpy.context.view_layer.update()
bpy.context.view_layer.objects.active = body
mod = [m for m in body.modifiers if m.type == 'ARMATURE'][0]
mod.object = arm
bpy.ops.object.modifier_copy(modifier=mod.name)
bpy.ops.object.modifier_apply(modifier=mod.name)
bpy.ops.object.select_all(action='DESELECT')
arm.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='POSE')
bpy.ops.pose.select_all(action='SELECT')
bpy.ops.pose.armature_apply(selected=False)
bpy.ops.object.mode_set(mode='OBJECT')
arm.animation_data_clear()
# Clean hierarchy: armature + body at the root, real metres, facing +Y
# (which becomes -Z, the game's forward, in the exported file), no empties.
for o in (arm, body):
    mw = o.matrix_world.copy()
    o.parent = None
    o.matrix_world = mw
for o in list(bpy.data.objects):
    if o.type == 'EMPTY':
        bpy.data.objects.remove(o, do_unlink=True)
import math, mathutils
turn = mathutils.Matrix.Rotation(math.pi, 4, 'Z')
for o in (arm, body):
    o.matrix_world = turn @ o.matrix_world
bpy.ops.object.select_all(action='DESELECT')
arm.select_set(True); body.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
mw = body.matrix_world.copy()
body.parent = arm
body.matrix_world = mw
for m in body.modifiers:
    if m.type == 'ARMATURE':
        m.object = arm
arm.name = "Soldier"
bpy.context.view_layer.update()
hd = arm.matrix_world @ arm.data.bones['CC_Base_Head_038'].head_local
print("head at", hd[:], "body dims", body.dimensions[:])
# textures
import numpy as np
def variant(img, name, fn):
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    out = fn(px.copy())
    v = bpy.data.images.new(name, w, h, alpha=True)
    v.pixels[:] = out.reshape(-1)
    v.filepath_raw = os.path.join(outdir, name + ".png")
    v.file_format = 'PNG'
    v.save()
for img in bpy.data.images:
    if img.size[0] > tex:
        img.scale(tex, tex)
CLOTH = ["Mark_Kitel_1", "Mark_Pants_1", "Mark_Plate_1", "Mark_Pouches_1", "Mark_Helmet1", "Mark_Gloves_1", "Mark_Boots_2"]
def grey(px):          # friendly: dark grey fatigues and kit
    l = px[..., 0] * 0.3 + px[..., 1] * 0.59 + px[..., 2] * 0.11
    g = l * 0.82
    px[..., 0] = g; px[..., 1] = g; px[..., 2] = g * 1.04
    return px
def subdued(px):       # enemy: olive kit, but no bright flag colours
    l = px[..., 0] * 0.3 + px[..., 1] * 0.59 + px[..., 2] * 0.11
    sat = np.max(px[..., :3], axis=-1) - np.min(px[..., :3], axis=-1)
    k = np.clip((sat - 0.12) * 5.0, 0.0, 1.0)[..., None]
    olive = np.stack([l * 0.95, l * 1.0, l * 0.72], axis=-1)
    px[..., :3] = px[..., :3] * (1 - k) + olive * k
    return px
for mat in body.data.materials:
    if mat.name not in CLOTH:
        continue
    base = None
    for l in mat.node_tree.links:
        if l.to_socket.name == 'Base Color' and l.from_node.type == 'TEX_IMAGE':
            base = l.from_node.image
    if base:
        variant(base, mat.name + "_grey", grey)
        variant(base, mat.name + "_enemy", subdued)
        print("variants for", mat.name, base.name, base.size[:])
# no baked idle animation: the game poses him
for a in list(bpy.data.actions):
    bpy.data.actions.remove(a)
bpy.ops.export_scene.gltf(filepath=os.path.join(outdir, "soldier.glb"), export_format='GLB',
    export_animations=False, export_image_format='JPEG', export_jpeg_quality=85, export_skins=True,
    export_yup=True, export_apply=False)
print("done", sum(len(p.vertices) - 2 for p in body.data.polygons))
