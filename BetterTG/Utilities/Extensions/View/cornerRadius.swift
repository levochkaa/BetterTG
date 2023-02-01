// cornerRadius.swift

import SwiftUI

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        Path(
            UIBezierPath(
                roundedRect: rect,
                byRoundingCorners: corners,
                cornerRadii: CGSize(
                    width: radius,
                    height: radius
                )
            )
            .cgPath
        )
    }
}

extension View {
    func cornerRadius(_ corners: UIRectCorner, radius: CGFloat = 15) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}
