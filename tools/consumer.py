"""Consume a clean Git snapshot and the actual `moon package` ZIP in separate modules.

Workspace overrides are explicit: neither mode is a Mooncakes registry test.
The workspace idea follows October's development lessons; fixtures/tests are new.
"""
import argparse
from datetime import datetime, timezone
from hashlib import sha256
from io import BytesIO
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import tempfile
import zipfile

from common import ROOT, evidence_base, run


TESTS = r'''///|
fn square() -> @surface.Mesh raise @surface.SurfaceError {
  @surface.Mesh::from_indexed(
    [
      { x: 0.0, y: 0.0, z: 0.0 }, { x: 2.0, y: 0.0, z: 0.0 },
      { x: 2.0, y: 2.0, z: 0.0 }, { x: 0.0, y: 2.0, z: 0.0 },
    ],
    [(0, 1, 2), (0, 2, 3)],
  )
}

///|
test "consumer edits, normals and detached arrays" {
  let mesh = square()
  let edge = mesh.find_edge(0, 2).unwrap()
  let flip = mesh.flip_edge(edge)
  assert_eq(flip.edge, edge)
  let split = mesh.split_edge(edge)
  assert_eq(split.vertex, 4)
  mesh.validate()
  assert_eq((mesh.stats().vertices, mesh.stats().faces), (5, 4))
  assert_eq(mesh.stats().euler, 1)
  let exported = mesh.to_indexed()
  let array = exported.positions()
  array[0] = { x: 99.0, y: 99.0, z: 99.0 }
  assert_eq(mesh.position(0).x, 0.0)
  assert_eq(exported.positions()[0].x, 0.0)
  assert_eq(mesh.face_normals().length(), 4)
  assert_eq(mesh.vertex_normals().length(), 5)
}

///|
test "consumer Loop boundary rule and input ownership" {
  let mesh = square()
  let before = mesh.to_indexed()
  let plan = mesh.plan_loop(2)
  let refined = @surface.subdivide_loop(mesh, 2)
  refined.mesh.validate()
  assert_eq(refined.stages, plan)
  assert_eq(refined.mesh.face_count(), 32)
  assert_eq(mesh.to_indexed(), before)
  let one = mesh.loop_step()
  assert_eq(one.position(0), { x: 0.25, y: 0.25, z: 0.0 })
  let copy = mesh.copy()
  copy.split_edge(copy.find_edge(0, 1).unwrap()) |> ignore
  assert_eq(mesh.to_indexed(), before)
}

///|
test "consumer typed rejection preserves original mesh" {
  let mesh = square()
  let before = mesh.to_indexed()
  try mesh.flip_edge(mesh.find_edge(0, 1).unwrap()) catch {
    e => assert_true(e is @surface.BoundaryEdge(_))
  } noraise {
    _ => fail("boundary flip accepted")
  }
  try mesh.split_edge(@surface.EdgeId(-1)) catch {
    e => assert_true(e is @surface.InvalidElement(_))
  } noraise {
    _ => fail("invalid id accepted")
  }
  assert_eq(mesh.to_indexed(), before)
  mesh.validate()
}

///|
test "consumer geometry job package is independently importable" {
  let response = @json.parse(@job.execute_json(
    "{\"format\":\"moonsurface/1\",\"positions\":[],\"triangles\":[]}",
  ))
  guard response is Object(fields) else { fail("missing response") }
  assert_eq(fields.get("ok"), Some(Json::boolean(true)))
}
'''


def unpack(data, destination):
    with zipfile.ZipFile(BytesIO(data)) as archive:
        names = set()
        for entry in archive.infolist():
            path = PurePosixPath(entry.filename.replace('\\', '/'))
            assert not path.is_absolute() and '..' not in path.parts
            assert path.parts and path.parts[0] not in ('.git', '_build', '.mooncakes', 'artifacts')
            assert not any(':' in part for part in path.parts)
            name = path.as_posix()
            assert name not in names, 'duplicate archive path'
            names.add(name)
            target = destination.joinpath(*path.parts).resolve()
            assert target.is_relative_to(destination.resolve())
            if entry.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(archive.read(entry))
    required = {'moon.mod', 'moon.pkg', 'LICENSE', 'README.md', 'THIRD_PARTY.md',
                'AI_USAGE.md', 'pkg.generated.mbti', 'topology.mbt', 'loop.mbt',
                'exchange/moon.pkg', 'examples/local_edit/main.mbt'}
    assert required <= names, required-names
    return len(names)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--target', choices=['native', 'js', 'wasm-gc'], required=True)
    args = parser.parse_args()
    assert not run(['git', 'status', '--porcelain'], capture=True).stdout.strip(), \
        'Commit source before checking exact snapshots and package contents'
    commit = run(['git', 'rev-parse', 'HEAD'], capture=True).stdout.strip()
    source = subprocess.run(['git', 'archive', '--format=zip', 'HEAD'], cwd=ROOT,
                            check=True, capture_output=True).stdout
    run(['moon', 'package'], target=args.target)
    version = re.search(r'^version\s*=\s*"([^"]+)"',
                        (ROOT/'moon.mod').read_text(encoding='utf-8'), re.M)[1]
    package = ROOT/'_build'/'publish'/f'ShiChengxu-moonsurface-{version}.zip'
    data = package.read_bytes()
    assert len(data) <= 64*1024*1024
    base = ROOT/'artifacts'
    base.mkdir(exist_ok=True)
    workspace = Path(tempfile.mkdtemp(prefix=f'consumer-{args.target}-', dir=base)).resolve()
    modes = []
    for mode, archive in [('source', source), ('package', data)]:
        work = workspace/mode
        library = work/'library'
        library.mkdir(parents=True)
        count = unpack(archive, library)
        consumer = work/'consumer'
        consumer.mkdir()
        (work/'moon.work').write_text('members = [ "./library", "./consumer" ]\n', encoding='utf-8')
        (consumer/'moon.mod').write_text('name = "local/moonsurface_consumer"\n'
            'version = "0.0.0"\nimport { "ShiChengxu/moonsurface@'+version+'" }\n', encoding='utf-8')
        (consumer/'moon.pkg').write_text('import {\n "ShiChengxu/moonsurface" @surface,\n'
            ' "ShiChengxu/moonsurface/exchange" @job,\n "moonbitlang/core/json",\n} for "test"\n', encoding='utf-8')
        (consumer/'consumer_test.mbt').write_text(TESTS, encoding='utf-8')
        run(['moon', 'check', '--target', args.target, '--deny-warn', str(consumer)],
            cwd=work, target=args.target)
        result = run(['moon', 'test', '--target', args.target, '--deny-warn', str(consumer)],
                     cwd=work, target=args.target, capture=True)
        assert 'Total tests: 4, passed: 4, failed: 0' in result.stdout, result.stdout+result.stderr
        modes.append(dict(mode=mode, tests=4, archive_entries=count))
    report = dict(evidence_base(args.target, [['python', 'tools/consumer.py', '--target', args.target],
                                            ['moon', 'package']]),
                  status='passed', timestamp_utc=datetime.now(timezone.utc).isoformat(),
                  package_sha256=sha256(data).hexdigest(), modes=modes,
                  dependency_resolution='explicit local workspace members; no registry installation')
    output = ROOT/'artifacts'/f'consumer-{args.target}.json'
    output.write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
    print(f'Consumer {args.target}: Git snapshot 4/4, actual moon package ZIP 4/4; {package.name}')


if __name__ == '__main__':
    main()
