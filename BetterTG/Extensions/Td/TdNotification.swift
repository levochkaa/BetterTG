// TdNotification.swift

import Foundation
import TDLibKitDynamic
    
struct TdNotification<T> {
    // MARK: Internal

    let name: Foundation.Notification.Name

    init(_ name: Foundation.Notification.Name) {
        self.name = name
    }
}
