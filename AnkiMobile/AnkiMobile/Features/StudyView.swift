//
//  StudyView.swift
//  AnkiMobile
//
//  Screens 3 & 4 — Study session. Front (question) → Show Answer → 4-button grading.
//  Ratings are applied through the SM-2 Scheduler and persisted immediately.
//

import SwiftUI
import SwiftData

struct StudyView: View {
    let deck: Deck
    let mode: StudyMode

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var queue: [Card] = []
    @State private var index = 0
    @State private var showingAnswer = false
    @State private var started = false
    @State private var startedWithCards = false
    /// When the current card first appeared — used to record answer time.
    @State private var cardShownAt = Date.now

    private let scheduler = Scheduler.shared

    private var current: Card? { index < queue.count ? queue[index] : nil }

    private var remaining: QueueCounts {
        guard index < queue.count else { return QueueCounts() }
        var counts = QueueCounts()
        for card in queue[index...] {
            switch card.state {
            case .new: counts.new += 1
            case .learning: counts.learning += 1
            case .review: counts.review += 1
            }
        }
        return counts
    }

    var body: some View {
        ZStack {
            Palette.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                if let card = current {
                    ScrollView {
                        CardFace(card: card, showingAnswer: showingAnswer, onToggleStar: { toggleStar(card) }, onToggleFlag: { toggleFlag(card) })
                            .padding(.horizontal, Metrics.screenMargin)
                            .padding(.top, Metrics.spaceSm)
                            .id(card.id)
                            .transition(.opacity)
                    }
                    ratingTray(for: card)
                } else {
                    completionView
                }
            }
        }
        .onAppear {
            guard !started else { return }
            queue = deck.studyQueue(mode: mode)
            startedWithCards = !queue.isEmpty
            started = true
            cardShownAt = .now
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        VStack(spacing: Metrics.spaceSm) {
            HStack(spacing: Metrics.spaceSm) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(Palette.surfaceElevated, in: RoundedRectangle(cornerRadius: Metrics.radiusSmall, style: .continuous))
                }
                .accessibilityLabel("End study session")
                VStack(alignment: .leading, spacing: 1) {
                    Text("STUDY SESSION")
                        .font(AppFont.labelSm)
                        .tracking(1)
                        .foregroundStyle(Palette.textMuted)
                    Text(deck.subtitle.isEmpty ? deck.name : deck.subtitle)
                        .font(AppFont.headlineSm)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                }
                Spacer()
            }

            HStack {
                HStack(spacing: 6) {
                    counterPill(remaining.new, "New", Palette.primary)
                    counterPill(remaining.learning, "Learn", Palette.warning)
                    counterPill(remaining.review, "Due", Palette.success)
                }
                Spacer()
                if !queue.isEmpty {
                    Text("Card \(min(index + 1, queue.count))/\(queue.count)")
                        .font(AppFont.monoSm)
                        .foregroundStyle(Palette.textMuted)
                }
            }
        }
        .padding(.horizontal, Metrics.screenMargin)
        .padding(.top, Metrics.spaceSm)
        .padding(.bottom, Metrics.spaceSm)
    }

    private func counterPill(_ value: Int, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(value)").font(AppFont.mono).foregroundStyle(color)
            Text(label).font(AppFont.labelSm).foregroundStyle(color.opacity(0.7))
        }
        .padding(.horizontal, Metrics.spaceXs)
        .padding(.vertical, 5)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: Metrics.radiusSmall, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radiusSmall, style: .continuous)
                .strokeBorder(color.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: Rating tray

    @ViewBuilder
    private func ratingTray(for card: Card) -> some View {
        VStack(spacing: 0) {
            Divider().overlay(Palette.hairline)
            if showingAnswer {
                let previews = scheduler.preview(card)
                HStack(spacing: Metrics.spaceXs) {
                    ForEach(Rating.allCases) { rating in
                        gradeButton(rating, interval: previews[rating]?.displayInterval ?? "")
                    }
                }
                .padding(.horizontal, Metrics.screenMargin)
                .padding(.top, Metrics.spaceSm)
                .padding(.bottom, Metrics.spaceLg)
            } else {
                Button(action: revealAnswer) {
                    HStack(spacing: 8) {
                        Image(systemName: "eye.fill")
                        Text("Show Answer")
                    }
                    .font(AppFont.headlineSm)
                    .foregroundStyle(Palette.canvas)
                    .frame(maxWidth: .infinity)
                    .frame(height: Metrics.touchComfortable)
                    .background(Palette.primary, in: RoundedRectangle(cornerRadius: Metrics.radiusPill, style: .continuous))
                }
                .padding(.horizontal, Metrics.screenMargin)
                .padding(.top, Metrics.spaceSm)
                .padding(.bottom, Metrics.spaceLg)
            }
        }
        .background(Palette.canvas)
    }

    private func gradeButton(_ rating: Rating, interval: String) -> some View {
        let color = accent(for: rating)
        return Button {
            rate(rating)
        } label: {
            VStack(spacing: 3) {
                Text(interval)
                    .font(AppFont.monoSm)
                    .foregroundStyle(color.opacity(0.8))
                Text(rating.title)
                    .font(AppFont.labelMd)
                    .foregroundStyle(color)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.touchComfortable)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: Metrics.radiusSmall, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radiusSmall, style: .continuous)
                    .strokeBorder(color.opacity(0.28), lineWidth: 1)
            )
        }
        .accessibilityLabel("\(rating.title), next review in \(interval)")
    }

    private func accent(for rating: Rating) -> Color {
        switch rating {
        case .again: return Palette.critical
        case .hard: return Palette.textSecondary
        case .good: return Palette.success
        case .easy: return Palette.primary
        }
    }

    // MARK: Completion

    private var completionView: some View {
        VStack(spacing: Metrics.spaceMd) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Palette.success)
                .accessibilityHidden(true)
            Text(startedWithCards ? "All caught up" : "Nothing due right now")
                .font(AppFont.headlineLg)
                .foregroundStyle(Palette.textPrimary)
            Text(startedWithCards
                 ? "You've cleared this session's queue."
                 : "This deck has no cards due. Check back later.")
                .font(AppFont.bodyMd)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button { dismiss() } label: {
                Text("Back to Deck")
                    .font(AppFont.headlineSm)
                    .foregroundStyle(Palette.canvas)
                    .frame(maxWidth: .infinity)
                    .frame(height: Metrics.touchComfortable)
                    .background(Palette.primary, in: RoundedRectangle(cornerRadius: Metrics.radiusPill, style: .continuous))
            }
            .padding(.horizontal, Metrics.screenMargin)
            .padding(.bottom, Metrics.spaceLg)
        }
        .onAppear { if startedWithCards { Haptics.success() } }
    }

    // MARK: Actions

    private func revealAnswer() {
        Haptics.impact(.light)
        withAnimation(.easeInOut(duration: 0.2)) { showingAnswer = true }
    }

    private func rate(_ rating: Rating) {
        guard let card = current else { return }
        Haptics.forRating(rating)

        // Capture the pre-review state so the log records the transition.
        let stateBefore = card.state
        let intervalBefore = card.interval

        scheduler.apply(rating, to: card, now: .now)
        card.markDirty()

        let elapsedMs = Int(Date.now.timeIntervalSince(cardShownAt) * 1000)
        let log = ReviewLog(
            card: card,
            rating: rating,
            lastInterval: intervalBefore,
            interval: card.interval,
            ease: card.ease,
            stateBefore: stateBefore,
            stateAfter: card.state,
            timeTakenMs: max(0, elapsedMs)
        )
        modelContext.insert(log)
        try? modelContext.save()

        // Cards still in learning reappear later in the same session.
        if card.state == .learning {
            queue.append(card)
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            showingAnswer = false
            index += 1
        }
        cardShownAt = .now
    }

    private func toggleStar(_ card: Card) {
        Haptics.impact(.light)
        card.isStarred.toggle()
        card.markDirty()
        try? modelContext.save()
    }

    private func toggleFlag(_ card: Card) {
        Haptics.impact(.light)
        card.isFlagged.toggle()
        card.markDirty()
        try? modelContext.save()
    }
}

// MARK: - Card face (front + revealed answer)

private struct CardFace: View {
    let card: Card
    let showingAnswer: Bool
    let onToggleStar: () -> Void
    let onToggleFlag: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
                .padding(.bottom, Metrics.spaceSm)
            Divider().overlay(Palette.hairline)

            // Question
            VStack(alignment: .leading, spacing: Metrics.spaceXs) {
                Text("PROMPT")
                    .font(AppFont.labelSm)
                    .tracking(1)
                    .foregroundStyle(Palette.textMuted)
                Text(card.front)
                    .font(AppFont.headlineMd)
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, showingAnswer ? Metrics.spaceMd : Metrics.space2xl)

            if showingAnswer {
                answerDivider
                VStack(alignment: .leading, spacing: Metrics.spaceSm) {
                    Text(card.back)
                        .font(AppFont.bodyMd)
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, Metrics.spaceXs)
                .padding(.bottom, Metrics.spaceMd)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Metrics.spaceLg)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.radiusCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radiusCard, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
    }

    private var toolbar: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(card.tags.prefix(3), id: \.self) { tag in
                    TagChip(text: tag)
                }
            }
            Spacer()
            HStack(spacing: 4) {
                iconButton("speaker.wave.2.fill", Palette.textMuted, label: "Play audio") {}
                iconButton(card.isStarred ? "star.fill" : "star",
                           card.isStarred ? Palette.warning : Palette.textMuted,
                           label: card.isStarred ? "Unstar card" : "Star card",
                           action: onToggleStar)
                iconButton(card.isFlagged ? "flag.fill" : "flag",
                           card.isFlagged ? Palette.critical : Palette.textMuted,
                           label: card.isFlagged ? "Unflag card" : "Flag card",
                           action: onToggleFlag)
            }
        }
    }

    private func iconButton(_ name: String, _ color: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 16))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
        }
        .accessibilityLabel(label)
    }

    private var answerDivider: some View {
        ZStack {
            Rectangle()
                .fill(
                    LinearGradient(colors: [.clear, Palette.primary.opacity(0.3), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .frame(height: 1)
            HStack(spacing: 4) {
                Image(systemName: "eye.fill").font(.system(size: 11))
                Text("ANSWER REVEALED")
                    .font(AppFont.labelSm)
                    .tracking(1)
            }
            .foregroundStyle(Palette.primary)
            .padding(.horizontal, Metrics.spaceSm)
            .padding(.vertical, 3)
            .background(Palette.surfaceElevated, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.primary.opacity(0.25), lineWidth: 1))
        }
    }
}

#Preview {
    let container = sampleContainer()
    return StudyView(deck: samplePharmacologyDeck(in: container), mode: .all)
        .modelContainer(container)
        .preferredColorScheme(.dark)
}
