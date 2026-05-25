import Combine
import Foundation

@MainActor
public final class SystemMonitor: ObservableObject {
    @Published public private(set) var snapshot = MetricSnapshot.placeholder

    private let provider = SystemMetricsProvider()
    private var timer: Timer?
    private var isRunning = false

    public init(snapshot: MetricSnapshot = .placeholder) {
        self.snapshot = snapshot
    }

    public func start() {
        guard !isRunning else {
            return
        }

        isRunning = true
        refresh()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard self?.isRunning == true else {
                    return
                }

                self?.refresh()
            }
        }
    }

    public func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    public func refresh() {
        snapshot = provider.sample()
    }
}
