// NotificationCenter.swift

import SwiftUI
import Combine

let nc = NotificationCenter()
let updatesQueue = DispatchQueue(label: "updatesQueue", qos: .userInteractive)

extension NotificationCenter {
    func publisher<T>(
        _ cancellables: inout Set<AnyCancellable>,
        for tdNotification: TdNotification<T>,
        _ perform: @escaping (T) -> Void
    ) {
        self
            .publisher(for: tdNotification.name)
            .receive(on: updatesQueue)
            .compactMap { $0.object as? T }
            .sink { perform($0) }
            .store(in: &cancellables)
    }
    
    func publisher(
        _ cancellables: inout Set<AnyCancellable>,
        for name: Notification.Name,
        _ perform: @escaping (Publisher.Output) -> Void
    ) {
        self
            .publisher(for: name)
            .receive(on: updatesQueue)
            .sink { perform($0) }
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
        mergeMany(names)
            .receive(on: updatesQueue)
            .sink { perform($0) }
            .store(in: &cancellables)
    }
}
