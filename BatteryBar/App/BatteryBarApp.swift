import AppKit
import SwiftUI
import Combine

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    let updateChecker = UpdateChecker()

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var cancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "--"
            button.target = self
            button.action = #selector(togglePopover)
        }

        popover = NSPopover()
        popover.behavior = .transient
        let checker = updateChecker
        let panelController = NSHostingController(
            rootView: DetailPanel(appState: appState, updateChecker: updateChecker)
                .task { await checker.checkIfNeeded() }
        )

        panelController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = panelController

        cancellable = appState.$smoothedReading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] reading in
                self?.updateStatusBar(reading)
            }

        appState.start()
        CrashGuard.install()
    }

    private func updateStatusBar(_ reading: BatteryReading?) {
        guard let button = statusItem.button else { return }
        if let r = reading {
            button.image = MenuBarRenderer.renderLabel(r)
            button.title = ""
        } else {
            button.image = nil
            button.title = "--"
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        CrashGuard.markCleanExit()
        appState.prepareForTermination()
    }
}

@main
enum BatteryBarMain {
    @MainActor
    static func main() {
        // Recovery helpers must not create app state or write battery history.
        CrashGuard.handleHelperInvocationIfNeeded()
        BatteryBarApp.main()
    }
}

struct BatteryBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
