import Foundation
import SwiftUI
import AppKit
import TitikCore
import TitikKeymap
import TitikUI

/// Column identifier for sorting processes.
public enum ProcessSortColumn: String, CaseIterable, Sendable {
    case cpu = "CPU"
    case memory = "Memory"
    case pid = "PID"
    case name = "Name"
}

/// `@MainActor` observable view model driving the Activity Monitor dynamic UI.
@MainActor
public final class ActivityMonitorViewModel: ObservableObject {
    @Published public var processes: [ProcessEntry] = []
    @Published public var filteredProcesses: [ProcessEntry] = []
    @Published public var systemVitals: SystemVitals? = nil
    @Published public var searchQuery: String = "" {
        didSet {
            lastInteractionDate = Date()
            applyFilter()
        }
    }
    @Published public var selectedIndex: Int = 0 {
        didSet {
            if selectedIndex >= 0 && selectedIndex < filteredProcesses.count {
                selectedPid = filteredProcesses[selectedIndex].pid
            }
        }
    }
    @Published public var sortColumn: ProcessSortColumn = .cpu
    @Published public var sortAscending: Bool = false
    @Published public var pendingConfirmation: PendingConfirmation? = nil {
        didSet {
            updateKeymapScope()
        }
    }
    @Published public var statusMessage: String? = nil
    @Published public var isSampling: Bool = false

    public let keymapScope = PluginKeymapScope()
    public var onDismiss: (@MainActor () -> Void)?

    public let sampler: DarwinProcessSampler
    public var selectedPid: pid_t?

    private var samplingTask: Task<Void, Never>?
    private var lastInteractionDate: Date = .distantPast
    private let interactionPauseThreshold: TimeInterval = 3.0

    public init(sampler: DarwinProcessSampler = DarwinProcessSampler(), autoStart: Bool = false) {
        self.sampler = sampler
        self.updateKeymapScope()
        if autoStart {
            self.start()
        }
    }

    deinit {
        samplingTask?.cancel()
    }

    /// Starts periodic background sampling on a 1.5-second interval.
    public func start() {
        guard samplingTask == nil else { return }
        samplingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.performSample()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    /// Stops periodic sampling.
    public func stop() {
        samplingTask?.cancel()
        samplingTask = nil
    }

    /// Performs an immediate sample pass.
    public func sampleNow() {
        Task { [weak self] in
            await self?.performSample()
        }
    }

    private func performSample() async {
        isSampling = true
        let localSampler = self.sampler

        let (sampledProcesses, vitals) = await Task.detached(priority: .userInitiated) {
            localSampler.sample()
        }.value

        guard !Task.isCancelled else { return }

        self.systemVitals = vitals
        self.updateProcesses(newProcesses: sampledProcesses)
        self.isSampling = false
    }

    /// Updates internal process list, respecting active search and navigation lock.
    public func updateProcesses(newProcesses: [ProcessEntry]) {
        let isActivelyInteracting = !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty ||
            Date().timeIntervalSince(lastInteractionDate) < interactionPauseThreshold

        if isActivelyInteracting && !processes.isEmpty {
            // Preserve current visual order; update metrics for existing entries, append new, remove dead
            let newMap = Dictionary(uniqueKeysWithValues: newProcesses.map { ($0.pid, $0) })
            var updated: [ProcessEntry] = []
            var seenPids = Set<pid_t>()

            for existing in processes {
                if let latest = newMap[existing.pid] {
                    updated.append(latest)
                    seenPids.insert(existing.pid)
                }
            }

            for latest in newProcesses where !seenPids.contains(latest.pid) {
                updated.append(latest)
            }
            self.processes = updated
        } else {
            self.processes = sortProcesses(newProcesses)
        }

        applyFilter()
    }

    /// Sorts a collection of processes according to active sort column and order.
    private func sortProcesses(_ list: [ProcessEntry]) -> [ProcessEntry] {
        list.sorted { first, second in
            switch sortColumn {
            case .cpu:
                return sortAscending ? first.cpuPercent < second.cpuPercent : first.cpuPercent > second.cpuPercent
            case .memory:
                return sortAscending ? first.memoryBytes < second.memoryBytes : first.memoryBytes > second.memoryBytes
            case .pid:
                return sortAscending ? first.pid < second.pid : first.pid > second.pid
            case .name:
                let result = first.name.localizedCaseInsensitiveCompare(second.name)
                return sortAscending ? result == .orderedAscending : result == .orderedDescending
            }
        }
    }

    /// Toggles the sort column cyclically: CPU -> Memory -> PID -> Name -> CPU.
    public func toggleSort() {
        switch sortColumn {
        case .cpu:
            sortColumn = .memory
            sortAscending = false
        case .memory:
            sortColumn = .pid
            sortAscending = true
        case .pid:
            sortColumn = .name
            sortAscending = true
        case .name:
            sortColumn = .cpu
            sortAscending = false
        }
        self.processes = sortProcesses(self.processes)
        applyFilter()
    }

    /// Applies in-memory case-insensitive search filter across process names and PIDs.
    public func applyFilter() {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if trimmed.isEmpty {
            self.filteredProcesses = processes
        } else {
            self.filteredProcesses = processes.filter { process in
                process.name.lowercased().contains(trimmed) ||
                String(process.pid).contains(trimmed) ||
                process.user.lowercased().contains(trimmed)
            }
        }

        // Restore or clamp selection
        if let targetPid = selectedPid, let idx = filteredProcesses.firstIndex(where: { $0.pid == targetPid }) {
            self.selectedIndex = idx
        } else if !filteredProcesses.isEmpty {
            self.selectedIndex = min(max(0, self.selectedIndex), filteredProcesses.count - 1)
            self.selectedPid = filteredProcesses[self.selectedIndex].pid
        } else {
            self.selectedIndex = 0
            self.selectedPid = nil
        }
    }

    // MARK: - Navigation

    public func selectPrevious() {
        lastInteractionDate = Date()
        guard !filteredProcesses.isEmpty else { return }
        selectedIndex = max(0, selectedIndex - 1)
        selectedPid = filteredProcesses[selectedIndex].pid
    }

    public func selectNext() {
        lastInteractionDate = Date()
        guard !filteredProcesses.isEmpty else { return }
        selectedIndex = min(filteredProcesses.count - 1, selectedIndex + 1)
        selectedPid = filteredProcesses[selectedIndex].pid
    }

    public var selectedProcess: ProcessEntry? {
        guard selectedIndex >= 0 && selectedIndex < filteredProcesses.count else { return nil }
        return filteredProcesses[selectedIndex]
    }

    // MARK: - Termination & Actions

    public func requestGracefulTerminate() {
        guard let target = selectedProcess else { return }
        pendingConfirmation = PendingConfirmation(action: .graceful, target: target)
    }

    public func requestForceKill() {
        guard let target = selectedProcess else { return }
        pendingConfirmation = PendingConfirmation(action: .force, target: target)
    }

    public func confirmPendingAction() {
        guard let pending = pendingConfirmation else { return }
        let target = pending.target
        let action = pending.action
        pendingConfirmation = nil

        let result = sampler.killProcess(pid: target.pid, signal: action.signal)
        switch result {
        case .success:
            statusMessage = "Sent \(action.displayName) to \(target.name) (PID \(target.pid))"
            sampleNow()
        case .failure(let error):
            statusMessage = error.localizedDescription
        }
    }

    public func cancelPendingAction() {
        pendingConfirmation = nil
    }

    // MARK: - Keymap Scope Handling

    public func updateKeymapScope() {
        keymapScope.removeAll()
        if pendingConfirmation != nil {
            keymapScope.register("y", label: "Confirm") { [weak self] in self?.confirmPendingAction() }
            keymapScope.register("↵", label: "Confirm") { [weak self] in self?.confirmPendingAction() }
            keymapScope.register("n", label: "Cancel") { [weak self] in self?.cancelPendingAction() }
            keymapScope.register("esc", label: "Cancel") { [weak self] in self?.cancelPendingAction() }
        } else {
            keymapScope.register("↑", label: "Navigate") { [weak self] in self?.selectPrevious() }
            keymapScope.register("↓") { [weak self] in self?.selectNext() }
            keymapScope.register("⌘K", label: "Kill") { [weak self] in self?.requestGracefulTerminate() }
            keymapScope.register("⌘⌫") { [weak self] in self?.requestGracefulTerminate() }
            keymapScope.register("⇧⌘⌫") { [weak self] in self?.requestForceKill() }
            keymapScope.register("⇥", label: "Sort") { [weak self] in self?.toggleSort() }
            keymapScope.register("esc", label: "Close") { [weak self] in self?.onDismiss?() }
        }
    }
}
