import Foundation
import Darwin

/// A process as one that cannot be confused with a later one: the pid comes back after
/// the process exits, the pid with its start time does not.
public struct ProcessIdentity: Equatable, Sendable {
    public let pid: Int32
    /// Seconds since 1970 (`kp_proc.p_starttime`).
    public let start: Double

    public init(pid: Int32, start: Double) {
        self.pid = pid
        self.start = start
    }

    /// Shells between Claude Code and its hook command: not the session's process.
    public static let shells: Set<String> = ["sh", "bash", "zsh", "dash", "fish", "ksh", "tcsh", "csh"]

    /// The Claude Code process from the hook's ancestors, nearest first: the first that is
    /// not a shell (`claude` or the `node` running it).
    public static func claude(among ancestors: [(identity: ProcessIdentity, name: String)]) -> ProcessIdentity? {
        ancestors.first { !shells.contains($0.name) && $0.identity.pid > 1 }?.identity
    }

    /// The running process with this pid, or nil when there is none. A process that is
    /// exiting or exited but not yet reaped counts as none: WebStorm leaves a closed tab's
    /// Claude Code like that (`?E` in `ps`), and no exit event comes for it.
    public static func running(_ pid: Int32) -> (identity: ProcessIdentity, name: String, parent: Int32)? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0, info.kp_proc.p_pid == pid,
              !isEnding(stat: info.kp_proc.p_stat, flags: info.kp_proc.p_flag) else { return nil }
        let t = info.kp_proc.p_starttime
        let name = withUnsafeBytes(of: info.kp_proc.p_comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return (ProcessIdentity(pid: pid, start: Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000), name, info.kp_eproc.e_ppid)
    }

    /// `SZOMB`, or `P_WEXIT` set: on its way out.
    static func isEnding(stat: CChar, flags: Int32) -> Bool {
        stat == 5 || flags & 0x0000_2000 != 0
    }

    /// Still the same process. `startTime` stands in for the system in tests.
    public func isAlive(startTime: (Int32) -> Double? = { ProcessIdentity.running($0)?.identity.start }) -> Bool {
        guard let now = startTime(pid) else { return false }
        return abs(now - start) < 1
    }
}
