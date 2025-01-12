// TdNotification.swift

import SwiftUI
import TDLibKit
    
struct TdNotification<T> {
    let name: Foundation.Notification.Name
    
    init(_ name: Foundation.Notification.Name) {
        self.name = name
    }
}
