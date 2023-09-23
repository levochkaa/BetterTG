// View.swift

func captionText(from dateString: String) -> some View {
    Text(dateString)
        .font(.caption)
        .foregroundColor(.white).opacity(0.5)
}

func messageOverlayDate(_ dateString: String) -> some View {
    captionText(from: dateString)
        .padding(3)
        .background(.gray6)
        .cornerRadius(15)
}
