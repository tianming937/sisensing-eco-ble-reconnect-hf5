"""Export only the reviewed hf8-r2 delta; never export a full vendor project.

Requires a legally obtained project hf6/code44 baseline and the hf8-r2/code46 tree.
Text fingerprints normalize CRLF/CR to LF; APK fingerprints are always raw bytes.
"""
from __future__ import annotations

import argparse
import difflib
import hashlib
import json
from pathlib import Path


CHANGED = (
    "apktool.yml",
    "smali_classes5/com/sisensing/common/ble/LocalBleService.smali",
    "smali_classes5/com/sisensing/common/ble/LocalBleService$m.smali",
    "smali_classes5/com/sisensing/common/ble/a.smali",
    "smali_classes7/p/a$c.smali",
    "smali_classes8/com/sisensing/common/ble/BleReconnectV16.smali",
)
ADDED = tuple(
    f"smali_classes8/com/sisensing/common/ble/{name}.smali"
    for name in ("BleAuditHf7", "BlePendingScanHf7", "BleWakeSchedulerHf7", "BleForegroundGuardHf8")
)
COMPAT = (
    "kotlin/annotation/annotation.kotlin_builtins",
    "kotlin/collections/collections.kotlin_builtins",
    "kotlin/coroutines/coroutines.kotlin_builtins",
    "kotlin/internal/internal.kotlin_builtins",
    "kotlin/kotlin.kotlin_builtins",
    "kotlin/ranges/ranges.kotlin_builtins",
    "kotlin/reflect/reflect.kotlin_builtins",
    "META-INF/services/a26",
    "META-INF/services/b95",
    "META-INF/services/com.tencent.qcloud.tuicore.interfaces.TUIInitializer",
    "META-INF/services/javax.ws.rs.ext.MessageBodyReader",
    "META-INF/services/javax.ws.rs.ext.MessageBodyWriter",
    "META-INF/services/javax.ws.rs.ext.Providers",
    "META-INF/services/org.glassfish.jersey.internal.spi.AutoDiscoverable",
    "META-INF/services/wk1",
)


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def text(path: Path) -> str:
    return path.read_text(encoding="utf-8-sig").replace("\r\n", "\n").replace("\r", "\n")


def inventory(root: Path) -> dict[str, str]:
    excluded = {"build", "dist", "original", ".git"}
    result = {}
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        rel = path.relative_to(root)
        if rel.parts[0] in excluded or path.suffix in {".bak", ".orig", ".rej"}:
            continue
        result[rel.as_posix()] = sha(path.read_bytes())
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", required=True, type=Path)
    parser.add_argument("--target", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    base, target = args.base.resolve(), args.target.resolve()
    output = args.output.resolve()
    if base == target or output == base or output == target:
        raise ValueError("Use separate baseline, target and patch-output directories")
    if "versionCode: 44" not in text(base / "apktool.yml"):
        raise ValueError("Expected project hf6/code44 baseline")
    if "versionCode: 46" not in text(target / "apktool.yml"):
        raise ValueError("Expected project hf8-r2/code46 target")
    if 'FGS_START_COMMAND_ABORT_NOT_STICKY_HF8' not in text(target / CHANGED[1]):
        raise ValueError("Rejected earlier hf8 build: r2 foreground startup protection missing")

    before_tree, after_tree = inventory(base), inventory(target)
    changed = {p for p in before_tree.keys() & after_tree.keys() if before_tree[p] != after_tree[p]}
    added = after_tree.keys() - before_tree.keys()
    removed = before_tree.keys() - after_tree.keys()
    expected_added = set(ADDED) | {"unknown/" + p for p in COMPAT}
    if changed != set(CHANGED) or added != expected_added or removed:
        raise ValueError(f"Unreviewed source delta: changed={sorted(changed)}, added={sorted(added)}, removed={sorted(removed)}")

    chunks, files = [], []
    for rel in (*CHANGED, *ADDED):
        before = text(base / rel) if rel in CHANGED else ""
        after = text(target / rel)
        chunks.append(f"diff --git a/{rel} b/{rel}\n")
        if rel in ADDED:
            chunks.append("new file mode 100644\n")
        chunks.extend(difflib.unified_diff(
            before.splitlines(keepends=True), after.splitlines(keepends=True),
            fromfile=f"a/{rel}" if rel in CHANGED else "/dev/null",
            tofile=f"b/{rel}", n=3,
        ))
        files.append({"path": rel, "beforeSha256": sha(before.encode()) if rel in CHANGED else None,
                      "afterSha256": sha(after.encode())})
    copies = []
    for rel in COMPAT:
        source = base / rel
        destination = target / "unknown" / rel
        if source.read_bytes() != destination.read_bytes():
            raise ValueError(f"Compatibility metadata must be copied byte-for-byte: {rel}")
        copies.append({"source": rel, "target": "unknown/" + rel, "sha256": sha(source.read_bytes())})
    if text(base / "AndroidManifest.xml") != text(target / "AndroidManifest.xml"):
        raise ValueError("Manifest/permission surface must be unchanged")

    patch = "".join(chunks).encode("utf-8")
    manifest = {
        "schemaVersion": 1,
        "baseline": "02.23.01.00-v16.1-hf6 (code44), project source tree",
        "target": "02.23.01.00-v16.1-hf8 (code46, r2)",
        "textHashNormalization": "UTF-8 without BOM, LF line endings",
        "patchSha256": sha(patch),
        "androidManifestSha256": sha(text(base / "AndroidManifest.xml").encode()),
        "files": files,
        "compatibilityCopies": copies,
    }
    output.mkdir(parents=True, exist_ok=True)
    patch_path = output / "v16.1-hf8-over-hf6.patch"
    manifest_path = output / "hf8-source-manifest.json"
    if patch_path.exists() or manifest_path.exists():
        raise FileExistsError("Refusing to replace an existing patch/manifest")
    patch_path.write_bytes(patch)
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"SOURCE_DELTA_PASS changed={len(changed)} added={len(added)} removed={len(removed)}")
    print(f"PATCH_SHA256={sha(patch)}")
    print(f"PATCH_BYTES={len(patch)}")


if __name__ == "__main__":
    main()
