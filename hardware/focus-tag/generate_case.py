"""Generate BrewFocus's 20 mm NFC case with Blender, in millimetres.

Blender --background --factory-startup --python generate_case.py -- --output exports
Print STLs are saved at Z=0 in their intended orientation; no supports are needed.
"""

import argparse
import json
import math
from pathlib import Path
import struct
import sys

import bmesh
import bpy
from mathutils import Vector


def revolve(name, profile, material, ribs=False):
    segments = 192
    vertices = []
    for radius, height in profile:
        for i in range(segments):
            angle = 2 * math.pi * i / segments
            # Three small retention pads; the lead-in tapers them toward the tip.
            pad = 0
            if ribs and radius > 12 and height > 1.2:
                distance = abs((angle + math.pi / 3) % (2 * math.pi / 3) - math.pi / 3)
                pad = 0.20 * max(0, 1 - distance / math.radians(5))
                if height > 3.3:
                    pad = 0
            vertices.append(((radius + pad) * math.cos(angle),
                             (radius + pad) * math.sin(angle), height))
    faces = []
    for row in range(len(profile)):
        next_row = (row + 1) % len(profile)
        for i in range(segments):
            j = (i + 1) % segments
            faces.append((row * segments + i, row * segments + j,
                          next_row * segments + j, next_row * segments + i))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=0.00001)
    bmesh.ops.dissolve_degenerate(bm, edges=list(bm.edges), dist=0.00001)
    # Collapsing each revolution pole can leave an unused edge along the axis.
    bmesh.ops.delete(bm, geom=[edge for edge in bm.edges if not edge.link_faces], context="EDGES")
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    return obj


def prism(name, points, bottom, top):
    n = len(points)
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([(x, y, z) for z in (bottom, top) for x, y in points], [],
                    [tuple(reversed(range(n))), tuple(range(n, 2 * n))]
                    + [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)])
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def subtract(obj, cutter):
    bpy.context.view_layer.objects.active = obj
    modifier = obj.modifiers.new("Engraving", "BOOLEAN")
    modifier.operation = "DIFFERENCE"
    modifier.solver = "EXACT"
    modifier.object = cutter
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    bpy.data.objects.remove(cutter, do_unlink=True)
    # Exact booleans can leave coincident vertices on triangulated planar faces.
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=0.00001)
    bmesh.ops.dissolve_degenerate(bm, edges=list(bm.edges), dist=0.00001)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(obj.data)
    bm.free()


def validate(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    non_manifold = sum(not edge.is_manifold for edge in bm.edges)
    if non_manifold:
        print("Invalid edges:", [(len(e.link_faces), [tuple(v.co) for v in e.verts])
                                 for e in bm.edges if not e.is_manifold])
    volume = bm.calc_volume(signed=True)
    bm.free()
    assert non_manifold == 0, f"{obj.name}: {non_manifold} non-manifold edges"
    assert volume > 0, f"{obj.name}: invalid volume"
    return {"dimensions_mm": [round(v, 3) for v in obj.dimensions],
            "volume_mm3": round(volume, 2), "non_manifold_edges": non_manifold}


def export_stl(objects, path):
    triangles = []
    for obj in objects:
        obj.data.calc_loop_triangles()
        for face in obj.data.loop_triangles:
            v = [obj.matrix_world @ obj.data.vertices[i].co for i in face.vertices]
            normal = (v[1] - v[0]).cross(v[2] - v[0]).normalized()
            triangles.append(struct.pack("<12fH", *normal, *v[0], *v[1], *v[2], 0))
    path.write_bytes(b"BrewFocus Focus Tag - millimetres".ljust(80, b"\0")
                     + struct.pack("<I", len(triangles)) + b"".join(triangles))


def material(name, color, roughness=0.5):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1)
    shader.inputs["Roughness"].default_value = roughness
    return mat


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=Path(__file__).parent / "exports")
    parser.add_argument("--tag-diameter", type=float, default=20)
    parser.add_argument("--clearance", type=float, default=0.15,
                        help="Radial clearance in mm; increase if the lid is too tight")
    parser.add_argument("--no-render", action="store_true")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    assert 10 <= args.tag_diameter <= 22, "This 34 mm shell supports tags from 10 to 22 mm"
    assert 0.05 <= args.clearance <= 0.35, "Use radial clearance from 0.05 to 0.35 mm"
    args.output.mkdir(parents=True, exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0

    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 0.001
    scene.unit_settings.length_unit = "MILLIMETERS"
    black = material("Matte black PLA", (0.045, 0.045, 0.047))
    pocket = 13
    plug = pocket - args.clearance
    inner = args.tag_diameter / 2 + 0.5
    base = revolve("Base", [(0, 0), (16.4, 0), (17, 0.6), (17, 4.4), (16.6, 4.8),
                            (13.3, 4.8), (13, 4.5), (13, 1.2), (0, 1.2)], black)
    lid = revolve("Lid", [(0, 0), (16.4, 0), (17, 0.6), (17, 1.2),
                          (plug, 1.2), (plug, 3.3), (plug - 0.3, 3.6),
                          (inner, 3.6), (inner, 1.2), (0, 1.2)], black, ribs=True)
    validate(lid)
    # Shallow rim notch for a fingernail; never reaches the tag pocket.
    subtract(base, prism("Opening notch", [(15.5, -2), (18, -2), (18, 2), (15.5, 2)], 4.1, 5))
    # Discreet 8 mm coffee mark engraved 0.4 mm into the outside of the lid.
    bowl = [(-3, 2), (-3, -0.3)] + [
        (3 * math.cos(t), -0.3 + 3 * math.sin(t))
        for t in [math.pi + math.pi * i / 24 for i in range(1, 25)]
    ] + [(3, 2)]
    # Mirror Y because the printed lid is flipped when assembled.
    subtract(lid, prism("Cup bowl", [(x, -y) for x, y in reversed(bowl)], -0.01, 0.4))
    validate(lid)
    handle = revolve("Handle cutter", [(0.85, -0.01), (1.8, -0.01), (1.8, 0.4), (0.85, 0.4)], black)
    handle.location = (3, -0.5, 0)
    subtract(lid, handle)
    validate(lid)
    subtract(lid, prism("Saucer", [(-4, 3.5), (4, 3.5), (4, 4.2), (-4, 4.2)], -0.01, 0.4))

    bpy.context.view_layer.update()
    report = {"units": "mm", "printer": "Bambu Lab A1 / 0.4 mm nozzle",
              "tag_diameter_mm": args.tag_diameter, "tag_pocket_diameter_mm": inner * 2,
              "radial_clearance_mm": args.clearance, "assembled_dimensions_mm": [34, 34, 6],
              "plastic_above_tag_mm": 1.2, "minimum_plastic_under_engraving_mm": 0.8,
              "base": validate(base), "lid": validate(lid),
              "physical_fit_verified": False, "nfc_read_range_verified": False}
    export_stl([base], args.output / "brewfocus-tag-base.stl")
    export_stl([lid], args.output / "brewfocus-tag-lid.stl")
    base.location.x = -21
    lid.location.x = 21
    bpy.context.view_layer.update()
    export_stl([base, lid], args.output / "brewfocus-tag-print-plate.stl")
    (args.output / "validation.json").write_text(json.dumps(report, indent=2) + "\n")
    bpy.ops.wm.save_as_mainfile(filepath=str(args.output / "brewfocus-tag.blend"))

    if not args.no_render:
        # Show one assembled case and an exploded pair, generated from the actual meshes.
        lid.location = (-23, 0, 6)
        lid.rotation_euler.x = math.pi
        base.location = (-23, 0, 0)
        other_base = base.copy()
        bpy.context.collection.objects.link(other_base)
        other_base.location = (23, 0, 0)
        other_lid = lid.copy()
        bpy.context.collection.objects.link(other_lid)
        other_lid.location = (23, 7, 27)
        sticker = revolve("20 mm NFC sticker", [(0, 0), (args.tag_diameter / 2, 0),
                           (args.tag_diameter / 2, 0.6), (0, 0.6)],
                          material("NFC sticker", (0.48, 0.27, 0.09)))
        sticker.location = (23, 0, 11)
        bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.06))
        bpy.context.object.data.materials.append(material("Ground", (0.74, 0.74, 0.72)))
        world = scene.world
        world.use_nodes = True
        world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.8, 0.8, 0.8, 1)
        world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.35
        for location, energy, size in [((-25, -40, 75), 180000, 55), ((50, 20, 55), 130000, 45)]:
            bpy.ops.object.light_add(type="AREA", location=location)
            light = bpy.context.object
            light.data.energy = energy
            light.data.shape = "DISK"
            light.data.size = size
            light.rotation_euler = (Vector((0, 0, 0)) - light.location).to_track_quat("-Z", "Y").to_euler()
        bpy.ops.object.camera_add(location=(55, -100, 100))
        camera = bpy.context.object
        camera.rotation_euler = (Vector((0, 0, 6)) - camera.location).to_track_quat("-Z", "Y").to_euler()
        camera.data.type = "ORTHO"
        camera.data.ortho_scale = 115
        scene.camera = camera
        scene.render.engine = "CYCLES"
        scene.cycles.samples = 48
        scene.render.resolution_x = 1400
        scene.render.resolution_y = 950
        scene.render.resolution_percentage = 100
        scene.render.filepath = str(args.output / "preview.png")
        scene.render.image_settings.file_format = "PNG"
        scene.view_settings.view_transform = "AgX"
        bpy.ops.render.render(write_still=True)
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
