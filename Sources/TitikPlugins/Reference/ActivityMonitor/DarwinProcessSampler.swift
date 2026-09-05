import Foundation
import Darwin
import Darwin.libproc
import MachO

/// Represents a single active process discovered on the system.
public struct ProcessEntry: Identifiable, Hashable, Sendable {
    public let pid: pid_t
    public let name: String
    public let cpuPercent: Double
    public let memoryBytes: UInt64
    public let user: String
    public let isSystemProcess: Bool

    public var id: pid_t { pid }

    public init(
        pid: pid_t,
        name: String,
        cpuPercent: Double,
        memoryBytes: UInt64,
        user: String,
        isSystemProcess: Bool
    ) {
        self.pid = pid
        self.name = name
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.user = user
        self.isSystemProcess = isSystemProcess
    }
}

/// Host-level CPU and physical memory statistics.
public struct SystemVitals: Sendable, Equatable {
    public let overallCpuPercent: Double
    public let usedMemoryBytes: UInt64
    public let totalMemoryBytes: UInt64
    public let processCount: Int

    public init(
        overallCpuPercent: Double,
        usedMemoryBytes: UInt64,
        totalMemoryBytes: UInt64,
        processCount: Int
    ) {
        self.overallCpuPercent = overallCpuPercent
        self.usedMemoryBytes = usedMemoryBytes
        self.totalMemoryBytes = totalMemoryBytes
        self.processCount = processCount
    }
}

/// Supported termination signal categories.
public enum TerminationKind: String, Sendable, CaseIterable {
    case graceful
    case force

    public var signal: Int32 {
        switch self {
        case .graceful: return SIGTERM
        case .force: return SIGKILL
        }
    }

    public var displayName: String {
        switch self {
        case .graceful: return "Terminate"
        case .force: return "Force Kill"
        }
    }
}

/// Describes an action awaiting user confirmation.
public struct PendingConfirmation: Equatable, Sendable {
    public let action: TerminationKind
    public let target: ProcessEntry

    public init(action: TerminationKind, target: ProcessEntry) {
        self.action = action
        self.target = target
    }
}

/// Typed error cases for process signal operations.
public enum ProcessOperationError: Error, LocalizedError, Equatable, Sendable {
    case permissionDenied(pid: pid_t, name: String)
    case processNotFound(pid: pid_t)
    case systemCallFailed(errno: Int32)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied(let pid, let name):
            return "Permission denied: Cannot terminate \(name) (PID \(pid)). Requires elevated privileges."
        case .processNotFound(let pid):
            return "Process \(pid) not found. It may have already terminated."
        case .systemCallFailed(let errno):
            return "Process operation failed with system errno: \(errno)."
        }
    }
}

private struct ProcessCpuRecord {
    let cpuTimeNs: UInt64
    let timestamp: Date
}

private struct HostCpuRecord {
    let user: UInt32
    let system: UInt32
    let idle: UInt32
    let nice: UInt32
}

/// Native Darwin C API wrapper for non-blocking process sampling and host vitals collection.
public final class DarwinProcessSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var previousCpuRecords: [pid_t: ProcessCpuRecord] = [:]
    private var previousHostRecord: HostCpuRecord?
    private let hostPageSize: UInt64
    private let totalPhysicalMemory: UInt64

    public init() {
        var pageSize: vm_size_t = 0
        _ = host_page_size(mach_host_self(), &pageSize)
        self.hostPageSize = UInt64(pageSize > 0 ? pageSize : 4096)

        var memSize: UInt64 = 0
        var memLen = MemoryLayout<UInt64>.size
        var mib: [Int32] = [CTL_HW, HW_MEMSIZE]
        sysctl(&mib, 2, &memSize, &memLen, nil, 0)
        self.totalPhysicalMemory = memSize
    }

    /// Samples all active processes and host system vitals.
    public func sample() -> (processes: [ProcessEntry], vitals: SystemVitals) {
        let now = Date()
        let pids = enumerateActivePids()

        var processEntries: [ProcessEntry] = []
        processEntries.reserveCapacity(pids.count)

        lock.lock()
        var currentCpuRecords: [pid_t: ProcessCpuRecord] = [:]
        currentCpuRecords.reserveCapacity(pids.count)

        for pid in pids {
            guard let entry = sampleProcess(pid: pid, now: now, currentRecords: &currentCpuRecords) else {
                continue
            }
            processEntries.append(entry)
        }

        self.previousCpuRecords = currentCpuRecords
        let vitals = collectSystemVitals(processCount: processEntries.count)
        lock.unlock()

        return (processEntries, vitals)
    }

    /// Enumerate all active PIDs on macOS via `proc_listpids`.
    public func enumerateActivePids() -> [pid_t] {
        let count = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard count > 0 else { return [] }

        let numPids = Int(count) / MemoryLayout<pid_t>.stride
        var pids = [pid_t](repeating: 0, count: numPids)
        let bytesRead = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(MemoryLayout<pid_t>.stride * numPids))
        guard bytesRead > 0 else { return [] }

        let actualCount = Int(bytesRead) / MemoryLayout<pid_t>.stride
        return pids.prefix(actualCount).filter { $0 > 0 }
    }

    private func sampleProcess(
        pid: pid_t,
        now: Date,
        currentRecords: inout [pid_t: ProcessCpuRecord]
    ) -> ProcessEntry? {
        var taskInfo = proc_taskinfo()
        let size = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, Int32(MemoryLayout<proc_taskinfo>.size))
        guard size == MemoryLayout<proc_taskinfo>.size else { return nil }

        let totalCpuNs = taskInfo.pti_total_user + taskInfo.pti_total_system
        currentRecords[pid] = ProcessCpuRecord(cpuTimeNs: totalCpuNs, timestamp: now)

        let cpuPercent: Double
        if let prev = previousCpuRecords[pid] {
            let deltaCpu = Double(totalCpuNs >= prev.cpuTimeNs ? totalCpuNs - prev.cpuTimeNs : 0) / 1_000_000_000.0
            let deltaTime = now.timeIntervalSince(prev.timestamp)
            if deltaTime > 0 {
                cpuPercent = (deltaCpu / deltaTime) * 100.0
            } else {
                cpuPercent = 0.0
            }
        } else {
            cpuPercent = 0.0
        }

        let memoryBytes = taskInfo.pti_resident_size
        let name = Self.processName(for: pid)

        var bsdInfo = proc_bsdinfo()
        let bsdSize = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, Int32(MemoryLayout<proc_bsdinfo>.size))

        let user: String
        let isSystem: Bool
        if bsdSize == MemoryLayout<proc_bsdinfo>.size {
            let uid = bsdInfo.pbi_uid
            isSystem = (uid == 0 || pid < 100)
            if let pw = getpwuid(uid), let pwName = pw.pointee.pw_name {
                user = String(cString: pwName)
            } else {
                user = "\(uid)"
            }
        } else {
            user = "unknown"
            isSystem = (pid < 100)
        }

        return ProcessEntry(
            pid: pid,
            name: name,
            cpuPercent: cpuPercent,
            memoryBytes: memoryBytes,
            user: user,
            isSystemProcess: isSystem
        )
    }

    /// Resolves the process name using `proc_name` or `proc_pidpath`.
    public static func processName(for pid: pid_t) -> String {
        var nameBuffer = [CChar](repeating: 0, count: 1024)
        let nameLen = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
        if nameLen > 0 {
            let name = nameBuffer.withUnsafeBufferPointer { ptr -> String in
                guard let base = ptr.baseAddress else { return "" }
                return String(cString: base).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if !name.isEmpty {
                return name
            }
        }

        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let pathLen = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
        if pathLen > 0 {
            let fullPath = pathBuffer.withUnsafeBufferPointer { ptr -> String in
                guard let base = ptr.baseAddress else { return "" }
                return String(cString: base).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let baseName = (fullPath as NSString).lastPathComponent
            if !baseName.isEmpty {
                return baseName
            }
        }

        return "Process \(pid)"
    }

    /// Collects overall CPU load and physical RAM metrics via Mach host APIs.
    private func collectSystemVitals(processCount: Int) -> SystemVitals {
        var cpuPercent: Double = 0.0

        var cpuLoad = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &cpuLoad) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        if kr == KERN_SUCCESS {
            let u = cpuLoad.cpu_ticks.0
            let s = cpuLoad.cpu_ticks.1
            let i = cpuLoad.cpu_ticks.2
            let n = cpuLoad.cpu_ticks.3

            if let prev = previousHostRecord {
                let deltaUser = u >= prev.user ? u - prev.user : 0
                let deltaSystem = s >= prev.system ? s - prev.system : 0
                let deltaIdle = i >= prev.idle ? i - prev.idle : 0
                let deltaNice = n >= prev.nice ? n - prev.nice : 0
                let total = deltaUser + deltaSystem + deltaIdle + deltaNice
                if total > 0 {
                    let busy = deltaUser + deltaSystem + deltaNice
                    cpuPercent = (Double(busy) / Double(total)) * 100.0
                }
            }
            previousHostRecord = HostCpuRecord(user: u, system: s, idle: i, nice: n)
        }

        var usedMemory: UInt64 = 0
        var vmStats = vm_statistics64()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let vmKr = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vmCount)
            }
        }

        if vmKr == KERN_SUCCESS {
            let active = UInt64(vmStats.active_count)
            let wired = UInt64(vmStats.wire_count)
            let speculative = UInt64(vmStats.speculative_count)
            let compressor = UInt64(vmStats.compressor_page_count)
            usedMemory = (active + wired + speculative + compressor) * hostPageSize
        }

        return SystemVitals(
            overallCpuPercent: min(100.0, max(0.0, cpuPercent)),
            usedMemoryBytes: usedMemory,
            totalMemoryBytes: totalPhysicalMemory,
            processCount: processCount
        )
    }

    /// Sends a POSIX signal to the target process with typed error translation.
    public func killProcess(pid: pid_t, signal: Int32) -> Result<Void, ProcessOperationError> {
        let ret = Darwin.kill(pid, signal)
        if ret == 0 {
            return .success(())
        }

        let err = errno
        switch err {
        case EPERM:
            let name = Self.processName(for: pid)
            return .failure(.permissionDenied(pid: pid, name: name))
        case ESRCH:
            return .failure(.processNotFound(pid: pid))
        default:
            return .failure(.systemCallFailed(errno: err))
        }
    }
}
