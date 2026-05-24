import AppKit

final class SystemMonitorStatusView: NSControl {
    private static let statusWidth: CGFloat = 213

    private let iconView = NSImageView()
    private let downLabel = NSTextField(labelWithString: "--")
    private let upLabel = NSTextField(labelWithString: "--")
    private let cpuValueLabel = NSTextField(labelWithString: "--")
    private let ramValueLabel = NSTextField(labelWithString: "--")
    private let ssdValueLabel = NSTextField(labelWithString: "--")
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func update(snapshot: MetricSnapshot) {
        downLabel.stringValue = "↓ \(snapshot.networkDownRate.statusRateString)"
        upLabel.stringValue = "↑ \(snapshot.networkUpRate.statusRateString)"
        cpuValueLabel.stringValue = snapshot.cpuUsage.percentString
        ramValueLabel.stringValue = snapshot.memoryUsage.percentString
        ssdValueLabel.stringValue = snapshot.diskAvailable.statusBytesString
    }

    override func mouseDown(with event: NSEvent) {
        isHighlighted = true
    }

    override func mouseUp(with event: NSEvent) {
        isHighlighted = false

        guard bounds.contains(convert(event.locationInWindow, from: nil)) else {
            return
        }

        guard let action else {
            return
        }

        NSApp.sendAction(action, to: target, from: self)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.11).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        frame = NSRect(x: 0, y: 0, width: Self.statusWidth, height: NSStatusBar.system.thickness)
        toolTip = "System Monitor"

        iconView.image = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "System Monitor")
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        iconView.contentTintColor = .labelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let networkStack = NSStackView(views: [downLabel, upLabel])
        networkStack.orientation = .vertical
        networkStack.alignment = .leading
        networkStack.spacing = -2
        networkStack.translatesAutoresizingMaskIntoConstraints = false

        let metricsStack = NSStackView(views: [
            metricStack(title: "CPU", valueLabel: cpuValueLabel),
            metricStack(title: "RAM", valueLabel: ramValueLabel),
            metricStack(title: "SSD", valueLabel: ssdValueLabel)
        ])
        metricsStack.orientation = .horizontal
        metricsStack.alignment = .centerY
        metricsStack.spacing = 5
        metricsStack.translatesAutoresizingMaskIntoConstraints = false

        let rootStack = NSStackView(views: [iconView, networkStack, metricsStack])
        rootStack.orientation = .horizontal
        rootStack.alignment = .centerY
        rootStack.spacing = 6
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(rootStack)

        [downLabel, upLabel, cpuValueLabel, ramValueLabel, ssdValueLabel].forEach(configureValueLabel)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.statusWidth),
            heightAnchor.constraint(equalToConstant: NSStatusBar.system.thickness),
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            rootStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            networkStack.widthAnchor.constraint(equalToConstant: 54),
            iconView.widthAnchor.constraint(equalToConstant: 17),
            iconView.heightAnchor.constraint(equalToConstant: 17)
        ])
    }

    private func metricStack(title: String, valueLabel: NSTextField) -> NSStackView {
        let titleLabel = NSTextField(labelWithString: title)
        configureTitleLabel(titleLabel)

        let stack = NSStackView(views: [titleLabel, valueLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = -2
        stack.widthAnchor.constraint(equalToConstant: title == "SSD" ? 42 : 31).isActive = true
        return stack
    }

    private func configureTitleLabel(_ label: NSTextField) {
        label.font = .monospacedDigitSystemFont(ofSize: 8, weight: .semibold)
        label.textColor = .labelColor
        label.alignment = .left
        label.lineBreakMode = .byClipping
        label.allowsDefaultTighteningForTruncation = true
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private func configureValueLabel(_ label: NSTextField) {
        label.font = .monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
        label.textColor = .labelColor
        label.alignment = .left
        label.lineBreakMode = .byClipping
        label.allowsDefaultTighteningForTruncation = true
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
    }
}
