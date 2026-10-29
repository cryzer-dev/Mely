import Testing
import Foundation
@testable import MelyCore

@Suite struct CharacterPoseTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Moscow")!
        return c
    }()
    func at(_ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: hour))!
    }
    func pose(_ i: CharacterInputs, _ hour: Int = 14) -> CharacterPose {
        CharacterMood.pose(i, now: at(hour), calendar: calendar)
    }

    @Test func mostUrgentWins() {
        let noon = at(14)
        #expect(pose(CharacterInputs(sessions: [.working], lastActivity: noon, pendingApprovals: 1, musicPlaying: true)) == .worried)
        #expect(pose(CharacterInputs(sessions: [.waitingAnswer, .working], lastActivity: noon)) == .curious)
        #expect(pose(CharacterInputs(sessions: [.error("x"), .working], lastActivity: noon)) == .scared)
        #expect(pose(CharacterInputs(sessions: [.error("x")], lastActivity: noon.addingTimeInterval(-10 * 60))) == .idle)
        #expect(pose(CharacterInputs(sessions: [.working], lastActivity: noon, planPercent: 95)) == .sad)
        #expect(pose(CharacterInputs(sessions: [.rateLimited], lastActivity: noon)) == .sad)
        #expect(pose(CharacterInputs(sessions: [.finished(summary: ""), .working], lastActivity: noon)) == .happy)
        #expect(pose(CharacterInputs(sessions: [.thinking], lastActivity: noon, musicPlaying: true)) == .working)
        #expect(pose(CharacterInputs(sessions: [.idle], lastActivity: noon, musicPlaying: true)) == .dancing)
        #expect(pose(CharacterInputs(sessions: [.idle], lastActivity: noon)) == .idle)
    }

    @Test func focusOutranksWorkButNotWhatNeedsTheUser() {
        let noon = at(14)
        // Focus and Claude working: focused; a permission or a question: as without the focus.
        #expect(pose(CharacterInputs(sessions: [.working], lastActivity: noon, focus: .working)) == .focused)
        #expect(pose(CharacterInputs(sessions: [.finished(summary: "")], lastActivity: noon, focus: .working)) == .focused)
        #expect(pose(CharacterInputs(sessions: [.working], lastActivity: noon, pendingApprovals: 1, focus: .working)) == .worried)
        #expect(pose(CharacterInputs(sessions: [.waitingAnswer], lastActivity: noon, focus: .working)) == .curious)
        #expect(pose(CharacterInputs(sessions: [.error("x")], lastActivity: noon, focus: .working)) == .scared)
        #expect(pose(CharacterInputs(sessions: [.rateLimited], lastActivity: noon, focus: .resting)) == .sad)
        // Music, sleep: the focus wins.
        #expect(pose(CharacterInputs(lastActivity: noon, musicPlaying: true, focus: .resting)) == .resting)
        #expect(pose(CharacterInputs(focus: .working), 1) == .focused)
    }

    @Test func focusMoodFollowsThePhase() {
        let now = at(14)
        var timer = FocusTimer()
        #expect(timer.mood == nil)
        timer.start(now: now, duration: 25 * 60)
        #expect(timer.mood == .working)
        timer.pause(now: now.addingTimeInterval(60))
        #expect(timer.mood == nil)
        timer.resume(now: now.addingTimeInterval(120))
        timer.tick(now: now.addingTimeInterval(27 * 60), idleSeconds: 0)
        #expect(timer.mood == nil)
        timer.takeBreak(now: now.addingTimeInterval(27 * 60), rhythm: FocusRhythm())
        #expect(timer.mood == .resting)
    }

    @Test func sleepsWhenQuiet() {
        // 20 quiet minutes: asleep, day or night.
        #expect(pose(CharacterInputs(lastActivity: at(14).addingTimeInterval(-25 * 60))) == .sleeping)
        #expect(pose(CharacterInputs(lastActivity: at(14).addingTimeInterval(-5 * 60))) == .idle)
        // Launched at night with nothing going on: asleep; by day: awake.
        #expect(pose(CharacterInputs(), 1) == .sleeping)
        #expect(pose(CharacterInputs(), 14) == .idle)
        // Music wakes it up.
        #expect(pose(CharacterInputs(musicPlaying: true), 1) == .dancing)
    }
}

@Suite struct SessionAndChatPoseTests {
    @Test func eachSessionStateHasAPose() {
        #expect(CharacterMood.pose(for: .idle) == .idle)
        #expect(CharacterMood.pose(for: .thinking) == .working)
        #expect(CharacterMood.pose(for: .working) == .working)
        #expect(CharacterMood.pose(for: .waitingApproval) == .worried)
        #expect(CharacterMood.pose(for: .waitingAnswer) == .curious)
        #expect(CharacterMood.pose(for: .finished(summary: "")) == .happy)
        #expect(CharacterMood.pose(for: .error("x")) == .scared)
        #expect(CharacterMood.pose(for: .rateLimited) == .sad)
    }
}
