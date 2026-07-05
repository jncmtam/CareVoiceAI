import Foundation

enum APIError: Error, Identifiable, Equatable {
    var id: String { localizedDescription }

    case invalidURL
    case missingToken
    case network(message: String)
    case offline
    case timeout
    case server(code: String, message: String, statusCode: Int, traceId: String?)
    case decoding(message: String)
    case encoding(message: String)
    case file(message: String)
    case pollingTimeout
    case cancelled
    case unknown(message: String)

    var userMessage: String {
        switch self {
        case .invalidURL:
            return L10n.text("error.invalid_url")
        case .missingToken:
            return L10n.text("error.missing_token")
        case .network:
            return L10n.errorDefault
        case .offline:
            return L10n.networkOffline
        case .timeout:
            return L10n.text("error.timeout")
        case .server(_, let message, _, _):
            return message
        case .decoding:
            return L10n.text("error.decoding")
        case .encoding:
            return L10n.text("error.encoding")
        case .file(let message):
            return message
        case .pollingTimeout:
            return L10n.text("error.polling_timeout")
        case .cancelled:
            return L10n.text("error.cancelled")
        case .unknown:
            return L10n.errorDefault
        }
    }

    static func from(_ error: Error) -> APIError {
        if let apiError = error as? APIError {
            return apiError
        }
        return .unknown(message: L10n.errorDefault)
    }

    static func == (lhs: APIError, rhs: APIError) -> Bool {
        lhs.userMessage == rhs.userMessage
    }
}
