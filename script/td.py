from __future__ import annotations

import argparse
import subprocess
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parent.parent
OUTPUT_PATH = ROOT_DIR / "BetterTG/Extensions/Td/Td+Generated.swift"
UPDATE_MODEL_PATH = Path("Sources/TDLibKitNative/Generated/SchemaViews.swift")
LOCAL_TDLIBKIT_ROOT = ROOT_DIR.parent.parent
PROJECT_PATH = ROOT_DIR / "BetterTG.xcodeproj"
SCHEME = "BetterTG"
DERIVED_DATA_PATH = ROOT_DIR / ".build/xcode"

CORE = """// Td+Generated.swift

// This file is generated from script/td.py
// Any modifications will be overwritten

import Foundation
import TDLibKit
"""

UPDATE_FUNC = """
func update(
    _ update: TDNativeUpdate,
    source: TdUpdateSource? = nil,
    notificationCenter: NotificationCenter = nc
) {
    switch update {
"""


def ensure_xcode_project() -> None:
    if (PROJECT_PATH / "project.pbxproj").is_file():
        return

    subprocess.run(
        [str(ROOT_DIR / "script/generate_xcodeproj.sh")],
        check=True,
    )


def resolve_xcode_packages() -> None:
    ensure_xcode_project()
    subprocess.run(
        [
            "xcodebuild",
            "-resolvePackageDependencies",
            "-project",
            str(PROJECT_PATH),
            "-scheme",
            SCHEME,
            "-derivedDataPath",
            str(DERIVED_DATA_PATH),
            "-packageAuthorizationProvider",
            "netrc",
            "-scmProvider",
            "system",
            "-skipPackagePluginValidation",
            "-skipMacroValidation",
        ],
        check=True,
    )


def update_model_source(cloned_source_packages_path: Path) -> Path:
    candidates = [
        LOCAL_TDLIBKIT_ROOT / UPDATE_MODEL_PATH,
        cloned_source_packages_path / "checkouts/TDLibKit" / UPDATE_MODEL_PATH,
        cloned_source_packages_path / "checkouts/tdlibkit" / UPDATE_MODEL_PATH,
    ]

    for candidate in candidates:
        if candidate.is_file():
            return candidate

    searched = "\n".join(f"- {candidate}" for candidate in candidates)
    raise FileNotFoundError(
        "Unable to find TDLibKit Update.swift after resolving Xcode packages. "
        f"Searched:\n{searched}"
    )


def parse_update_cases(update_source: str) -> list[tuple[str, str]]:
    cases: list[tuple[str, str]] = []

    declaration = "public enum TDNativeUpdate:"
    start = update_source.find(declaration)
    if start == -1:
        raise ValueError("TDNativeUpdate declaration not found")
    body_start = update_source.find("{", start)
    initializer = update_source.find("\n    init?", body_start)
    if body_start == -1 or initializer == -1:
        raise ValueError("Unable to isolate TDNativeUpdate cases")

    for line in update_source[body_start + 1 : initializer].splitlines():
        stripped = line.strip()
        if not stripped.startswith("case ") or "(" not in stripped or "(let" in stripped:
            continue

        declaration = stripped.removeprefix("case ")
        name, type_tail = declaration.split("(", maxsplit=1)
        type_name = type_tail.split(")", maxsplit=1)[0]
        cases.append((name, type_name))

    if not cases:
        raise ValueError("No TDNativeUpdate enum cases found in TDLibKit schema")

    return cases


def generate(update_source: str) -> bool:
    notifications: list[str] = []
    notification_names: list[str] = []
    update_cases: list[tuple[str, str]] = []

    for name, type_name in parse_update_cases(update_source):
        notifications.append(
            f"    static var {name}: TdNotification<{type_name}> {{ .init(.{name}) }}\n"
        )
        notification_names.append(f"    static let {name} = Self(\"{name}\")\n")

        update_cases.append(
            (
                f"        case .{name}(let {name}):\n",
                f"            notificationCenter.postTdUpdate(name: .{name}, object: {name}, source: source)\n",
            )
        )

    output_parts = [CORE, UPDATE_FUNC]
    for update_case in update_cases:
        output_parts.extend(update_case)
    output_parts.extend(["    }\n", "}\n\n", "extension TdNotification {\n"])
    output_parts.extend(notifications)
    output_parts.extend(["}\n\n", "extension Foundation.Notification.Name {\n"])
    output_parts.extend(notification_names)
    output_parts.append("}\n")
    output = "".join(output_parts)

    if OUTPUT_PATH.is_file() and OUTPUT_PATH.read_text() == output:
        return False

    OUTPUT_PATH.write_text(output)
    return True


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate BetterTG TDLib update bindings")
    parser.add_argument(
        "--skip-resolve",
        action="store_true",
        help="reuse the existing TDLibKit checkout instead of resolving packages",
    )
    parser.add_argument(
        "--cloned-source-packages-dir-path",
        type=Path,
        default=DERIVED_DATA_PATH / "SourcePackages",
        help="Swift package cache containing the TDLibKit checkout",
    )
    arguments = parser.parse_args()

    if arguments.skip_resolve:
        ensure_xcode_project()
    else:
        resolve_xcode_packages()
    source_path = update_model_source(arguments.cloned_source_packages_dir_path)
    changed = generate(source_path.read_text())
    status = "Generated" if changed else "Kept unchanged"
    try:
        source_description = source_path.relative_to(ROOT_DIR)
    except ValueError:
        source_description = source_path
    print(f"{status} {OUTPUT_PATH.relative_to(ROOT_DIR)} from {source_description}")


if __name__ == "__main__":
    main()
