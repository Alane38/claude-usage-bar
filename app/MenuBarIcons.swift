import AppKit

/// Dessin des icônes de la barre de menu. Les couleurs de piste sont résolues au dessin (clair/sombre).
enum MenuBarIcons {
    static func color(for tone: UsageTone) -> NSColor {
        switch tone {
        case .ok:      return NSColor(red: 0.13, green: 0.77, blue: 0.37, alpha: 1)
        case .warning: return NSColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1)
        case .danger:  return NSColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1)
        case .stale:   return NSColor.secondaryLabelColor
        }
    }

    /// Anneau externe : semaine. Anneau interne : session.
    static func dualRing(session: Double, weekly: Double, sessionTone: UsageTone, weeklyTone: UsageTone) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            drawRing(center: center, radius: 7.6, width: 2, percent: weekly, color: color(for: weeklyTone))
            drawRing(center: center, radius: 4.0, width: 2, percent: session, color: color(for: sessionTone))
            return true
        }
        image.isTemplate = false
        return image
    }

    /// Deux barres fines : session au-dessus, semaine en dessous.
    static func twoValues(session: Double, weekly: Double, sessionTone: UsageTone, weeklyTone: UsageTone) -> NSImage {
        let image = NSImage(size: NSSize(width: 24, height: 14), flipped: false) { rect in
            drawBar(in: NSRect(x: 0, y: 8, width: rect.width, height: 4), percent: session, color: color(for: sessionTone))
            drawBar(in: NSRect(x: 0, y: 2, width: rect.width, height: 4), percent: weekly, color: color(for: weeklyTone))
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func track() -> NSColor { NSColor.labelColor.withAlphaComponent(0.25) }

    private static func drawRing(center: NSPoint, radius: CGFloat, width: CGFloat, percent: Double, color: NSColor) {
        let trackPath = NSBezierPath()
        trackPath.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        trackPath.lineWidth = width
        track().setStroke()
        trackPath.stroke()

        let fraction = min(max(percent, 0), 100) / 100
        guard fraction > 0 else { return }
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 360 * fraction, clockwise: true)
        arc.lineWidth = width
        arc.lineCapStyle = .round
        color.setStroke()
        arc.stroke()
    }

    private static func drawBar(in rect: NSRect, percent: Double, color: NSColor) {
        track().setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
        let fraction = min(max(percent, 0), 100) / 100
        guard fraction > 0 else { return }
        var filled = rect
        filled.size.width = max(rect.width * fraction, rect.height)
        color.setFill()
        NSBezierPath(roundedRect: filled, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
    }
}
