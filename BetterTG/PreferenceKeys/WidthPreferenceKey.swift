// WidthPreferenceKey.swift

struct WidthPreferenceKey: PreferenceKey {
    typealias Value = Int
    static var defaultValue: Value = .zero
    static func reduce(value: inout Value, nextValue: () -> Value) {}
}
