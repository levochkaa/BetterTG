// ItemView.swift

struct ItemView: View {
    
    @State var item: OpenedItem
    
    @State private var showSaveConfirmationDialog = false
    
    @Environment(RootViewModel.self) var viewModel
    
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            
            ZoomableContainer {
                item.image
                    .resizable()
                    .scaledToFit()
            }
            .matchedGeometryEffect(id: item.id, in: viewModel.namespace)
        }
        .ignoresSafeArea()
        .overlay(alignment: .topTrailing) {
            makeButton(with: "xmark.circle") {
                withAnimation {
                    viewModel.openedItem = nil
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            makeButton(with: "square.and.arrow.up") {
                showSaveConfirmationDialog = true
            }
        }
        .confirmationDialog("", isPresented: $showSaveConfirmationDialog) {
            Button("Save") {
                guard let uiImage = UIImage(contentsOfFile: item.url.path()) else { return }
                UIImageWriteToSavedPhotosAlbum(uiImage, nil, nil, nil)
            }
        }
    }
    
    func makeButton(with systemName: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title)
                .foregroundStyle(.white)
        }
        .padding()
    }
}
