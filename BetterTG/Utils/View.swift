// View.swift

func captionText(from dateString: String) -> some View {
    Text(dateString)
        .font(.caption)
        .foregroundColor(.white).opacity(0.5)
}
