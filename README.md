# MoonSurface

Portable triangle-surface processing in MoonBit. The first milestone develops
checked topology, local split/flip, and uniform Loop subdivision. QEM and collapse
belong to a later milestone and are not currently implemented.

Status: early development, `0.1.0-alpha.1`, not published to Mooncakes.

## Development

Pinned compiler: `moonc 0.10.14+7d59c7ec9`, moon/moonrun `0.1.20260920`.
Python 3.12+ runs development scripts; Node 22+ executes the JS target.
The core uses only MoonBit's bundled standard library. Windows native needs MSVC.

```sh
moon fmt --check
python tools/check.py --target wasm-gc
python tools/check.py --target js
python tools/check.py --target native
moon info
```

The repository includes GitHub Actions with explicit check, build and test stages.
A workflow file alone is not evidence of a completed remote CI run.

## License

Apache-2.0. See [THIRD_PARTY.md](THIRD_PARTY.md) and [AI_USAGE.md](AI_USAGE.md).
