// SendDraftFileReference.swift

import Foundation

/// Persist filenames, not sandbox URLs. Legacy relocation accepts only a change
/// of the application-container UUID, never an arbitrary same-named file.
enum SendDraftFileReference {
    enum Kind {
        case voice(encoded: Bool)
        case video
        case videoThumbnail

        var storeName: String {
            switch self {
            case .voice: "VoiceNoteDrafts"
            case .video,
                 .videoThumbnail: "VideoNoteDrafts"
            }
        }

        func owns(_ name: String, id: UUID) -> Bool {
            let prefix = id.uuidString
            switch self {
            case .voice(encoded: false):
                return name == "\(prefix).wav"
            case .voice(encoded: true):
                if name == "\(prefix).ogg" { return true }
                guard name.hasPrefix("\(prefix)-"), name.hasSuffix(".ogg") else { return false }
                let token = String(name.dropFirst(prefix.count + 1).dropLast(4))
                return UUID(uuidString: token)?.uuidString == token
            case .video:
                return name == "\(prefix).mp4"
            case .videoThumbnail:
                return name == "\(prefix)-thumbnail.jpg"
            }
        }
    }

    static func resolve(
        _ reference: URL,
        id: UUID,
        kind: Kind,
        directory: URL,
        allowMissing: Bool = false,
    ) -> URL? {
        guard reference.baseURL == nil, reference.query == nil, reference.fragment == nil else { return nil }
        let name = reference.lastPathComponent
        guard kind.owns(name, id: id) else { return nil }
        if reference.scheme == nil {
            guard reference.relativeString == name else { return nil }
        } else {
            guard reference.isFileURL, reference.host == nil || reference.host == "",
                  !reference.pathComponents.contains(".."), !reference.pathComponents.contains(".")
            else { return nil }
            let oldDirectory = components(reference.deletingLastPathComponent())
            let currentDirectory = components(directory)
            guard oldDirectory == currentDirectory
                || isPreviousContainer(oldDirectory, current: currentDirectory, storeName: kind.storeName)
            else { return nil }
        }
        let result = directory.appendingPathComponent(name)
        guard isSafeManagedFile(result, directory: directory, allowMissing: allowMissing) else { return nil }
        return result
    }

    static func relative(
        _ file: URL,
        id: UUID,
        kind: Kind,
        directory: URL,
        allowMissing: Bool = false,
    ) throws -> URL {
        guard file.isFileURL,
              components(file.deletingLastPathComponent()) == components(directory),
              kind.owns(file.lastPathComponent, id: id),
              isSafeManagedFile(file, directory: directory, allowMissing: allowMissing),
              let relative = URL(string: file.lastPathComponent)
        else { throw CocoaError(.fileReadInvalidFileName) }
        return relative
    }

    static func isSafeManagedFile(_ file: URL, directory: URL, allowMissing: Bool = false) -> Bool {
        guard file.isFileURL,
              !file.pathComponents.contains(".."), !file.pathComponents.contains("."),
              components(file.deletingLastPathComponent()) == components(directory)
        else { return false }
        // Do not resolve a symlink to decide ownership, including one in a store
        // ancestor. Only the system /private aliases below are canonicalized.
        var ancestor = directory
        while ancestor.path != "/" {
            let path = NSString.path(withComponents: components(ancestor))
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                  attributes[.type] as? FileAttributeType == .typeDirectory
            else { return false }
            ancestor.deleteLastPathComponent()
        }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            return attributes[.type] as? FileAttributeType == .typeRegular
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return allowMissing
        } catch {
            return false
        }
    }

    static func hasRetainedManifest(for file: URL, directory: URL) -> Bool {
        let name = file.lastPathComponent
        guard name.count >= 40, let id = UUID(uuidString: String(name.prefix(36))),
              [.voice(encoded: false), .voice(encoded: true), .video, .videoThumbnail]
                .contains(where: { (kind: Kind) in kind.owns(name, id: id) })
        else { return false }
        return FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(id.uuidString).json").path)
    }

    private static func components(_ url: URL) -> [String] {
        var result = url.pathComponents
        // Foundation preserves these two equivalent Darwin system prefixes.
        // Normalize them lexically; never follow a user-controlled symlink.
        if result.count > 1, result[1] == "var" || result[1] == "tmp" {
            result.insert("private", at: 1)
        }
        return result
    }

    private static func isPreviousContainer(_ old: [String], current: [String], storeName: String) -> Bool {
        guard old.count == current.count, old.count >= 8,
              Array(old.suffix(3)) == ["Library", "Application Support", storeName],
              Array(current.suffix(3)) == ["Library", "Application Support", storeName]
        else { return false }
        let containerIndex = old.count - 4
        guard UUID(uuidString: old[containerIndex]) != nil,
              UUID(uuidString: current[containerIndex]) != nil,
              Array(old[(containerIndex - 3)..<containerIndex]) == ["Containers", "Data", "Application"]
        else { return false }
        return old.prefix(containerIndex) == current.prefix(containerIndex)
    }
}
