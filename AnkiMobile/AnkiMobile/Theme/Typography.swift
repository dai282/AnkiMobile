//
//  Typography.swift
//  AnkiMobile
//
//  Type scale from DESIGN.md. Manrope / JetBrains Mono are approximated with the
//  system font (SF Pro) and the monospaced system design until real fonts are bundled.
//

import SwiftUI

enum AppFont {
    // Manrope-style UI text
    static let display = Font.system(size: 34, weight: .semibold)
    static let headlineLg = Font.system(size: 26, weight: .semibold)
    static let headlineMd = Font.system(size: 20, weight: .semibold)
    static let headlineSm = Font.system(size: 17, weight: .semibold)
    static let bodyLg = Font.system(size: 19, weight: .regular)
    static let bodyMd = Font.system(size: 16, weight: .regular)
    static let bodySm = Font.system(size: 14, weight: .regular)
    static let labelMd = Font.system(size: 13, weight: .medium)
    static let labelSm = Font.system(size: 11, weight: .medium)

    // JetBrains-Mono-style metrics (intervals, counts) — monospaced to avoid layout jiggle
    static let mono = Font.system(size: 13, weight: .medium, design: .monospaced)
    static let monoSm = Font.system(size: 11, weight: .regular, design: .monospaced)
    static let monoMetric = Font.system(size: 26, weight: .semibold, design: .monospaced)
}
