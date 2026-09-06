//
//  Palette.swift
//  AnkiMobile
//
//  "Nocturne Focus" color system (see DESIGN.md).
//  Pure black and pure white are intentionally avoided.
//

import SwiftUI

extension Color {
    /// Creates a color from a hex string like "1c1d22" or "#1c1d22".
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        let r, g, b, a: UInt64
        switch cleaned.count {
        case 6: // RRGGBB
            (r, g, b, a) = (value >> 16, value >> 8 & 0xFF, value & 0xFF, 255)
        case 8: // RRGGBBAA
            (r, g, b, a) = (value >> 24, value >> 16 & 0xFF, value >> 8 & 0xFF, value & 0xFF)
        default:
            (r, g, b, a) = (0, 0, 0, 255)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

/// Central color palette. Every screen pulls from here.
enum Palette {
    // MARK: Surfaces (tonal layering, no harsh shadows)
    static let canvas = Color(hex: "16171a")          // Level 0 – ambient background
    static let surface = Color(hex: "1c1d22")         // Level 1 – decks, list containers
    static let surfaceElevated = Color(hex: "24262d") // Level 2 – active card, modals
    static let surfaceFloating = Color(hex: "2f313a") // Level 3 – popovers, docks
    static let surfaceLow = Color(hex: "1a1b1f")      // subtle inner fills

    // MARK: Typography grayscale
    static let textPrimary = Color(hex: "e2e4ea")     // muted pearl white
    static let textSecondary = Color(hex: "9ba1b0")   // soft silver slate
    static let textMuted = Color(hex: "6c7280")       // muted graphite

    // MARK: Functional study telemetry (desaturated accents)
    static let primary = Color(hex: "4f8cf6")   // cornflower blue – New / Good / navigation
    static let success = Color(hex: "52b788")   // sage green – Review (Due) / Easy
    static let warning = Color(hex: "e09f58")   // warm amber – Learning / Hard
    static let critical = Color(hex: "e06c75")  // coral rose – Again / destructive

    // MARK: Hairlines
    static let hairline = Color.white.opacity(0.07)
    static let hairlineStrong = Color.white.opacity(0.12)
}
