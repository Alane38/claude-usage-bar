import AppKit
import SwiftUI

/// Mode développement : `ClaudeUsageBar --snapshot /chemin/popover.png [--settings]` rend le popover dans un PNG puis quitte.
/// Permet de vérifier l'interface sans cliquer dans la barre de menu.
enum Snapshot {
    static var outputPath: String? {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--snapshot"), flag + 1 < args.count else { return nil }
        return args[flag + 1]
    }

    static func write(view: some View, to path: String, size: NSSize) {
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height).background(Color(white: 0.11)))
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.appearance = NSAppearance(named: .darkAqua)
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
