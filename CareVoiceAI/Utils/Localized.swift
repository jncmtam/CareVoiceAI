import Foundation

nonisolated enum L10n {
    static func text(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    static let appName = text("app.name")
    static let loadingOpeningApp = text("loading.opening_app")
    static let retry = text("common.retry")
    static let cancel = text("common.cancel")
    static let save = text("common.save")
    static let send = text("common.send")
    static let continueText = text("common.continue")
    static let logout = text("common.logout")
    static let changeRole = text("common.change_role")
    static let loading = text("common.loading")
    static let emptyDefault = text("empty.default")
    static let errorDefault = text("error.default")
    static let networkOffline = text("error.network_offline")
    static let rolePatient = text("role.patient")
    static let roleStaff = text("role.staff")
    static let staffLoginTitle = text("auth.staff_login.title")
    static let patientLoginTitle = text("auth.patient_login.title")
    static let login = text("auth.login")
    static let emailOrStaffCode = text("auth.email_or_staff_code")
    static let password = text("auth.password")
    static let phoneNumber = text("auth.phone_number")
    static let patientCode = text("auth.patient_code")
    static let requestOTP = text("auth.request_otp")
    static let verifyOTP = text("auth.verify_otp")
    static let otpCode = text("auth.otp_code")
    static let loginWithPatientCode = text("auth.login_patient_code")
    static let patientHomeTitle = text("patient.home.title")
    static let todayCheckin = text("patient.checkin.today")
    static let listenQuestion = text("patient.checkin.listen")
    static let recordAnswer = text("patient.checkin.record")
    static let stopRecording = text("patient.checkin.stop_recording")
    static let playRecording = text("patient.checkin.play_recording")
    static let sendAnswer = text("patient.checkin.send_answer")
    static let preparingQuestion = text("patient.checkin.preparing_question")
    static let analyzingResponse = text("patient.checkin.analyzing_response")
    static let savedOffline = text("patient.checkin.saved_offline")
    static let history = text("patient.history")
    static let medications = text("patient.medications")
    static let appointments = text("patient.appointments")
    static let hotline = text("patient.hotline")
    static let askQuestion = text("patient.hotline.ask")
    static let tapToTalk = text("patient.hotline.tap_to_talk")
    static let staffDashboard = text("staff.dashboard.title")
    static let staffPatients = text("staff.dashboard.patients")
    static let newPatient = text("staff.new_patient")
    static let uploadDocument = text("staff.upload_document")
    static let processingOCR = text("staff.ocr.processing")
    static let confirmOCR = text("staff.ocr.confirm")
    static let markViewed = text("staff.timeline.mark_viewed")
    static let callBack = text("staff.timeline.call_back")
    static let addNote = text("staff.timeline.add_note")
    static let settings = text("settings.title")
    static let notifications = text("settings.notifications")

    static func riskLabel(_ level: RiskLevel?) -> String {
        switch level {
        case .normal:
            return text("risk.normal")
        case .attention:
            return text("risk.attention")
        case .intervention:
            return text("risk.intervention")
        case .none:
            return text("risk.pending")
        }
    }

    static func jobStatus(_ status: JobStatus) -> String {
        text("job.\(status.rawValue)")
    }
}
