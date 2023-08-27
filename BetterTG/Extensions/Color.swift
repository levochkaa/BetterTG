// Color.swift

extension Color {
    static let gray6 = Color(uiColor: .systemGray6)
    static let gray5 = Color(uiColor: .systemGray5)
    static let gray4 = Color(uiColor: .systemGray4)
    static let gray3 = Color(uiColor: .systemGray3)
    static let gray2 = Color(uiColor: .systemGray2)
    
    init(red: Int, green: Int, blue: Int, opacity: Double) {
        self.init(.sRGB, red: Double(red / 255), green: Double(green / 255), blue: Double(blue / 255), opacity: opacity)
    }
    
    init(userId: Int64) {
        let colors: [Color] = [.red, .green, .yellow, .blue, .purple, .pink, .blue, .orange]
        let id = Int(String(userId).replacing("-100", with: "")) ?? 0
        self.init(uiColor: UIColor(colors[[0, 7, 4, 1, 6, 3, 5][id % 7]]))
    }
}
