import Foundation

extension String {
    var cvTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var cvNilIfEmpty: String? {
        let value = cvTrimmed
        return value.isEmpty ? nil : value
    }
}
