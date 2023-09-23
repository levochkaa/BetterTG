// ForwardedFromView.swift

struct ForwardedFromView: View {
    let name: String
    
    var body: some View {
        HStack(spacing: 0) {
            Text("FF: ")
                .foregroundColor(.white.opacity(0.5))
            
            Text(name)
                .bold()
                .lineLimit(1)
        }
        .padding(5)
    }
}
