"""Shared Blender helpers for the character pipeline (see design/asset-pipeline.md).

Conventions: Blender Z-up, character stands on Z=0 and faces -Y (exports to glTF +Z forward).
"""

import sys

import bpy
import bmesh
from mathutils import Vector


def args():
    """Arguments after `--` on the Blender command line."""
    return sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_glb(path, name=None):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == "MESH"]
    # Apply parent transforms (glTF import may add a root) and drop empties.
    for o in meshes:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
    for o in new:
        if o.type != "MESH":
            bpy.data.objects.remove(o)
    if len(meshes) > 1:
        join(meshes)
    obj = meshes[0]
    if name:
        obj.name = name
    apply_transforms(obj)
    return obj


def select_only(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]


def join(objs):
    select_only(objs)
    bpy.ops.object.join()
    return bpy.context.view_layer.objects.active


def apply_transforms(obj):
    select_only([obj])
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def bounds(obj):
    vs = [obj.matrix_world @ v.co for v in obj.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return lo, hi


def normalize(obj, height):
    """Scales obj to `height` meters, feet on Z=0, centered on X/Y."""
    lo, hi = bounds(obj)
    s = height / (hi.z - lo.z)
    for v in obj.data.vertices:
        v.co = (v.co - Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))) * s
    obj.data.update()


def remesh(obj, voxel, target_tris):
    """Voxel remesh to a closed mesh, then decimate to about target_tris triangles."""
    m = obj.modifiers.new("remesh", "REMESH")
    m.mode = "VOXEL"
    m.voxel_size = voxel
    m.adaptivity = 0.0
    select_only([obj])
    bpy.ops.object.modifier_apply(modifier=m.name)
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    if tris > target_tris:
        d = obj.modifiers.new("decimate", "DECIMATE")
        d.ratio = target_tris / tris
        bpy.ops.object.modifier_apply(modifier=d.name)
    bpy.ops.object.shade_smooth()


def largest_part(obj, keep_frac=0.02):
    """Welds split vertices, then deletes loose parts smaller than keep_frac of the mesh
    (floating bits from the generator). Returns the number of parts before cleaning."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.verts.ensure_lookup_table()
    seen, parts = set(), []
    for v in bm.verts:
        if v.index in seen:
            continue
        stack, part = [v], []
        seen.add(v.index)
        while stack:
            x = stack.pop()
            part.append(x)
            for e in x.link_edges:
                y = e.other_vert(x)
                if y.index not in seen:
                    seen.add(y.index)
                    stack.append(y)
        parts.append(part)
    parts.sort(key=len, reverse=True)
    total = sum(len(p) for p in parts)
    drop = [v for p in parts[1:] if len(p) < keep_frac * total for v in p]
    bmesh.ops.delete(bm, geom=drop, context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()
    return len(parts)


def smart_uv(obj, margin=0.004):
    select_only([obj])
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=margin)
    bpy.ops.object.mode_set(mode="OBJECT")


def setup_cycles_bake(samples=1):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples


def new_image_material(obj, name, size):
    """Gives obj one material with an image texture node (active, for baking)."""
    img = bpy.data.images.new(name, size, size, alpha=False)
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.8
    bsdf.inputs["Metallic"].default_value = 0.0
    nt.nodes.active = tex
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    return img


def bake_color(src, dst, extrusion, max_ray):
    """Bakes src's base color onto dst's active image (selected-to-active).
    Cycles' diffuse color pass is base color × (1 − metallic), which turns metal black, so
    metallic is switched off on src for the bake."""
    for slot in src.material_slots:
        nt = slot.material.node_tree
        for n in nt.nodes:
            if n.type == "BSDF_PRINCIPLED":
                for link in list(n.inputs["Metallic"].links):
                    nt.links.remove(link)
                n.inputs["Metallic"].default_value = 0.0
    setup_cycles_bake()
    sc = bpy.context.scene
    sc.render.bake.use_selected_to_active = True
    sc.render.bake.cage_extrusion = extrusion
    sc.render.bake.max_ray_distance = max_ray
    sc.render.bake.margin = 8
    select_only([dst])
    src.select_set(True)
    bpy.context.view_layer.objects.active = dst
    bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"})


def bake_mr(src, dst, size, extrusion, max_ray):
    """Bakes src's glTF metallic/roughness texture (G = roughness, B = metallic) onto dst's UVs.
    Rewires src's materials to emit that texture unchanged; returns the new image (non-color).
    Texels without a texture source get roughness 0.85, metallic 0."""
    for slot in src.material_slots:
        nt = slot.material.node_tree
        bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
        em = nt.nodes.new("ShaderNodeEmission")
        img_node = None
        for link in nt.links:
            if link.to_node == bsdf and link.to_socket.name in ("Metallic", "Roughness"):
                n = link.from_node
                while n.type != "TEX_IMAGE" and n.inputs and n.inputs[0].links:
                    n = n.inputs[0].links[0].from_node
                if n.type == "TEX_IMAGE":
                    img_node = n
        if img_node:
            nt.links.new(img_node.outputs["Color"], em.inputs["Color"])
        else:
            em.inputs["Color"].default_value = (0, 0.85, 0, 1)
        out_node = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
        nt.links.new(em.outputs["Emission"], out_node.inputs["Surface"])
    img = bpy.data.images.new(dst.name + "_mr", size, size, alpha=False, is_data=True)
    tex = dst.active_material.node_tree.nodes.active
    old = tex.image
    tex.image = img
    setup_cycles_bake()
    sc = bpy.context.scene
    sc.render.bake.use_selected_to_active = True
    sc.render.bake.cage_extrusion = extrusion
    sc.render.bake.max_ray_distance = max_ray
    sc.render.bake.margin = 8
    select_only([dst])
    src.select_set(True)
    bpy.context.view_layer.objects.active = dst
    bpy.ops.object.bake(type="EMIT")
    tex.image = old
    return img


def bake_normal(src, dst, size, extrusion, max_ray):
    """Bakes src's surface (its geometry) as a tangent-space normal map onto dst's UVs
    (OpenGL convention, as Godot expects). Folds of dst's own geometry are cancelled out,
    because the map reproduces src's surface direction. Returns the image (non-color)."""
    img = bpy.data.images.new(dst.name + "_normal", size, size, alpha=False, is_data=True)
    tex = dst.active_material.node_tree.nodes.active
    old = tex.image
    tex.image = img
    setup_cycles_bake()
    sc = bpy.context.scene
    sc.render.bake.use_selected_to_active = True
    sc.render.bake.cage_extrusion = extrusion
    sc.render.bake.max_ray_distance = max_ray
    sc.render.bake.margin = 8
    sc.render.bake.normal_space = "TANGENT"
    select_only([dst])
    src.select_set(True)
    bpy.context.view_layer.objects.active = dst
    bpy.ops.object.bake(type="NORMAL")
    tex.image = old
    return img


def save_image(img, path):
    img.filepath_raw = str(path)
    img.file_format = "PNG"
    img.save()


def export_glb(objs, path, animations=False):
    select_only(objs)
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True,
                              export_animations=animations, export_yup=True,
                              export_animation_mode="ACTIONS", export_force_sampling=True,
                              export_vertex_color="ACTIVE", export_tangents=True)
