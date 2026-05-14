import SwiftUI
import AppKit
import CoreText

enum AppFontRegistrar {
    static func registerFonts() {
        guard let url = Bundle.main.url(forResource: "Lobster-Regular", withExtension: "ttf") else {
            return
        }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private let splashIdentifier = NSUserInterfaceItemIdentifier("OdileSplashPanel")
    private var startupSplashPanel: NSPanel?
    private var colorsWindow: NSWindow?
    private var configuredWindows = Set<ObjectIdentifier>()
    private var isLaunchSplashCompleted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        showStartupSplash()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.hideMainWindows()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            self.completeStartupSplash()
        }
    }

    func showColorsWindow() {
        if colorsWindow == nil {
            let hostingController = NSHostingController(
                rootView: MusicEDLColorsView()
                    .frame(minWidth: 500, minHeight: 660)
            )

            let window = NSWindow(contentViewController: hostingController)
            window.title = ""
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.tabbingMode = .disallowed
            window.isReleasedWhenClosed = false
            window.isMovableByWindowBackground = true
            window.backgroundColor = .clear
            window.isOpaque = false
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            colorsWindow = window
        }

        if let visibleFrame = NSScreen.main?.visibleFrame {
            let width: CGFloat = 520
            let height = min(visibleFrame.height, 760)
            let frame = NSRect(
                x: visibleFrame.minX + 28,
                y: visibleFrame.maxY - height - 28,
                width: width,
                height: height
            )
            colorsWindow?.setFrame(frame, display: false)
        }

        colorsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func configureMainWindow(_ window: NSWindow) {
        guard window.identifier != splashIdentifier else { return }

        let windowID = ObjectIdentifier(window)
        let isFirstConfiguration = configuredWindows.insert(windowID).inserted

        window.title = "Odile"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.collectionBehavior = [.fullScreenNone]
        window.tabbingMode = .disallowed
        window.isMovableByWindowBackground = false
        window.backgroundColor = .clear
        window.appearance = NSAppearance(named: .darkAqua)
        window.isOpaque = false
        window.hasShadow = true
        window.toolbar?.showsBaselineSeparator = false
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.cornerRadius = AppTheme.cardCornerRadius
        window.contentView?.layer?.masksToBounds = true

        window.contentMinSize = NSSize(width: 1080, height: 620)
        window.contentMaxSize = NSSize(width: 1400, height: 900)

        if isFirstConfiguration {
            fitWindow(window, preferredContentSize: NSSize(width: 1220, height: 720))

            if !isLaunchSplashCompleted {
                window.alphaValue = 0
                window.orderOut(nil)
            }
        }
    }

    private func showStartupSplash() {
        guard startupSplashPanel == nil else { return }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 360),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.identifier = splashIdentifier
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: GogoMusicSplashView())
        panel.center()
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        startupSplashPanel = panel
    }

    private func completeStartupSplash() {
        guard !isLaunchSplashCompleted else { return }

        isLaunchSplashCompleted = true
        revealMainWindows()

        guard let panel = startupSplashPanel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self, weak panel] in
            Task { @MainActor in
                panel?.orderOut(nil)
                panel?.close()
                self?.startupSplashPanel = nil
            }
        }
    }

    private func hideMainWindows() {
        guard !isLaunchSplashCompleted else { return }

        for window in mainAppWindows {
            configureMainWindow(window)
            window.alphaValue = 0
            window.orderOut(nil)
        }
    }

    private func revealMainWindows() {
        for window in mainAppWindows {
            configureMainWindow(window)
            window.alphaValue = 0
            window.makeKeyAndOrderFront(nil)

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                window.animator().alphaValue = 1
            }
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    private var mainAppWindows: [NSWindow] {
        NSApp.windows.filter { window in
            window.identifier != splashIdentifier && !(window is NSPanel)
        }
    }

    private func fitWindow(_ window: NSWindow, preferredContentSize: NSSize) {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1400, height: 900)
        let width = min(preferredContentSize.width, max(1080, visibleFrame.width - 80))
        let height = min(preferredContentSize.height, max(620, visibleFrame.height - 80))

        window.setContentSize(NSSize(width: width, height: height))
        window.center()
    }
}

@main
struct OdileApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        AppFontRegistrar.registerFonts()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appDelegate)
                .frame(
                    minWidth: 1080,
                    idealWidth: 1220,
                    minHeight: 620,
                    idealHeight: 720
                )
                .background(
                    WindowAccessor { window in
                        appDelegate.configureMainWindow(window)
                    }
                )
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .toolbar) {
                Divider()
                Button("Colors") {
                    appDelegate.showColorsWindow()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }
        }
    }
}

private struct GogoMusicSplashView: View {
    var body: some View {
        ZStack {
            RadialGradient(
                colors: [
                    AppTheme.accent.opacity(0.26),
                    AppTheme.backgroundTop.opacity(0.08),
                    .clear
                ],
                center: .center,
                startRadius: 10,
                endRadius: 210
            )

            Image("LogoGogoLabs")
                .resizable()
                .scaledToFit()
                .frame(width: 250, height: 250)
                .shadow(color: AppTheme.accent.opacity(0.35), radius: 30, x: 0, y: 16)
        }
        .frame(width: 360, height: 360)
        .background(Color.clear)
    }
}

private struct WindowAccessor: NSViewRepresentable {
    let callback: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                callback(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                callback(window)
            }
        }
    }
}
