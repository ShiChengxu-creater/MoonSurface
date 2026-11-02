"""Run the declared compiler checks for one target (also configures MSVC)."""
import argparse
from common import run

parser = argparse.ArgumentParser()
parser.add_argument("--target", choices=["native", "js", "wasm-gc"], required=True)
args = parser.parse_args()
for command in ("check", "build", "test"):
    run(["moon", command, "--target", args.target, "--deny-warn"], target=args.target)
