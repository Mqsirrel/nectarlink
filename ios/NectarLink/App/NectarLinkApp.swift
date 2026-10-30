import SwiftUI

@main
struct NectarLinkApp: App {
    @StateObject private var store = CoreStore.shared
    @StateObject private var theme = ThemeManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(store: store, theme: theme)
                .onAppear {
                    store.startIfNeeded()
                }
                .onOpenURL { url in
                    handleIncomingUrl(url)
                }
                .onChange(of: scenePhase) { newPhase in
                    if newPhase == .active {
                        store.refresh()
                        store.consumeSharedInboxIfNeeded()
                    }
                }
        }
    }

    private func handleIncomingUrl(_ url: URL) {
        let raw = url.absoluteString
        if raw.lowercased().hasPrefix("nectarlink://pair") {
            store.joinPairing(link: raw)
        } else if raw.lowercased().hasPrefix("nectarlink://share") {
            store.consumeSharedInboxIfNeeded()
        } else if url.isFileURL, let pc = store.activePc {
            store.sendFiles(to: pc.id, urls: [url], handoff: false)
        }
    }
}
