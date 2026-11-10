#!/usr/bin/env python3
"""Export only Zombie Plague client assets added by the mod bundle into Vercel FastDL."""
from __future__ import annotations
import hashlib, json, re, shutil, sys
from pathlib import Path

ROOTS = ("gfx", "maps", "models", "sound", "sprites", "resource")
REF_RE = re.compile(r"""["']([^"' \r\n<>]+?\.(?:wav|mp3|ogg|mdl|spr|tga|bmp))["']""", re.I)
BINARY_AUDIO_RE = re.compile(rb"[A-Za-z0-9_./-]+\.(?:wav|mp3|ogg)", re.I)
TEXT_EXTS = {".sma", ".inc", ".ini", ".cfg", ".txt", ".json"}

def fail(message):
    raise SystemExit("ERROR: " + message)

def sha256(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()

def asset_files(cstrike):
    allowed_root = cstrike.resolve()
    visited_dirs, yielded = set(), set()
    for root_name in ROOTS:
        start = cstrike / root_name
        if not start.exists():
            continue
        stack = [(start, Path(root_name))]
        while stack:
            candidate, rel = stack.pop()
            try:
                real = candidate.resolve(strict=True)
                real.relative_to(allowed_root)
            except (FileNotFoundError, OSError, RuntimeError, ValueError):
                continue
            rel_key, real_key = rel.as_posix(), str(real)
            if real.is_dir():
                if real_key in visited_dirs:
                    continue
                visited_dirs.add(real_key)
                try:
                    for child in sorted(real.iterdir(), key=lambda p: p.name, reverse=True):
                        stack.append((candidate / child.name, rel / child.name))
                except OSError:
                    pass
            elif real.is_file() and rel_key not in yielded:
                yielded.add(rel_key)
                yield rel_key, real

def snapshot(cstrike, output):
    if not cstrike.is_dir():
        fail(f"missing cstrike directory: {cstrike}")
    baseline = {rel: sha256(path) for rel, path in asset_files(cstrike)}
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(baseline, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"Captured {len(baseline)} stock downloadable assets before the mod overlay.")

def text_sources(cstrike):
    roots = [cstrike / "addons/amxmodx/configs",
             cstrike / "addons/amxmodx/scripting",
             cstrike / "addons/amxmodx/data"]
    seen = set()
    for root in roots:
        if not root.exists():
            continue
        for path in root.rglob("*"):
            try:
                if path.is_file() and path.suffix.lower() in TEXT_EXTS:
                    real = path.resolve(strict=True)
                    if str(real) not in seen and real.stat().st_size <= 2_000_000:
                        seen.add(str(real))
                        yield real
            except (OSError, RuntimeError):
                continue

def copy_asset(src, rel, destination):
    target = destination / Path(rel)
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, target)
    return target.stat().st_size

def record_audio_reference(raw, cstrike, fastdl, copied, audio_refs, missing_audio):
    raw = str(raw).replace("\\", "/").strip().lstrip("./")
    if raw.lower().startswith("sound/"):
        raw = raw[6:]
    path = Path(raw)
    if path.is_absolute() or any(part in {"", ".", ".."} for part in path.parts):
        return
    if path.suffix.lower() not in {".wav", ".mp3", ".ogg"}:
        return

    rel = path.as_posix()
    audio_refs.add(rel)
    sound_root = (cstrike / "sound").resolve()
    try:
        resolved = sound_root.joinpath(*path.parts).resolve(strict=True)
        resolved.relative_to(sound_root)
    except (FileNotFoundError, OSError, RuntimeError, ValueError):
        valve_file = cstrike.parent / "valve" / "sound" / Path(*path.parts)
        if not valve_file.is_file():
            missing_audio.add(rel)
        return

    if not resolved.is_file():
        missing_audio.add(rel)
        return

    copied["sound/" + rel] = (
        sha256(resolved),
        copy_asset(resolved, "sound/" + rel, fastdl)
    )

def publish(cstrike, baseline_path, fastdl, report):
    if not cstrike.is_dir():
        fail(f"missing cstrike directory: {cstrike}")
    if not baseline_path.is_file():
        fail(f"stock manifest missing: {baseline_path}")
    baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
    current = list(asset_files(cstrike))
    copied = {}

    for rel, src in current:
        digest = sha256(src)
        if baseline.get(rel) != digest:
            copied[rel] = (digest, copy_asset(src, rel, fastdl))

    audio_refs, missing_audio = set(), set()
    for source in text_sources(cstrike):
        try:
            body = source.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        for raw in REF_RE.findall(body):
            record_audio_reference(raw, cstrike, fastdl, copied, audio_refs, missing_audio)

    # Compiled AMXX bytecode preserves literal paths passed to precache_sound/emit_sound.
    plugin_dir = cstrike / "addons" / "amxmodx" / "plugins"
    if plugin_dir.exists():
        for plugin in sorted(plugin_dir.glob("*.amxx")):
            try:
                if plugin.stat().st_size > 20_000_000:
                    continue
                raw_plugin = plugin.read_bytes()
            except OSError:
                continue
            for match in BINARY_AUDIO_RE.findall(raw_plugin):
                raw = match.decode("ascii", errors="ignore")
                record_audio_reference(raw, cstrike, fastdl, copied, audio_refs, missing_audio)

    # GoldSrc BSP entity lumps can embed ambient sound paths. Scan changed
    # custom maps so map-owned resources are exported even if AMXX/.res omit them.
    for rel, bsp in current:
        if not (rel.lower().startswith("maps/") and rel.lower().endswith(".bsp")):
            continue
        if baseline.get(rel) == sha256(bsp):
            continue
        try:
            if bsp.stat().st_size > 256_000_000:
                continue
            raw_bsp = bsp.read_bytes()
        except OSError:
            continue
        for match in BINARY_AUDIO_RE.findall(raw_bsp):
            record_audio_reference(match.decode("ascii", errors="ignore"),
                                   cstrike, fastdl, copied, audio_refs, missing_audio)

    new_maps = sorted(
        Path(rel).stem for rel, src in current
        if rel.lower().startswith("maps/") and rel.lower().endswith(".bsp")
        and baseline.get(rel) != sha256(src)
        and re.fullmatch(r"[A-Za-z0-9_]+", Path(rel).stem)
    )
    if new_maps:
        (cstrike / "mapcycle.txt").write_text("\n".join(new_maps) + "\n", encoding="utf-8")
        # Provide a lightweight map description if the custom map package omitted it.
        for map_name in new_maps:
            map_txt = cstrike / "maps" / (map_name + ".txt")
            if not map_txt.exists():
                map_txt.write_text(
                    f"NECROHAZARD Zombie Plague\\n{map_name}\\n",
                    encoding="utf-8"
                )
            copied["maps/" + map_name + ".txt"] = (
                sha256(map_txt),
                copy_asset(map_txt, "maps/" + map_name + ".txt", fastdl)
            )

    plugins_file = cstrike / "addons/amxmodx/configs/plugins.ini"
    active_plugins = []
    if plugins_file.exists():
        active_plugins = [
            line.strip() for line in plugins_file.read_text(encoding="utf-8", errors="ignore").splitlines()
            if line.strip() and not line.strip().startswith((";", "#"))
        ]

    total = sum(size for _digest, size in copied.values())
    lines = [
        "NECROHAZARD FastDL export report",
        f"Copied/new/changed client files: {len(copied)}",
        f"Total published bytes: {total}",
        f"New custom BSP maps: {len(new_maps)}",
        "",
        "MAP ROTATION:", *(new_maps or ["No new custom BSP maps were found in the mod bundle."]),
        "",
        "AUDIO REFERENCES FOUND IN MOD SOURCE, PLUGINS, AND BSP MAPS:", *(sorted(audio_refs) or ["No explicit sound paths were found."]),
        "",
        "AUDIO FILES MISSING FROM CSTRIKE AND VALVE SOUND:", *(sorted(missing_audio) or ["None."]),
        "",
        "ACTIVE AMXX PLUGINS:", *(active_plugins or ["No active entries found in plugins.ini."]),
        "",
        "PUBLISHED FASTDL FILES:", *(f"{rel} ({size} bytes)" for rel, (_digest, size) in sorted(copied.items())),
    ]
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n".join(lines[:min(len(lines), 100)]))
    print(f"FastDL export complete: {len(copied)} files, {total} bytes.")

def main():
    if len(sys.argv) < 2:
        fail("usage: snapshot <hlds-dir> <manifest> | publish <hlds-dir> <manifest> <fastdl-dir> <report>")
    mode = sys.argv[1]
    if mode == "snapshot" and len(sys.argv) == 4:
        snapshot(Path(sys.argv[2]) / "cstrike", Path(sys.argv[3]))
    elif mode == "publish" and len(sys.argv) == 6:
        publish(Path(sys.argv[2]) / "cstrike", Path(sys.argv[3]), Path(sys.argv[4]), Path(sys.argv[5]))
    else:
        fail("invalid arguments")

if __name__ == "__main__":
    main()
