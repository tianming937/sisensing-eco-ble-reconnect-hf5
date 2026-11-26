from __future__ import annotations

import argparse
import hashlib
import json
import struct
from collections import Counter
from pathlib import Path


NO_INDEX = 0xFFFFFFFF


def u16(data: bytes, offset: int) -> int:
    return struct.unpack_from("<H", data, offset)[0]


def u32(data: bytes, offset: int) -> int:
    return struct.unpack_from("<I", data, offset)[0]


def uleb(data: bytes, offset: int) -> tuple[int, int]:
    value = 0
    shift = 0
    for _ in range(5):
        if offset >= len(data):
            raise ValueError("truncated uleb128")
        byte = data[offset]
        offset += 1
        value |= (byte & 0x7F) << shift
        if byte < 0x80:
            return value, offset
        shift += 7
    raise ValueError("uleb128 too long")


class Dex:
    def __init__(self, path: Path) -> None:
        self.path = path
        self.data = path.read_bytes()
        if self.data[:4] != b"dex\n":
            raise ValueError(f"not dex: {path}")
        self.string_count = u32(self.data, 0x38)
        self.string_off = u32(self.data, 0x3C)
        self.type_count = u32(self.data, 0x40)
        self.type_off = u32(self.data, 0x44)
        self.method_count = u32(self.data, 0x58)
        self.method_off = u32(self.data, 0x5C)
        self.class_count = u32(self.data, 0x60)
        self.class_off = u32(self.data, 0x64)
        self._strings: dict[int, str] = {}

    def string(self, index: int) -> str:
        if index == NO_INDEX:
            return ""
        cached = self._strings.get(index)
        if cached is not None:
            return cached
        if not 0 <= index < self.string_count:
            return f"<bad-string-{index}>"
        item_off = u32(self.data, self.string_off + index * 4)
        _, cursor = uleb(self.data, item_off)
        end = self.data.find(b"\0", cursor)
        if end < 0:
            return "<unterminated-string>"
        value = self.data[cursor:end].decode("utf-8", errors="replace")
        self._strings[index] = value
        return value

    def type_name(self, index: int) -> str:
        if not 0 <= index < self.type_count:
            return f"<bad-type-{index}>"
        return self.string(u32(self.data, self.type_off + index * 4))

    def method_name(self, index: int) -> str:
        if not 0 <= index < self.method_count:
            return f"<bad-method-{index}>"
        return self.string(u32(self.data, self.method_off + index * 8 + 4))

    def audit(self) -> dict[str, object]:
        code_methods = 0
        zero_code_methods = 0
        zero_by_namespace: Counter[str] = Counter()
        zero_by_source: Counter[str] = Counter()
        examples: list[dict[str, object]] = []
        malformed: list[str] = []

        for class_index in range(self.class_count):
            base = self.class_off + class_index * 32
            try:
                descriptor = self.type_name(u32(self.data, base))
                source = self.string(u32(self.data, base + 16))
                class_data_off = u32(self.data, base + 24)
                if class_data_off == 0:
                    continue
                cursor = class_data_off
                static_count, cursor = uleb(self.data, cursor)
                instance_count, cursor = uleb(self.data, cursor)
                direct_count, cursor = uleb(self.data, cursor)
                virtual_count, cursor = uleb(self.data, cursor)
                for _ in range(static_count + instance_count):
                    _, cursor = uleb(self.data, cursor)
                    _, cursor = uleb(self.data, cursor)

                method_index = 0
                for group_count in (direct_count, virtual_count):
                    method_index = 0
                    for _ in range(group_count):
                        diff, cursor = uleb(self.data, cursor)
                        method_index += diff
                        access_flags, cursor = uleb(self.data, cursor)
                        code_off, cursor = uleb(self.data, cursor)
                        if code_off == 0:
                            continue
                        code_methods += 1
                        if code_off + 16 > len(self.data):
                            raise ValueError(f"bad code_off {code_off}")
                        insns_size = u32(self.data, code_off + 12)
                        insns_off = code_off + 16
                        insns_end = insns_off + insns_size * 2
                        if insns_end > len(self.data):
                            raise ValueError(f"bad insns_end {insns_end}")
                        insns = self.data[insns_off:insns_end]
                        if insns_size > 0 and not any(insns):
                            zero_code_methods += 1
                            bare = descriptor[1:-1] if descriptor.startswith("L") else descriptor
                            namespace = bare.split("/", 1)[0] if "/" in bare else "obfuscated-root"
                            zero_by_namespace[namespace] += 1
                            if source:
                                zero_by_source[source] += 1
                            if len(examples) < 50:
                                examples.append(
                                    {
                                        "class": descriptor,
                                        "source": source,
                                        "method_index": method_index,
                                        "method": self.method_name(method_index),
                                        "access_flags": access_flags,
                                        "code_off": code_off,
                                        "insns_size": insns_size,
                                    }
                                )
            except (IndexError, struct.error, ValueError) as exc:
                if len(malformed) < 50:
                    malformed.append(f"class[{class_index}]: {exc}")

        return {
            "path": str(self.path.resolve()),
            "sha256": hashlib.sha256(self.data).hexdigest(),
            "file_size": len(self.data),
            "header_file_size": u32(self.data, 0x20),
            "classes": self.class_count,
            "methods": self.method_count,
            "methods_with_code": code_methods,
            "all_zero_code_methods": zero_code_methods,
            "top_zero_namespaces": zero_by_namespace.most_common(30),
            "top_zero_sources": zero_by_source.most_common(40),
            "examples": examples,
            "malformed": malformed,
        }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("inputs", nargs="+", type=Path)
    args = parser.parse_args()
    reports = [Dex(path).audit() for path in args.inputs]
    print(json.dumps(reports, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
