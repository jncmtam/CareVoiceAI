import Foundation

struct StaffLoginRequest: Encodable {
    let login: String
    let password: String
    let deviceId: String
}

struct PatientOtpRequest: Encodable {
    let phoneNumber: String
    let patientCode: String?
}

struct PatientOtpResponse: Decodable {
    let otpSessionId: String
    let maskedPhoneNumber: String
    let expiresIn: Int
    let canResendAfter: Int
}

struct PatientOtpVerifyRequest: Encodable {
    let otpSessionId: String
    let otpCode: String
    let deviceId: String
}

struct PatientCodeLoginRequest: Encodable {
    let patientCode: String
    let phoneLast4: String
    let deviceId: String
}

struct PatientPasswordLoginRequest: Encodable {
    let login: String
    let password: String
    let deviceId: String
}

struct AuthResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int
    let user: AppUser
    let patient: PatientSessionContext?
}

struct RefreshTokenRequest: Encodable {
    let refreshToken: String
}

struct RefreshTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int
}

struct LogoutRequest: Encodable {
    let deviceId: String
    let refreshToken: String?
}

struct CurrentUserResponse: Decodable {
    let user: AppUser
    let patient: PatientSessionContext?
}

struct AppUser: Codable, Identifiable {
    let id: String
    let role: UserRole
    let fullName: String
    let staffCode: String?
    let department: String?

    init(id: String, role: UserRole, fullName: String, staffCode: String? = nil, department: String? = nil) {
        self.id = id
        self.role = role
        self.fullName = fullName
        self.staffCode = staffCode
        self.department = department
    }
}

struct PatientSessionContext: Codable, Identifiable {
    let id: String
    let patientCode: String
    let fullName: String
}
