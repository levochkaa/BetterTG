// TdNotification.swift

import Foundation
import TDLibKit
    
struct TdNotification<T> {
    // MARK: Internal

    let name: Foundation.Notification.Name

    init(_ name: Foundation.Notification.Name) {
        self.name = name
    }
}
