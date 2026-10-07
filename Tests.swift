import Foundation

@main
struct Tests {
    static func main() {
        var failures = 0
        func check(_ ok: Bool, _ what: String, line: Int = #line) {
            if !ok { failures += 1; print("FAIL Tests.swift:\(line) \(what)") }
        }

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let m: TimeInterval = 60
        let noon = Date(timeIntervalSince1970: 1_699_963_200)      // 2023-11-14 12:00 UTC
        let midnight = Date(timeIntervalSince1970: 1_700_006_400)  // 2023-11-15 00:00 UTC
        func fresh() -> Pomodoro {
            var p = Pomodoro()
            p.cal = utc
            _ = p.tick(now: noon)
            return p
        }

        // Countdown display
        var p = fresh()
        check(p.s.day == "2023-11-14" && p.s.count == 0, "first tick sets today")
        p.start(minutes: 25, now: noon)
        check(p.s.phase == .focus, "start enters focus")
        check(clock(p.secondsLeft(now: noon)) == "25:00", "fresh pomodoro shows 25:00")
        check(clock(p.secondsLeft(now: noon + 0.4)) == "25:00", "partial second rounds up")
        check(clock(p.secondsLeft(now: noon + 1)) == "24:59", "one second later shows 24:59")
        check(p.tick(now: noon + 24 * m).isEmpty, "nothing happens before the end")

        // Focus ends: count +1, then wait for the user; the break starts only when asked
        check(p.tick(now: noon + 25 * m) == [.focusDone], "focus ends on time")
        check(p.s.count == 1 && p.s.phase == .finished, "count 1, waiting for the user")
        check(p.tick(now: noon + 90 * m).isEmpty && p.s.phase == .finished, "break never starts by itself")
        check(p.secondsLeft(now: noon + 90 * m) == 0, "nothing counts down while waiting")
        p.startBreak(now: noon + 90 * m)
        check(p.s.phase == .shortBreak && p.s.end == noon + 95 * m, "short break is 5 min from when it's started")
        check(p.tick(now: noon + 95 * m) == [.breakDone], "break ends")
        check(p.s.phase == .idle && p.secondsLeft(now: noon + 95 * m) == 0, "idle after break")

        // 15 minute pomodoro
        p = fresh()
        p.start(minutes: 15, now: noon)
        check(p.tick(now: noon + 14 * m).isEmpty, "15 min not done at 14")
        check(p.tick(now: noon + 15 * m) == [.focusDone], "15 min done at 15")

        // 50 min pomodoro gets a 10 min break
        p = fresh()
        p.start(minutes: 50, now: noon)
        check(p.tick(now: noon + 49 * m).isEmpty, "50 min not done at 49")
        check(p.tick(now: noon + 50 * m) == [.focusDone], "50 min done at 50")
        check(p.nextBreak == Pomodoro.deepBreak, "50 min offers 10 min break")
        p.startBreak(now: noon + 50 * m)
        check(p.s.phase == .shortBreak && p.s.end == noon + 60 * m, "break after 50 is 10 min")
        p = fresh()
        p.start(minutes: 25, now: noon)
        _ = p.tick(now: noon + 25 * m)
        check(p.nextBreak == Pomodoro.shortBreak, "25 min offers 5 min break")

        // Every 4th pomodoro gets the long break
        p = fresh()
        p.s.count = 3
        p.start(minutes: 25, now: noon)
        _ = p.tick(now: noon + 25 * m)
        check(p.s.count == 4 && p.nextBreak == Pomodoro.longBreak, "4th pomodoro offers long break")
        p.startBreak(now: noon + 25 * m)
        check(p.s.phase == .longBreak && p.s.end == noon + 40 * m, "long break is 15 min")
        p = fresh()
        p.s.count = 3
        p.start(minutes: 50, now: noon)
        _ = p.tick(now: noon + 50 * m)
        check(p.nextBreak == Pomodoro.longBreak, "4th pomodoro gets long break after a 50 too")

        // Stop discards the pomodoro; skipping or stopping a break keeps the count
        p = fresh()
        p.start(minutes: 25, now: noon)
        p.stop()
        check(p.tick(now: noon + 26 * m).isEmpty && p.s.count == 0 && p.s.phase == .idle, "stop discards pomodoro")
        p = fresh()
        p.start(minutes: 25, now: noon)
        _ = p.tick(now: noon + 25 * m)
        p.stop()
        check(p.s.phase == .idle && p.s.count == 1, "skipping break keeps the count")
        p.startBreak(now: noon + 30 * m)
        p.stop()
        check(p.s.phase == .idle && p.s.count == 1, "stopping a running break keeps the count")

        // Asleep through the end: still counted, and the question is waiting on wake
        p = fresh()
        p.start(minutes: 25, now: noon)
        check(p.tick(now: noon + 180 * m) == [.focusDone], "long sleep finishes the pomodoro once")
        check(p.s.count == 1 && p.s.phase == .finished, "long sleep counts pomodoro and waits")

        // Break running when asleep: wakes to the right time left
        p = fresh()
        p.start(minutes: 25, now: noon)
        _ = p.tick(now: noon + 25 * m)
        p.startBreak(now: noon + 25 * m)
        _ = p.tick(now: noon + 27 * m)
        check(p.s.phase == .shortBreak && clock(p.secondsLeft(now: noon + 27 * m)) == "03:00", "wake mid-break")

        // Count resets at midnight
        p = fresh()
        p.s.count = 7
        _ = p.tick(now: midnight - 1)
        check(p.s.count == 7, "count kept before midnight")
        _ = p.tick(now: midnight)
        check(p.s.count == 0 && p.s.day == "2023-11-15", "count reset at midnight")

        // Pomodoro finishing after midnight counts for the new day
        p = fresh()
        p.s.count = 7
        p.start(minutes: 25, now: midnight - 10 * m)
        _ = p.tick(now: midnight + 15 * m)
        check(p.s.count == 1 && p.s.day == "2023-11-15", "post-midnight pomodoro counts for new day")

        // Waiting past midnight: count resets, so the next break is a short one
        p = fresh()
        p.s.count = 3
        p.start(minutes: 25, now: midnight - 30 * m)
        _ = p.tick(now: midnight - 5 * m)
        check(p.s.count == 4 && p.nextBreak == Pomodoro.longBreak, "4th of the day offers long break")
        _ = p.tick(now: midnight + 5 * m)
        check(p.s.phase == .finished && p.s.count == 0 && p.nextBreak == Pomodoro.shortBreak, "after midnight offers short break")

        // Manual reset
        p = fresh()
        p.s.count = 5
        p.resetCount(now: noon)
        check(p.s.count == 0, "reset count")

        // Persistence survives relaunch; corrupt data is rejected instead of crashing
        p = fresh()
        p.start(minutes: 25, now: noon)
        let saved = try? JSONEncoder().encode(p.s)
        check(saved.flatMap { try? JSONDecoder().decode(State.self, from: $0) } == p.s, "state round-trips")
        check((try? JSONDecoder().decode(State.self, from: Data("garbage".utf8))) == nil, "corrupt state rejected")
        let old = Data(#"{"phase":"finished","end":0,"day":"2023-11-14","count":2}"#.utf8)  // saved before `minutes` existed
        p.s = (try? JSONDecoder().decode(State.self, from: old)) ?? State()
        check(p.s.phase == .finished && p.s.count == 2 && p.nextBreak == Pomodoro.shortBreak, "older saved state still loads")

        if failures > 0 {
            print("\(failures) test(s) failed")
            exit(1)
        }
        print("All tests passed")
    }
}
