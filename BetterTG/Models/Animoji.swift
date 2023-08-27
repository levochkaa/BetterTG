// Animoji.swift

struct Animoji: Identifiable {
    let id = UUID()
    var type: AnimojiType
    var realEmoji: String
    
    enum AnimojiType {
        case webp(URL), webm(URL), tgs(URL)
    }
}

extension Animoji: Equatable {
    static func == (lhs: Animoji, rhs: Animoji) -> Bool {
        lhs.id == rhs.id
    }
}
