//
//  Haptics.swift
//  AnkiMobile
//
//  Thin wrapper over UIKit feedback generators for tactile study feedback.
//

import UIKit

enum Haptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Distinct feel per grading choice — "Again" is the most pronounced.
    static func forRating(_ rating: Rating) {
        switch rating {
        case .again: impact(.medium)
        case .hard: impact(.soft)
        case .good: impact(.light)
        case .easy: impact(.rigid)
        }
    }
}
