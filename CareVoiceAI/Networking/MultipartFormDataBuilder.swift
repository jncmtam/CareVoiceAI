import Foundation

struct MultipartFile {
    let fieldName: String
    let fileName: String
    let mimeType: String
    let data: Data
}

struct MultipartFormDataBuilder {
    let boundary: String

    init(boundary: String = "Boundary-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    var contentType: String {
        "multipart/form-data; boundary=\(boundary)"
    }

    func build(fields: [String: String], files: [MultipartFile]) -> Data {
        var data = Data()
        for (name, value) in fields {
            data.append("--\(boundary)\r\n")
            data.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            data.append("\(value)\r\n")
        }

        for file in files {
            data.append("--\(boundary)\r\n")
            data.append("Content-Disposition: form-data; name=\"\(file.fieldName)\"; filename=\"\(file.fileName)\"\r\n")
            data.append("Content-Type: \(file.mimeType)\r\n\r\n")
            data.append(file.data)
            data.append("\r\n")
        }

        data.append("--\(boundary)--\r\n")
        return data
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let value = string.data(using: .utf8) {
            append(value)
        }
    }
}
