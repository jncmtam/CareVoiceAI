import Foundation

actor AudioCache {
    static let shared = AudioCache()

    func cachedFile(for remoteURL: URL, cacheKey: String?) async throws -> URL {
        let fileName = (cacheKey?.cvTrimmed.isEmpty == false ? cacheKey! : remoteURL.lastPathComponent)
            .replacingOccurrences(of: "/", with: "_")
        let destination = FileStorage.audioCacheDirectory.appendingPathComponent(fileName.hasSuffix(".m4a") ? fileName : "\(fileName).m4a")
        if FileManager.default.fileExists(atPath: destination.path) {
            return destination
        }
        let (temporary, _) = try await URLSession.shared.download(from: remoteURL)
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }
}
