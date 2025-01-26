file_path = "BetterTG/Extensions/Td/Td+Generated.swift"
update_path = "td_update.txt"

core = """// Td+Generated.swift

// This file is generated from td.py
// Any modifications will be overwritten

import SwiftUI
import TDLibKit
"""

update_func = """
func update(_ update: Update) {
    switch update {
        case .updateAuthorizationState(let updateAuthorizationState):
            TDLib.shared.UpdateAuthorizationState(updateAuthorizationState.authorizationState)
"""


def main(update: str):
    (notifications, notification_names, update_cases) = ([], [], [])
    for line in update.split("\n")[1:-1]:
        if "case " in line and "(" in line and "(let" not in line:
            after_case = line.split("case ")[1]
            name_split = after_case.split("(")
            name = name_split[0]
            type = name_split[1].split(")")[0]
            notifications.append(
                f"    static var {name}: TdNotification<{
                    type}> {{ .init(.{name}) }}\n"
            )
            notification_names.append(
                f"    static let {name} = Self(\"{name}\")\n")
            if name == "updateAuthorizationState":
                continue
            update_cases.append(
                (
                    f"        case .{name}(let {name}):\n",
                    f"            nc.post(name: .{name}, object: {name})\n"
                )
            )

    file = open(file_path, "w")

    file.write(core)

    for line in update_func:
        file.write(line)
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

    file.close()


if __name__ == "__main__":
    # probably, fetching from currently used tdlib is better, but this solution is faster to implement
    with open(update_path, "r") as file:
        main(file.read())
