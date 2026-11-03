"""Shows that code written for LLM Toolkit Lite runs unchanged on the full LLM Toolkit.

Usage: python -I tools/check_upgrade.py <godot executable> <full version's addons/llm_toolkit>

Builds a scratch project with the full add-on in addons/llm_toolkit/ (an upgrade is exactly that
folder replaced), then runs this repository's tests there (they skip the Lite-only checks) and opens
the demo for a few frames.
"""
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
godot, full = sys.argv[1], sys.argv[2]

DEMO_RUNNER = """extends SceneTree
var frames := 0
func _init() -> void:
	root.add_child(load("res://demo/demo.tscn").instantiate())
func _process(_delta: float) -> bool:
	frames += 1
	if frames == 10:
		print("demo ran ", frames, " frames, ", Llm.new().has_method("json"))
		return true
	return false
"""

with tempfile.TemporaryDirectory() as tmp:
    shutil.copytree(full, os.path.join(tmp, "addons", "llm_toolkit"))
    for folder in ("tests", "demo"):
        shutil.copytree(os.path.join(ROOT, folder), os.path.join(tmp, folder),
                        ignore=shutil.ignore_patterns("out", "*.import", "*.uid"))
    shutil.copy(os.path.join(ROOT, "project.godot"), tmp)
    with open(os.path.join(tmp, "demo_runner.gd"), "w", newline="\n") as f:
        f.write(DEMO_RUNNER)
    subprocess.run([godot, "--headless", "--path", tmp, "--import"], capture_output=True, timeout=300)

    def run(*args):
        """Godot's output and exit code. A script that fails to parse leaves Godot running, hence the timeout."""
        try:
            r = subprocess.run([godot, "--headless", "--path", tmp, *args], capture_output=True, timeout=120)
            return (r.stdout + r.stderr).decode("utf-8", "replace"), r.returncode
        except subprocess.TimeoutExpired as e:
            return ((e.stdout or b"") + (e.stderr or b"")).decode("utf-8", "replace") + "\n(timed out)", -1

    log, code = run("res://tests/test_lite.tscn")
    demo_log, _ = run("-s", "res://demo_runner.gd")
    failed = 0
    for line in log.splitlines():
        if line.startswith(("Testing", "FAIL")) or " checks, " in line or "SCRIPT ERROR" in line or "Parse Error" in line:
            print("  " + line.strip())
    if code != 0 or "Testing the FULL addon" not in log:
        failed += 1
        print("  FAIL  the tests on the full version (exit %d)" % code)
    errors = [l for l in demo_log.splitlines() if "SCRIPT ERROR" in l or "Parse Error" in l]
    if "demo ran 10 frames, true" not in demo_log or errors:
        failed += 1
        print("  FAIL  the demo on the full version")
        for e in errors:
            print("        " + e)
    else:
        print("  ok    the demo runs on the full version")
    sys.exit(1 if failed else 0)
