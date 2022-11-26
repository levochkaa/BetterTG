// NotificationCenter+Publishers.swift

import Foundation
import Combine

extension NotificationCenter {
    
    static var cancellable = Set<AnyCancellable>()
    
    public func publisher(
        for name: Notification.Name,
        perform: @escaping (Publisher.Output) -> Void
    ) {
        self.publisher(for: name)
            .receive(on: RunLoop.main)
            .sink { notification in
                perform(notification)
            }
            .store(in: &NotificationCenter.cancellable)
    }
    
    public func publisher(for name: Notification.Name) -> NotificationCenter.Publisher {
        return self.publisher(for: name, object: nil)
    }
    
    public func mergeMany(
        _ publishers: [Publisher],
        perform: @escaping (Publisher.Output) -> Void
    ) {
        Publishers.MergeMany(publishers)
            .receive(on: RunLoop.main)
            .sink { notification in
                perform(notification)
            }
            .store(in: &NotificationCenter.cancellable)
    }
}
