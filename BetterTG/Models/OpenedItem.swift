// OpenedItem.swift

struct OpenedItem: Identifiable {
    var id: String
    var image: Image
    var url: URL
}

extension OpenedItem {
    init(from selectedImage: SelectedImage) {
        self.id = selectedImage.id.uuidString
        self.image = selectedImage.image
        self.url = selectedImage.url
    }
}
