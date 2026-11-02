"""Independent batch triangle-list checks; no halfedge implementation or dependencies.

This is a local mathematical reference, not an OpenMesh/OpenSubdiv comparison.
Fixed seed, analytic stencils, full oriented face comparison and negative controls.
"""
import argparse
from collections import Counter, defaultdict
from datetime import datetime, timezone
from hashlib import sha256
import json
import math
import random

from common import ROOT, evidence_base, run


def key(a, b):
    return tuple(sorted((a, b)))


def connected(graph):
    unseen = set(graph)
    count = 0
    while unseen:
        count += 1
        stack = [unseen.pop()]
        while stack:
            for other in graph[stack.pop()]:
                if other in unseen:
                    unseen.remove(other)
                    stack.append(other)
    return count


def audit(points, faces):
    """Rebuild incidence and vertex links directly from triangles."""
    assert all(len(p) == 3 and all(math.isfinite(x) for x in p) for p in points)
    incidence = {}
    neighbors = {i: set() for i in range(len(points))}
    links = {i: defaultdict(set) for i in range(len(points))}
    seen = set()
    for face in faces:
        assert len(face) == 3 and len(set(face)) == 3
        assert all(isinstance(v, int) and 0 <= v < len(points) for v in face)
        canonical = tuple(sorted(face))
        assert canonical not in seen, "duplicate face"
        seen.add(canonical)
        a, b, c = (points[i] for i in face)
        u = [b[i] - a[i] for i in range(3)]
        v = [c[i] - a[i] for i in range(3)]
        length = max(math.hypot(*u), math.hypot(*v))
        assert length > 0
        u, v = [x / length for x in u], [x / length for x in v]
        cross = [u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0]]
        assert math.hypot(*cross) > 1e-14, "degenerate face"
        for a, b, c in (face, face[1:] + face[:1], face[2:] + face[:2]):
            incidence.setdefault(key(a, b), []).append((a, b, c))
            neighbors[a].add(b)
            neighbors[b].add(a)
            links[a][b].add(c)
            links[a][c].add(b)
    boundary = defaultdict(set)
    for pair, uses in incidence.items():
        assert len(uses) in (1, 2), "non-manifold edge"
        if len(uses) == 2:
            assert uses[0][:2] == uses[1][1::-1], "inconsistent orientation"
        else:
            a, b = pair
            boundary[a].add(b)
            boundary[b].add(a)
    assert all(len(adjacent) == 2 for adjacent in boundary.values())
    for vertex, link in links.items():
        assert neighbors[vertex], "isolated vertex"
        assert connected(link) == 1, "disconnected vertex link"
        degrees = Counter(len(v) for v in link.values())
        if vertex in boundary:
            assert degrees[1] == 2 and set(degrees) <= {1, 2}, "not a link path"
        else:
            assert set(degrees) == {2}, "not a link cycle"
    stats = dict(vertices=len(points), edges=len(incidence), faces=len(faces),
                 boundary_edges=sum(len(uses) == 1 for uses in incidence.values()),
                 boundary_loops=connected(boundary), components=connected(neighbors),
                 euler=len(points)-len(incidence)+len(faces))
    return stats, incidence, neighbors, boundary


def loop_reference(points, faces):
    _, edges, neighbors, boundary = audit(points, faces)
    stencils = []
    for vertex, adjacent in neighbors.items():
        if vertex in boundary:
            stencils.append([(vertex, .75)] + [(v, .125) for v in sorted(boundary[vertex])])
        else:
            n = len(adjacent)
            beta = (5/8 - (3/8 + math.cos(2*math.pi/n)/4)**2) / n
            stencils.append([(vertex, 1-n*beta)] + [(v, beta) for v in sorted(adjacent)])
    indices = {}
    for (a, b), uses in edges.items():
        indices[a, b] = len(stencils)
        stencil = [(a, .5), (b, .5)] if len(uses) == 1 else [
            (a, 3/8), (b, 3/8), (uses[0][2], 1/8), (uses[1][2], 1/8)]
        stencils.append(stencil)
    positions = [[math.fsum(points[v][axis]*weight for v, weight in row)
                  for axis in range(3)] for row in stencils]
    output = []
    for a, b, c in faces:
        ab, bc, ca = (indices[key(u, v)] for u, v in ((a, b), (b, c), (c, a)))
        output.extend([[a, ab, ca], [b, bc, ab], [c, ca, bc], [ab, bc, ca]])
    return positions, output


def oriented(faces):
    return sorted(min(tuple(f[i:] + f[:i]) for i in range(3)) for f in faces)


def compare(expected, actual):
    points, faces = expected
    assert actual['ok'] is True, actual
    assert len(points) == len(actual['positions'])
    scale = max((abs(x) for p in points for x in p), default=1) or 1
    error = max((abs(x-y)/scale for p, q in zip(points, actual['positions'])
                 for x, y in zip(p, q)), default=0)
    assert error < 5e-13, f"coordinate error: {error}"
    assert oriented(faces) == oriented(actual['triangles']), "oriented triangles differ"
    stats, *_ = audit(actual['positions'], actual['triangles'])
    assert stats == actual['stats'], (stats, actual['stats'])
    return error


def split_reference(points, faces, a, b, fraction=.5):
    points = points + [[(1-fraction)*points[a][axis] + fraction*points[b][axis]
                        for axis in range(3)]]
    vertex = len(points)-1
    result = []
    for face in faces:
        if a in face and b in face:
            for i in range(3):
                u, v, w = face[i:] + face[:i]
                if key(u, v) == key(a, b):
                    result.extend([[u, vertex, w], [vertex, v, w]])
                    break
        else:
            result.append(face)
    return points, result


def flip_reference(points, faces, a, b):
    _, edges, *_ = audit(points, faces)
    uses = edges[key(a, b)]
    assert len(uses) == 2
    u, v, w = uses[0]
    x = uses[1][2]
    other = [f for f in faces if not (u in f and v in f)]
    return points, other + [[w, x, v], [x, w, u]]


def fixtures():
    triangle = ([[0., 0., 0.], [2., 0., 0.], [0., 2., 0.]], [[0, 1, 2]])
    tetra = ([[1., 1., 1.], [-1., -1., 1.], [-1., 1., -1.], [1., -1., -1.]],
             [[0, 2, 1], [0, 1, 3], [0, 3, 2], [1, 2, 3]])
    ring = [[math.cos(i*2*math.pi/5)*(1+.05*i), math.sin(i*2*math.pi/5), .04*i]
            for i in range(5)]
    fan = ([[.03, .02, .17]] + ring, [[0, i+1, (i+1) % 5+1] for i in range(5)])
    outer = [[-2., -2., 0.], [2., -2., 0.], [2., 2., 0.], [-2., 2., 0.]]
    inner = [[x/4, y/4, 0.] for x, y, _ in outer]
    annulus = (outer+inner, [f for i in range(4) for f in
                           ([i, (i+1) % 4, (i+1) % 4+4], [i, (i+1) % 4+4, i+4])])
    rng = random.Random(20261103)
    grid = ([[float(x), float(y), rng.uniform(-.03, .03)] for y in range(5) for x in range(5)],
            [f for y in range(4) for x in range(4) for f in
             ([y*5+x, y*5+x+1, (y+1)*5+x+1], [y*5+x, (y+1)*5+x+1, (y+1)*5+x])])
    disconnected = (triangle[0]+[[x+5, y, z] for x, y, z in triangle[0]],
                    triangle[1]+[[3, 4, 5]])
    return dict(empty=([], []), triangle=triangle, tetrahedron=tetra, valence5=fan,
                annulus=annulus, seeded_grid=grid, disconnected=disconnected,
                reversed=(tetra[0], [list(reversed(f)) for f in tetra[1]]),
                tiny=([[x*1e-150 for x in p] for p in tetra[0]], tetra[1]),
                huge=([[x*1e150 for x in p] for p in tetra[0]], tetra[1]))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--target', choices=['native', 'js', 'wasm-gc'], required=True)
    args = parser.parse_args()
    run(['moon', 'build', '--target', args.target, '--deny-warn'], target=args.target)
    cases = []
    jobs = []
    maximum_error = 0.

    def execute(points, faces, operations=None, **extra):
        job = dict(format='moonsurface/1', positions=points, triangles=faces,
                   operations=operations or [], **extra)
        payload = json.dumps(job, separators=(',', ':'), allow_nan=False)
        result = run(['moon', 'run', 'cmd/moonsurface', '--target', args.target, '--', payload],
                     target=args.target, capture=True)
        jobs.append(dict(input_sha256=sha256(payload.encode()).hexdigest(),
                         output_sha256=sha256(result.stdout.encode()).hexdigest()))
        return json.loads(result.stdout)

    # Fresh jobs at each depth also verify cumulative preflight and stage counts.
    for name, (points, faces) in fixtures().items():
        expected = (points, faces)
        for level in range(3):
            result = execute(points, faces, [dict(kind='loop', levels=level)])
            error = compare(expected, result)
            maximum_error = max(maximum_error, error)
            stages = result['operations'][0]['stages']
            assert len(stages) == level+1 and stages[-1] == result['stats']
            cases.append(dict(name=f'{name}/loop-{level}', stats=result['stats'], error=error))
            expected = loop_reference(*expected)

    square = ([[0., 0., 0.], [2., 0., 0.], [2., 2., 0.], [0., 2., 0.]],
              [[0, 1, 2], [0, 2, 3]])
    sequences = [
        [dict(kind='split', edge=[0, 2], fraction=.3)],
        [dict(kind='split', edge=[1, 0], fraction=.25)],
        [dict(kind='flip', edge=[0, 2])],
        [dict(kind='flip', edge=[0, 2]), dict(kind='split', edge=[1, 3], fraction=.4)],
        [dict(kind='split', edge=[0, 1]), dict(kind='split', edge=[1, 2]),
         dict(kind='split', edge=[0, 2]), dict(kind='flip', edge=[0, 6])],
    ]
    for index, operations in enumerate(sequences):
        expected = square
        for op in operations:
            if op['kind'] == 'split':
                expected = split_reference(*expected, *op['edge'], op.get('fraction', .5))
            else:
                expected = flip_reference(*expected, *op['edge'])
        result = execute(*square, operations)
        maximum_error = max(maximum_error, compare(expected, result))
        cases.append(dict(name=f'edit-sequence-{index}', stats=result['stats']))
        # Rebuild after edits, then compare subdivision of that exported mesh.
        refined = execute(result['positions'], result['triangles'], [dict(kind='loop', levels=1)])
        maximum_error = max(maximum_error, compare(loop_reference(result['positions'], result['triangles']), refined))

    p, f = square
    rejected = [execute(p, [[0, 1, 1]]), execute(p, f+[[2, 1, 0]]),
                execute(p, [[0, 1, 2], [0, 3, 2]]), execute(p, [[0, 1, 2.5], [0, 2, 3]]),
                execute(p, f, [dict(kind='flip', edge=[0, 1])]),
                execute(p, f, [dict(kind='loop', levels=2)], limits=dict(max_output_faces=10)),
                execute(p, f, [dict(kind='split', edge=[0, 2]), dict(kind='flip', edge=[0, 1])]),
                execute(p, f, mystery=True)]
    for result in rejected:
        assert result['ok'] is False and 'positions' not in result and 'triangles' not in result
    # Negative controls demonstrate that the comparison detects real mutations.
    good = execute(*square, [dict(kind='loop', levels=1)])
    expected = loop_reference(*square)
    mutants = [json.loads(json.dumps(good)) for _ in range(3)]
    mutants[0]['positions'][0][0] += .1
    mutants[1]['triangles'][0].reverse()
    mutants[2]['stats']['euler'] += 1
    for mutant in mutants:
        try:
            compare(expected, mutant)
        except AssertionError:
            pass
        else:
            raise AssertionError('negative control was not detected')
    report = dict(evidence_base(args.target, [['python', 'tools/reference.py', '--target', args.target]]),
                  status='passed',
                  timestamp_utc=datetime.now(timezone.utc).isoformat(), fixture_seed=20261103,
                  loop_jobs=30, edit_jobs=len(sequences)*2, rejection_jobs=len(rejected),
                  negative_controls=len(mutants), max_normalized_coordinate_error=maximum_error,
                  reference='independent stdlib Python triangle-list implementation; not OpenMesh',
                  cases=cases, job_hashes=jobs, control_baseline_jobs=1,
                  unverified=['OpenMesh/OpenSubdiv oracle', 'QEM', 'performance and RSS'])
    output = ROOT / 'artifacts' / f'reference-{args.target}.json'
    output.parent.mkdir(exist_ok=True)
    output.write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
    print(f"Reference {args.target}: 40 valid jobs, {len(rejected)} rejections, 3 negative controls passed; error={maximum_error:.3g}")


if __name__ == '__main__':
    main()
