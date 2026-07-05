import Foundation

struct DemoCatalog {
    let profiles: [String: PatientProfile]
    let priorityPatients: [PatientSummary]
    let timelines: [String: [TimelineEntry]]
    let medicationsByPatient: [String: [Medication]]
    let appointmentsByPatient: [String: [Appointment]]
}

enum DemoPatientSeed {
    static func make(referenceDate: Date = Date()) -> DemoCatalog {
        let today = referenceDate
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: today) ?? today
        let nextWeek = Calendar.current.date(byAdding: .day, value: 7, to: today) ?? today

        let specs: [DemoPatientSpec] = [
            DemoPatientSpec(
                id: "pat_001", code: "VC-2026-000001", name: "Chu Minh Tâm", dob: "1998-07-15", gender: .male,
                phone: "+84327628468", caregiver: "Trần Minh Anh", caregiverPhone: "+84987654321",
                diagnoses: ["Đái tháo đường type 2", "Tăng huyết áp"], age: 28,
                risk: .intervention, handling: .new, unread: 2, summary: "Mệt và chóng mặt nhẹ sau đổi liều thuốc — bệnh nhân chính.",
                reasons: ["Check-in: bệnh nhân báo chóng mặt", "Check-in: bệnh nhân chọn 'Có triệu chứng bất thường'"],
                checkinAt: today, missedDoses: nil, caregiverAlert: today, notes: "Bệnh nhân chính — SĐT 0327628468."
            ),
            DemoPatientSpec(
                id: "pat_002", code: "VC-2026-000002", name: "Nguyễn Thị Hoa", dob: "1966-09-12", gender: .female,
                phone: "+84903334455", caregiver: "Phạm Quang Minh", caregiverPhone: "+84906667788",
                diagnoses: ["Suy tim", "Rối loạn lipid máu"], age: 60,
                risk: .attention, handling: .viewed, unread: 0, summary: "Phù chân nhẹ buổi chiều, điều dưỡng đang theo dõi.",
                reasons: ["Check-in: bệnh nhân báo mệt bất thường"], checkinAt: yesterday, missedDoses: 1,
                caregiverAlert: yesterday, notes: "Cần nhắc uống thuốc buổi tối."
            ),
            DemoPatientSpec(
                id: "pat_003", code: "VC-2026-000003", name: "Lê Quốc Đạt", dob: "1971-01-05", gender: .male,
                phone: "+84908889900", caregiver: nil, caregiverPhone: nil,
                diagnoses: ["Sau phẫu thuật khớp gối"], age: 55,
                risk: .normal, handling: .resolved, unread: 0, summary: "Tập vận động tốt, không đau tăng thêm.",
                reasons: ["Không có triệu chứng cảnh báo trong phản hồi hôm nay"], checkinAt: today, missedDoses: nil,
                caregiverAlert: nil, notes: nil
            ),
            DemoPatientSpec(
                id: "pat_004", code: "VC-2026-000004", name: "Phạm Thị Lan", dob: "1952-11-18", gender: .female,
                phone: "+84907771234", caregiver: "Phạm Văn Tú", caregiverPhone: "+84909998877",
                diagnoses: ["COPD", "Hen phế quản"], age: 74,
                risk: .attention, handling: .new, unread: 1, summary: "Ho nhiều hơn 2 ngày, cần xác nhận có sốt không.",
                reasons: ["Check-in: bệnh nhân báo sốt"], checkinAt: today, missedDoses: 2,
                caregiverAlert: today, notes: "Sống một mình, ưu tiên gọi buổi sáng."
            ),
            DemoPatientSpec(
                id: "pat_005", code: "VC-2026-000005", name: "Hoàng Văn Em", dob: "1945-06-02", gender: .male,
                phone: "+84905556677", caregiver: "Hoàng Thị Sen", caregiverPhone: "+84904443322",
                diagnoses: ["Parkinson", "Táo bón"], age: 81,
                risk: .normal, handling: .resolved, unread: 0, summary: "Ăn uống ổn, không té ngã trong tuần qua.",
                reasons: ["Không có triệu chứng cảnh báo trong phản hồi hôm nay"], checkinAt: yesterday, missedDoses: nil,
                caregiverAlert: nil, notes: "Di chuyển chậm, cần nhắc tập phục hồi."
            ),
            DemoPatientSpec(
                id: "pat_006", code: "VC-2026-000006", name: "Đỗ Minh Châu", dob: "1960-04-25", gender: .female,
                phone: "+84902223344", caregiver: "Đỗ Quang Huy", caregiverPhone: "+84901112233",
                diagnoses: ["Suy thận mạn", "Thiếu máu"], age: 66,
                risk: .intervention, handling: .viewed, unread: 0, summary: "Đã gọi BN, phù nặng hơn — chờ xác nhận ổn định sau can thiệp.",
                reasons: ["Check-in: bệnh nhân báo khó thở", "Check-in: bệnh nhân báo mệt bất thường"],
                checkinAt: today, missedDoses: 1, caregiverAlert: today,
                notes: "Điều dưỡng đã gọi sáng nay, cần check-in lại chiều."
            ),
            DemoPatientSpec(
                id: "pat_007", code: "VC-2026-000007", name: "Võ Thị Nga", dob: "1975-08-30", gender: .female,
                phone: "+84906665544", caregiver: nil, caregiverPhone: nil,
                diagnoses: ["Viêm khớp dạng thấp"], age: 51,
                risk: .normal, handling: nil, unread: 0, summary: "Không có cảnh báo mới.",
                reasons: nil, checkinAt: twoDaysAgo, missedDoses: nil, caregiverAlert: nil, notes: nil
            ),
            DemoPatientSpec(
                id: "pat_008", code: "VC-2026-000008", name: "Bùi Văn Hùng", dob: "1955-12-09", gender: .male,
                phone: "+84903332211", caregiver: "Bùi Thị Hạnh", caregiverPhone: "+84907778899",
                diagnoses: ["Nhồi máu cơ tim cũ", "Rối loạn nhịp"], age: 71,
                risk: .attention, handling: .resolved, unread: 0, summary: "Đã ổn định sau can thiệp hôm qua, tiếp tục theo dõi.",
                reasons: ["Check-in: bệnh nhân báo chóng mặt"], checkinAt: yesterday, missedDoses: nil,
                caregiverAlert: nil, notes: "Ca đêm qua đã xử lý xong."
            ),
            DemoPatientSpec(
                id: "pat_009", code: "VC-2026-000009", name: "Ngô Thị Mai", dob: "1968-02-14", gender: .female,
                phone: "+84909990011", caregiver: "Ngô Văn Phúc", caregiverPhone: "+84908881122",
                diagnoses: ["Basedow", "Loãng xương"], age: 58,
                risk: .normal, handling: nil, unread: 0, summary: "Đang phân tích check-in mới nhất...",
                reasons: nil, checkinAt: today, missedDoses: nil, caregiverAlert: nil, notes: nil,
                pendingCheckin: true
            ),
        ]

        var profiles: [String: PatientProfile] = [:]
        var priorityPatients: [PatientSummary] = []
        var timelines: [String: [TimelineEntry]] = [:]
        var medicationsByPatient: [String: [Medication]] = [:]
        var appointmentsByPatient: [String: [Appointment]] = [:]

        for spec in specs {
            let profile = PatientProfile(
                id: spec.id,
                patientCode: spec.code,
                fullName: spec.name,
                dateOfBirth: spec.dob,
                gender: spec.gender,
                phoneNumber: spec.phone,
                caregiverName: spec.caregiver,
                caregiverPhoneNumber: spec.caregiverPhone,
                diagnoses: spec.diagnoses,
                latestRiskLevel: spec.displayRisk,
                latestCheckinAt: spec.checkinAt,
                nextAppointmentAt: spec.id == "pat_001" ? nextWeek : nil,
                notes: spec.notes,
                age: spec.age,
                isActive: true
            )
            profiles[spec.id] = profile
            priorityPatients.append(
                PatientSummary(
                    patientId: spec.id,
                    patientCode: spec.code,
                    fullName: spec.name,
                    age: spec.age,
                    diagnoses: spec.diagnoses,
                    latestRiskLevel: spec.displayRisk,
                    latestSummary: spec.summary,
                    latestCheckinAt: spec.checkinAt,
                    handlingStatus: spec.handling,
                    unreadAlertCount: spec.unread,
                    alertReasons: spec.reasons,
                    caregiverAlertSentAt: spec.caregiverAlert,
                    missedMedicationDoses: spec.missedDoses,
                    patientPhone: spec.phone,
                    caregiverPhone: spec.caregiverPhone
                )
            )
            timelines[spec.id] = spec.timelineEntries(referenceDate: referenceDate, pending: spec.pendingCheckin)
            medicationsByPatient[spec.id] = spec.id == "pat_001" ? defaultMedications : []
            if spec.id == "pat_001" {
                appointmentsByPatient[spec.id] = [
                    Appointment(id: "apt_001", appointmentAt: nextWeek, department: "Nội tiết", doctorName: "BS. Lê Minh", status: "scheduled")
                ]
            }
        }

        return DemoCatalog(
            profiles: profiles,
            priorityPatients: priorityPatients,
            timelines: timelines,
            medicationsByPatient: medicationsByPatient,
            appointmentsByPatient: appointmentsByPatient
        )
    }

    private static var defaultMedications: [Medication] {
        [
            Medication(
                id: "med_001", name: "Metformin", strength: "500mg", dosage: "1 viên",
                frequency: "Ngày 2 lần", timesOfDay: [.morning, .evening],
                instructions: "Uống sau ăn sáng và tối.", startDate: nil, endDate: nil, isActive: true
            ),
            Medication(
                id: "med_002", name: "Amlodipine", strength: "5mg", dosage: "1 viên",
                frequency: "Mỗi sáng", timesOfDay: [.morning],
                instructions: "Uống vào cùng một giờ mỗi ngày.", startDate: nil, endDate: nil, isActive: true
            )
        ]
    }

}

private struct DemoPatientSpec {
    let id: String
    let code: String
    let name: String
    let dob: String
    let gender: Gender
    let phone: String
    let caregiver: String?
    let caregiverPhone: String?
    let diagnoses: [String]
    let age: Int
    let risk: RiskLevel
    let handling: HandlingStatus?
    let unread: Int
    let summary: String
    let reasons: [String]?
    let checkinAt: Date
    let missedDoses: Int?
    let caregiverAlert: Date?
    let notes: String?
    var pendingCheckin: Bool = false

    var displayRisk: RiskLevel {
        guard handling == .resolved else { return risk }
        switch risk {
        case .intervention:
            return .attention
        case .attention:
            return .normal
        case .normal:
            return .normal
        }
    }

    func timelineEntries(referenceDate: Date, pending: Bool) -> [TimelineEntry] {
        if pending {
            return [
                TimelineEntry(
                    id: "tl_\(id)_pending",
                    type: .checkinResponse,
                    occurredAt: referenceDate,
                    status: .processing,
                    riskLevel: nil,
                    summary: nil,
                    transcript: nil,
                    riskReasons: nil,
                    handlingStatus: nil,
                    staffAlertId: nil,
                    staffNote: nil,
                    handledByName: nil,
                    displayMessage: "Đang phân tích phản hồi mới nhất...",
                    jobId: "job_demo_checkin_\(id)"
                )
            ]
        }
        guard risk != .normal || handling != nil else { return [] }
        return [
            TimelineEntry(
                id: "tl_\(id)_001",
                type: .checkinResponse,
                occurredAt: checkinAt,
                status: .completed,
                riskLevel: risk,
                summary: summary,
                transcript: "Phản hồi check-in demo của \(name).",
                riskReasons: reasons,
                handlingStatus: handling,
                staffAlertId: handling == .new || handling == .viewed ? "alert_\(id)" : nil,
                staffNote: handling == .resolved ? "Điều dưỡng đã xác nhận BN ổn định sau can thiệp." : nil,
                handledByName: handling == .resolved ? "Nguyễn Thị Lan" : nil,
                displayMessage: nil,
                jobId: nil
            )
        ]
    }
}