import UIKit

enum PhoneDialer {
    enum Failure: Error, Equatable {
        case invalidNumber
        case unavailable
    }

    @discardableResult
    static func call(_ rawNumber: String) -> Bool {
        switch dial(rawNumber) {
        case .success:
            return true
        case .failure:
            return false
        }
    }

    static func dial(_ rawNumber: String) -> Result<Void, Failure> {
        let sanitized = sanitize(rawNumber)
        guard !sanitized.isEmpty, let url = URL(string: "tel:\(sanitized)") else {
            return .failure(.invalidNumber)
        }
        guard UIApplication.shared.canOpenURL(url) else {
            return .failure(.unavailable)
        }
        UIApplication.shared.open(url)
        return .success(())
    }

    static func sanitize(_ rawNumber: String) -> String {
        let trimmed = rawNumber.cvTrimmed
        var result = ""
        for character in trimmed {
            if character.isNumber || character == "+" {
                result.append(character)
            }
        }
        return result
    }
}