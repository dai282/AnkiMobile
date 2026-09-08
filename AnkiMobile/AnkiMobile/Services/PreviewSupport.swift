//
//  PreviewSupport.swift
//  AnkiMobile
//
//  Helpers used only by SwiftUI #Preview blocks.
//

import SwiftData

/// An in-memory model container pre-seeded with sample data, for previews.
@MainActor
func sampleContainer() -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    // swiftlint:disable:next force_try
    let container = try! ModelContainer(for: Deck.self, Card.self, ReviewLog.self, SyncState.self, configurations: config)
    SampleData.seed(container.mainContext)
    return container
}

/// The first leaf deck (Pharmacology) from a seeded container, for detail/study previews.
@MainActor
func samplePharmacologyDeck(in container: ModelContainer) -> Deck {
    let decks = (try? container.mainContext.fetch(FetchDescriptor<Deck>())) ?? []
    return decks.first { $0.name == "Pharmacology" } ?? decks.first!
}
