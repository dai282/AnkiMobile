//
//  DeckDetailView.swift
//  AnkiMobile
//
//  Screen 2 — Deck Details & study configuration.
//

import SwiftUI
import SwiftData

struct DeckDetailView: View {
    let deck: Deck

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    /// Observe cards so counts refresh immediately after study ratings.
    @Query private var allCards: [Card]

    @State private var studyMode: StudyMode?
    @State private var isDownloading = false

    private var counts: QueueCounts {
        // allCards is observed only to keep this reactive to rating changes; the actual
        // subtree counting + daily new-limit lives in Deck.counts(introducedToday:).
        _ = allCards
        return deck.counts(newStudiedByDeck: CollectionStore.newStudiedTodayByDeck())
    }

    /// Rough session-length estimate (~0.4 min per due card).
    private var estimatedMinutes: Int {
        max(1, Int((Double(counts.total) * 0.4).rounded()))
    }

    /// A subdeck whose parent hasn't been downloaded — can't be studied here.
    private var isLockedSubdeck: Bool {
        !deck.isTopLevel && !deck.isEffectivelyDownloaded
    }

    var body: some View {
        // A re-import (Download Decks) purges + re-inserts decks/cards, deleting the object this
        // pushed view is holding. Accessing a deleted model faults fatally, so bail to the fresh
        // (@Query-backed) deck list instead.
        if deck.modelContext == nil {
            Color.clear.onAppear { dismiss() }
        } else {
            content
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: Metrics.spaceMd) {
                identityBanner
                if isLockedSubdeck {
                    lockedSubdeckPrompt
                } else {
                    queueBreakdown
                    studySection
                }
            }
            .padding(.horizontal, Metrics.screenMargin)
            .padding(.vertical, Metrics.spaceMd)
        }
        .background(Palette.canvas.ignoresSafeArea())
        .navigationTitle(deck.name)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $studyMode) { mode in
            StudyView(deck: deck, mode: mode)
        }
    }

    // MARK: Identity banner

    private var identityBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(deck.subtitle.isEmpty ? deck.name : deck.subtitle)
                .font(AppFont.headlineLg)
                .foregroundStyle(Palette.textPrimary)
            HStack(spacing: 5) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.warning)
                Text(metaLine)
                    .font(AppFont.bodySm)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard(cornerRadius: Metrics.radiusCard, fill: Palette.surfaceLow)
    }

    private var metaLine: String {
        var parts: [String] = []
        if deck.isHighCadence { parts.append("High Cadence") }
        parts.append("\(deck.allCards.count) cards total")
        return parts.joined(separator: " · ")
    }

    // MARK: Queue breakdown

    private var queueBreakdown: some View {
        VStack(alignment: .leading, spacing: Metrics.spaceMd) {
            HStack {
                Text("Today's Queue")
                    .font(AppFont.headlineSm)
                    .foregroundStyle(Palette.textPrimary)
                Text("\(counts.total) Ready")
                    .font(AppFont.monoSm)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, Metrics.spaceXs)
                    .padding(.vertical, 3)
                    .background(Palette.surfaceElevated, in: Capsule())
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 12))
                    Text("~\(estimatedMinutes) mins")
                        .font(AppFont.monoSm)
                }
                .foregroundStyle(Palette.success)
                .padding(.horizontal, Metrics.spaceXs)
                .padding(.vertical, 4)
                .background(Palette.surfaceElevated, in: Capsule())
            }

            SegmentedProgressBar(counts: counts, height: 8)

            HStack(spacing: Metrics.spaceXs) {
                metricTile("New", counts.new, "Unseen cards", Palette.primary)
                metricTile("Learn", counts.learning, "Short intervals", Palette.warning)
                metricTile("Review", counts.review, "Due repetition", Palette.success)
            }
        }
        .surfaceCard(cornerRadius: Metrics.radiusCard)
    }

    private func metricTile(_ label: String, _ value: Int, _ caption: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(label)
                    .font(AppFont.labelSm)
                    .foregroundStyle(Palette.textSecondary)
            }
            Text("\(value)")
                .font(AppFont.headlineLg)
                .foregroundStyle(color)
            Text(caption)
                .font(AppFont.labelSm)
                .foregroundStyle(Palette.textMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Metrics.spaceSm)
        .background(Palette.surfaceLow, in: RoundedRectangle(cornerRadius: Metrics.radiusPill, style: .continuous))
    }

    // MARK: Study section

    /// Shown on a top-level deck: study when downloaded, otherwise offer to download.
    @ViewBuilder
    private var studySection: some View {
        if deck.isEffectivelyDownloaded {
            studyActions
        } else {
            downloadCTA
        }
    }

    /// Shown on a subdeck whose parent isn't downloaded — points the user to the parent.
    private var lockedSubdeckPrompt: some View {
        VStack(alignment: .leading, spacing: Metrics.spaceSm) {
            HStack(spacing: 6) {
                Image(systemName: "lock.icloud")
                    .foregroundStyle(Palette.textMuted)
                Text("Part of a Cloud Only deck")
                    .font(AppFont.headlineSm)
                    .foregroundStyle(Palette.textPrimary)
            }
            Text("Sub-decks download together with their parent. Download \(deck.rootDeck.name) to study this deck.")
                .font(AppFont.bodySm)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let parent = deck.parent {
                NavigationLink(value: parent) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.forward.square")
                        Text("Open \(parent.name)")
                    }
                    .font(AppFont.labelMd)
                    .foregroundStyle(Palette.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Palette.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: Metrics.radiusPill, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Metrics.radiusPill, style: .continuous)
                            .strokeBorder(Palette.primary.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard(cornerRadius: Metrics.radiusCard)
    }

    private var downloadCTA: some View {
        VStack(alignment: .leading, spacing: Metrics.spaceSm) {
            HStack(spacing: 6) {
                Image(systemName: "icloud")
                    .foregroundStyle(Palette.textMuted)
                Text("This deck is Cloud Only. Download it to study offline.")
                    .font(AppFont.bodySm)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: downloadDeck) {
                HStack(spacing: 8) {
                    Image(systemName: isDownloading ? "arrow.down.circle" : "icloud.and.arrow.down")
                        .rotationEffect(.degrees(isDownloading ? 360 : 0))
                        .animation(isDownloading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isDownloading)
                    Text(isDownloading ? "Downloading…" : String(format: "Download to Study · %.0f MB", deck.sizeMB))
                }
                .font(AppFont.headlineSm)
                .foregroundStyle(Palette.canvas)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Palette.primary, in: RoundedRectangle(cornerRadius: Metrics.radiusPill, style: .continuous))
            }
            .disabled(isDownloading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard(cornerRadius: Metrics.radiusCard)
    }

    private func downloadDeck() {
        isDownloading = true
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            deck.isDownloaded = true
            deck.markDirty()
            for sub in deck.subdecks {
                sub.isDownloaded = true
                sub.markDirty()
            }
            try? modelContext.save()
            isDownloading = false
        }
    }

    // MARK: Study actions

    private var studyActions: some View {
        VStack(spacing: Metrics.spaceXs) {
            Button {
                studyMode = .all
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text("Study All Due Cards (\(counts.total))")
                }
                .font(AppFont.headlineSm)
                .foregroundStyle(Palette.canvas)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Palette.primary, in: RoundedRectangle(cornerRadius: Metrics.radiusPill, style: .continuous))
            }
            .disabled(counts.total == 0)
            .opacity(counts.total == 0 ? 0.5 : 1)

            HStack(spacing: Metrics.spaceXs) {
                secondaryAction("New Only (\(counts.new))", "plus.circle", Palette.primary, .newOnly, enabled: counts.new > 0)
                secondaryAction("Reviews Only (\(counts.review))", "arrow.clockwise", Palette.success, .reviewsOnly, enabled: counts.review > 0)
            }
        }
    }

    private func secondaryAction(_ title: String, _ icon: String, _ color: Color, _ mode: StudyMode, enabled: Bool) -> some View {
        Button {
            studyMode = mode
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title).lineLimit(1)
            }
            .font(AppFont.labelMd)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Palette.surfaceElevated, in: RoundedRectangle(cornerRadius: Metrics.radiusPill, style: .continuous))
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }

}

// StudyMode drives .fullScreenCover(item:) so it must be Identifiable.
extension StudyMode: Identifiable {
    var id: Int {
        switch self {
        case .all: return 0
        case .newOnly: return 1
        case .reviewsOnly: return 2
        }
    }
}

#Preview {
    let container = sampleContainer()
    return NavigationStack {
        DeckDetailView(deck: samplePharmacologyDeck(in: container))
    }
    .modelContainer(container)
    .preferredColorScheme(.dark)
}
