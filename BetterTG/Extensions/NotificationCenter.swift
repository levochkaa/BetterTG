// NotificationCenter.swift

import Foundation
import Combine

let nc: NotificationCenter = .default
var cancellables = Set<AnyCancellable>()

extension NotificationCenter {
    
    static var cancellables = Set<AnyCancellable>()
    
    func publisher(
        for name: Notification.Name,
        @_implicitSelfCapture perform: @escaping (Publisher.Output) -> Void
    ) {
        self.publisher(for: name)
            .receive(on: RunLoop.main)
            .sink { notification in
                perform(notification)
            }
            .store(in: &NotificationCenter.cancellables)
    }
    
    func post(name: Notification.Name) {
        self.post(name: name, object: nil)
    }
    
    func publisher(for name: Notification.Name) -> NotificationCenter.Publisher {
        self.publisher(for: name, object: nil)
    }
    
    func mergeMany(_ names: [Notification.Name]) -> Publishers.MergeMany<NotificationCenter.Publisher> {
        let publishers = names.map { self.publisher(for: $0) }
        return Publishers.MergeMany(publishers)
    }
    
    func mergeMany(
        _ names: [Notification.Name],
        @_implicitSelfCapture perform: @escaping (Publisher.Output) -> Void
    ) {
        let publishers = names.map { self.publisher(for: $0) }
        Publishers.MergeMany(publishers)
            .receive(on: RunLoop.main)
            .sink { notification in
                perform(notification)
            }
            .store(in: &NotificationCenter.cancellables)
    }
    
    func mergeMany(
        _ publishers: [Publisher],
        @_implicitSelfCapture perform: @escaping (Publisher.Output) -> Void
    ) {
        Publishers.MergeMany(publishers)
            .receive(on: RunLoop.main)
            .sink { notification in
                perform(notification)
            }
            .store(in: &NotificationCenter.cancellables)
    }
}
