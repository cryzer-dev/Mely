import Testing
import Foundation
@testable import MelyCore

@Suite struct FocusTimerTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    /// `m` minutes after `t0`.
    func at(_ m: Double) -> Date { t0.addingTimeInterval(m * 60) }
    func mins(_ m: Double) -> TimeInterval { m * 60 }
    let task = FocusTaskRef(id: "r1", title: "Отчёт по релизу")

    func records(_ events: [FocusEvent]) -> [FocusRecord] {
        events.compactMap { if case let .record(r) = $0 { r } else { nil } }
    }

    /// A session of `m` minutes from `start`, run to its end.
    func finished(_ m: Double, from start: Double, _ timer: inout FocusTimer) {
        timer.start(now: at(start), duration: mins(m), task: task)
        timer.tick(now: at(start + m), idleSeconds: 0)
    }

    // MARK: 1.1 Cycle

    @Test func fullCycle() {
        var timer = FocusTimer()
        #expect(timer.start(now: at(0), duration: mins(40), task: task) == [.started])
        #expect(timer.tick(now: at(21.3), idleSeconds: 1).isEmpty)
        #expect(timer.remaining(now: at(21.3)) == mins(18.7))
        #expect(timer.progress(now: at(21.3)) > 0.5)

        let end = timer.tick(now: at(40), idleSeconds: 1)
        #expect(end.first == .finished(worked: mins(40)))
        #expect(records(end).map(\.worked) == [mins(40)])
        #expect(records(end).first?.taskId == "r1")
        #expect(timer.phase == .finished)

        #expect(timer.takeBreak(now: at(41)) == [.breakStarted(mins(5))])
        #expect(timer.remaining(now: at(43)) == mins(3))
        #expect(timer.tick(now: at(46), idleSeconds: 1) == [.breakOver])

        #expect(timer.continue(now: at(47)) == [.started])
        #expect(timer.task == task)
        #expect(timer.remaining(now: at(47)) == mins(40))
    }

    @Test func plusFiveMinutes() {
        var timer = FocusTimer()
        timer.start(now: at(0), duration: mins(25))
        timer.extend(by: mins(5), now: at(23))
        #expect(timer.remaining(now: at(23)) == mins(7))
        #expect(timer.tick(now: at(25), idleSeconds: 0).isEmpty)
        #expect(timer.tick(now: at(30), idleSeconds: 0).first == .finished(worked: mins(30)))
    }

    @Test func moreAfterTheEndRewritesTheRecord() {
        var timer = FocusTimer()
        finished(40, from: 0, &timer)
        let id = timer.sessionId
        timer.extend(by: mins(10), now: at(41))
        #expect(timer.phase == .working)
        let end = timer.tick(now: at(51), idleSeconds: 0)
        #expect(records(end).map(\.worked) == [mins(50)])
        #expect(records(end).first?.id == id)
        #expect(timer.streak == 1)   // still one session
    }

    @Test func stopAfterTwelveMinutes() {
        var timer = FocusTimer()
        timer.start(now: at(0), duration: mins(40), task: task)
        let events = timer.stop(now: at(12))
        #expect(records(events).map(\.worked) == [mins(12)])
        #expect(timer.phase == .idle)
        #expect(timer.takeBreak(now: at(12)).isEmpty)   // no break after «Стоп»
    }

    @Test func oneSessionAtATime() {
        var timer = FocusTimer()
        timer.start(now: at(0), duration: mins(25))
        #expect(timer.start(now: at(5), duration: mins(40), task: task).isEmpty)
        #expect(timer.task == nil)

        let events = timer.replace(now: at(10), duration: mins(40), task: task)
        #expect(records(events).map(\.worked) == [mins(10)])
        #expect(events.last == .started)
        #expect(timer.task == task)
        #expect(timer.remaining(now: at(10)) == mins(40))
    }

    @Test func longBreakAfterFourInARow() {
        var timer = FocusTimer()
        var start = 0.0
        for n in 1...4 {
            finished(25, from: start, &timer)
            let expected = n == 4 ? mins(15) : mins(5)
            #expect(timer.takeBreak(now: at(start + 25)) == [.breakStarted(expected)])
            timer.tick(now: at(start + 25 + expected / 60), idleSeconds: 0)
            start += 25 + expected / 60
        }
        #expect(timer.streak == 4)
    }

    @Test func streakBreaksAfterThirtyMinutes() {
        var timer = FocusTimer()
        for i in 0..<3 { finished(25, from: Double(i) * 30, &timer); timer.skipBreak() }
        #expect(timer.streak == 3)
        // The 4th session starts 31 min after the 3rd ended: not in a row.
        finished(25, from: 85 + 31, &timer)
        #expect(timer.streak == 1)
        #expect(timer.takeBreak(now: at(200)) == [.breakStarted(mins(5))])
    }

    @Test func customRhythm() {
        var timer = FocusTimer()
        finished(50, from: 0, &timer)
        #expect(timer.takeBreak(now: at(50), rhythm: FocusRhythm(shortBreak: mins(10))) == [.breakStarted(mins(10))])
    }

    @Test func awayAfterTheEndDoesNotCountTheTail() {
        var timer = FocusTimer()
        timer.start(now: at(0), duration: mins(40))
        let end = timer.tick(now: at(40), idleSeconds: 0)
        // Back 20 minutes later, nothing pressed: the timer did not go on.
        #expect(timer.tick(now: at(60), idleSeconds: 0).isEmpty)
        #expect(timer.phase == .finished)
        #expect(timer.worked(now: at(60)) == mins(40))
        #expect(records(end).map(\.worked) == [mins(40)])
    }

    @Test func manualPauseKeepsTheRemainingTime() {
        var timer = FocusTimer()
        timer.start(now: at(0), duration: mins(25))
        timer.pause(now: at(10))
        #expect(timer.phase == .paused(.manual))
        #expect(timer.remaining(now: at(30)) == mins(15))
        #expect(timer.tick(now: at(30), idleSeconds: 0).isEmpty)   // not lifted by input
        #expect(timer.tick(now: at(40), idleSeconds: 9999).isEmpty)
        #expect(timer.phase == .paused(.manual))
        timer.resume(now: at(40))
        #expect(timer.remaining(now: at(40)) == mins(15))
        #expect(timer.tick(now: at(55), idleSeconds: 0).first == .finished(worked: mins(25)))
    }

    // MARK: 1.2 Away, lock, sleep

    @Test func away() {
        var timer = FocusTimer()
        timer.start(now: at(0), duration: mins(40))
        timer.tick(now: at(10), idleSeconds: 0)
        // Last input at 10:00; at 15:00 that is 5 minutes: paused from 10:00.
        #expect(timer.tick(now: at(15), idleSeconds: mins(5)) == [.autoPaused])
        #expect(timer.phase == .paused(.away))
        #expect(timer.worked(now: at(15)) == mins(10))
        #expect(timer.tick(now: at(16), idleSeconds: mins(6)).isEmpty)
        // Back at 17:00.
        #expect(timer.tick(now: at(17), idleSeconds: 1) == [.returned(away: mins(7))])
        #expect(timer.tick(now: at(17.1), idleSeconds: 1).isEmpty)   // said once
        #expect(timer.phase == .paused(.away))                          // waits for «Продолжить»
        timer.resume(now: at(18))
        #expect(timer.remaining(now: at(18)) == mins(30))
        let end = timer.tick(now: at(48), idleSeconds: 0)
        #expect(end.first == .finished(worked: mins(40)))
    }

    @Test func awayThresholdFromSettings() {
        var timer = FocusTimer()
        timer.start(now: at(0), duration: mins(40))
        #expect(timer.tick(now: at(10), idleSeconds: mins(5), awayAfter: mins(10)).isEmpty)
        #expect(timer.tick(now: at(12), idleSeconds: mins(10), awayAfter: mins(10)) == [.autoPaused])
        #expect(timer.worked(now: at(12)) == mins(2))
    }

    @Test func awayTrackingOff() {
        var timer = FocusTimer()
        timer.start(now: at(0), duration: mins(25))
        #expect(timer.tick(now: at(20), idleSeconds: nil).isEmpty)
        #expect(timer.phase == .working)
        #expect(timer.tick(now: at(25), idleSeconds: nil).first == .finished(worked: mins(25)))
    }

    @Test func breakGoesOnWhileAway() {
        var timer = FocusTimer()
        finished(25, from: 0, &timer)
        timer.takeBreak(now: at(25))
        #expect(timer.tick(now: at(29), idleSeconds: mins(4)).isEmpty)
        timer.lock(now: at(29))
        #expect(timer.phase == .onBreak)
        #expect(timer.tick(now: at(30), idleSeconds: mins(5)) == [.breakOver])
    }

    @Test func closedTheLid() {
        var timer = FocusTimer()
        timer.start(now: at(0), duration: mins(40))
        timer.tick(now: at(10), idleSeconds: 0)
        timer.lock(now: at(10))
        #expect(timer.phase == .paused(.locked))
        // Asleep past the planned end: nothing finishes, nothing is counted.
        #expect(timer.tick(now: at(70), idleSeconds: 0).isEmpty)
        #expect(timer.unlock(now: at(70)) == [.returned(away: mins(60))])
        #expect(timer.unlock(now: at(71)).isEmpty)
        #expect(timer.phase == .paused(.locked))   // not lifted by itself
        #expect(timer.worked(now: at(70)) == mins(10))
        timer.resume(now: at(71))
        #expect(timer.remaining(now: at(71)) == mins(30))
    }

    @Test func idleBeforeTheEndPausesAtTheLastInput() {
        // The tick at the end comes late (load): the input stopped before the end.
        var timer = FocusTimer()
        timer.start(now: at(0), duration: mins(25))
        timer.tick(now: at(20), idleSeconds: 0)
        #expect(timer.tick(now: at(26), idleSeconds: mins(6)) == [.autoPaused])
        #expect(timer.worked(now: at(26)) == mins(20))
    }

    // MARK: 1.3 Meetings

    func meeting(_ m: Double, _ id: String = "groom") -> FocusMeeting {
        FocusMeeting(id: id, title: "Груминг", start: at(m))
    }

    @Test func meetingMidFocus() {
        // Focus of 50 min at 10:30 (= 0), the meeting at 11:00 (= 30).
        var timer = FocusTimer()
        timer.start(now: at(0), duration: mins(50))
        #expect(timer.tick(now: at(0), idleSeconds: 0, nextMeeting: meeting(30)).isEmpty)
        #expect(timer.tick(now: at(24.9), idleSeconds: 0, nextMeeting: meeting(30)).isEmpty)
        #expect(timer.tick(now: at(25), idleSeconds: 0, nextMeeting: meeting(30)) == [.meetingSoon(meeting(30))])
        #expect(timer.tick(now: at(26), idleSeconds: 0, nextMeeting: meeting(30)).isEmpty)   // once
    }

    @Test func meetingRightNow() {
        var timer = FocusTimer()
        timer.start(now: at(0), duration: mins(25))
        #expect(timer.tick(now: at(0), idleSeconds: 0, nextMeeting: meeting(2)) == [.meetingSoon(meeting(2))])
    }

    @Test func meetingAfterTheEndIsNotWarned() {
        var timer = FocusTimer()
        timer.start(now: at(0), duration: mins(25))
        #expect(timer.tick(now: at(22), idleSeconds: 0, nextMeeting: meeting(26)).isEmpty)
        #expect(timer.tick(now: at(24), idleSeconds: 0, nextMeeting: meeting(25)).isEmpty)
        // «+5 мин» moves the end past it.
        timer.extend(by: mins(5), now: at(24))
        #expect(timer.tick(now: at(24), idleSeconds: 0, nextMeeting: meeting(26)) == [.meetingSoon(meeting(26))])
    }

    @Test func newSessionWarnsAgain() {
        var timer = FocusTimer()
        timer.start(now: at(0), duration: mins(25))
        timer.tick(now: at(0), idleSeconds: 0, nextMeeting: meeting(3))
        timer.stop(now: at(1))
        timer.start(now: at(1), duration: mins(25))
        #expect(timer.tick(now: at(1), idleSeconds: 0, nextMeeting: meeting(3)) == [.meetingSoon(meeting(3))])
    }

    // MARK: 1.4 Restore

    func roundTrip(_ timer: FocusTimer) -> FocusTimer? {
        let defaults = UserDefaults(suiteName: "mely-focus-\(UUID().uuidString)")!
        timer.save(to: defaults)
        return FocusTimer.saved(in: defaults)
    }

    @Test func restoreMidSession() throws {
        var timer = FocusTimer()
        timer.start(now: at(0), duration: mins(40), task: task)
        timer.tick(now: at(10), idleSeconds: 0)
        var restored = try #require(roundTrip(timer))
        #expect(restored == timer)
        #expect(restored.restore(now: at(12)).isEmpty)
        #expect(restored.phase == .working)
        #expect(restored.remaining(now: at(12)) == mins(28))
        #expect(restored.tick(now: at(40), idleSeconds: 0).first == .finished(worked: mins(40)))
    }

    @Test func restoreAfterThePlannedEnd() throws {
        var timer = FocusTimer()
        timer.start(now: at(0), duration: mins(40), task: task)
        timer.tick(now: at(30), idleSeconds: 0)   // last input saved at 30
        var restored = try #require(roundTrip(timer))
        let events = restored.restore(now: at(90))
        #expect(!events.contains(.finished(worked: mins(30))))   // silently
        #expect(records(events).map(\.worked) == [mins(30)])
        #expect(restored.phase == .finished)
        #expect(restored.streak == 1)
    }

    @Test func restorePausedAndBreak() throws {
        var paused = FocusTimer()
        paused.start(now: at(0), duration: mins(25))
        paused.pause(now: at(5))
        var restored = try #require(roundTrip(paused))
        restored.restore(now: at(100))
        #expect(restored.phase == .paused(.manual))
        #expect(restored.remaining(now: at(100)) == mins(20))

        var onBreak = FocusTimer()
        finished(25, from: 0, &onBreak)
        onBreak.takeBreak(now: at(25))
        var back = try #require(roundTrip(onBreak))
        #expect(back.restore(now: at(60)).isEmpty)
        #expect(back.phase == .breakOver)
    }
}
