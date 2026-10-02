// TDLibClientReadiness.swift

import Combine

/// Updated on TDLib's main-queue accepted-update path. Readiness belongs to one
/// client epoch, including replacements that do not change the selected account.
final class TDLibClientReadiness {
    private let subject = CurrentValueSubject<TdUpdateSource?, Never>(nil)
    private var activeSource: TdUpdateSource?

    var publisher: AnyPublisher<TdUpdateSource?, Never> {
        subject.removeDuplicates().eraseToAnyPublisher()
    }

    func activate(_ source: TdUpdateSource) {
        activeSource = source
        subject.send(nil)
    }

    func update(ready: Bool, source: TdUpdateSource) {
        guard source == activeSource else { return }
        subject.send(ready ? source : nil)
    }
}
