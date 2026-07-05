import Foundation
import UniformTypeIdentifiers

enum UploadLimits {
    static let maxDocumentBytes = 25 * 1024 * 1024
    static let maxAudioBytes = 250 * 1024 * 1024

    static func validateDocument(fileURL: URL) throws {
        try validate(fileURL: fileURL, maxBytes: maxDocumentBytes, kind: .document)
    }

    static func validateAudio(fileURL: URL) throws {
        try validate(fileURL: fileURL, maxBytes: maxAudioBytes, kind: .audio)
    }

    static func validateAudio(data: Data, fileName: String) throws {
        _ = fileName
        guard !data.isEmpty else {
            throw APIError.file(message: L10n.text("error.file_unreadable"))
        }
        guard data.count <= maxAudioBytes else {
            let limitMB = maxAudioBytes / (1024 * 1024)
            throw APIError.file(message: String(format: L10n.text("error.file_too_large_audio"), limitMB))
        }
    }

    private enum Kind {
        case document
        case audio
    }

    private static func validate(fileURL: URL, maxBytes: Int, kind: Kind) throws {
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile != false else {
            throw APIError.file(message: L10n.text("error.file_unreadable"))
        }
        guard let size = values.fileSize else { return }
        guard size <= maxBytes else {
            let limitMB = maxBytes / (1024 * 1024)
            switch kind {
            case .document:
                throw APIError.file(message: String(format: L10n.text("error.file_too_large_document"), limitMB))
            case .audio:
                throw APIError.file(message: String(format: L10n.text("error.file_too_large_audio"), limitMB))
            }
        }
    }
}

extension URL {
    var uploadMimeType: String {
        if let type = UTType(filenameExtension: pathExtension),
           let mime = type.preferredMIMEType {
            return mime
        }
        switch pathExtension.lowercased() {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "heic":
            return "image/heic"
        case "pdf":
            return "application/pdf"
        case "docx":
            return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "doc":
            return "application/msword"
        case "wav":
            return "audio/wav"
        case "m4a", "aac":
            return "audio/mp4"
        case "mp3":
            return "audio/mpeg"
        default:
            return "application/octet-stream"
        }
    }
}