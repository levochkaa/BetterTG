// NotificationCenter.swift

import Combine

let nc = NotificationCenter()
var cancellables = Set<AnyCancellable>()

// TODO: fix cancellables

extension NotificationCenter {
    func publisher(
        for name: Notification.Name,
        @_implicitSelfCapture perform: @escaping (Publisher.Output) -> Void
    ) {
        publisher(for: name)
            .receive(on: RunLoop.main)
            .sink { notification in
                perform(notification)
            }
            .store(in: &cancellables)
    }
    
    func post(name: Notification.Name) {
        post(name: name, object: nil)
    }
    
    func publisher(for name: Notification.Name) -> NotificationCenter.Publisher {
        publisher(for: name, object: nil)
    }
    
    func mergeMany(_ names: [Notification.Name]) -> Publishers.MergeMany<NotificationCenter.Publisher> {
        Publishers.MergeMany(names.map { publisher(for: $0) })
    }
    
    func mergeMany(
        _ names: [Notification.Name],
        @_implicitSelfCapture perform: @escaping (Publisher.Output) -> Void
    ) {
        Publishers.MergeMany(names.map { publisher(for: $0) })
            .receive(on: RunLoop.main)
            .sink { notification in
                perform(notification)
            }
            .store(in: &cancellables)
    }
}
