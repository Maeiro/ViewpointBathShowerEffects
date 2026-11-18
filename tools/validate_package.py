import argparse
import hashlib
import zipfile
from pathlib import Path


def properties(text):
    text = text.replace("\\\r\n", "").replace("\\\n", "")
    return dict(line.strip().split("=", 1) for line in text.splitlines()
                if "=" in line and not line.lstrip().startswith("#"))


parser = argparse.ArgumentParser()
parser.add_argument("-ViewpointJar", required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
source = root / "content/mods/ViewpointBathShowerEffects"
packaged = root / "dist/ViewpointBathShowerEffects/Contents/mods/ViewpointBathShowerEffects"
for path in source.rglob("*"):
    if path.is_file():
        assert hashlib.sha256(path.read_bytes()).digest() == hashlib.sha256(
            (packaged / path.relative_to(source)).read_bytes()).digest(), f"Stale package: {path}"
for path in (source / "mod.info", source / "42/mod.info"):
    info = properties(path.read_text())
    assert info["id"] == "ViewpointBathShowerEffects"
    assert "javaJarFile" not in info and "javaPkgName" not in info
addon_folder = source / "42/media/viewpoint/addons/maeiro.bath-shower-effects"
addon = properties((addon_folder / "addon.properties").read_text())
assert addon["api"] == "1.0" and addon["side"] == "client"
assert set(addon["permissions"].split(",")) == {"lua", "shaders"}
with zipfile.ZipFile(addon_folder / addon["jar"]) as jar:
    assert not any(name.startswith("viewpoint/") for name in jar.namelist())
    assert not any("Test" in name or "Check" in name for name in jar.namelist())
    for name in jar.namelist():
        if name.endswith(".class"):
            assert int.from_bytes(jar.read(name)[6:8], "big") == 61, "Addon must target Java 17"
with zipfile.ZipFile(args.ViewpointJar) as viewpoint:
    for base in ("default", "somber"):
        folder = source / f"42/media/viewpoint/shaderpacks/maeiro.bath-shower-{base}"
        pack = properties((folder / "pack.properties").read_text())
        assert pack["base"] == base
        assert pack["passes"].split() == ["bathShower"], "Declare only new passes; the renderer inherits the base graph"
        assert pack["pass.bathShower.stage"] == "final"
        assert pack["pass.bathShower.inputs"] == "color depth"
        assert (folder / "shaders/bath_shower.frag").read_bytes() == (root / "src/shaders/bath_shower.frag").read_bytes()
with zipfile.ZipFile(root / "dist/ViewpointBathShowerEffects.zip") as archive:
    names = {name.replace("\\", "/") for name in archive.namelist()}
    for relative in ("mod.info", "42/mod.info"):
        assert f"ViewpointBathShowerEffects/Contents/mods/ViewpointBathShowerEffects/{relative}" in names
print("PASS: package hashes, Java 17/API isolation, additive pass declarations, final stage, ZIP tree")
