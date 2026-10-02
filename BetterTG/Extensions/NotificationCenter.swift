// NotificationCenter.swift

import Combine
import Foundation

let nc = NotificationCenter()
let updatesQueue = DispatchQueue(label: "updatesQueue", qos: .userInteractive)

extension NotificationCenter {
    func scopedPublisher<T>(
        _ cancellables: inout Set<AnyCancellable>,
        for tdNotification: TdNotification<T>,
        _ perform: @escaping (TdScopedUpdate<T>) -> Void,
    ) {
        publisher(for: tdNotification.name)
            .compactMap { TdScopedUpdate<T>(notification: $0) }
            .receive(on: DispatchQueue.main)
            .sink { perform($0) }
            .store(in: &cancellables)
    }

    func publisher<T>(
        _ cancellables: inout Set<AnyCancellable>,
        for tdNotification: TdNotification<T>,
        _ perform: @escaping (T) -> Void,
    ) {
        publisher(for: tdNotification.name)
            .receive(on: DispatchQueue.main)
            .compactMap { $0.object as? T }
            .sink { perform($0) }
            .store(in: &cancellables)
    }

    func publisher(
        _ cancellables: inout Set<AnyCancellable>,
        for name: Notification.Name,
        _ perform: @escaping (Publisher.Output) -> Void,
    ) {
        publisher(for: name)
            .receive(on: DispatchQueue.main)
            .sink { perform($0) }
            .store(in: &cancellables)
    }

    func publisher<T>(for tdNotification: TdNotification<T>) -> AnyPublisher<T, Never> {
        publisher(for: tdNotification.name, object: nil)
            .receive(on: updatesQueue)
            .compactMap { $0.object as? T }
            .eraseToAnyPublisher()
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
        _ perform: @escaping (Publisher.Output) -> Void,
    ) {
        mergeMany(names)
            .receive(on: DispatchQueue.main)
            .sink { perform($0) }
            .store(in: &cancellables)
    }
}
