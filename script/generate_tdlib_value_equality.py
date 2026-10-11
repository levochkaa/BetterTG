#!/usr/bin/env python3
"""Generate content Hashable conformances for native TDLibKit 2 views used by BetterTG.

TDLibKit 1 models were value types with synthesized deep Equatable/Hashable. BetterTG
ownership and change detection compare those values, so this keeps content equality
for the closure of the root types below. Types that already declare a conformance in
BetterTG sources are referenced, never regenerated.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SCHEMA = ROOT.parent.parent / "Sources/TDLibKitNative/Generated/SchemaViews.swift"
OUTPUT = ROOT / "BetterTG/Extensions/Td/TDNativeValueEquality+Generated.swift"
SOURCE_ROOTS = (ROOT / "BetterTG", ROOT / "BetterTGNotificationService")

# Native views compared or hashed by BetterTG state, ownership and probe code.
ROOTS = (
    "AuthorizationState",
    "BasicGroup",
    "Chat",
    "ChatMember",
    "ChatMemberStatus",
    "ChatPermissions",
    "ChatPosition",
    "ChatType",
    "DraftMessage",
    "ForumTopic",
    "ForumTopicInfo",
    "Message",
    "MessageForwardInfo",
    "MessageInteractionInfo",
    "MessageProperties",
    "MessageReplyTo",
    "MessageSelfDestructType",
    "Supergroup",
    "TextQuote",
    "UpdateForumTopic",
    "UpdateMessageSendFailed",
    "UnreadReaction",
    "UpdateMessageSendSucceeded",
    "User",
)

STRUCT = re.compile(r"^public struct TDNative([A-Za-z][A-Za-z0-9]*):")
ENUM = re.compile(r"^public enum TDNative([A-Za-z][A-Za-z0-9]*):")
INITIALIZER = re.compile(r"^    public init\((.*)\) \{$")
CASE = re.compile(r"^    case ([A-Za-z][A-Za-z0-9]*)(?:\((TDNative[A-Za-z0-9]+)\))?$")
NATIVE = re.compile(r"TDNative([A-Za-z][A-Za-z0-9]*)")
EXISTING = re.compile(
    r"^extension TDNative([A-Za-z][A-Za-z0-9]*):[^{]*\b(?:Hashable|Equatable)\b",
    re.MULTILINE,
)
KEYWORDS = {"default", "extension", "func", "import", "in", "operator", "protocol", "self", "static", "subscript"}


def reference(field: str) -> str:
    return f"{chr(96)}{field}{chr(96)}" if field in KEYWORDS else field


def split_parameters(parameters: str) -> list[str]:
    result: list[str] = []
    start = 0
    depth = 0
    for index, character in enumerate(parameters):
        if character in "[(<{":
            depth += 1
        elif character in ")]>}":
            depth -= 1
        elif character == "," and depth == 0:
            result.append(parameters[start:index].strip())
            start = index + 1
    if parameters[start:].strip():
        result.append(parameters[start:].strip())
    return result


def parse(schema: str):
    structs: dict[str, list[tuple[str, str]]] = {}
    enums: dict[str, list[tuple[str, str | None]]] = {}
    current_struct: str | None = None
    current_enum: str | None = None
    for line in schema.splitlines():
        if match := STRUCT.match(line):
            current_struct, current_enum = match.group(1), None
            structs.setdefault(current_struct, [])
            continue
        if match := ENUM.match(line):
            current_enum, current_struct = match.group(1), None
            enums[current_enum] = []
            continue
        if current_struct is not None and (match := INITIALIZER.match(line)):
            fields = []
            for parameter in split_parameters(match.group(1)):
                name, kind = parameter.split(":", maxsplit=1)
                fields.append((name.strip().strip(chr(96)), kind.strip()))
            structs[current_struct] = fields
            continue
        if current_enum is not None:
            if line.startswith("    init?") or line.startswith("    public init?"):
                current_enum = None
                continue
            if match := CASE.match(line):
                payload = match.group(2)
                enums[current_enum].append((match.group(1), payload[len("TDNative"):] if payload else None))
    return structs, enums


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--schema", type=Path, default=DEFAULT_SCHEMA)
    args = parser.parse_args()

    structs, enums = parse(args.schema.read_text())
    existing: set[str] = set()
    for source_root in SOURCE_ROOTS:
        for source in source_root.rglob("*.swift"):
            if source == OUTPUT:
                continue
            existing.update(EXISTING.findall(source.read_text()))

    selected: set[str] = set()
    pending = list(ROOTS)
    while pending:
        name = pending.pop()
        if name in selected or name in existing:
            continue
        if name in structs:
            selected.add(name)
            for _, kind in structs[name]:
                pending.extend(NATIVE.findall(kind))
        elif name in enums:
            # Enums without payloads already receive synthesized Hashable in TDLibKit.
            if all(payload is None for _, payload in enums[name]):
                continue
            selected.add(name)
            pending.extend(payload for _, payload in enums[name] if payload)
        else:
            raise SystemExit(f"error: TDNative{name} is not a schema struct or enum")

    lines = [
        "// Generated by script/generate_tdlib_value_equality.py. Do not edit.\n",
        "// Content equality for native views, matching TDLibKit 1 value semantics.\n\n",
        "import Foundation\n",
        "import TDLibKit\n",
    ]
    for name in sorted(selected):
        lines.append(f"\nextension TDNative{name}: @retroactive Hashable {{\n")
        if name in structs:
            fields = structs[name]
            lines.append("    public static func == (lhs: Self, rhs: Self) -> Bool {\n")
            for field, _ in fields:
                lines.append(f"        guard lhs.{field} == rhs.{field} else {{ return false }}\n")
            lines.append("        return true\n    }\n\n")
            if fields:
                lines.append("    public func hash(into hasher: inout Hasher) {\n")
                for field, _ in fields:
                    lines.append(f"        hasher.combine({reference(field)})\n")
            else:
                lines.append("    public func hash(into hasher: inout Hasher) {\n")
                lines.append("        hasher.combine(Self.typeID)\n")
            lines.append("    }\n")
        else:
            cases = enums[name]
            lines.append("    public static func == (lhs: Self, rhs: Self) -> Bool {\n")
            lines.append("        switch (lhs, rhs) {\n")
            for case, payload in cases:
                if payload:
                    lines.append(f"        case (.{case}(let lhs), .{case}(let rhs)):\n            lhs == rhs\n")
                else:
                    lines.append(f"        case (.{case}, .{case}):\n            true\n")
            if len(cases) > 1:
                lines.append("        default:\n            false\n")
            lines.append("        }\n    }\n\n")
            lines.append("    public func hash(into hasher: inout Hasher) {\n")
            lines.append("        switch self {\n")
            for index, (case, payload) in enumerate(cases):
                if payload:
                    lines.append(f"        case .{case}(let value):\n")
                    lines.append(f"            hasher.combine({index})\n            hasher.combine(value)\n")
                else:
                    lines.append(f"        case .{case}:\n            hasher.combine({index})\n")
            lines.append("        }\n    }\n")
        lines.append("}\n")
    output = "".join(lines)
    if not OUTPUT.exists() or OUTPUT.read_text() != output:
        OUTPUT.write_text(output)
        print(f"Generated {OUTPUT.relative_to(ROOT)} ({len(selected)} conformances)")
    else:
        print(f"Kept {OUTPUT.relative_to(ROOT)} unchanged ({len(selected)} conformances)")


if __name__ == "__main__":
    main()
