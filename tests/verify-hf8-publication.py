"""Guard the public hf8 release bundle against mismatched or binary source."""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PATCH = ROOT / "patches" / "v16.1-hf8-over-hf6.patch"
MANIFEST = ROOT / "patches" / "hf8-source-manifest.json"
RELEASE = ROOT / "releases" / "v16.1-hf8"


def check(condition: bool, label: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {label}")
    print(f"PASS: {label}")


manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
patch_hash = hashlib.sha256(PATCH.read_bytes()).hexdigest()
check(patch_hash == manifest["patchSha256"], "source patch hash matches source manifest")
check(manifest["baseline"].endswith("hf6 (code44), project source tree"), "patch baseline is hf6/code44")
check(manifest["target"].endswith("hf8 (code46, r2)"), "patch target is hf8-r2/code46")
check(len(manifest["files"]) == 10, "patch has six edits and four new source classes")
check(len(manifest["compatibilityCopies"]) == 15, "compatibility copy list is explicit")
check(all(row["beforeSha256"] is not None for row in manifest["files"][:6]), "existing source fingerprints are present")
check(all(row["beforeSha256"] is None for row in manifest["files"][6:]), "new source fingerprints are present")

sha_line = (RELEASE / "SHA256SUMS.txt").read_text(encoding="utf-8").strip()
apk_hash, asset_name = sha_line.split(maxsplit=1)
check(asset_name == "sisensing-eco-v16.1-hf8-code46-r2.apk", "release checksum names the r2 asset")
check(re.fullmatch(r"[0-9a-f]{64}", apk_hash) is not None, "release checksum is a SHA-256 value")
readme = (ROOT / "README.md").read_text(encoding="utf-8")
check("releases/download/v16.1-hf8/" + asset_name in readme, "README has a direct APK download link")
check("HF8_LIMITATIONS.md" in readme and "HF8_TESTING.md" in readme, "README discloses testing limits")
check("test pre" not in readme.lower(), "release text is not an unreviewed placeholder")

for path in ROOT.rglob("*"):
    if not path.is_file() or ".git" in path.parts:
        continue
    relative = path.relative_to(ROOT)
    if relative.parts and relative.parts[0] == "work":
        continue
    check(path.suffix.lower() not in {".apk", ".aab", ".apks", ".dex", ".so", ".jks", ".keystore", ".p12", ".pem", ".pk8"},
          f"no ignored vendor binary/key is tracked in source tree: {relative.as_posix()}")

for rel in ("README.md", "README-HF5.md", "docs/HF8_INSTALL.md", "docs/HF8_BUILD.md",
            "docs/HF8_DESIGN.md", "docs/HF8_TESTING.md", "docs/HF8_LIMITATIONS.md",
            "patches/v16.1-hf8-over-hf6.patch", "patches/hf8-source-manifest.json"):
    check((ROOT / rel).is_file(), f"required public file exists: {rel}")
print("HF8_PUBLICATION_VERIFY_RESULT=PASS")
