import Foundation

enum PatientInputValidator {
    private static let patientCodePattern = #"^VC-\d{4}-\d{6}$"#
    private static let vnMobilePattern = #"^\+84[3-9]\d{8}$"#

    struct ValidationResult {
        var isValid: Bool { fieldErrors.isEmpty }
        let fieldErrors: [Field: String]
    }

    enum Field: String, Hashable {
        case patientCode
        case fullName
        case phoneNumber
        case caregiverPhone
    }

    static func validatePatientCode(_ patientCode: String) -> String? {
        let code = normalizePatientCode(patientCode)
        if code.isEmpty {
            return L10n.text("validation.patient_code.required")
        }
        if code.range(of: patientCodePattern, options: .regularExpression) == nil {
            return L10n.text("validation.patient_code.format")
        }
        return nil
    }

    static func validateNewPatient(
        fullName: String,
        phoneNumber: String,
        caregiverPhone: String
    ) -> ValidationResult {
        var errors: [Field: String] = [:]

        let name = fullName.cvTrimmed
        if name.count < 2 {
            errors[.fullName] = L10n.text("validation.full_name.min")
        }

        if let phoneError = phoneValidationMessage(for: phoneNumber) {
            errors[.phoneNumber] = phoneError
        }

        let caregiver = caregiverPhone.cvTrimmed
        if !caregiver.isEmpty, let caregiverError = phoneValidationMessage(for: caregiver) {
            errors[.caregiverPhone] = caregiverError
        }

        return ValidationResult(fieldErrors: errors)
    }

    static func normalizePatientCode(_ value: String) -> String {
        value.cvTrimmed.uppercased()
    }

    static func normalizePhoneNumber(_ value: String) -> String {
        var cleaned = value.cvTrimmed
        cleaned = cleaned.replacingOccurrences(of: " ", with: "")
        cleaned = cleaned.replacingOccurrences(of: "-", with: "")
        cleaned = cleaned.replacingOccurrences(of: ".", with: "")
        cleaned = cleaned.replacingOccurrences(of: "(", with: "")
        cleaned = cleaned.replacingOccurrences(of: ")", with: "")

        if cleaned.hasPrefix("00") {
            cleaned = "+" + cleaned.dropFirst(2)
        }
        if cleaned.hasPrefix("+") {
            let digits = cleaned.dropFirst().filter(\.isNumber)
            return "+\(digits)"
        }

        let digits = cleaned.filter(\.isNumber)
        if digits.hasPrefix("84") {
            return "+\(digits)"
        }
        if digits.count == 10, digits.first == "0" {
            return "+84" + digits.dropFirst()
        }
        if digits.count == 9, ["3", "5", "7", "8", "9"].contains(String(digits.prefix(1))) {
            return "+84\(digits)"
        }
        return digits.isEmpty ? "" : "+\(digits)"
    }

    private static func phoneValidationMessage(for value: String) -> String? {
        let trimmed = value.cvTrimmed
        if trimmed.isEmpty {
            return L10n.text("validation.phone.required")
        }
        let normalized = normalizePhoneNumber(trimmed)
        if normalized.range(of: vnMobilePattern, options: .regularExpression) == nil {
            return L10n.text("validation.phone.format")
        }
        return nil
    }
}