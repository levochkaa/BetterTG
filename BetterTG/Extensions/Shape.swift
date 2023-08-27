// Shape.swift

extension Shape {
    @_disfavoredOverload @inlinable func fill(_ color: Color) -> some View {
        fill(color)
    }
}
