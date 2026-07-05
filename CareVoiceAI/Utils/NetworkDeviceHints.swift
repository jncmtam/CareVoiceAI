import Foundation

enum APIBaseURLNormalizer {
    static func normalize(_ raw: String) -> String? {
        let trimmed = raw.cvTrimmed
        guard let url = URL(string: trimmed), let host = url.host, !host.isEmpty else { return nil }
        var normalized = trimmed
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        _ = host
        return normalized
    }
}