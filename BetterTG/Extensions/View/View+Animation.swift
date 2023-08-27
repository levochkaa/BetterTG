// View+Animation.swift

extension View {
    @ViewBuilder func animation<T: Equatable>(value: T) -> some View {
        animation(.default, value: value)
    }
}
