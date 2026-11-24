import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Обложки кэшируются на диск — повторно не качаются.
        URLCache.shared = URLCache(memoryCapacity: 64 << 20, diskCapacity: 512 << 20)
    }

    // Крестик закрывает окно — и вместе с ним приложение.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // При выходе гасим все «игры», чтобы в Discord не остался висеть статус.
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { Runner.shared.stopAll() }
    }
}

@main
struct EmbersApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = GameStore()
    @ObservedObject private var runner = Runner.shared

    var body: some Scene {
        Window("Embers", id: "main") {
            ContentView()
                .environmentObject(store)
                .environmentObject(runner)
                .frame(minWidth: 760, minHeight: 600)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1040, height: 780)
    }
}
