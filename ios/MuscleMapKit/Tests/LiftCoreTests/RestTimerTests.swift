import Foundation
import Testing
@testable import LiftCore

/// AC-16 (specs/log-workout.llm.md, "Rest timer"). The clock is always passed in.
@Suite("Rest timer")
struct RestTimerTests {
    let now = Date(timeIntervalSince1970: 1_793_700_000)

    private func running(_ seconds: Int = 90) -> RestTimer {
        var timer = RestTimer()
        timer.start(seconds: seconds, at: now)
        return timer
    }

    @Test("AC-16: no timer means 0 left")
    func notRunning() {
        var timer = RestTimer()
        #expect(timer.isRunning == false)
        #expect(timer.remaining(at: now) == 0)
        timer.start(seconds: 10, at: now)
        #expect(timer.remaining(at: now) == 10, "starting it gives time left")
    }

    @Test("AC-16: start counts down from the rest time")
    func countsDown() {
        let timer = running(90)
        #expect(timer.isRunning)
        #expect(timer.remaining(at: now) == 90)
        #expect(timer.remaining(at: now.addingTimeInterval(30)) == 60)
        #expect(timer.remaining(at: now.addingTimeInterval(89)) == 1)
    }

    @Test("AC-16: at the end time and after it, 0 is left, never less")
    func neverBelowZero() {
        let timer = running(90)
        #expect(timer.remaining(at: now.addingTimeInterval(89)) == 1)
        #expect(timer.remaining(at: now.addingTimeInterval(90)) == 0)
        #expect(timer.remaining(at: now.addingTimeInterval(500)) == 0)
    }

    @Test("AC-16: starting with 0 seconds has 0 left")
    func startZero() {
        #expect(running(0).isRunning, "a timer is set, even though it is already at 0")
        #expect(running(0).remaining(at: now) == 0)
    }

    @Test("AC-16: starting again restarts the count")
    func restart() {
        var timer = running(90)
        timer.start(seconds: 60, at: now.addingTimeInterval(40))
        #expect(timer.remaining(at: now.addingTimeInterval(40)) == 60)
    }

    @Test("AC-16: +30 adds half a minute")
    func plus30() {
        var timer = running(90)
        timer.add(30, at: now.addingTimeInterval(10))
        #expect(timer.remaining(at: now.addingTimeInterval(10)) == 110)
    }

    @Test("AC-16: -30 takes half a minute off")
    func minus30() {
        var timer = running(90)
        timer.add(-30, at: now.addingTimeInterval(10))
        #expect(timer.remaining(at: now.addingTimeInterval(10)) == 50)
    }

    @Test("AC-16: -30 with less than 30 s left goes to 0, not below")
    func minusPastZero() {
        var timer = running(90)
        let late = now.addingTimeInterval(80)
        #expect(timer.remaining(at: late) == 10)
        timer.add(-30, at: late)
        #expect(timer.remaining(at: late) == 0)
        #expect(timer.remaining(at: late.addingTimeInterval(60)) == 0)
    }

    @Test("AC-16: skip stops the timer")
    func skip() {
        var timer = running(90)
        #expect(timer.remaining(at: now) == 90)
        timer.skip()
        #expect(timer.isRunning == false)
        #expect(timer.endsAt == nil)
        #expect(timer.remaining(at: now) == 0)
    }

    @Test("AC-16: it encodes and decodes with the same end time")
    func codable() throws {
        let timer = running(90)
        let data = try JSONEncoder().encode(timer)
        let back = try JSONDecoder().decode(RestTimer.self, from: data)
        #expect(back == timer)
        #expect(back.endsAt == now.addingTimeInterval(90))
        #expect(back.remaining(at: now.addingTimeInterval(30)) == 60)
    }

    @Test("AC-16: a stopped timer also survives encoding")
    func codableStopped() throws {
        var timer = running(90)
        #expect(timer.isRunning)
        timer.skip()
        let data = try JSONEncoder().encode(timer)
        let back = try JSONDecoder().decode(RestTimer.self, from: data)
        #expect(back.isRunning == false)
    }
}
