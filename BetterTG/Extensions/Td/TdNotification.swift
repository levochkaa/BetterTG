// TdNotification.swift

import SwiftUI
import TDLibKit
    
struct TdNotification<T> {
    // MARK: Lifecycle

    init(_ name: Foundation.Notification.Name) {
        self.name = name
    }

    // MARK: Internal

    let name: Foundation.Notification.Name
}
