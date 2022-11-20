// NotificationCenter+Extension.swift

import Foundation
import Combine

extension NotificationCenter {
    public func publisher(
        for name: Notification.Name,
        in set: inout Set<AnyCancellable>,
        perform: @escaping ((Publisher.Output) -> Void)
    ) {
        self.publisher(for: name)
            .receive(on: RunLoop.main)
            .sink { notification in
                perform(notification)
            }
            .store(in: &set)
    }
    
    public func publisher(for name: Notification.Name) -> NotificationCenter.Publisher {
        return self.publisher(for: name, object: nil)
    }
    
    public func mergeMany(
        _ publishers: [Publisher],
        in set: inout Set<AnyCancellable>,
        perform: @escaping ((Publisher.Output) -> Void)
    ) {
        Publishers.MergeMany(publishers)
            .receive(on: RunLoop.main)
            .sink { notification in
                perform(notification)
            }
            .store(in: &set)
    }
}
