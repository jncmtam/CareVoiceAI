import Foundation

nonisolated enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case patch = "PATCH"
    case delete = "DELETE"
}

nonisolated struct APIEndpoint {
    let method: HTTPMethod
    let path: String
    var queryItems: [URLQueryItem] = []
    var headers: [String: String] = [:]
    var body: Data?

    init(
        method: HTTPMethod,
        path: String,
        queryItems: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: Data? = nil
    ) {
        self.method = method
        self.path = path
        self.queryItems = queryItems
        self.headers = headers
        self.body = body
    }
}
