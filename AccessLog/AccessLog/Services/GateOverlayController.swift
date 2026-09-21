import AppKit

/// Dark full-screen shields so the Access Log form is visible after login
/// even when macOS starts the app in the background.
@MainActor
final class GateOverlayController {
    static let shared = GateOverlayController()

    private var shields: [NSPanel] = []

    func show() {
        hide()
        for screen in NSScreen.screens {
            let panel = NSPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.normalWindow)) + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.isOpaque = false
            panel.backgroundColor = NSColor.black.withAlphaComponent(0.35)
            panel.hasShadow = false
            panel.ignoresMouseEvents = false
            panel.hidesOnDeactivate = false
            panel.isFloatingPanel = true
            panel.becomesKeyOnlyIfNeeded = true
            panel.isRestorable = false
            panel.setFrame(screen.frame, display: true)
            panel.orderFrontRegardless()
            shields.append(panel)
        }
    }

    func hide() {
        for panel in shields {
            panel.orderOut(nil)
            panel.close()
        }
        shields.removeAll()
    }
}
