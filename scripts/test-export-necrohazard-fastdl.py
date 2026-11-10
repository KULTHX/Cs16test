#!/usr/bin/env python3
from __future__ import annotations
import importlib.util
import tempfile
from pathlib import Path

script = Path(__file__).with_name("export-necrohazard-fastdl.py")
spec = importlib.util.spec_from_file_location("fastdl_export", script)
module = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(module)

with tempfile.TemporaryDirectory(prefix="fastdl-test-") as temp:
    root = Path(temp)
    hlds = root / "hlds"
    cstrike = hlds / "cstrike"
    fastdl = root / "fastdl"
    report = root / "EXPORT-REPORT.txt"
    manifest = root / "stock.json"

    (cstrike / "maps").mkdir(parents=True)
    (cstrike / "sound" / "vox").mkdir(parents=True)
    (cstrike / "addons" / "amxmodx" / "configs").mkdir(parents=True)
    (cstrike / "addons" / "amxmodx" / "scripting").mkdir(parents=True)

    (cstrike / "maps" / "de_dust2.bsp").write_bytes(b"stock-map")
    (cstrike / "sound" / "vox" / "one.wav").write_bytes(b"stock-sound")
    module.snapshot(cstrike, manifest)

    (cstrike / "maps" / "zm_survival.bsp").write_bytes(b"custom-map")
    (cstrike / "sound" / "necro").mkdir(parents=True)
    (cstrike / "sound" / "necro" / "count9.wav").write_bytes(b"countdown-sound")
    (cstrike / "models").mkdir()
    (cstrike / "models" / "zp_test.mdl").write_bytes(b"custom-model")
    (cstrike / "addons" / "amxmodx" / "plugins").mkdir(parents=True)
    (cstrike / "addons" / "amxmodx" / "plugins" / "countdown.amxx").write_bytes(
        b"compiled-plugin\x00sound/necro/count9.wav\x00"
    )

    module.publish(cstrike, manifest, fastdl, report)

    assert (fastdl / "maps" / "zm_survival.bsp").read_bytes() == b"custom-map"
    assert (fastdl / "sound" / "necro" / "count9.wav").read_bytes() == b"countdown-sound"
    assert (fastdl / "models" / "zp_test.mdl").read_bytes() == b"custom-model"
    assert (cstrike / "mapcycle.txt").read_text(encoding="utf-8").strip() == "zm_survival"
    text = report.read_text(encoding="utf-8")
    assert "necro/count9.wav" in text
    assert "New custom BSP maps: 1" in text
print("FastDL exporter smoke test passed: custom map, model, and countdown sound were exported.")
