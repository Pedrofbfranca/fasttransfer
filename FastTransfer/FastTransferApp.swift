import SwiftUI
import AppKit

@main
struct FastTransferApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var transferManager = TransferManager.shared
    @StateObject private var favoritesManager = FavoritesManager.shared
    @StateObject private var historyManager = HistoryManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(transferManager)
                .environmentObject(favoritesManager)
                .environmentObject(historyManager)
                .frame(minWidth: 700, minHeight: 500)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return TransferManager.shared.activeJobs.isEmpty
    }

    // Handle files passed via Quick Action / open URL
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        DispatchQueue.main.async {
            TransferManager.shared.addSources(urls)
        }
    }
}
