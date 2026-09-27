"""Render the Crash zeppelin sprite frames from an assembled Blender scene.

Run this INSIDE Blender on the scene that already has the zeppelin hull and
the propeller doodad(s) imported with their m2 animation:

    Scripting tab -> Open -> zep_render.py -> Run Script

(or headless:  blender -b your_scene.blend -P tools/zep_render.py)

What it does:
  1. Finds the propeller object(s) (by name substring, or list them
     explicitly in PROP_OBJECTS below).
  2. Measures the prop's rotation speed from the imported animation and
     picks the frame span covering exactly one full revolution (divided by
     SYMMETRY) -- rendering that span gives a perfectly seamless loop, so
     the whole 96-unit m2 loop never needs to be rendered.
  3. Aims an orthographic side camera at the model (transparent film,
     sun + ambient light) and renders FRAMES evenly spaced PNGs into
     OUT_DIR.
  4. Prints the sprite-sheet fps that matches the animation's real speed.

Then feed the PNGs to tools/build_zep_sheet.py.

If the auto-detect can't measure the spin (e.g. the rotation lives on an
armature bone that doesn't move the object's matrix), scrub the timeline,
note the frame numbers where the prop completes one revolution, and set
SPAN_START / SPAN_END manually.
"""

import math
import os

import bpy
from mathutils import Vector

# ======================= CONFIG (edit these) =======================

# Objects that spin. Either exact names ["Propeller", "Propeller.001"] or
# leave empty to match every object whose name contains PROP_NAME_HINT.
# (In this scene the propeller doodad imported as "zepanimation" /
# "zepanimation_Geoset0"; the hull is transport_zeppelin*.)
PROP_OBJECTS = []
PROP_NAME_HINT = "zepanimation"

# Stray helper objects to keep out of the render and camera framing.
EXCLUDE_OBJECTS = ["Icosphere"]

FRAMES = 10        # sprite frames to render across one revolution
SYMMETRY = 1       # blade symmetry: 2 for a 2-blade prop halves the loop

# Manual span override (scene frame numbers). None = auto-detect from the
# prop's animation. SPAN covers exactly one revolution / SYMMETRY.
SPAN_START = None
SPAN_END = None

# Camera direction the ship is seen FROM. She must end up nose-pointing
# RIGHT in the image. Try "FRONT" first; if the nose points left re-run
# with "BACK" (or fix it later with --flip-x in build_zep_sheet.py).
VIEW = "FRONT"     # FRONT | BACK | LEFT | RIGHT
MARGIN = 1.08      # bounding-box framing margin

RES_X, RES_Y = 512, 256   # 2x the final 256x128 sprite frame

# Output folder. "//" = next to the .blend file.
OUT_DIR = "//zep_frames"

# Pin everything that isn't a prop at its span-start pose so hull bobbing
# baked into the m2 loop doesn't break the seamless prop loop (the addon
# does the bobbing in code).
PIN_HULL = True

# ====================================================================


def prop_objects():
    if PROP_OBJECTS:
        objs = [bpy.data.objects[n] for n in PROP_OBJECTS if n in bpy.data.objects]
        missing = [n for n in PROP_OBJECTS if n not in bpy.data.objects]
        if missing:
            print("WARNING: PROP_OBJECTS not found in scene: %s" % ", ".join(missing))
    else:
        hint = PROP_NAME_HINT.lower()
        objs = [o for o in bpy.data.objects if hint in o.name.lower()]
    if not objs:
        raise RuntimeError(
            "No propeller objects found. Set PROP_OBJECTS or PROP_NAME_HINT "
            "at the top of the script. Scene objects: %s"
            % ", ".join(sorted(o.name for o in bpy.data.objects)))
    print("Prop objects: %s" % ", ".join(o.name for o in objs))
    return objs


def rotation_channels(obj):
    """Everything on this object that can rotate: the object itself, plus
    each pose bone when it's an armature (wow.export glTF puts the m2
    animation on bones, so the object matrix alone never turns)."""
    channels = [(obj.name, obj, None)]
    if obj.type == "ARMATURE" and obj.pose:
        channels += [("%s:%s" % (obj.name, pb.name), obj, pb)
                     for pb in obj.pose.bones]
    return channels


def channel_quat(obj, bone, depsgraph):
    ev = obj.evaluated_get(depsgraph)
    if bone is not None:
        return (ev.matrix_world @ ev.pose.bones[bone.name].matrix).to_quaternion()
    return ev.matrix_world.to_quaternion()


def measure_revolution(scene, prop):
    """Walk scene frames accumulating rotation on every channel of the prop
    until the fastest one has turned 360/SYMMETRY degrees. Returns
    ((start, end) or None, degrees_turned, channel_name)."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    channels = rotation_channels(prop)
    start = scene.frame_start
    target = 2 * math.pi / max(1, SYMMETRY)
    step = 0.25  # quarter-frame sampling; props can spin fast
    scene.frame_set(start)
    prev = [channel_quat(o, b, depsgraph) for _, o, b in channels]
    total = [0.0] * len(channels)
    f = start
    max_f = scene.frame_end
    best = 0
    while total[best] < target and f < max_f:
        f += step
        scene.frame_set(int(f), subframe=f - int(f))
        for i, (_, o, b) in enumerate(channels):
            cur = channel_quat(o, b, depsgraph)
            total[i] += prev[i].rotation_difference(cur).angle
            prev[i] = cur
        best = max(range(len(channels)), key=lambda i: total[i])
    name = channels[best][0]
    if total[best] < target * 0.98:
        return None, total[best], name
    return (float(start), f), total[best], name


def detect_revolution_span(scene, props):
    """Try each candidate prop object; use the first whose object or bones
    actually complete a revolution."""
    for prop in props:
        span, total, channel = measure_revolution(scene, prop)
        if span:
            print("Spin found on '%s': one revolution/%d = frames "
                  "%.2f .. %.2f (%.2f frames, %.0f deg accumulated)"
                  % (channel, SYMMETRY, span[0], span[1],
                     span[1] - span[0], math.degrees(total)))
            return span
        print("'%s' best channel '%s' only turned %.0f deg over frames "
              "%d-%d, trying next..."
              % (prop.name, channel, math.degrees(total),
                 scene.frame_start, scene.frame_end))
    raise RuntimeError(
        "No candidate object completes a revolution. Scrub the timeline, "
        "note the frames where the prop comes back around, and set "
        "SPAN_START/SPAN_END manually at the top of the script.")


def scene_bounds(exclude=()):
    """World-space bounding box of all visible mesh objects."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    lo = Vector((1e18, 1e18, 1e18))
    hi = Vector((-1e18, -1e18, -1e18))
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH" or obj.hide_render or obj in exclude:
            continue
        ev = obj.evaluated_get(depsgraph)
        for corner in ev.bound_box:
            p = ev.matrix_world @ Vector(corner)
            lo = Vector(map(min, lo, p))
            hi = Vector(map(max, hi, p))
    if lo.x > hi.x:
        raise RuntimeError("No visible mesh objects to frame.")
    return lo, hi


VIEW_DIRS = {
    # camera position offset axis, and which world axes span image (x, y)
    "FRONT": (Vector((0, -1, 0)), "x", "z"),
    "BACK":  (Vector((0, 1, 0)),  "x", "z"),
    "LEFT":  (Vector((-1, 0, 0)), "y", "z"),
    "RIGHT": (Vector((1, 0, 0)),  "y", "z"),
}


def setup_camera_and_lights():
    lo, hi = scene_bounds()
    center = (lo + hi) / 2
    size = hi - lo
    off_dir, ax_w, ax_h = VIEW_DIRS[VIEW.upper()]

    width = getattr(size, ax_w)
    height = getattr(size, ax_h)
    depth = size.length  # generous stand-off

    cam_data = bpy.data.cameras.get("ZepCam") or bpy.data.cameras.new("ZepCam")
    cam_data.type = "ORTHO"
    aspect = RES_X / RES_Y
    cam_data.ortho_scale = max(width, height * aspect) * MARGIN
    cam_data.clip_start = 0.01
    cam_data.clip_end = depth * 10 + 100

    cam = bpy.data.objects.get("ZepCamObj")
    if not cam:
        cam = bpy.data.objects.new("ZepCamObj", cam_data)
        bpy.context.scene.collection.objects.link(cam)
    cam.data = cam_data
    cam.location = center + off_dir * (depth * 2 + 1)
    # aim at the center
    look = (center - cam.location).normalized()
    cam.rotation_euler = look.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = cam

    # key light: sun over the camera's shoulder, plus flat world ambient
    sun = bpy.data.objects.get("ZepSun")
    if not sun:
        sun_data = bpy.data.lights.new("ZepSunLight", type="SUN")
        sun = bpy.data.objects.new("ZepSun", sun_data)
        bpy.context.scene.collection.objects.link(sun)
    sun.data.energy = 3.0
    sun.location = cam.location + Vector((0, 0, depth))
    sun_look = (center - sun.location).normalized()
    sun.rotation_euler = sun_look.to_track_quat("-Z", "Y").to_euler()

    world = bpy.context.scene.world or bpy.data.worlds.new("ZepWorld")
    bpy.context.scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (1, 1, 1, 1)
        bg.inputs[1].default_value = 0.6


def pin_non_props(props, at_frame):
    """Freeze every non-prop object at its at_frame pose by stripping its
    action (restored by the caller via the returned list)."""
    scene = bpy.context.scene
    scene.frame_set(int(at_frame), subframe=at_frame - int(at_frame))
    depsgraph = bpy.context.evaluated_depsgraph_get()
    saved = []
    prop_set = set(props)
    for obj in scene.objects:
        ad = obj.animation_data
        if not ad or not ad.action or obj in prop_set:
            continue
        pose = obj.evaluated_get(depsgraph).matrix_world.copy()
        saved.append((obj, ad.action))
        ad.action = None
        obj.matrix_world = pose
    if saved:
        print("Pinned %d animated non-prop object(s): %s"
              % (len(saved), ", ".join(o.name for o, _ in saved)))
    return saved


def main():
    scene = bpy.context.scene
    props = prop_objects()

    for name in EXCLUDE_OBJECTS:
        obj = bpy.data.objects.get(name)
        if obj and not obj.hide_render:
            obj.hide_render = True
            print("Excluded '%s' from render and framing" % name)

    if SPAN_START is not None and SPAN_END is not None:
        span = (float(SPAN_START), float(SPAN_END))
        print("Using manual span: frames %.2f .. %.2f" % span)
    else:
        span = detect_revolution_span(scene, props)

    pinned = pin_non_props(props, span[0]) if PIN_HULL else []
    try:
        setup_camera_and_lights()

        render = scene.render
        render.resolution_x, render.resolution_y = RES_X, RES_Y
        render.resolution_percentage = 100
        render.film_transparent = True
        render.image_settings.file_format = "PNG"
        render.image_settings.color_mode = "RGBA"
        for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE", "CYCLES"):
            try:
                render.engine = engine
                break
            except TypeError:
                continue

        out_dir = bpy.path.abspath(OUT_DIR)
        os.makedirs(out_dir, exist_ok=True)

        start, end = span
        for i in range(FRAMES):
            # end of the span equals the start pose, so never render it
            f = start + (end - start) * i / FRAMES
            scene.frame_set(int(f), subframe=f - int(f))
            render.filepath = os.path.join(out_dir, "frame_%02d.png" % i)
            bpy.ops.render.render(write_still=True)
            print("rendered %s (scene frame %.2f)" % (render.filepath, f))

        real_secs = (end - start) / scene.render.fps * scene.render.fps_base
        sheet_fps = FRAMES / real_secs if real_secs > 0 else 15
        print("\nDone: %d frames in %s" % (FRAMES, out_dir))
        print("One revolution/%d takes %.3fs of animation -> sheet fps for "
              "true-to-life prop speed: %.1f" % (SYMMETRY, real_secs, sheet_fps))
        print("Next: python tools/build_zep_sheet.py \"%s\" --fps %d"
              % (out_dir, round(sheet_fps)))
    finally:
        for obj, action in pinned:
            obj.animation_data.action = action


main()
