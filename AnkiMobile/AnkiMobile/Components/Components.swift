//
//  Components.swift
//  AnkiMobile
//
//  Small reusable views and modifiers shared across screens.
//

import SwiftUI

// MARK: - Surface card container

private struct SurfaceCardModifier: ViewModifier {
    var padding: CGFloat
    var cornerRadius: CGFloat
    var fill: Color
    var border: Color

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(fill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            )
    }
}

extension View {
    /// Wraps content in a tonal surface with a hairline border (see DESIGN.md elevation).
    func surfaceCard(
        padding: CGFloat = Metrics.spaceMd,
        cornerRadius: CGFloat = Metrics.radiusDeckRow,
        fill: Color = Palette.surface,
        border: Color = Palette.hairline
    ) -> some View {
        modifier(SurfaceCardModifier(padding: padding, cornerRadius: cornerRadius, fill: fill, border: border))
    }
}

// MARK: - Count pills (New / Learn / Due)

struct CountPills: View {
    let counts: QueueCounts
    var compact: Bool = false

    var body: some View {
        HStack(spacing: Metrics.spaceSm) {
            value(counts.new, Palette.primary)
            value(counts.learning, Palette.warning)
            value(counts.review, Palette.success)
        }
    }

    private func value(_ number: Int, _ color: Color) -> some View {
        Text("\(number)")
            .font(compact ? AppFont.monoSm : AppFont.mono)
            .foregroundStyle(color)
    }
}

// MARK: - Tri-color proportional bar

struct SegmentedProgressBar: View {
    let counts: QueueCounts
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let total = CGFloat(max(1, counts.total))
            HStack(spacing: 0) {
                segment(color: Palette.primary, part: counts.new, total: total, width: geo.size.width)
                segment(color: Palette.warning, part: counts.learning, total: total, width: geo.size.width)
                segment(color: Palette.success, part: counts.review, total: total, width: geo.size.width)
                Spacer(minLength: 0)
            }
        }
        .frame(height: height)
        .background(Palette.surfaceLow)
        .clipShape(Capsule())
    }

    private func segment(color: Color, part: Int, total: CGFloat, width: CGFloat) -> some View {
        color.frame(width: width * CGFloat(part) / total)
    }
}

// MARK: - Storage badge

struct StoragePill: View {
    let deck: Deck

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: deck.isDownloaded ? "checkmark.icloud.fill" : "icloud")
                .font(.system(size: 11))
            Text(label)
                .font(AppFont.labelSm)
        }
        .foregroundStyle(deck.isDownloaded ? Palette.success : Palette.textMuted)
        .padding(.horizontal, Metrics.spaceXs)
        .padding(.vertical, 3)
        .background(
            (deck.isDownloaded ? Palette.success.opacity(0.12) : Palette.surfaceLow),
            in: Capsule()
        )
        .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
    }

    private var label: String {
        let size = String(format: "%.0f MB", deck.sizeMB)
        return deck.isDownloaded ? "Downloaded (\(size))" : "Cloud Only (\(size))"
    }
}

// MARK: - Tag chip

struct TagChip: View {
    let text: String

    var body: some View {
        Text("#\(text)")
            .font(AppFont.monoSm)
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, Metrics.spaceSm)
            .padding(.vertical, 5)
            .background(Palette.surfaceElevated, in: RoundedRectangle(cornerRadius: Metrics.radiusMicro, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radiusMicro, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            )
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(AppFont.labelSm)
            .tracking(1.2)
            .foregroundStyle(Palette.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Metrics.space2xs)
    }
}
