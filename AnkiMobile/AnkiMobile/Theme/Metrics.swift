//
//  Metrics.swift
//  AnkiMobile
//
//  Spacing (8pt cadence) and continuous corner radii from DESIGN.md.
//

import CoreGraphics

enum Metrics {
    // Spacing
    static let space2xs: CGFloat = 4
    static let spaceXs: CGFloat = 8
    static let spaceSm: CGFloat = 12
    static let spaceMd: CGFloat = 16
    static let spaceLg: CGFloat = 20
    static let spaceXl: CGFloat = 24
    static let space2xl: CGFloat = 32

    // Corner radii (used with .continuous style for iOS squircles)
    static let radiusCard: CGFloat = 20        // primary flashcards
    static let radiusSheet: CGFloat = 24       // modals / sheets
    static let radiusDeckRow: CGFloat = 16     // deck list items
    static let radiusPill: CGFloat = 12        // pills, badges, answer buttons
    static let radiusSmall: CGFloat = 8
    static let radiusMicro: CGFloat = 6        // cloze / micro badges

    // Screen margins
    static let screenMargin: CGFloat = 16

    // Touch targets
    static let touchMin: CGFloat = 44
    static let touchComfortable: CGFloat = 52
}
