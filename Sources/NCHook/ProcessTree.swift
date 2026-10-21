import Foundation
import Darwin
import MelyCore

enum ProcessTree {
    /// Bundle id of the nearest ancestor process that lives inside an `.app`
    /// (the terminal or IDE that started Claude Code), or nil.
    static func hostAppBundleId() -> String? {
        var pid = getppid()
        var hops = 0
        while pid > 1 && hops < 32 {
            if let path = executablePath(of: pid),
               let appPath = HookContext.appBundlePath(containing: path),
               let id = Bundle(path: appPath)?.bundleIdentifier {
                return id
            }
            guard let parent = parentPid(of: pid), parent != pid else { return nil }
            pid = parent
            hops += 1
        }
        return nil
    }

    /// "/dev/ttysNNN" of the nearest ancestor attached to a terminal (the hook's own stdio are pipes).
    static func controllingTTY() -> String? {
        var pid = getppid()
        for _ in 0..<8 where pid > 1 {
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.size
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
            guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return nil }
            let dev = info.kp_eproc.e_tdev
            if dev != -1, let name = devname(dev, S_IFCHR) {
                return "/dev/" + String(cString: name)
            }
            pid = info.kp_eproc.e_ppid
        }
        return nil
    }

    private static func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let n = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard n > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func parentPid(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }
}
