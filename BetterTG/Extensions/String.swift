// String.swift

extension String {
    var attributedString: AttributedString {
        let mutable = NSMutableAttributedString(string: self)
        mutable.addAttributes([
            .font: UIFont.systemFont(ofSize: 17),
            .foregroundColor: UIColor.white
        ], range: NSRange(location: 0, length: count))
        return AttributedString(mutable)
    }
}
