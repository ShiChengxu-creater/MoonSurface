# Real model fixtures

Both models come from Khronos glTF Sample Assets, fixed revision
`8f492390ddc7a2ae221a1369ef560589cf8c70fb`:

- Avocado: Microsoft, 2017, CC0-1.0. A modeled cut avocado with a hand-painted texture;
  this fixture uses geometry, corner UV and material ids, not the texture image.
- Suzanne: Norbert Nopper / UX3D, 2017, CC0-1.0. Blender's chimpanzee test model.

The original legal notices are retained in each `SOURCE.md`, with the full CC0
text in `CC0-1.0.txt`. `source.json` records exact upstream URLs and hashes.
`tools/prepare_models.py` can reproduce the derived JSON from the fixed upstream
gltf/buffer inputs. It never downloads texture/screenshot images.

The importer handles the only mesh's uncompressed triangle primitives in mesh-local
coordinates. It exactly welds equal positions, keeps authored UVs per corner,
retains primitive material ids and marks authored-normal discontinuities as feature
constraints. It does not repair topology or apply scene transforms. The independent
manifold checker must accept the result. Full glTF round-tripping is not claimed.

`position_probe` is an explicitly added analytic linear attribute for checking
resampling. It is not presented as a channel authored by the asset creators.
These fixtures are CC0 data; the processing code is Apache-2.0.
