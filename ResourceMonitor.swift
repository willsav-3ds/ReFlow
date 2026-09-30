import Foundation
import Darwin
import Combine

/// Samples this process's own memory footprint, CPU usage, and thread count straight
/// from the Mach kernel APIs — the same underlying data Activity Monitor and Xcode's own
/// memory/CPU gauges read. Only samples on a timer while something is actually watching
/// (see `startSampling`/`stopSampling`, driven by `DebugStatsWindowController`), so
/// leaving the debug window closed costs nothing beyond the last-known values sitting
/// unused in memory.
@MainActor
final class ResourceMonitor: ObservableObject {
    static let shared = ResourceMonitor()

    @Published private(set) var memoryFootprintMB: Double = 0
    @Published private(set) var cpuUsagePercent: Double = 0
    @Published private(set) var threadCount: Int = 0

    private var timer: Timer?
    private static let sampleInterval: TimeInterval = 1.0

    private init() {}

    func startSampling() {
        guard timer == nil else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: Self.sampleInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
    }

    func stopSampling() {
        timer?.invalidate()
        timer = nil
    }

    /// Forces an immediate sample outside the regular timer tick — used by
    /// `DebugStatsView`'s "Repoll" button, for when you want a fresh reading right now
    /// rather than waiting up to `sampleInterval` for the next automatic one.
    func resample() {
        sample()
    }

    private func sample() {
        memoryFootprintMB = Self.currentMemoryFootprintMB()
        let (cpu, threads) = Self.currentCPUUsageAndThreadCount()
        cpuUsagePercent = cpu
        threadCount = threads
    }

    /// `phys_footprint` from `TASK_VM_INFO` — the same number macOS uses for the memory
    /// figure shown in Activity Monitor and Xcode's memory gauge. Deliberately not
    /// `resident_size` from the older `TASK_BASIC_INFO`: that figure double-counts memory
    /// shared with the system and reads misleadingly high.
    private static func currentMemoryFootprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / 1024 / 1024
    }

    /// Sums each thread's `cpu_usage` (scaled against `TH_USAGE_SCALE`, the same way
    /// `top`/Activity Monitor derive a live per-process CPU%), rather than reading the
    /// cumulative user+system time `TASK_BASIC_INFO` reports — that figure only ever
    /// grows, so it would show total lifetime CPU seconds, not a live percentage.
    private static func currentCPUUsageAndThreadCount() -> (percent: Double, count: Int) {
        var threadsList: thread_act_array_t?
        var threadsCount: mach_msg_type_number_t = 0
        guard task_threads(mach_task_self_, &threadsList, &threadsCount) == KERN_SUCCESS,
              let threadsList else { return (0, 0) }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: threadsList),
                vm_size_t(Int(threadsCount) * MemoryLayout<thread_t>.stride)
            )
        }

        var totalUsage: Double = 0
        for i in 0..<Int(threadsCount) {
            var threadInfo = thread_basic_info()
            var threadInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)
            let infoResult = withUnsafeMutablePointer(to: &threadInfo) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(threadInfoCount)) {
                    thread_info(threadsList[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &threadInfoCount)
                }
            }
            guard infoResult == KERN_SUCCESS, threadInfo.flags & TH_FLAGS_IDLE == 0 else { continue }
            totalUsage += Double(threadInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100
        }
        return (totalUsage, Int(threadsCount))
    }
}
