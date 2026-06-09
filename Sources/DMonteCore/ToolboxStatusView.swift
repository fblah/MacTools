import AppKit

public final class ToolboxStatusView: NSControl {
    public static let statusWidth: CGFloat = 22

    public var onClick: (() -> Void)?

    private let image: NSImage
    private let highlightLayer = CALayer()
    private var trackingArea: NSTrackingArea?

    public init(image: NSImage) {
        self.image = image
        super.init(frame: NSRect(x: 0, y: 0, width: Self.statusWidth, height: NSStatusBar.system.thickness))
        wantsLayer = true
        highlightLayer.backgroundColor = NSColor.labelColor.withAlphaComponent(0.11).cgColor
        highlightLayer.cornerRadius = 6
        highlightLayer.masksToBounds = true
        highlightLayer.isHidden = true
        layer?.insertSublayer(highlightLayer, at: 0)
        toolTip = "D'Monte's Tool Box"
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current else {
            return
        }

        context.saveGraphicsState()
        image.isTemplate = true
        NSColor.labelColor.set()

        let imageSize = NSSize(width: 22, height: 22)
        let imageRect = NSRect(
            x: bounds.midX - imageSize.width / 2,
            y: bounds.midY - imageSize.height / 2,
            width: imageSize.width,
            height: imageSize.height
        )
        image.draw(in: imageRect)
        context.restoreGraphicsState()
    }

    public override func layout() {
        super.layout()
        highlightLayer.frame = bounds.insetBy(dx: 1, dy: 3)
    }

    public override func mouseDown(with event: NSEvent) {
        highlightLayer.isHidden = false
        onClick?()
    }

    public override func mouseUp(with event: NSEvent) {
        highlightLayer.isHidden = !isMouseInside
    }

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    public override func updateTrackingAreas() {
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

    public override func mouseEntered(with event: NSEvent) {
        highlightLayer.isHidden = false
    }

    public override func mouseExited(with event: NSEvent) {
        highlightLayer.isHidden = true
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    private var isMouseInside: Bool {
        guard let window else {
            return false
        }

        let mouseInWindow = window.mouseLocationOutsideOfEventStream
        let mouseInView = convert(mouseInWindow, from: nil)
        return bounds.contains(mouseInView)
    }
}
