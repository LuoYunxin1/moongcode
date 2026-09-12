#!/usr/bin/env python3
"""Independent analytic/CLI oracle; Python standard library, no controller emulator.

Runs the real CLI (not MoonGCode's geometry helper). Numeric expectations use
math.pi/hypot and exact quarter/full-circle fixtures. Exits nonzero on a mismatch.
"""
import argparse
import itertools
import hashlib
import platform
import json
import math
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run_suite(repo, target):
    subprocess.run(["moon", "build", "cmd/main", "--target", target, "--release"],
                   cwd=repo, check=True)
    build = repo / "_build" / target / "release" / "build" / "cmd" / "main"
    if target == "js":
        command = [shutil.which("node") or "node", str(build / "main.js")]
    else:
        binary = next((build / n for n in ("main.exe", "main") if (build / n).is_file()), None)
        if binary is None:
            raise RuntimeError(f"Native CLI not found under {build}")
        command = [str(binary)]
    groups = {key: {"total": 0, "passed": 0, "failure_samples": []}
              for key in ("analytic_arcs", "workspace_audits", "cli_contracts")}
    max_length_error = max_seconds_error = max_relative_error = 0.0

    def record(group, name, passed, detail):
        bucket = groups[group]
        bucket["total"] += 1
        bucket["passed"] += int(passed)
        if not passed and len(bucket["failure_samples"]) < 4:
            bucket["failure_samples"].append({"case": name, "detail": detail})

    with tempfile.TemporaryDirectory(prefix="moongcode-reference-") as directory:
        temp = Path(directory)
        source = temp / "fixture.nc"

        def invoke(args, text=None):
            if text is not None:
                source.write_text(text, encoding="utf-8")
            return subprocess.run(command + args, cwd=repo, capture_output=True,
                                  text=True, encoding="utf-8", timeout=15)

        planes = [("G17", "X", "Y", "Z", "I", "J"),
                  ("G18", "Z", "X", "Y", "K", "I"),
                  ("G19", "Y", "Z", "X", "J", "K")]
        grid = itertools.product(planes, ("G2", "G3"), ("G21", "G20"),
                                 ("G91.1", "G90.1"), (0.25, 1.0, 10.0),
                                 (-2.0, 0.0, 3.0), (False, True))
        for plane, motion, units, center_mode, radius, rise_ratio, full in grid:
            code, u, v, w, cu, cv = plane
            rise = radius * rise_ratio
            direction = -1 if motion == "G2" else 1
            eu, ev = (radius, 0.0) if full else (0.0, radius * direction)
            center_u = -radius if center_mode == "G91.1" else 0.0
            text = (f"{units} G90 {center_mode} F60\nG0 {u}{radius}\n"
                    f"{code} {motion} {u}{eu} {v}{ev} {w}{rise} {cu}{center_u} {cv}0\nM30\n")
            scale = 25.4 if units == "G20" else 1.0
            expected_arc = math.hypot(radius * (2 * math.pi if full else math.pi / 2), rise) * scale
            expected_seconds = radius * scale / 100 + expected_arc / scale
            result = invoke(["analyze", str(source)], text)
            match = re.search(r"distance_mm=(\S+) seconds=(\S+)", result.stdout)
            name = f"{code}/{motion}/{units}/{center_mode}/r={radius}/rise={rise}/full={full}"
            detail = {"exit": result.returncode}
            passed = False
            if match:
                length, seconds = map(float, match.groups())
                actual_arc = length - radius * scale
                length_error = abs(actual_arc - expected_arc)
                seconds_error = abs(seconds - expected_seconds)
                relative_error = length_error / expected_arc
                finite = math.isfinite(length) and math.isfinite(seconds)
                if finite:
                    max_length_error = max(max_length_error, length_error)
                    max_seconds_error = max(max_seconds_error, seconds_error)
                    max_relative_error = max(max_relative_error, relative_error)
                passed = (result.returncode == 0 and finite and
                          math.isclose(actual_arc, expected_arc, rel_tol=1e-12, abs_tol=1e-9) and
                          math.isclose(seconds, expected_seconds, rel_tol=1e-12, abs_tol=1e-9))
                detail.update(actual_arc_mm=actual_arc, expected_arc_mm=expected_arc,
                              actual_seconds=seconds, expected_seconds=expected_seconds)
            record("analytic_arcs", name, passed, detail)

        profile = temp / "machine.profile"
        for plane, motion, separate, limit in itertools.product(
                ("G17", "G18", "G19"), ("G2", "G3"), (False, True), (4, 6)):
            axis = "Y" if plane == "G17" else "Z"
            lines = ["MOONGCODE_PROFILE 1", "name reference-envelope"]
            lines += [f"axis {a} {-limit if a == axis else -100} {limit if a == axis else 100}"
                      for a in "XYZ"]
            lines += ["max-feed 2400", "rapid-feed 6000", "max-spindle 24000",
                      "max-arc-radius 500", "max-dwell 30", "require-spindle true",
                      "allow-rapid-z-down false", "allow-unsupported false", "tools 0"]
            profile.write_text("\n".join(lines) + "\n", encoding="utf-8")
            offsets = {"G17": "I5 J0", "G18": "I5 K0", "G19": "J5 K0"}[plane]
            separator = "\n" if separate else " "
            text = f"G21 F60 M3 S1000\n{plane}{separator}{motion} {offsets}\nM5 M30\n"
            result = invoke(["audit-profile", str(source), str(profile)], text)
            expected_exit = 1 if limit == 4 else 0
            has_bounds = "audit.workspace.bounds" in result.stdout
            passed = result.returncode == expected_exit and has_bounds == (limit == 4)
            record("workspace_audits", f"{plane}/{motion}/separate={separate}/limit={limit}",
                   passed, {"exit": result.returncode, "bounds_diagnostic": has_bounds})

        cli_cases = [
            ("default demo", [], None, 0, "=== audit ==="),
            ("unknown", ["auidt"], None, 2, "cli.command.unknown"),
            ("unknown before known word", ["auidt", "audit"], None, 2, "cli.command.unknown"),
            ("missing argument", ["analyze"], None, 2, "cli.file.required"),
            ("missing file", ["analyze", str(temp / "absent.nc")], None, 2, "io.read.failed"),
            ("extra arguments", ["analyze", str(source), "demo"], "M30\n", 2, "cli.arguments.extra"),
            ("extra help arguments", ["help", "demo"], None, 2, "cli.arguments.extra"),
            ("extra profiles arguments", ["profiles", "demo"], None, 2, "cli.arguments.extra"),
            ("invalid replay analysis", ["analyze", str(source)], "G1 X2\nM30\n", 1, "interpret.feed.missing"),
            ("invalid replay trace", ["trace", str(source)], "G1 X2\nM30\n", 1, "interpret.feed.missing"),
            ("invalid normalization", ["normalize", str(source)], "G1 X?\n", 1, "error["),
            ("invalid explanation", ["explain", str(source)], "G1 X?\n", 1, "error["),
            ("syntax validation is not replay", ["validate", str(source)], "G1 X2\nM30\n", 0, ""),
            ("help", ["help"], None, 0, "usage:"),
        ]
        for name, args, text, exit_code, marker in cli_cases:
            result = invoke(args, text)
            record("cli_contracts", name, result.returncode == exit_code and marker in result.stdout,
                   {"exit": result.returncode, "expected_exit": exit_code, "stdout": result.stdout[:300]})
    groups["analytic_arcs"].update(max_length_abs_error_mm=max_length_error,
                                   max_time_abs_error_seconds=max_seconds_error,
                                   max_length_relative_error=max_relative_error)
    revision = subprocess.run(["git", "rev-parse", "HEAD"], cwd=repo,
                              capture_output=True, text=True, check=True).stdout.strip()
    versions = subprocess.run(["moon", "version", "--all"], capture_output=True,
                              text=True, check=True).stdout.strip()
    return {"schema": 1, "source_revision": revision,
            "oracle_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            "environment": {"platform": platform.platform(), "python": platform.python_version(),
                            "moon": versions,
                            "node": subprocess.run(["node", "--version"], capture_output=True,
                                                   text=True, check=True).stdout.strip()},
            "target": target, "oracle": "Python math.hypot/pi; no external controller execution",
            "tolerance": {"relative": 1e-12, "absolute": 1e-9}, "groups": groups,
            "passed": all(v["passed"] == v["total"] for v in groups.values())}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=ROOT, help="Also supports a separate baseline checkout")
    parser.add_argument("--target", choices=("js", "native"), default="js")
    parser.add_argument("--output", type=Path, help="Write measured JSON evidence")
    args = parser.parse_args()
    report = run_suite(args.repo.resolve(), args.target)
    text = json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False) + "\n"
    print(text)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding="utf-8")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
