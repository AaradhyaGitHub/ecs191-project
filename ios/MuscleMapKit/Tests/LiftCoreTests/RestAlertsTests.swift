import Foundation
import Testing
@testable import LiftCore

// specs/lift-feedback.llm.md, AC-1 to AC-3. The clock is always passed in.

@Suite("Rest alerts (lift-feedback)")
struct RestAlertsTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func end(in seconds: Double) -> Date { now.addingTimeInterval(seconds) }

    // MARK: AC-1 countdownCues

    @Test("AC-1: 30 s left gives ticks 10 to 1 and one end, in time order")
    func ac1_fullCountdown() {
        let endsAt = end(in: 30)
        let cues = countdownCues(endsAt: endsAt, after: now)
        var expected = (1...10).reversed().map {
            TimedCue(at: endsAt.addingTimeInterval(-Double($0)), cue: .tick(secondsLeft: $0))
        }
        expected.append(TimedCue(at: endsAt, cue: .end))
        #expect(cues == expected)
    }

    @Test("AC-1: a long rest (1 hour) still has only 11 cues")
    func ac1_longRest() {
        let cues = countdownCues(endsAt: end(in: 3600), after: now)
        #expect(cues.count == 11)
        #expect(cues.first == TimedCue(at: end(in: 3590), cue: .tick(secondsLeft: 10)))
        #expect(cues.last == TimedCue(at: end(in: 3600), cue: .end))
    }

    @Test("AC-1: a 5-s rest starts at tick 5")
    func ac1_fiveSecondRest() {
        let endsAt = end(in: 5)
        let cues = countdownCues(endsAt: endsAt, after: now)
        #expect(cues.first == TimedCue(at: now, cue: .tick(secondsLeft: 5)))
        #expect(cues.count == 6)
        #expect(cues.last == TimedCue(at: endsAt, cue: .end))
    }

    @Test("AC-1: ticks already in the past are left out (5.5 s left starts at tick 5)")
    func ac1_pastTicksDropped() {
        let endsAt = end(in: 5.5)
        let cues = countdownCues(endsAt: endsAt, after: now)
        #expect(cues.first?.cue == .tick(secondsLeft: 5))
        #expect(cues.count == 6)
    }

    @Test("AC-1: less than 1 s left gives only the end beep")
    func ac1_onlyEnd() {
        let endsAt = end(in: 0.5)
        #expect(countdownCues(endsAt: endsAt, after: now) == [TimedCue(at: endsAt, cue: .end)])
    }

    @Test("AC-1: no timer gives no cues")
    func ac1_noTimer() {
        #expect(countdownCues(endsAt: nil, after: now).isEmpty)
    }

    @Test("AC-1: an ended timer gives no cues")
    func ac1_ended() {
        #expect(countdownCues(endsAt: end(in: -3), after: now).isEmpty)
    }

    // MARK: AC-2 restNotices, app not being left

    @Test("AC-2: more than 10 s left gives '10 seconds left' and 'Rest is over'")
    func ac2_twoNotices() throws {
        let endsAt = end(in: 60)
        let notices = restNotices(endsAt: endsAt, now: now, leavingApp: false)
        #expect(notices.count == 2)
        let ten = try #require(notices.first { $0.id == RestNoticeID.tenLeft })
        #expect(ten.fireAt == endsAt.addingTimeInterval(-10))
        #expect(ten.title == "10 seconds left")
        #expect(ten.sound == "countdown_10.caf")
        let over = try #require(notices.first { $0.id == RestNoticeID.over })
        #expect(over.fireAt == endsAt)
        #expect(over.title == "Rest is over")
    }

    @Test("AC-2: 'Rest is over' has no sound (Q-9)")
    func ac2_overHasNoSound() throws {
        let notices = restNotices(endsAt: end(in: 60), now: now, leavingApp: false)
        let over = try #require(notices.first { $0.id == RestNoticeID.over })
        #expect(over.sound == nil)
    }

    @Test("AC-2: 11 s left (just above the threshold) still plans both")
    func ac2_justAboveTen() {
        let notices = restNotices(endsAt: end(in: 11), now: now, leavingApp: false)
        #expect(Set(notices.map(\.id)) == [RestNoticeID.tenLeft, RestNoticeID.over])
    }

    @Test("AC-2: exactly 10 s left plans only 'Rest is over'")
    func ac2_exactlyTen() {
        let notices = restNotices(endsAt: end(in: 10), now: now, leavingApp: false)
        #expect(notices.map(\.id) == [RestNoticeID.over])
    }

    @Test("AC-2: 5 s left plans only 'Rest is over' at the end")
    func ac2_underTen() {
        let endsAt = end(in: 5)
        let notices = restNotices(endsAt: endsAt, now: now, leavingApp: false)
        #expect(notices.count == 1)
        #expect(notices.first?.id == RestNoticeID.over)
        #expect(notices.first?.fireAt == endsAt)
        #expect(notices.first?.title == "Rest is over")
    }

    @Test("AC-2: no timer gives no notices")
    func ac2_noTimer() {
        #expect(restNotices(endsAt: nil, now: now, leavingApp: false).isEmpty)
    }

    @Test("AC-2: an ended timer gives no notices")
    func ac2_ended() {
        #expect(restNotices(endsAt: end(in: -1), now: now, leavingApp: false).isEmpty)
    }

    // MARK: AC-3 restNotices, leaving the app

    @Test("AC-3: leaving with 7 s left sends one notice now with countdown_7 and keeps 'Rest is over'")
    func ac3_leavingUnderTen() throws {
        let endsAt = end(in: 7)
        let notices = restNotices(endsAt: endsAt, now: now, leavingApp: true)
        #expect(notices.count == 2)
        let nowNotices = notices.filter { $0.fireAt == nil }
        #expect(nowNotices.count == 1)
        #expect(nowNotices.first?.sound == "countdown_7.caf")
        let over = try #require(notices.first { $0.id == RestNoticeID.over })
        #expect(over.fireAt == endsAt)
        #expect(over.title == "Rest is over")
    }

    @Test("AC-3: seconds left are rounded to the nearest second (6.6 gives 7, 6.4 gives 6)")
    func ac3_rounding() {
        let up = restNotices(endsAt: end(in: 6.6), now: now, leavingApp: true)
        #expect(up.first { $0.fireAt == nil }?.sound == "countdown_7.caf")
        let down = restNotices(endsAt: end(in: 6.4), now: now, leavingApp: true)
        #expect(down.first { $0.fireAt == nil }?.sound == "countdown_6.caf")
    }

    @Test("AC-3: exactly 10 s left uses countdown_10")
    func ac3_exactlyTen() {
        let notices = restNotices(endsAt: end(in: 10), now: now, leavingApp: true)
        #expect(notices.first { $0.fireAt == nil }?.sound == "countdown_10.caf")
        #expect(notices.contains { $0.id == RestNoticeID.over })
    }

    @Test("AC-3: 9.6 s left rounds to 10, not 11 or 9")
    func ac3_roundsUpToTen() {
        let notices = restNotices(endsAt: end(in: 9.6), now: now, leavingApp: true)
        #expect(notices.first { $0.fireAt == nil }?.sound == "countdown_10.caf")
    }

    @Test("AC-3: under half a second left still uses countdown_1 (kept in 1 to 10)")
    func ac3_lowerBound() {
        let notices = restNotices(endsAt: end(in: 0.4), now: now, leavingApp: true)
        #expect(notices.first { $0.fireAt == nil }?.sound == "countdown_1.caf")
        #expect(notices.contains { $0.id == RestNoticeID.over })
    }

    @Test("AC-3: leaving with more than 10 s left is the same plan as AC-2")
    func ac3_leavingOverTen() {
        let endsAt = end(in: 45)
        #expect(restNotices(endsAt: endsAt, now: now, leavingApp: true)
                == restNotices(endsAt: endsAt, now: now, leavingApp: false))
    }

    @Test("AC-3: ids are fixed and different, so a new plan replaces the old one")
    func ac3_fixedIds() {
        #expect(RestNoticeID.tenLeft == "rest.ten-left")
        #expect(RestNoticeID.over == "rest.over")
        let notices = restNotices(endsAt: end(in: 7), now: now, leavingApp: true)
        let ids = notices.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(Set(ids).isSubset(of: [RestNoticeID.tenLeft, RestNoticeID.over]))
    }

    @Test("AC-3: leaving with no timer gives no notices")
    func ac3_noTimer() {
        #expect(restNotices(endsAt: nil, now: now, leavingApp: true).isEmpty)
    }

    @Test("AC-3: leaving after the timer ended gives no notices")
    func ac3_ended() {
        #expect(restNotices(endsAt: end(in: -5), now: now, leavingApp: true).isEmpty)
    }

    // MARK: countdownSound

    @Test("AC-3: countdownSound names the file, kept in 1 to 10")
    func ac3_countdownSound() {
        #expect(countdownSound(secondsLeft: 7) == "countdown_7.caf")
        #expect(countdownSound(secondsLeft: 1) == "countdown_1.caf")
        #expect(countdownSound(secondsLeft: 10) == "countdown_10.caf")
        #expect(countdownSound(secondsLeft: 0) == "countdown_1.caf")
        #expect(countdownSound(secondsLeft: -4) == "countdown_1.caf")
        #expect(countdownSound(secondsLeft: 11) == "countdown_10.caf")
        #expect(countdownSound(secondsLeft: 600) == "countdown_10.caf")
    }
}
