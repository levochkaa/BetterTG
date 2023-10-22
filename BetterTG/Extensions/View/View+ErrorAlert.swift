// View+ErrorAlert.swift

import SwiftUI

extension View {
    @ViewBuilder func errorAlert(show: Binding<Bool>, text: String) -> some View {
        alert("Error", isPresented: show) { Text(text) }
    }
}
