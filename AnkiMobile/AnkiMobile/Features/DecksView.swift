//
//  DecksView.swift
//  AnkiMobile
//
//  Screen 1 — Decks Overview. Daily queue summary + hierarchical deck list.
//

import SwiftUI
import SwiftData

struct DecksView: View {
    /// Called when the user taps the sync/account controls — switches to the Sync tab.
    var onOpenSync: () -> Void = {}

    @Query(sort: \Deck.sortOrder) private var allDecks: [Deck]
    @State private var searchText = ""
    @State private var expandedDeckIDs: Set<UUID> = []

    private var topLevelDecks: [Deck] {
        allDecks
            .filter { $0.parent == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Daily queue only reflects decks you can actually study (i.e. downloaded ones).
    private var aggregate: QueueCounts {
        topLevelDecks
            .filter { $0.isDownloaded }
            .reduce(into: QueueCounts()) { total, deck in
                let counts = deck.counts()
                total.new += counts.new
                total.learning += counts.learning
                total.review += counts.review
            }
    }

    private var filteredDecks: [Deck] {
        guard !searchText.isEmpty else { return topLevelDecks }
        let query = searchText.lowercased()
        return topLevelDecks.filter { deck in
            deck.name.lowercased().contains(query)
                || deck.subdecks.contains { $0.name.lowercased().contains(query) }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Metrics.spaceMd) {
                    searchRow
                    DailyQueueCard(counts: aggregate)
                    decksSection
                    syncBanner
                }
                .padding(.horizontal, Metrics.screenMargin)
                .padding(.top, Metrics.spaceSm)
                .padding(.bottom, Metrics.space2xl)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.canvas.ignoresSafeArea())
            .navigationTitle("Decks")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { syncStatusPill }
                ToolbarItem(placement: .topBarTrailing) { avatar }
            }
            .navigationDestination(for: Deck.self) { deck in
                DeckDetailView(deck: deck)
            }
        }
    }

    // MARK: Toolbar

    private var syncStatusPill: some View {
        Button(action: onOpenSync) {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.icloud.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.success)
                Text("Synced")
                    .font(AppFont.labelSm)
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(.horizontal, Metrics.spaceSm)
            .padding(.vertical, 6)
            .background(Palette.surfaceElevated, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sync status: synced. Open Sync tab")
    }

    private var avatar: some View {
        Button(action: onOpenSync) {
            Image(systemName: "person.fill")
                .font(.system(size: 15))
                .foregroundStyle(Palette.primary)
                .frame(width: 30, height: 30)
                .background(Palette.primary.opacity(0.18), in: Circle())
                .overlay(Circle().strokeBorder(Palette.primary.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Account and sync. Open Sync tab")
    }

    // MARK: Search

    private var searchRow: some View {
        HStack(spacing: Metrics.spaceSm) {
            HStack(spacing: Metrics.spaceSm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Palette.textMuted)
                TextField("Search decks, tags, or notes…", text: $searchText)
                    .font(AppFont.bodySm)
                    .foregroundStyle(Palette.textPrimary)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, Metrics.spaceSm)
            .frame(height: Metrics.touchMin)
            .background(Palette.surfaceLow, in: RoundedRectangle(cornerRadius: Metrics.radiusPill, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radiusPill, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            )
        }
    }

    // MARK: Deck list

    private var decksSection: some View {
        VStack(alignment: .leading, spacing: Metrics.spaceSm) {
            SectionHeader(title: "Decks Available")
            if filteredDecks.isEmpty {
                emptyState
            } else {
                VStack(spacing: Metrics.spaceXs) {
                    ForEach(filteredDecks) { deck in
                        if deck.subdecks.isEmpty {
                            NavigationLink(value: deck) {
                                DeckRow(deck: deck)
                            }
                            .buttonStyle(.plain)
                        } else {
                            ExpandableDeckRow(
                                deck: deck,
                                isExpanded: expandedDeckIDs.contains(deck.id),
                                onToggle: { toggle(deck) }
                            )
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        let searching = !searchText.isEmpty
        VStack(spacing: Metrics.spaceSm) {
            Image(systemName: searching ? "magnifyingglass" : "square.stack.3d.up.slash")
                .font(.system(size: 34))
                .foregroundStyle(Palette.textMuted)
            Text(searching ? "No decks match your search" : "No decks yet")
                .font(AppFont.headlineSm)
                .foregroundStyle(Palette.textPrimary)
            Text(searching
                 ? "Try a different name or tag."
                 : "Pull decks from AnkiWeb in the Sync tab to get started.")
                .font(AppFont.bodySm)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
            if !searching {
                Button("Go to Sync", action: onOpenSync)
                    .font(AppFont.labelMd)
                    .foregroundStyle(Palette.primary)
                    .padding(.top, Metrics.space2xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Metrics.space2xl)
    }

    private func toggle(_ deck: Deck) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedDeckIDs.contains(deck.id) {
                expandedDeckIDs.remove(deck.id)
            } else {
                expandedDeckIDs.insert(deck.id)
            }
        }
    }

    // MARK: Footer banner

    private var syncBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Palette.success)
            Text("Last synced with AnkiWeb 4 mins ago • All media local")
                .font(AppFont.labelSm)
                .foregroundStyle(Palette.textMuted)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, Metrics.spaceMd)
        .frame(maxWidth: .infinity)
        .background(Palette.surfaceLow.opacity(0.7), in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
    }
}

// MARK: - Daily queue summary card

private struct DailyQueueCard: View {
    let counts: QueueCounts

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.spaceSm) {
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(Palette.primary)
                Text("Daily Queue")
                    .font(AppFont.headlineSm)
                    .foregroundStyle(Palette.textPrimary)
            }

            HStack(spacing: Metrics.spaceXs) {
                metric("NEW", counts.new, Palette.primary)
                metric("LEARNING", counts.learning, Palette.warning)
                metric("TO REVIEW", counts.review, Palette.success)
            }

            SegmentedProgressBar(counts: counts, height: 6)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard(cornerRadius: Metrics.radiusCard, fill: Palette.surface)
    }

    private func metric(_ label: String, _ value: Int, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(AppFont.labelSm)
                .tracking(0.8)
                .foregroundStyle(Palette.textMuted)
            Text("\(value)")
                .font(AppFont.monoMetric)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Metrics.spaceSm)
        .background(Palette.surfaceLow, in: RoundedRectangle(cornerRadius: Metrics.radiusPill, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radiusPill, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
    }
}

// MARK: - Deck rows

private struct DeckRow: View {
    let deck: Deck

    var body: some View {
        HStack(spacing: Metrics.spaceSm) {
            iconTile
            VStack(alignment: .leading, spacing: 3) {
                Text(deck.name)
                    .font(AppFont.headlineSm)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                if !deck.subtitle.isEmpty {
                    Text(deck.subtitle)
                        .font(AppFont.labelSm)
                        .foregroundStyle(Palette.textMuted)
                        .lineLimit(1)
                }
                StoragePill(deck: deck)
            }
            Spacer(minLength: Metrics.spaceXs)
            CountPills(counts: deck.counts())
        }
        .padding(Metrics.spaceSm)
        .frame(minHeight: 64)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.radiusDeckRow, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radiusDeckRow, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
    }

    private var iconTile: some View {
        Image(systemName: deck.iconSystemName)
            .font(.system(size: 18))
            .foregroundStyle(Palette.primary)
            .frame(width: 38, height: 38)
            .background(Palette.surfaceElevated, in: RoundedRectangle(cornerRadius: Metrics.radiusPill, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radiusPill, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            )
    }
}

private struct ExpandableDeckRow: View {
    let deck: Deck
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Chevron toggles the subdeck drawer; tapping the rest of the row opens
            // the parent deck's detail view (a parent deck is still a studyable deck).
            HStack(spacing: Metrics.spaceSm) {
                Button(action: onToggle) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.textMuted)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 28, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                NavigationLink(value: deck) {
                    HStack(spacing: Metrics.spaceSm) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(deck.name)
                                .font(AppFont.headlineSm)
                                .foregroundStyle(Palette.textPrimary)
                                .lineLimit(1)
                            Text(deck.subtitle)
                                .font(AppFont.labelSm)
                                .foregroundStyle(Palette.textMuted)
                                .lineLimit(1)
                            StoragePill(deck: deck)
                        }
                        Spacer(minLength: Metrics.spaceXs)
                        CountPills(counts: deck.counts())
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(Metrics.spaceSm)

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(deck.subdecks.sorted { $0.sortOrder < $1.sortOrder }) { sub in
                        NavigationLink(value: sub) {
                            SubdeckRow(deck: sub)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Palette.surfaceLow.opacity(0.6))
            }
        }
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.radiusDeckRow, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radiusDeckRow, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusDeckRow, style: .continuous))
    }
}

private struct SubdeckRow: View {
    let deck: Deck

    var body: some View {
        HStack(spacing: Metrics.spaceSm) {
            Image(systemName: deck.iconSystemName)
                .font(.system(size: 15))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 20)
            Text(deck.name)
                .font(AppFont.bodySm)
                .foregroundStyle(Palette.textPrimary)
            Spacer(minLength: Metrics.spaceXs)
            CountPills(counts: deck.counts(), compact: true)
        }
        .padding(.horizontal, Metrics.spaceMd)
        .padding(.vertical, Metrics.spaceSm)
        .overlay(alignment: .top) {
            Rectangle().fill(Palette.hairline).frame(height: 1)
        }
    }
}

#Preview {
    DecksView()
        .modelContainer(sampleContainer())
        .preferredColorScheme(.dark)
}
