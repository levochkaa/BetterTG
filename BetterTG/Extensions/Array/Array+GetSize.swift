// Array+GetSize.swift

import TDLibKit

public enum PhotoSizeType: Int {
    // For info on cases, see https://core.telegram.org/api/files#image-thumbnail-types
    case iString, sBox, mBox, xBox, yBox, wBox, aCrop, bCrop, cCrop, dCrop, jOutline
    
    var td: String {
        switch self {
            case .iString: return "i"
            case .sBox: return "s"
            case .mBox: return "m"
            case .xBox: return "x"
            case .yBox: return "y"
            case .wBox: return "w"
            case .aCrop: return "a"
            case .bCrop: return "b"
            case .cCrop: return "c"
            case .dCrop: return "d"
            case .jOutline: return "j"
        }
    }
}

public extension Array where Element == PhotoSize {
    
    /// Searches for a photo with a supplied size type. If not found,
    /// searches for the nearest smaller image.
    /// - Parameter type: Size type of the photo. See https://core.telegram.org/api/files#image-thumbnail-types
    /// - Returns: Found photo, or nil if it can not be found
    func getSize(_ type: PhotoSizeType) -> PhotoSize? {
        let filtered = self.filter { $0.type == type.td }
        
        if filtered.isEmpty {
            if type.rawValue == 0 {
                return nil
            } else {
                return getSize(PhotoSizeType(rawValue: type.rawValue - 1)!)
            }
        } else {
            return filtered.first
        }
    }
}
