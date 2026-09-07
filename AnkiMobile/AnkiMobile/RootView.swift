//
//  RootView.swift
//  AnkiMobile
//
//  Bottom tab navigation: Decks and Sync.
//

import SwiftUI
import SwiftData

struct RootView: View {
    private enum Tab: Hashable {
        case decks
        case sync
    }

    @State private var selection: Tab = .decks
    /// Shared login state across both tabs (Decks pill reflects it; Sync tab owns login).
    @State private var auth = AuthController(engine: MockSyncEngine())

    var body: some View {
        TabView(selection: $selection) {
            DecksView(onOpenSync: { selection = .sync })
                .tag(Tab.decks)
                .tabItem {
                    Label("Decks", systemImage: "rectangle.stack.fill")
                }
            SyncView()
                .tag(Tab.sync)
                .tabItem {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                }
        }
        .tint(Palette.primary)
        .environment(auth)
    }
}

#Preview {
    RootView()
        .modelContainer(sampleContainer())
        .environment(AuthController(engine: MockSyncEngine()))
        .preferredColorScheme(.dark)
}
