"""Render standalone scientific figures from a completed, clean model report.

Optional documentation tool; does not participate in the product or CI checks.
"""
import argparse
from hashlib import sha256
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
if (ROOT/'artifacts/reference-env').is_dir():
    sys.path.insert(0, str(ROOT/'artifacts/reference-env'))
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d.art3d import Poly3DCollection


def lengths(job):
    points = np.asarray(job['positions'])
    faces = np.asarray(job['triangles'])
    edges = np.unique(np.sort(np.concatenate([
        faces[:, [0, 1]], faces[:, [1, 2]], faces[:, [2, 0]],
    ]), axis=1), axis=0)
    return np.linalg.norm(points[edges[:, 0]]-points[edges[:, 1]], axis=1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--report', type=Path, default=ROOT/'artifacts/model-js-reference.json')
    parser.add_argument('--output', type=Path, default=ROOT/'docs/evidence')
    args = parser.parse_args()
    report_bytes = args.report.read_bytes()
    report = json.loads(report_bytes)
    assert report['status'] == 'passed' and not report['source_dirty']
    work = Path(report['workspace'])
    args.output.mkdir(parents=True, exist_ok=True)
    data = []
    for row in report['real_models']:
        name = row['name']
        variants = []
        for filename, expected in [
            (name+'-input.json', row['attributed']['input_sha256']),
            (name+'-output.json', row['attributed']['output_sha256']),
            (name+'-geometry-output.json', row['geometry_only']['output_sha256']),
            (name+'-meshlab.json', row['meshlab_geometry_only']['output_sha256']),
        ]:
            content = (work/filename).read_bytes()
            assert sha256(content).hexdigest() == expected, filename
            variants.append(json.loads(content))
        data.append((row, variants))

    plt.rcParams.update({'font.family': 'DejaVu Sans', 'font.size': 10,
                         'axes.spines.top': False, 'axes.spines.right': False})
    fig = plt.figure(figsize=(12, 8), layout='constrained')
    titles = ['Source', 'MoonSurface + attributes', 'MeshLab geometry only']
    for row_id, (row, variants) in enumerate(data):
        source = np.asarray(variants[0]['positions'])
        center = (source.max(axis=0)+source.min(axis=0))/2
        radius = np.ptp(source, axis=0).max()*.55
        for col, index in enumerate([0, 1, 3]):
            job = variants[index]
            points = (np.asarray(job['positions'])-center)/radius
            faces = np.asarray(job['triangles'])
            # glTF is Y-up; put Y along the plotting vertical.
            points = points[:, [0, 2, 1]]
            ax = fig.add_subplot(2, 3, row_id*3+col+1, projection='3d')
            polygons = Poly3DCollection(points[faces], facecolor='#e5edf3',
                edgecolor='#32546f', linewidth=.18, alpha=1)
            ax.add_collection3d(polygons)
            ax.set(xlim=(-1, 1), ylim=(-1, 1), zlim=(-1, 1))
            ax.set_box_aspect((1, 1, 1), zoom=1.3)
            ax.view_init(elev=18, azim=-65)
            ax.set_axis_off()
            ax.set_title(f"{row['provenance']['name']} | {titles[col]}\n"
                         f"V={len(points):,}  F={len(faces):,}", pad=1)
    fig.suptitle('Real asset remeshing: actual output triangulations', fontsize=16)
    fig.supxlabel('Fixed CC0 geometry; same view and bounds per asset; no textures. '
                  'Feature and boundary policies differ.', fontsize=10)
    fig.savefig(args.output/'real-models.png', dpi=180)
    plt.close(fig)

    fig, axes = plt.subplots(1, 2, figsize=(12, 4.8), layout='constrained')
    colors = ['#697580', '#087e8b', '#a054b0', '#d77527']
    labels = ['Source', 'MoonSurface + attributes', 'MoonSurface geometry only', 'MeshLab geometry only']
    for ax, (row, variants) in zip(axes, data):
        target = row['provenance']['target_edge_length']
        ax.axvspan(.8, 4/3, color='#dfeadf', alpha=.8, zorder=0)
        for job, color, label in zip(variants, colors, labels):
            values = np.sort(lengths(job)/target)
            ax.step(values, np.arange(1, len(values)+1)/len(values), where='post',
                    color=color, label=label, linewidth=1.7)
        ax.set_xscale('log')
        ax.set(ylim=(0, 1.01), xlabel='Edge length / target (log scale)',
               ylabel='Cumulative fraction of all unique edges', title=row['provenance']['name'])
        ax.grid(alpha=.2)
        ax.legend(loc='lower right', fontsize=8)
    fig.suptitle('Edge length distributions (full range, no tail clipping)', fontsize=14)
    fig.supxlabel('Shaded band: 4/5 to 4/3 target. Protected features can leave edges outside the band.', fontsize=10)
    fig.savefig(args.output/'edge-lengths.png', dpi=180)
    plt.close(fig)

    report.pop('workspace')
    report['input_report_sha256'] = sha256(report_bytes).hexdigest()
    report['figures'] = dict(matplotlib=matplotlib.__version__, numpy=np.__version__,
                              command='python tools/render_model_report.py')
    (args.output/'model-feedback.json').write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
    print('Saved real-models.png, edge-lengths.png and model-feedback.json')


if __name__ == '__main__':
    main()
