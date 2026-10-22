#!/usr/bin/env python
"""Report what a stock `.mdl` actually draws: its mesh's real extent and which
faces of it exist.

`boundingInfo` in a `.mdl` is not the geometry and neither is the collider -
`stone_abut_rep_rep.mdl` declares a 4.43 m bounding box, carries a 3.43 m
collider, and draws **two parallel planes**. Scaling a piece like that to fill a
cell gives a correct volume made of flat faces, which is what "the meshes are
stacks of polygons" means in practice. The only way to know is to read the
vertex buffer.

    python tools/meshfaces.py                 # every model, solid ones first
    python tools/meshfaces.py pillar wall     # only paths matching a term

The `.msh` beside each model is a Lua header describing byte offsets into the
`.msh.blob` next to it: `vertexAttr.position` is float32 xyz, and
`indices.position` is uint32 triangle corners. Both `count` and `offset` are in
**bytes** - reading them as element counts gives 32 vertices where there are 8.

"faces" is how many of the six axis-aligned extremes of the mesh's own box have
a triangle lying in them. Six means a closed box; two means a pair of planes.
"""
import glob
import os
import re
import struct
import sys
import zipfile

ROOT = r"C:\Program Files (x86)\Steam\steamapps\common\Transport Fever 3"

BB_RE = re.compile(r"bbMax\s*=\s*{([^}]*)}\s*,\s*bbMin\s*=\s*{([^}]*)}", re.S)
MESH_RE = re.compile(r'mesh\s*=\s*"([^"]+)"')
#: `vertexAttr.position` carries a `numComp` between its count and its offset
#: and `indices.position` does not, so anything in between is skipped.
POS_RE = re.compile(r"position\s*=\s*{\s*count\s*=\s*(\d+)\s*,"
                    r"(?:\s*numComp\s*=\s*\d+\s*,)?\s*offset\s*=\s*(\d+)", re.S)


def nums(s):
    return [float(x) for x in re.findall(r"-?\d+\.?\d*(?:e[-+]?\d+)?", s)]


HALF_RE = re.compile(r"halfExtents\s*=\s*{([^}]*)}", re.S)
TRANSF_RE = re.compile(r"transf\s*=\s*{([^}]*)}", re.S)


def collider_of(mdl_text):
    """The collider's box in model space, or None if it has none worth having.

    It is the collider that collides, not the mesh, and the two need not agree:
    reading one off the other is how this mod spent three rounds compensating
    for the wrong number.
    """
    at = mdl_text.find("collider")
    if at < 0:
        return None
    blob = mdl_text[at:at + 400]
    kind = re.search(r'type\s*=\s*"(\w+)"', blob)
    if not kind or kind.group(1) != "BOX":
        return None
    h = HALF_RE.search(blob)
    t = TRANSF_RE.search(blob)
    if not h:
        return None
    half = nums(h.group(1))[:3]
    centre = nums(t.group(1))[12:15] if t else [0.0, 0.0, 0.0]
    if len(half) < 3 or len(centre) < 3:
        return None
    return ([centre[k] - half[k] for k in range(3)],
            [centre[k] + half[k] for k in range(3)])


def mesh_faces(zf, mdl_path, mesh_rel):
    """(extent, triangle count, faces covered) for a model's lod0 mesh."""
    msh = os.path.dirname(mdl_path) + "/" + mesh_rel
    try:
        head = zf.read(msh).decode("utf-8", "replace")
        blob = zf.read(msh + ".blob")
    except KeyError:
        return None

    # Both `indices` and `vertexAttr` have a `position` entry, so each is read
    # from its own keyword forward rather than by matching nested braces.
    verts = idx = None
    for kind in ("vertexAttr", "indices"):
        at = head.find(kind)
        if at < 0:
            continue
        m = POS_RE.search(head, at)
        if not m:
            continue
        count, offset = int(m.group(1)), int(m.group(2))
        if kind == "vertexAttr":
            verts = [struct.unpack_from("<3f", blob, offset + 12 * i)
                     for i in range(count // 12)]
        else:
            idx = struct.unpack_from("<%dI" % (count // 4), blob, offset)
    if not verts or not idx or max(idx) >= len(verts):
        return None

    lo = [min(v[ax] for v in verts) for ax in range(3)]
    hi = [max(v[ax] for v in verts) for ax in range(3)]
    covered = set()
    tris = [idx[i:i + 3] for i in range(0, len(idx) - 2, 3)]
    for t in tris:
        vs = [verts[i] for i in t]
        for ax in range(3):
            vals = {round(v[ax], 3) for v in vs}
            if len(vals) == 1:
                at = vals.pop()
                if abs(at - lo[ax]) < 0.01:
                    covered.add((ax, 0))
                elif abs(at - hi[ax]) < 0.01:
                    covered.add((ax, 1))
    return lo, hi, len(tris), len(covered)


def main(argv):
    rows = []
    for zp in glob.glob(ROOT + r"\**\*.zip", recursive=True):
        try:
            zf = zipfile.ZipFile(zp)
        except Exception:
            continue
        for n in zf.namelist():
            if not n.endswith(".mdl"):
                continue
            if argv and not any(a.lower() in n.lower() for a in argv):
                continue
            try:
                t = zf.read(n).decode("utf-8", "replace")
            except Exception:
                continue
            m = MESH_RE.search(t)
            b = BB_RE.search(t)
            if not m or not b:
                continue
            got = mesh_faces(zf, n, m.group(1))
            if got is None:
                continue
            lo, hi, tris, faces = got
            size = [hi[k] - lo[k] for k in range(3)]
            if min(size) < 0.2 or max(size) > 40:
                continue
            rows.append((-faces, tris, n, lo, hi, size, collider_of(t)))

    rows.sort()
    print("%-5s %-6s %-40s %-26s %s"
          % ("faces", "tris", "model", "mesh box", "collider vs mesh"))
    for faces, tris, n, lo, hi, size, coll in rows[:60]:
        if coll is None:
            verdict = "no collider"
        else:
            # Positive means the collider sticks out past the geometry, which is
            # what reaches into a neighbouring cell while nothing on screen says
            # so. Negative means it is inside the mesh and can be ignored.
            over = max(max(coll[1][k] - hi[k], lo[k] - coll[0][k])
                       for k in range(3))
            verdict = "%+.2f m %s" % (over, "OUT" if over > 0.01 else "inside")
        print("%-5d %-6d %-40s %-26s %s"
              % (-faces, tris, n[-40:],
                 "%.2f x %.2f x %.2f" % (size[0], size[1], size[2]), verdict))
    print("%d models read" % len(rows))


if __name__ == "__main__":
    main(sys.argv[1:])
