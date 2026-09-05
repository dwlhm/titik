import SwiftUI
import AppKit
import TitikCore
import TitikUI

/// Primary SwiftUI presentation for Activity Monitor dynamic HUD.
public struct ActivityMonitorView: View {
    @ObservedObject public var viewModel: ActivityMonitorViewModel

    public init(viewModel: ActivityMonitorViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Vitals Panel
            headerVitalsPanel
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()
                .background(Color.white.opacity(0.12))

            // Confirmation Banner Modal (if active)
            if let pending = viewModel.pendingConfirmation {
                confirmationBanner(for: pending)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Status Message Toast
            if let status = viewModel.statusMessage {
                statusBanner(message: status)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
            }

            // Table Column Headers
            tableColumnHeaders
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)

            // Scrollable Process Table
            processTable
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(Theme.springInteractive, value: viewModel.pendingConfirmation != nil)
        .animation(Theme.springInteractive, value: viewModel.statusMessage != nil)
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
    }

    // MARK: - Header Vitals

    private var headerVitalsPanel: some View {
        HStack(spacing: 20) {
            // CPU Overall Meter
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "cpu")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.accent)
                    Text("CPU Load")
                        .font(Theme.fontFooterLabel)
                        .foregroundColor(Theme.textSecondary)
                    Spacer()
                    let cpuVal = viewModel.systemVitals?.overallCpuPercent ?? 0.0
                    Text(String(format: "%.1f%%", cpuVal))
                        .font(Theme.fontCode)
                        .foregroundColor(metricColor(for: cpuVal, warnThreshold: 60.0, alertThreshold: 85.0))
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.white.opacity(0.12))
                            .frame(height: 6)

                        let cpuVal = viewModel.systemVitals?.overallCpuPercent ?? 0.0
                        let width = max(0, min(geo.size.width * CGFloat(cpuVal / 100.0), geo.size.width))
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(metricColor(for: cpuVal, warnThreshold: 60.0, alertThreshold: 85.0))
                            .frame(width: width, height: 6)
                    }
                }
                .frame(height: 6)
            }

            // RAM Pressure Meter
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "memorychip")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.categoryClipboard)
                    Text("RAM Pressure")
                        .font(Theme.fontFooterLabel)
                        .foregroundColor(Theme.textSecondary)
                    Spacer()
                    let used = viewModel.systemVitals?.usedMemoryBytes ?? 0
                    let total = viewModel.systemVitals?.totalMemoryBytes ?? 1
                    let percent = total > 0 ? (Double(used) / Double(total)) * 100.0 : 0.0
                    Text("\(formatBytes(used)) / \(formatBytes(total)) (\(String(format: "%.0f%%", percent)))")
                        .font(Theme.fontCode)
                        .foregroundColor(metricColor(for: percent, warnThreshold: 75.0, alertThreshold: 90.0))
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.white.opacity(0.12))
                            .frame(height: 6)

                        let used = viewModel.systemVitals?.usedMemoryBytes ?? 0
                        let total = viewModel.systemVitals?.totalMemoryBytes ?? 1
                        let percent = total > 0 ? (Double(used) / Double(total)) * 100.0 : 0.0
                        let width = max(0, min(geo.size.width * CGFloat(percent / 100.0), geo.size.width))
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(metricColor(for: percent, warnThreshold: 75.0, alertThreshold: 90.0))
                            .frame(width: width, height: 6)
                    }
                }
                .frame(height: 6)
            }

            // Process Count Badge
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(viewModel.filteredProcesses.count)")
                    .font(Theme.fontBrand)
                    .foregroundColor(Theme.textPrimary)
                Text(viewModel.searchQuery.isEmpty ? "processes" : "matching")
                    .font(Theme.fontBadge)
                    .foregroundColor(Theme.textMuted)
            }
            .frame(minWidth: 55)
        }
    }

    // MARK: - Table Headers

    private var tableColumnHeaders: some View {
        HStack(spacing: 8) {
            Text("PID")
                .font(Theme.fontKeycap)
                .foregroundColor(viewModel.sortColumn == .pid ? Theme.accent : Theme.textMuted)
                .frame(width: 60, alignment: .leading)

            Text("PROCESS NAME")
                .font(Theme.fontKeycap)
                .foregroundColor(viewModel.sortColumn == .name ? Theme.accent : Theme.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 2) {
                if viewModel.sortColumn == .cpu {
                    Image(systemName: viewModel.sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8))
                }
                Text("CPU %")
                    .font(Theme.fontKeycap)
            }
            .foregroundColor(viewModel.sortColumn == .cpu ? Theme.accent : Theme.textMuted)
            .frame(width: 75, alignment: .trailing)

            HStack(spacing: 2) {
                if viewModel.sortColumn == .memory {
                    Image(systemName: viewModel.sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8))
                }
                Text("MEMORY")
                    .font(Theme.fontKeycap)
            }
            .foregroundColor(viewModel.sortColumn == .memory ? Theme.accent : Theme.textMuted)
            .frame(width: 85, alignment: .trailing)

            Text("USER")
                .font(Theme.fontKeycap)
                .foregroundColor(Theme.textMuted)
                .frame(width: 75, alignment: .trailing)
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Process Table

    private var processTable: some View {
        ScrollViewReader { proxy in
            #if os(macOS)
            if #available(macOS 14.0, *) {
                processScrollViewContent
                    .onChange(of: viewModel.selectedIndex) { _, newIdx in
                        scrollToIndex(newIdx, proxy: proxy)
                    }
            } else {
                processScrollViewContent
                    .onChange(of: viewModel.selectedIndex) { newIdx in
                        scrollToIndex(newIdx, proxy: proxy)
                    }
            }
            #else
            processScrollViewContent
            #endif
        }
    }

    private func scrollToIndex(_ newIdx: Int, proxy: ScrollViewProxy) {
        if newIdx >= 0 && newIdx < viewModel.filteredProcesses.count {
            let pid = viewModel.filteredProcesses[newIdx].pid
            withAnimation(.easeInOut(duration: 0.15)) {
                proxy.scrollTo(pid, anchor: .center)
            }
        }
    }

    private var processScrollViewContent: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 2) {
                if viewModel.filteredProcesses.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 20))
                            .foregroundColor(Theme.textMuted)
                        Text("No processes match '\(viewModel.searchQuery)'")
                            .font(Theme.fontRowSubtitle)
                            .foregroundColor(Theme.textMuted)
                    }
                    .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    ForEach(Array(viewModel.filteredProcesses.enumerated()), id: \.element.pid) { idx, process in
                        processRow(process: process, index: idx)
                            .id(process.pid)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func processRow(process: ProcessEntry, index: Int) -> some View {
        let isSelected = (index == viewModel.selectedIndex)

        return HStack(spacing: 8) {
            // PID
            Text("\(process.pid)")
                .font(Theme.fontCode)
                .foregroundColor(isSelected ? Theme.textPrimary : Theme.textMuted)
                .frame(width: 60, alignment: .leading)

            // Icon + Process Name
            HStack(spacing: 6) {
                Image(systemName: process.isSystemProcess ? "gearshape.2.fill" : "app.fill")
                    .font(.system(size: 11))
                    .foregroundColor(process.isSystemProcess ? Theme.categoryCommand : Theme.categoryApp)

                Text(process.name)
                    .font(Theme.fontRowTitle)
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // CPU %
            Text(String(format: "%.1f%%", process.cpuPercent))
                .font(Theme.fontCode)
                .foregroundColor(metricColor(for: process.cpuPercent, warnThreshold: 50.0, alertThreshold: 80.0))
                .frame(width: 75, alignment: .trailing)

            // Memory
            Text(formatBytes(process.memoryBytes))
                .font(Theme.fontCode)
                .foregroundColor(isSelected ? Theme.textPrimary : Theme.textSecondary)
                .frame(width: 85, alignment: .trailing)

            // User
            Text(process.user)
                .font(Theme.fontRowSubtitle)
                .foregroundColor(Theme.textMuted)
                .lineLimit(1)
                .frame(width: 75, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.selectionBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Theme.accent.opacity(0.4), lineWidth: 1)
                )
                .opacity(isSelected ? 1.0 : 0.0)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectedIndex = index
            viewModel.selectedPid = process.pid
        }
    }

    // MARK: - Confirmation Banner

    private func confirmationBanner(for pending: PendingConfirmation) -> some View {
        let isForce = (pending.action == .force)
        let alertColor = isForce ? Color.red : Color.orange

        return HStack(spacing: 12) {
            Image(systemName: isForce ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundColor(alertColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(pending.action.displayName): \(pending.target.name) (PID \(pending.target.pid))")
                    .font(Theme.fontRowTitle)
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.textPrimary)

                Text(isForce
                     ? "Force kill immediately terminates without saving application state."
                     : "Terminate sends graceful SIGTERM, allowing normal cleanup.")
                    .font(Theme.fontFooterLabel)
                    .foregroundColor(Theme.textSecondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    viewModel.confirmPendingAction()
                } label: {
                    HStack(spacing: 4) {
                        Text("Confirm")
                            .font(Theme.fontKeycap)
                            .foregroundColor(.white)
                        Text("[Y / ↵]")
                            .font(Theme.fontBadge)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(alertColor.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    viewModel.cancelPendingAction()
                } label: {
                    HStack(spacing: 4) {
                        Text("Cancel")
                            .font(Theme.fontKeycap)
                            .foregroundColor(Theme.textSecondary)
                        Text("[Esc / N]")
                            .font(Theme.fontBadge)
                            .foregroundColor(Theme.textMuted)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(alertColor.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(alertColor.opacity(0.5), lineWidth: 1)
                )
        )
    }

    // MARK: - Status Banner

    private func statusBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(Theme.accent)
            Text(message)
                .font(Theme.fontFooterLabel)
                .foregroundColor(Theme.textSecondary)
            Spacer()
            Button {
                viewModel.statusMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }

    // MARK: - Formatting Helpers

    private func metricColor(for value: Double, warnThreshold: Double, alertThreshold: Double) -> Color {
        if value >= alertThreshold {
            return Color.red
        } else if value >= warnThreshold {
            return Color.orange
        } else {
            return Theme.categoryClipboard
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
