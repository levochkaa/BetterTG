// WithBindable.swift

import SwiftUI
import Observation

struct WithBindable<M: AnyObject & Observable>: View {
    @Environment(M.self) var model
    
    let content: (Bindable<M>) -> AnyView
    init(@ViewBuilder _ content: @escaping (Bindable<M>) -> some View) {
        self.content = { model in AnyView(content(model)) }
    }
    
    var body: some View {
        content(Bindable(model))
    }
}
