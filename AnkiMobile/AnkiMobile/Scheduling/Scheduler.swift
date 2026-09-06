//
//  Scheduler.swift
//  AnkiMobile
//
//  A simplified SM-2 scheduler inspired by Anki's default algorithm.
//  Given a card and a rating (Again/Hard/Good/Easy) it computes the next due date,
//  interval, and ease — and can preview all four outcomes for the rating buttons.
//

import Foundation

/// The four grading choices, matching the study screen's action bar.
enum Rating: Int, CaseIterable, Identifiable {
    case again = 0
    case hard = 1
    case good = 2
    case easy = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .again: return "Again"
        case .hard: return "Hard"
        case .good: return "Good"
        case .easy: return "Easy"
        }
    }
}

struct Scheduler {
    // MARK: Configuration
    var learningStepsMinutes: [Int] = [1, 10]
    var graduatingIntervalDays: Int = 1
    var easyIntervalDays: Int = 4
    var minEase: Double = 1.3
    var startingEase: Double = 2.5
    var easyBonus: Double = 1.3
    var hardIntervalMultiplier: Double = 1.2
    var lapseIntervalMultiplier: Double = 0.0
    var relearnStepMinutes: Int = 10

    static let shared = Scheduler()

    /// The result of applying a rating, without mutating the card.
    struct Outcome {
        var state: CardState
        var due: Date
        var interval: Int
        var ease: Double
        var reps: Int
        var lapses: Int
        var learningStep: Int
        var displayInterval: String
    }

    /// Outcomes for all four ratings — used to label the grading buttons.
    func preview(_ card: Card, now: Date = .now) -> [Rating: Outcome] {
        var result: [Rating: Outcome] = [:]
        for rating in Rating.allCases {
            result[rating] = outcome(for: card, rating: rating, now: now)
        }
        return result
    }

    /// Applies a rating to the card, mutating its scheduling fields.
    func apply(_ rating: Rating, to card: Card, now: Date = .now) {
        let o = outcome(for: card, rating: rating, now: now)
        card.state = o.state
        card.due = o.due
        card.interval = o.interval
        card.ease = o.ease
        card.reps = o.reps
        card.lapses = o.lapses
        card.learningStep = o.learningStep
    }

    // MARK: - Core

    private func outcome(for card: Card, rating: Rating, now: Date) -> Outcome {
        switch card.state {
        case .new, .learning:
            return learningOutcome(card: card, rating: rating, now: now)
        case .review:
            return reviewOutcome(card: card, rating: rating, now: now)
        }
    }

    private func learningOutcome(card: Card, rating: Rating, now: Date) -> Outcome {
        let steps = learningStepsMinutes.isEmpty ? [1, 10] : learningStepsMinutes
        let isNew = (card.state == .new)
        let idx = isNew ? 0 : min(card.learningStep, steps.count - 1)
        let reps = card.reps + 1
        let ease = card.ease == 0 ? startingEase : card.ease

        switch rating {
        case .again:
            let delay = steps[0]
            return Outcome(state: .learning, due: now.addingMinutes(delay), interval: 0,
                           ease: ease, reps: reps, lapses: card.lapses, learningStep: 0,
                           displayInterval: formatMinutes(delay))
        case .hard:
            let delay = max(steps[0], Int((Double(steps[idx]) * 1.5).rounded()))
            return Outcome(state: .learning, due: now.addingMinutes(delay), interval: 0,
                           ease: ease, reps: reps, lapses: card.lapses, learningStep: idx,
                           displayInterval: formatMinutes(delay))
        case .good:
            let nextStep = idx + 1
            if nextStep >= steps.count {
                let days = graduatingIntervalDays
                return Outcome(state: .review, due: now.addingDays(days), interval: days,
                               ease: ease, reps: reps, lapses: card.lapses, learningStep: 0,
                               displayInterval: formatDays(days))
            } else {
                let delay = steps[nextStep]
                return Outcome(state: .learning, due: now.addingMinutes(delay), interval: 0,
                               ease: ease, reps: reps, lapses: card.lapses, learningStep: nextStep,
                               displayInterval: formatMinutes(delay))
            }
        case .easy:
            let days = easyIntervalDays
            return Outcome(state: .review, due: now.addingDays(days), interval: days,
                           ease: ease, reps: reps, lapses: card.lapses, learningStep: 0,
                           displayInterval: formatDays(days))
        }
    }

    private func reviewOutcome(card: Card, rating: Rating, now: Date) -> Outcome {
        var ease = card.ease == 0 ? startingEase : card.ease
        let currentInterval = max(1, card.interval)
        let reps = card.reps + 1

        switch rating {
        case .again:
            ease = max(minEase, ease - 0.20)
            let lapses = card.lapses + 1
            let reduced = max(1, Int((Double(currentInterval) * lapseIntervalMultiplier).rounded()))
            return Outcome(state: .learning, due: now.addingMinutes(relearnStepMinutes), interval: reduced,
                           ease: ease, reps: reps, lapses: lapses, learningStep: 0,
                           displayInterval: formatMinutes(relearnStepMinutes))
        case .hard:
            ease = max(minEase, ease - 0.15)
            let days = max(currentInterval + 1, Int((Double(currentInterval) * hardIntervalMultiplier).rounded()))
            return Outcome(state: .review, due: now.addingDays(days), interval: days,
                           ease: ease, reps: reps, lapses: card.lapses, learningStep: 0,
                           displayInterval: formatDays(days))
        case .good:
            let days = max(currentInterval + 1, Int((Double(currentInterval) * ease).rounded()))
            return Outcome(state: .review, due: now.addingDays(days), interval: days,
                           ease: ease, reps: reps, lapses: card.lapses, learningStep: 0,
                           displayInterval: formatDays(days))
        case .easy:
            ease += 0.15
            let days = max(currentInterval + 1, Int((Double(currentInterval) * ease * easyBonus).rounded()))
            return Outcome(state: .review, due: now.addingDays(days), interval: days,
                           ease: ease, reps: reps, lapses: card.lapses, learningStep: 0,
                           displayInterval: formatDays(days))
        }
    }

    // MARK: - Formatting

    func formatMinutes(_ minutes: Int) -> String {
        if minutes <= 1 { return "<1m" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        return "\(hours)h"
    }

    func formatDays(_ days: Int) -> String {
        if days < 1 { return "<1d" }
        if days < 30 { return "\(days)d" }
        if days < 365 { return String(format: "%.1fmo", Double(days) / 30.0) }
        return String(format: "%.1fy", Double(days) / 365.0)
    }
}

// MARK: - Date helpers

extension Date {
    func addingMinutes(_ minutes: Int) -> Date { addingTimeInterval(Double(minutes) * 60) }
    func addingDays(_ days: Int) -> Date { addingTimeInterval(Double(days) * 86_400) }
}
