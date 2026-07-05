from __future__ import annotations

import subprocess
import os
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parent
OUTPUT_PATH = ROOT_DIR / "BetterTG/Extensions/Td/Td+Generated.swift"
UPDATE_MODEL_PATH = Path("Sources/TDLibKit/Generated/Models/Update.swift")
PROJECT_PATH = ROOT_DIR / "BetterTG.xcodeproj"
SCHEME = "BetterTG"
DERIVED_DATA_PATH = ROOT_DIR / ".build/xcode"

CORE = """// Td+Generated.swift

// This file is generated from td.py
// Any modifications will be overwritten

import SwiftUI
import TDLibKit
"""

UPDATE_FUNC = """
func update(_ update: Update) {
    switch update {
        case .updateAuthorizationState(let updateAuthorizationState):
            TDLib.shared.UpdateAuthorizationState(updateAuthorizationState.authorizationState)
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


def update_model_source() -> Path:
    candidates = [
        DERIVED_DATA_PATH / "SourcePackages/checkouts/TDLibKit" / UPDATE_MODEL_PATH,
        DERIVED_DATA_PATH / "SourcePackages/checkouts/tdlibkit" / UPDATE_MODEL_PATH,
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

    for line in update_source.splitlines():
        stripped = line.strip()
        if not stripped.startswith("case ") or "(" not in stripped or "(let" in stripped:
            continue

        declaration = stripped.removeprefix("case ")
        name, type_tail = declaration.split("(", maxsplit=1)
        type_name = type_tail.split(")", maxsplit=1)[0]
        cases.append((name, type_name))

    if not cases:
        raise ValueError("No Update enum cases found in TDLibKit Update.swift")

    return cases


def generate(update_source: str) -> None:
    notifications: list[str] = []
    notification_names: list[str] = []
    update_cases: list[tuple[str, str]] = []

    for name, type_name in parse_update_cases(update_source):
        notifications.append(
            f"    static var {name}: TdNotification<{type_name}> {{ .init(.{name}) }}\n"
        )
        notification_names.append(f"    static let {name} = Self(\"{name}\")\n")

        if name == "updateAuthorizationState":
            continue

        update_cases.append(
            (
                f"        case .{name}(let {name}):\n",
                f"            nc.post(name: .{name}, object: {name})\n",
            )
        )

    with OUTPUT_PATH.open("w") as file:
        file.write(CORE)
        file.write(UPDATE_FUNC)
        for update_case in update_cases:
            file.write(update_case[0])
            file.write(update_case[1])
        file.write("    }\n")
        file.write("}\n\n")

        file.write("extension TdNotification {\n")
        for notification in notifications:
            file.write(notification)
        file.write("}\n\n")

        file.write("extension Foundation.Notification.Name {\n")
        for notification_name in notification_names:
            file.write(notification_name)
        file.write("}\n")


def main() -> None:
    if os.environ.get("BETTERTG_TD_SKIP_RESOLVE") == "1":
        ensure_xcode_project()
    else:
        resolve_xcode_packages()
    source_path = update_model_source()
    generate(source_path.read_text())
    print(f"Generated {OUTPUT_PATH.relative_to(ROOT_DIR)} from {source_path.relative_to(ROOT_DIR)}")


if __name__ == "__main__":
    main()
