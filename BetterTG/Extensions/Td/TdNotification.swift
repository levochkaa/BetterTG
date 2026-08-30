// TdNotification.swift

import Foundation
import TDLibKitDynamic
    
struct TdNotification<T> {
    // MARK: Lifecycle

    init(_ name: Foundation.Notification.Name) {
        self.name = name
    }

    // MARK: Internal

    let name: Foundation.Notification.Name
}
