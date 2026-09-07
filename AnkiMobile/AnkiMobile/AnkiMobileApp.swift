//
//  AnkiMobileApp.swift
//  AnkiMobile
//

import SwiftUI
import SwiftData

@main
struct AnkiMobileApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: Deck.self, Card.self, ReviewLog.self, SyncState.self)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
        SampleData.seedIfNeeded(container.mainContext)
        SyncState.ensure(in: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .tint(Palette.primary)
        }
        .modelContainer(container)
    }
}
