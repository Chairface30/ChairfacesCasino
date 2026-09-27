"""Rewire the zeppelin's textures after a path-broken glTF import.

Run INSIDE Blender (Scripting tab -> Open -> Run Script), same as
zep_render.py.

The wow.export glTFs reference their textures through relative paths that
only resolve inside the wow.export folder tree; imported from anywhere
else, Blender silently creates the materials with no image nodes at all
(that's the all-pink ship, and why Find Missing Files reports nothing).

Every material is named after its texture (mat_jlo_goblinzep_hull ->
jlo_goblinzep_hull.png), so this script walks all materials, finds the
matching PNG under TEXTURE_ROOT, and plugs it into the Principled BSDF's
Base Color. Re-run zep_render.py afterwards.
"""

import os

import bpy

# Where the exported PNGs live (searched recursively by filename).
TEXTURE_ROOT = r"C:\Users\slayi\wow.export"


def build_png_index(root):
    index = {}
    for dirpath, _dirnames, filenames in os.walk(root):
        for fn in filenames:
            if fn.lower().endswith(".png"):
                index.setdefault(fn.lower(), os.path.join(dirpath, fn))
    return index


def texture_name_for(mat):
    """mat_jlo_goblinzep_hull / jlo_goblinzep_engine.001 -> jlo_...png"""
    name = mat.name
    if "." in name:  # strip Blender's .001 duplicate suffix
        base, ext = name.rsplit(".", 1)
        if ext.isdigit():
            name = base
    if name.startswith("mat_"):
        name = name[4:]
    return name.lower() + ".png"


def has_base_color_image(mat, bsdf):
    link = next((l for l in mat.node_tree.links
                 if l.to_node == bsdf and l.to_socket.name == "Base Color"),
                None)
    return link is not None and link.from_node.type == "TEX_IMAGE"


def main():
    pngs = build_png_index(TEXTURE_ROOT)
    if not pngs:
        raise RuntimeError("No PNGs found under %s" % TEXTURE_ROOT)

    fixed, already, unmatched = [], [], []
    for mat in bpy.data.materials:
        if not mat.use_nodes:
            continue
        bsdf = next((n for n in mat.node_tree.nodes
                     if n.type == "BSDF_PRINCIPLED"), None)
        if not bsdf:
            continue
        if has_base_color_image(mat, bsdf):
            already.append(mat.name)
            continue
        want = texture_name_for(mat)
        path = pngs.get(want)
        if not path:
            unmatched.append("%s (wanted %s)" % (mat.name, want))
            continue
        img = bpy.data.images.load(path, check_existing=True)
        node = mat.node_tree.nodes.new("ShaderNodeTexImage")
        node.image = img
        node.location = (bsdf.location.x - 320, bsdf.location.y)
        mat.node_tree.links.new(node.outputs["Color"],
                                bsdf.inputs["Base Color"])
        fixed.append("%s <- %s" % (mat.name, os.path.basename(path)))

    print("Hooked %d material(s):" % len(fixed))
    for line in fixed:
        print("   " + line)
    if already:
        print("Already textured: %s" % ", ".join(already))
    if unmatched:
        print("NO MATCH (still pink): %s" % "; ".join(unmatched))
    print("Done. Check Material Preview, then re-run zep_render.py.")


main()
