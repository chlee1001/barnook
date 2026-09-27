import AppKit

/// Menu bar glyphs, not the app bundle icon. Each option uses a template image
/// so macOS can tint it for light and dark menu bars.
enum MenuBarIcon: String, CaseIterable {
    case nook
    case ellipsis
    case chevronLeft
    case chevronRight
    case dot
    case star

    var title: String {
        switch self {
        case .nook: "Nook"
        case .ellipsis: "Ellipsis"
        case .chevronLeft: "Left arrow"
        case .chevronRight: "Right arrow"
        case .dot: "Dot"
        case .star: "Star"
        }
    }

    @MainActor var image: NSImage {
        switch self {
        case .nook: Self.nookImage
        case .ellipsis: Self.ellipsisImage
        case .chevronLeft: Self.leftImage
        case .chevronRight: Self.rightImage
        case .dot: Self.dotImage
        case .star: Self.starImage
        }
    }

    @MainActor private static let ellipsisImage = symbol("ellipsis", pointSize: 16)
    @MainActor private static let leftImage = symbol("chevron.left", pointSize: 15, weight: .bold)
    @MainActor private static let rightImage = symbol("chevron.right", pointSize: 15)
    @MainActor private static let dotImage = symbol("circle.fill", pointSize: 6)
    @MainActor private static let starImage = symbol("star.fill", pointSize: 14)

    @MainActor private static func symbol(
        _ name: String, pointSize: CGFloat, weight: NSFont.Weight = .medium
    ) -> NSImage {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: weight))!
        image.isTemplate = true
        return image
    }

    /// A monochrome bar and sheltered item, matching the app icon.
    @MainActor private static let nookImage: NSImage = {
        let image = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { _ in
            NSColor.black.set()
            let nook = NSBezierPath()
            nook.lineWidth = 2
            nook.lineCapStyle = .round
            nook.move(to: NSPoint(x: 4.5, y: 4.5))
            nook.line(to: NSPoint(x: 4.5, y: 11))
            nook.curve(to: NSPoint(x: 15.5, y: 11), controlPoint1: NSPoint(x: 4.5, y: 18), controlPoint2: NSPoint(x: 15.5, y: 18))
            nook.line(to: NSPoint(x: 15.5, y: 4.5))
            nook.stroke()
            NSBezierPath(roundedRect: NSRect(x: 2, y: 13, width: 16, height: 2.5), xRadius: 1.25, yRadius: 1.25).fill()
            NSBezierPath(roundedRect: NSRect(x: 8.5, y: 6, width: 3, height: 3), xRadius: 0.8, yRadius: 0.8).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
