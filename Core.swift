import Foundation

let goal = 10

enum Phase: String, Codable {
    case idle, focus, finished, shortBreak, longBreak  // finished: waiting for the user to start a break or skip it
    var isBreak: Bool { self == .shortBreak || self == .longBreak }
    var isCounting: Bool { self == .focus || isBreak }
}

/// Everything the app persists. What's on screen is derived from this plus the clock.
struct State: Codable, Equatable {
    var phase = Phase.idle
    var end = Date.distantPast   // when the current phase ends
    var day = ""                 // date `count` belongs to, "yyyy-MM-dd"
    var count = 0                // pomodoros completed on `day`
    var minutes: Int?            // length of the current/last pomodoro; optional so older saved state still loads
}

enum Event: Equatable { case focusDone, breakDone }

struct Pomodoro {
    static let lengths = [15, 25, 50]               // pomodoro lengths offered, in minutes
    static let shortBreak: TimeInterval = 5 * 60
    static let deepBreak: TimeInterval = 10 * 60    // short break after a 50 min pomodoro
    static let longBreak: TimeInterval = 15 * 60
    static let longBreakEvery = 4

    var s = State()
    var cal = Calendar.autoupdatingCurrent

    func dayKey(_ date: Date) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    mutating func start(minutes: Int, now: Date) {
        s.phase = .focus
        s.end = now + TimeInterval(minutes * 60)
        s.minutes = minutes
    }

    /// Long break after every 4th pomodoro of the day; otherwise 10 min after a 50, else 5.
    var nextBreak: TimeInterval {
        if s.count > 0 && s.count % Self.longBreakEvery == 0 { return Self.longBreak }
        return (s.minutes ?? 25) >= 50 ? Self.deepBreak : Self.shortBreak
    }

    mutating func startBreak(now: Date) {
        s.phase = nextBreak == Self.longBreak ? .longBreak : .shortBreak
        s.end = now + nextBreak
    }

    /// No pause: stopping focus throws the pomodoro away; otherwise it skips the break.
    mutating func stop() { s.phase = .idle }

    mutating func resetCount(now: Date) {
        s.day = dayKey(now)
        s.count = 0
    }

    /// Ends whatever phase has run out by `now`, so sleep or a relaunch catches up.
    mutating func tick(now: Date) -> [Event] {
        var events: [Event] = []
        if s.phase == .focus, now >= s.end {
            let day = dayKey(s.end)
            if s.day != day { s.day = day; s.count = 0 }
            s.count += 1
            s.phase = .finished
            events.append(.focusDone)
        }
        if s.phase.isBreak, now >= s.end {
            s.phase = .idle
            events.append(.breakDone)
        }
        let today = dayKey(now)
        if s.day != today { s.day = today; s.count = 0 }
        return events
    }

    /// Whole seconds left, rounded up so a fresh 25 min pomodoro shows 25:00.
    func secondsLeft(now: Date) -> Int {
        s.phase.isCounting ? max(0, Int(s.end.timeIntervalSince(now).rounded(.up))) : 0
    }
}

func clock(_ seconds: Int) -> String {
    String(format: "%02d:%02d", seconds / 60, seconds % 60)
}
