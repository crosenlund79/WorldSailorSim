"""Paints the animated companions (Iteration I024; Real Horizon look).

Three species, each a set of short frame clips:
  cat     a seal-point Ragdoll   (companion_cat.py)
  dog     a fawn Pug             (companion_dog.py)
  parrot  a green-cheeked conure (companion_parrot.py)

Each animal is a soft 3D puppet (companion_quadruped.py for the cat and the
dog) posed per frame and painted by companion_render.py in the Real Horizon
manner (DEV_GUIDES/ART_DIRECTION.md): tonal washes lit from the upper left,
short directional fur / feather strokes anchored to the body, a thin
translucent blue-grey edge, a soft contact shadow. Everything is
deterministic: running it twice gives the same files.

View: from above and a little in front, the animal facing right (the game
mirrors it for left). Every frame of a species is drawn on the same 256 x 256
transparent canvas with the animal's ground point at the same place:
  cat, dog   (128, 160)
  parrot     (128, 176) perch / feet point; in flight the bird's centre is at (128, 128)

Writes
  assets/companions/<kind>/<clip>_<NN>.png       every frame
  assets/companions/cat|dog/{resting,sleeping,alert,stretching}.png
                                                 copies of frame 00 of those clips (older references)
  data/companions/<kind>_visuals.tres            one CompanionPoseArt per clip

Usage:
  python3 tools/companions/paint_companion_clips.py            everything
  python3 tools/companions/paint_companion_clips.py cat dog    some species
  options: --clips=walk,turn   only these clips (no .tres rewrite)
           --review=DIR        also write contact sheets to DIR
           --jobs=N            worker processes (default: CPU count)
Requirements: Python 3 with Pillow and numpy.
"""
import math
import os
import shutil
import sys
from multiprocessing import Pool

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from PIL import Image, ImageDraw  # noqa: E402

import companion_cat  # noqa: E402
import companion_dog  # noqa: E402
import companion_parrot  # noqa: E402
from companion_quadruped import build as build_quad  # noqa: E402
from companion_render import Scene, render  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
ASSETS = os.path.join(ROOT, "assets", "companions")
DATA = os.path.join(ROOT, "data", "companions")

# Clip order in the .tres (also the review sheets).
CLIP_ORDER = {
    "cat": ["resting", "walk", "turn", "sit", "lie_down", "sleeping", "wake", "stretching", "groom", "alert", "pet", "settle"],
    "dog": ["resting", "walk", "turn", "sit", "lie_down", "sleeping", "wake", "stretching", "tail_wag", "alert", "pet", "settle"],
    "parrot": ["resting", "blink", "head_turn", "hop", "takeoff", "fly", "land", "ruffle", "preen", "sleeping", "wake", "alert"],
}
ORIGIN = {"cat": (128.0, 160.0), "dog": (128.0, 160.0), "parrot": (128.0, 176.0)}
# Placement in the game: canvas side in scene units, ground point as a fraction.
DISPLAY = {"cat": (66.0, (0.5, 0.625)), "dog": (56.0, (0.5, 0.625)), "parrot": (50.0, (0.5, 0.6875))}
WORKSHOP = {"cat": "pet.snovs", "dog": "pet.dog", "parrot": "pet.parrot"}
LEGACY = ("resting", "sleeping", "alert", "stretching")    # still-image names kept as copies of frame 00
FLIGHT_CLIPS = {"fly"}

_CLIPS = {}


def clips_of(kind):
    if kind not in _CLIPS:
        _CLIPS[kind] = {"cat": companion_cat.clips, "dog": companion_dog.clips, "parrot": companion_parrot.clips}[kind]()
    return _CLIPS[kind]


def paint_frame(kind, clip, index):
    pose = clips_of(kind)[clip][0][index]
    if kind == "parrot":
        built = companion_parrot.build(pose)
        scene = Scene(ORIGIN[kind], companion_parrot.STYLE)
        scene.add(built.prims)
        scene.decals.append(companion_parrot.face(built, pose))
        lift = pose.get("lift", (0, 0, 0))
        airborne = pose.get("wing", 0) >= 0.5 and pose["body"][1] + lift[2] > 24
        scene.shadow = "flight" if airborne else "ground"
    else:
        mod = companion_cat if kind == "cat" else companion_dog
        sp = mod.Ragdoll() if kind == "cat" else mod.Pug()
        built = build_quad(sp, pose)
        scene = Scene(ORIGIN[kind], sp.style)
        scene.add(built.prims)
        scene.decals.append(mod.face(built, pose))
    return render(scene)


def frame_path(kind, clip, index):
    return os.path.join(ASSETS, kind, "%s_%02d.png" % (clip, index))


def _job(args):
    kind, clip, index = args
    img = paint_frame(kind, clip, index)
    path = frame_path(kind, clip, index)
    img.save(path, optimize=True)
    a = img.getchannel("A")
    return kind, clip, index, a.getbbox()


def res(path):
    return "res://" + os.path.relpath(path, ROOT).replace(os.sep, "/")


# --- .tres ----------------------------------------------------------------------------------

MOVE_SPEED = {"cat": {"walk_speed": 20.5}, "dog": {"walk_speed": 11.0}, "parrot": {"fly_speed": 110.0}}


def write_tres(kind):
    clips = clips_of(kind)
    names = CLIP_ORDER[kind]
    size, pivot = DISPLAY[kind]
    lines = ['[gd_resource type="Resource" script_class="CompanionVisualSet" load_steps=%d format=3]' % (len(names) + 3), "",
             '[ext_resource type="Script" path="res://src/companion/companion_visual_set.gd" id="1_set"]',
             '[ext_resource type="Script" path="res://src/companion/companion_pose_art.gd" id="2_pose"]', ""]
    for name in names:
        poses, fps, loop = clips[name]
        frames = [res(frame_path(kind, name, i)) for i in range(len(poses))]
        lines += ['[sub_resource type="Resource" id="Pose_%s"]' % name,
                  'script = ExtResource("2_pose")',
                  'pose = &"%s"' % name,
                  'image_path = "%s"' % frames[0],
                  'frames = Array[String]([%s])' % ", ".join('"%s"' % f for f in frames[1:]),
                  "fps = %s" % _num(fps),
                  "loop = %s" % ("true" if loop else "false"), ""]
    lines += ["[resource]", 'script = ExtResource("1_set")', 'kind = &"%s"' % kind, 'workshop_id = "%s"' % WORKSHOP[kind],
              "poses = Array[ExtResource(\"2_pose\")]([%s])" % ", ".join('SubResource("Pose_%s")' % n for n in names),
              "display_size = %s" % _num(size), "pivot = Vector2(%s, %s)" % (_num(pivot[0]), _num(pivot[1]))]
    # Movement matched to the drawn stride (stride px x display_size/256 x fps/frames),
    # so the feet do not slide: cat 64 px per 8 frames at 10 fps, dog 40 px.
    if kind in MOVE_SPEED:
        lines += ["%s = %s" % (key, _num(value)) for key, value in MOVE_SPEED[kind].items()]
    path = os.path.join(DATA, "%s_visuals.tres" % kind)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print("wrote", os.path.relpath(path, ROOT))


def _num(v):
    v = float(v)
    return ("%d.0" % v) if v == int(v) else ("%.4f" % v).rstrip("0")


# --- Review sheets ----------------------------------------------------------------------------

def review(kind, names, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    clips = clips_of(kind)
    cols = max(len(clips[n][0]) for n in names)
    cell = 160
    bg = (196, 192, 184, 255)
    sheet = Image.new("RGBA", (cols * cell + 90, len(names) * cell), bg)
    d = ImageDraw.Draw(sheet)
    small_cell = 64
    small = Image.new("RGBA", (cols * small_cell + 90, len(names) * small_cell), bg)
    ds = ImageDraw.Draw(small)
    size, _ = DISPLAY[kind]
    gx, gy = ORIGIN[kind]
    crop = (int(gx - 96), int(gy - 150), int(gx + 96), int(gy + 42)) if kind == "parrot" else (24, 40, 232, 248)
    for j, name in enumerate(names):
        poses, fps, loop = clips[name]
        d.text((4, j * cell + 4), "%s\n%d f @%s\n%s" % (name, len(poses), fps, "loop" if loop else "once"), fill=(40, 40, 40, 255))
        ds.text((4, j * small_cell + 4), name, fill=(40, 40, 40, 255))
        for i in range(len(poses)):
            im = Image.open(frame_path(kind, name, i)).convert("RGBA")
            c = im.crop(crop).resize((cell, cell), Image.LANCZOS)
            sheet.alpha_composite(c, (90 + i * cell, j * cell))
            # in-game size: the 256 canvas drawn display_size units, at about 1.5 px per unit
            s = max(8, int(round(size * 1.5)))
            g = im.resize((s, s), Image.LANCZOS)
            ox = 90 + i * small_cell + (small_cell - s) // 2
            oy = j * small_cell + (small_cell - s) // 2
            small.alpha_composite(g, (ox, oy))
    sheet.save(os.path.join(out_dir, "%s_clips.png" % kind))
    small.save(os.path.join(out_dir, "%s_ingame.png" % kind))
    print("review", os.path.join(out_dir, "%s_clips.png" % kind), os.path.join(out_dir, "%s_ingame.png" % kind))


def main(argv):
    kinds = [a for a in argv if not a.startswith("--")] or ["cat", "dog", "parrot"]
    opts = dict(a[2:].split("=", 1) for a in argv if a.startswith("--") and "=" in a)
    only = opts.get("clips")
    jobs = []
    for kind in kinds:
        os.makedirs(os.path.join(ASSETS, kind), exist_ok=True)
        names = CLIP_ORDER[kind] if not only else [c for c in only.split(",") if c in CLIP_ORDER[kind]]
        for name in names:
            for i in range(len(clips_of(kind)[name][0])):
                jobs.append((kind, name, i))
    n = int(opts.get("jobs", os.cpu_count() or 2))
    with Pool(n) as pool:
        results = pool.map(_job, jobs, chunksize=1)
    edge = []
    for kind, clip, index, box in results:
        if box and (box[0] <= 1 or box[1] <= 1 or box[2] >= 255 or box[3] >= 255):
            edge.append("%s/%s_%02d %s" % (kind, clip, index, box))
    print("painted %d frames" % len(results))
    if edge:
        print("WARNING: frames touching the canvas edge:\n  " + "\n  ".join(edge))
    for kind in kinds:
        if not only:
            # remove frames of clips that no longer exist / have fewer frames
            keep = {os.path.basename(frame_path(kind, c, i)) for c in CLIP_ORDER[kind] for i in range(len(clips_of(kind)[c][0]))}
            for f in os.listdir(os.path.join(ASSETS, kind)):
                if f.endswith(".png") and "_" in f and f[-6:-4].isdigit() and f not in keep:
                    os.remove(os.path.join(ASSETS, kind, f))
                    imp = os.path.join(ASSETS, kind, f + ".import")
                    if os.path.exists(imp):
                        os.remove(imp)
            if kind in ("cat", "dog"):
                for name in LEGACY:
                    shutil.copyfile(frame_path(kind, name, 0), os.path.join(ASSETS, kind, name + ".png"))
            write_tres(kind)
        if "review" in opts:
            names = CLIP_ORDER[kind] if not only else [c for c in only.split(",") if c in CLIP_ORDER[kind]]
            review(kind, names, opts["review"])


if __name__ == "__main__":
    main(sys.argv[1:])
