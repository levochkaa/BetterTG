// NotificationCenter+Publishers.swift

import Foundation
import Combine

let nc: NotificationCenter = .default

extension NotificationCenter {
    
    static var cancellable = Set<AnyCancellable>()
    
    func publisher(
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
    
    func publisher(for name: Notification.Name) -> NotificationCenter.Publisher {
        self.publisher(for: name, object: nil)
    }
    
    func mergeMany(
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
