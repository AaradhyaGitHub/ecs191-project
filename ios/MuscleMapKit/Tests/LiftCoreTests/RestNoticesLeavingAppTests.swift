import Foundation
import Testing
@testable import LiftCore

// The app keeps the notices planned in the app when it leaves with more than 10 s left, and
// plans again only when leaving changes the plan (RestAlertController, #67 device fix).
// These tests pin the rule it relies on: leaving changes the plan only with 10 s or less left.

@Suite("Rest notices when leaving the app (lift-feedback device fix)")
struct RestNoticesLeavingAppTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func notices(left seconds: Double?, leavingApp: Bool) -> [RestNotice] {
        restNotices(endsAt: seconds.map { now.addingTimeInterval($0) }, now: now, leavingApp: leavingApp)
    }

    @Test("More than 10 s left: leaving the app gives the same plan as staying",
          arguments: [10.001, 10.5, 11, 30, 90, 3600])
    func moreThanTenLeft_samePlan(left: Double) {
        #expect(notices(left: left, leavingApp: true) == notices(left: left, leavingApp: false))
    }

    @Test("No timer, or an ended one: leaving the app gives the same empty plan",
          arguments: [nil, 0, -5] as [Double?])
    func noTimer_samePlan(left: Double?) {
        #expect(notices(left: left, leavingApp: true).isEmpty)
        #expect(notices(left: left, leavingApp: false).isEmpty)
    }

    @Test("10 s or less left: leaving the app changes the plan (the countdown goes out now)",
          arguments: [10, 9.6, 5, 1, 0.2])
    func tenOrLessLeft_planChanges(left: Double) {
        let away = notices(left: left, leavingApp: true)
        #expect(away != notices(left: left, leavingApp: false))
        #expect(away.first?.id == RestNoticeID.tenLeft)
        #expect(away.first?.fireAt == nil)
    }
}
