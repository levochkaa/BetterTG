// Array+GetSize.swift

import TDLibKit

// MARK: - PhotoSizeType

/// For info on cases, see https://core.telegram.org/api/files#image-thumbnail-types
public enum PhotoSizeType: Int {
    /// 100x100
    case sBox
    /// 320x320
    case mBox
    /// 800x800
    case xBox
    /// 1280x1280
    case yBox
    /// 2560x2560
    case wBox
    /// 160x160
    case aCrop
    /// 320x320
    case bCrop
    /// 640x640
    case cCrop
    /// 1280x1280
    case dCrop
    
    /// Type for stickers where dimensions are exact.
    case iString
    /// Outline for animated stickers.
    case jOutline
    
    // MARK: Internal

    var td: String {
        switch self {
        case .sBox: "s"
        case .mBox: "m"
        case .xBox: "x"
        case .yBox: "y"
        case .wBox: "w"
        case .aCrop: "a"
        case .bCrop: "b"
        case .cCrop: "c"
        case .dCrop: "d"
        case .iString: "i"
        case .jOutline: "j"
        }
    }

    var fallbackOrder: [Self] {
        switch self {
        case .sBox:
            [.sBox]
        case .mBox:
            [.mBox, .sBox]
        case .xBox:
            [.xBox, .mBox, .sBox]
        case .yBox:
            [.yBox, .xBox, .mBox, .sBox]
        case .wBox:
            [.wBox, .yBox, .xBox, .mBox, .sBox]
        case .aCrop:
            [.aCrop]
        case .bCrop:
            [.bCrop, .aCrop]
        case .cCrop:
            [.cCrop, .bCrop, .aCrop]
        case .dCrop:
            [.dCrop, .cCrop, .bCrop, .aCrop]
        case .iString:
            [.iString]
        case .jOutline:
            [.jOutline]
        }
    }
}

public extension [PhotoSize] {
    /// Searches for a photo with a supplied size type. If not found,
    /// searches for the nearest smaller image.
    /// - Parameter type: Size type of the photo. See https://core.telegram.org/api/files#image-thumbnail-types
    /// - Returns: Found photo, or nil if it can not be found
    func getSize(_ type: PhotoSizeType?) -> PhotoSize? {
        guard let type else { return first }

        for candidate in type.fallbackOrder {
            if let size = first(candidate) {
                return size
            }
        }

        return nil
    }
    
    func first(_ type: PhotoSizeType) -> PhotoSize? {
        first { $0.type == type.td }
    }
}
