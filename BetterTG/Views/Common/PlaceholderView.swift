// PlaceholderView.swift

struct PlaceholderView: View {
    
    @State var userId: Int64
    @State var title: String
    @State var fontSize: CGFloat = 40
    
    var body: some View {
        Text(String(title.prefix(1).capitalized))
            .font(.system(size: fontSize, design: .rounded))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(fromUserId: userId).gradient)
    }
}
