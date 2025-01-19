// Array+GetSize.swift

import TDLibKit

/// For info on cases, see https://core.telegram.org/api/files#image-thumbnail-types
public enum PhotoSizeType: Int {
    /// 100x100
    case sBox
    /// 100x100
    case mBox
    /// 320x320
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
    
    case iString
    case jOutline
    
    var td: String {
        switch self {
            case .sBox: return "s"
            case .mBox: return "m"
            case .xBox: return "x"
            case .yBox: return "y"
            case .wBox: return "w"
            case .aCrop: return "a"
            case .bCrop: return "b"
            case .cCrop: return "c"
            case .dCrop: return "d"
            case .iString: return "i"
            case .jOutline: return "j"
        }
    }
}

public extension Array where Element == PhotoSize {
    
    /// Searches for a photo with a supplied size type. If not found,
    /// searches for the nearest smaller image.
    /// - Parameter type: Size type of the photo. See https://core.telegram.org/api/files#image-thumbnail-types
    /// - Returns: Found photo, or nil if it can not be found
    func getSize(_ type: PhotoSizeType?) -> PhotoSize? {
        guard let type else { return first }
        let filtered = self.filter { $0.type == type.td }
        
        if filtered.isEmpty {
            if type.rawValue == 0 {
                return nil
            } else {
                return getSize(PhotoSizeType(rawValue: type.rawValue - 1))
            }
        } else {
            return filtered.first
        }
    }
    
    func first(_ type: PhotoSizeType) -> PhotoSize? {
        first { $0.type == type.td }
    }
}
