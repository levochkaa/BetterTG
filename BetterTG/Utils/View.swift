// View.swift

func captionText(from dateString: String) -> some View {
    Text(dateString)
        .font(.caption)
        .foregroundStyle(.white).opacity(0.5)
}
