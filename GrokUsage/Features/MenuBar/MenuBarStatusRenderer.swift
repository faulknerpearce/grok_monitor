import AppKit
import SwiftUI

/// Renders the menu bar status as a single bitmap.
/// MenuBarExtra drops GeometryReader / Circle SwiftUI, so we draw explicitly.
enum MenuBarStatusRenderer {
    static func image(
        snapshot: WeeklyUsageSnapshot?,
        isSignedIn: Bool,
        showBar: Bool,
        showCategories: Bool,
        visibleProductIDs: Set<String>
    ) -> NSImage {
        let height: CGFloat = 22
        let font = NSFont.systemFont(ofSize: 13.5, weight: .semibold)
        let smallFont = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        let textColor = NSColor.black
        let iconSize: CGFloat = 16
        let barWidth: CGFloat = 48
        let barHeight: CGFloat = 8
        let dotSize: CGFloat = 7
        let gap: CGFloat = 7

        if !isSignedIn || snapshot == nil {
            return unsignedImage(height: height, font: font, textColor: textColor, iconSize: iconSize)
        }

        let snap = snapshot!
        let products = menuBarProducts(from: snap, visibleProductIDs: visibleProductIDs)
        // Menu bar shows used % (matches Settings → Usage).
        let usedText = "\(Int(snap.usedPercent.rounded()))%"

        var width: CGFloat = iconSize
        width += gap + usedText.size(withAttributes: [.font: font]).width
        if showBar { width += gap + barWidth }

        if showCategories {
            for product in products {
                let label = "\(ProductCatalog.shortName(for: product.id)) \(Int(product.percentOfPool.rounded()))%"
                width += gap + dotSize + 4 + label.size(withAttributes: [.font: smallFont]).width
            }
        }

        width = ceil(width + 2)
        let image = NSImage(size: NSSize(width: width, height: height))
        image.isTemplate = false

        image.lockFocus()
        defer { image.unlockFocus() }
        NSGraphicsContext.current?.imageInterpolation = .high

        var x: CGFloat = 0
        let midY = height / 2

        drawGrokIcon(in: NSRect(x: 0, y: midY - iconSize / 2, width: iconSize, height: iconSize))
        x = iconSize + gap

        let usedAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        let usedSize = usedText.size(withAttributes: usedAttrs)
        usedText.draw(
            at: NSPoint(x: x, y: midY - usedSize.height / 2 - 0.5),
            withAttributes: usedAttrs
        )
        x += usedSize.width + gap

        if showBar {
            let barRect = NSRect(x: x, y: midY - barHeight / 2, width: barWidth, height: barHeight)
            NSColor.black.withAlphaComponent(0.14).setFill()
            NSBezierPath(roundedRect: barRect, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()

            let segments = products.isEmpty
                ? [ProductUsage(id: "used", displayName: "Used", percentOfPool: snap.usedPercent, colorToken: .chat)]
                : products
            var segX = barRect.minX
            let clip = NSBezierPath(roundedRect: barRect, xRadius: barHeight / 2, yRadius: barHeight / 2)
            for product in segments {
                let segW = barRect.width * CGFloat(min(100, max(0, product.percentOfPool)) / 100)
                guard segW > 0.5 else { continue }
                let segRect = NSRect(x: segX, y: barRect.minY, width: segW, height: barRect.height)
                nsColor(product.colorToken).setFill()
                NSGraphicsContext.saveGraphicsState()
                clip.addClip()
                NSBezierPath(rect: segRect).fill()
                NSGraphicsContext.restoreGraphicsState()
                segX += segW
            }
            x += barWidth + gap
        }

        if showCategories {
            for product in products {
                let dotRect = NSRect(x: x, y: midY - dotSize / 2, width: dotSize, height: dotSize)
                nsColor(product.colorToken).setFill()
                NSBezierPath(ovalIn: dotRect).fill()
                x += dotSize + 4

                let label = "\(ProductCatalog.shortName(for: product.id)) \(Int(product.percentOfPool.rounded()))%"
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: smallFont,
                    .foregroundColor: textColor
                ]
                let labelSize = label.size(withAttributes: attrs)
                label.draw(
                    at: NSPoint(x: x, y: midY - labelSize.height / 2 - 0.5),
                    withAttributes: attrs
                )
                x += labelSize.width + gap
            }
        }

        return image
    }

    /// Official Grok singularity mark (not the prohibition / "do not enter" circle-slash).
    private static let grokIconTemplate: NSImage? = {
        guard let image = NSImage(named: "MenuBarIcon") else { return nil }
        let copy = (image.copy() as? NSImage) ?? image
        copy.isTemplate = true
        return copy
    }()

    private static func drawGrokIcon(in rect: NSRect) {
        if let icon = grokIconTemplate {
            NSGraphicsContext.saveGraphicsState()
            NSColor.black.set()
            icon.size = rect.size
            icon.draw(
                in: rect,
                from: NSRect(origin: .zero, size: icon.size),
                operation: .sourceOver,
                fraction: 1.0,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
            NSGraphicsContext.restoreGraphicsState()
            return
        }

        drawGrokIconVector(in: rect)
    }

    /// Fallback geometry matching `MenuBarIcon.pdf` (16×16 artboard, official Grok mark).
    private static func drawGrokIconVector(in rect: NSRect) {
        let s = min(rect.width, rect.height) / 16
        let ox = rect.midX - 8 * s
        let oy = rect.midY - 8 * s

        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: ox + x * s, y: oy + y * s)
        }

        let path = NSBezierPath()

        // Upper/right arm of the singularity mark
        path.move(to: p(6.385, 6.066))
        path.line(to: p(11.104, 9.554))
        path.curve(to: p(11.777, 9.393), controlPoint1: p(11.336, 9.725), controlPoint2: p(11.666, 9.659))
        path.curve(to: p(10.943, 5.153), controlPoint1: p(12.357, 7.992), controlPoint2: p(12.098, 6.309))
        path.curve(to: p(6.714, 4.321), controlPoint1: p(9.789, 3.997), controlPoint2: p(8.182, 3.743))
        path.line(to: p(5.110, 3.577))
        path.curve(to: p(11.950, 4.141), controlPoint1: p(7.411, 2.003), controlPoint2: p(10.204, 2.392))
        path.curve(to: p(13.362, 9.121), controlPoint1: p(13.335, 5.528), controlPoint2: p(13.763, 7.417))
        path.line(to: p(13.366, 9.118))
        path.curve(to: p(14.993, 14.668), controlPoint1: p(12.785, 11.621), controlPoint2: p(13.509, 12.622))
        path.curve(to: p(15.098, 14.815), controlPoint1: p(15.028, 14.716), controlPoint2: p(15.063, 14.765))
        path.line(to: p(13.146, 12.859))
        path.line(to: p(13.146, 12.866))
        path.line(to: p(6.383, 6.065))
        path.close()

        // Lower/left arm of the singularity mark
        path.move(to: p(5.411, 5.218))
        path.curve(to: p(5.453, 10.651), controlPoint1: p(3.759, 6.797), controlPoint2: p(4.044, 9.241))
        path.curve(to: p(9.692, 11.494), controlPoint1: p(6.495, 11.694), controlPoint2: p(8.202, 12.120))
        path.line(to: p(11.292, 12.234))
        path.curve(to: p(10.210, 12.824), controlPoint1: p(11.004, 12.442), controlPoint2: p(10.634, 12.667))
        path.curve(to: p(4.441, 11.662), controlPoint1: p(8.294, 13.614), controlPoint2: p(5.999, 13.221))
        path.curve(to: p(3.281, 5.887), controlPoint1: p(2.943, 10.162), controlPoint2: p(2.472, 7.855))
        path.curve(to: p(1.896, 2.324), controlPoint1: p(3.885, 4.415), controlPoint2: p(2.894, 3.375))
        path.curve(to: p(0.902, 1.185), controlPoint1: p(1.542, 1.952), controlPoint2: p(1.187, 1.580))
        path.line(to: p(5.409, 5.217))
        path.close()

        NSColor.black.setFill()
        path.fill()
    }

    private static func unsignedImage(
        height: CGFloat,
        font: NSFont,
        textColor: NSColor,
        iconSize: CGFloat
    ) -> NSImage {
        let label = "Grok"
        let labelWidth = label.size(withAttributes: [.font: font]).width
        let width = iconSize + 6 + labelWidth + 2
        let image = NSImage(size: NSSize(width: width, height: height))
        image.isTemplate = false
        image.lockFocus()
        drawGrokIcon(in: NSRect(x: 0, y: (height - iconSize) / 2, width: iconSize, height: iconSize))
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        let size = label.size(withAttributes: attrs)
        label.draw(
            at: NSPoint(x: iconSize + 6, y: (height - size.height) / 2 - 0.5),
            withAttributes: attrs
        )
        image.unlockFocus()
        return image
    }

    private static func menuBarProducts(
        from snapshot: WeeklyUsageSnapshot,
        visibleProductIDs: Set<String>
    ) -> [ProductUsage] {
        let byID = Dictionary(
            snapshot.products.map { ($0.id.lowercased(), $0) },
            uniquingKeysWith: { _, last in last }
        )
        return ProductCatalog.displayOrder.compactMap { id in
            guard visibleProductIDs.contains(id),
                  let product = byID[id],
                  product.percentOfPool > 0.05
            else { return nil }
            return product
        }
    }

    private static func nsColor(_ token: ProductColor) -> NSColor {
        let c = token.sRGB
        return NSColor(calibratedRed: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
    }
}
