// NotificationCenter.swift

import Combine

let nc = NotificationCenter()

extension NotificationCenter {
    func publisher(
        _ cancellables: inout Set<AnyCancellable>,
        for name: Notification.Name,
        _ perform: @escaping (Publisher.Output) -> Void
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
        _ cancellables: inout Set<AnyCancellable>,
        _ names: [Notification.Name],
        _ perform: @escaping (Publisher.Output) -> Void
    ) {
        Publishers.MergeMany(names.map { publisher(for: $0) })
            .receive(on: RunLoop.main)
            .sink { notification in
                perform(notification)
            }
            .store(in: &cancellables)
    }
}
