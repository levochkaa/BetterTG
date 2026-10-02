// ProfileHeaderLayoutProbe.swift

#if DEBUG
import UIKit

/// Read-only geometry of the actual opened profile. Never replaces user content.
@MainActor enum ProfileHeaderLayoutProbe {
    private static var lastResult: String?

    static func recordIfRequested(header: UIView, avatar: UIView, labels: [UILabel]) {
        guard ProcessInfo.processInfo.arguments.contains("-ui-probe-profile-header-layout"),
              header.window != nil, header.bounds.width > 40 else { return }
        header.layoutIfNeeded()
        let availableWidth = header.bounds.width - 40
        let visibleLabels = labels.filter { !$0.isHidden }
        let labelsFillWidth = !visibleLabels.isEmpty && visibleLabels.allSatisfy { label in
            let frame = label.convert(label.bounds, to: header)
            return abs(frame.width - availableWidth) < 0.5
                && abs(frame.midX - header.bounds.midX) < 0.5
        }
        let avatarUnchanged = abs(avatar.bounds.width - 96) < 0.5 && abs(avatar.bounds.height - 96) < 0.5
        let result = "Profile header layout probe \(labelsFillWidth && avatarUnchanged ? "passed" : "failed"): "
            + "actual-profile=true; visible-labels-fill-width=\(labelsFillWidth); avatar-96pt=\(avatarUnchanged); "
            + "header-width=\(header.bounds.width); title-width=\(labels.first?.bounds.width ?? 0); "
            + "visible-label-count=\(visibleLabels.count); category=\(header.traitCollection.preferredContentSizeCategory.rawValue); "
            + "text/metadata-logged=false; synthetic-content/server-writes=0; "
            + "other-widths/Dynamic-Type/RTL=unverified"
        guard result != lastResult else { return }
        lastResult = result
        log(result)
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? Data(result.utf8).write(
                to: documents.appendingPathComponent("profile-header-layout-probe.txt"), options: .atomic,
            )
        }
    }
}
#endif
