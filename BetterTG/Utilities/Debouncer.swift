// Debouncer.swift

class Debouncer {
    private var timer: Timer?
    
    func call(delay: TimeInterval, _ action: @escaping () -> Void) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            action()
        }
    }
}
