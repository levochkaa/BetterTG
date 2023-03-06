// MessageAttributes.swift

import ActivityKit
import WidgetKit
import SwiftUI

struct MessageAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var lastMessageText: String
    }
    
    var name: String
    var avatarId: String
}
