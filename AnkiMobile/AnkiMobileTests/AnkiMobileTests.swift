//
//  AnkiMobileTests.swift
//  AnkiMobileTests
//
//  Pure-logic unit tests (Swift Testing) for the scheduler, Anki schema mapping,
//  the minimal protobuf codec, the stored-zip media reader, and queue counting.
//

import Testing
import Foundation
@testable import AnkiMobile

// MARK: - Scheduler

@Suite struct SchedulerTests {
    private let scheduler = Scheduler.shared

    private func newCard() -> Card {
        let c = Card(front: "q", back: "a")
        c.state = .new; c.interval = 0; c.ease = 2.5; c.reps = 0; c.learningStep = 0
        return c
    }

    @Test func newGoodEntersLearning() {
        let c = newCard()
        scheduler.apply(.good, to: c)
        #expect(c.state == .learning)
        #expect(c.reps == 1)
    }

    @Test func newAgainEntersLearningAtFirstStep() {
        let c = newCard()
        scheduler.apply(.again, to: c)
        #expect(c.state == .learning)
        #expect(c.learningStep == 0)
    }

    @Test func newEasyGraduatesToReview() {
        let c = newCard()
        scheduler.apply(.easy, to: c)
        #expect(c.state == .review)
        #expect(c.interval == 4)   // easyIntervalDays
    }

    @Test func lastLearningStepGoodGraduates() {
        let c = newCard()
        c.state = .learning; c.learningStep = 1; c.reps = 1   // final step of [1, 10]
        scheduler.apply(.good, to: c)
        #expect(c.state == .review)
        #expect(c.interval == 1)   // graduatingIntervalDays
    }

    @Test func reviewGoodGrowsInterval() {
        let c = newCard()
        c.state = .review; c.interval = 10; c.ease = 2.5; c.reps = 5
        scheduler.apply(.good, to: c)
        #expect(c.state == .review)
        #expect(c.interval > 10)
    }

    @Test func reviewAgainLapsesToLearning() {
        let c = newCard()
        c.state = .review; c.interval = 10; c.ease = 2.5; c.lapses = 0
        scheduler.apply(.again, to: c)
        #expect(c.state == .learning)
        #expect(c.lapses == 1)
        #expect(c.ease < 2.5)      // ease penalised on lapse
    }

    @Test func previewCoversAllFourRatings() {
        let previews = scheduler.preview(newCard())
        #expect(Set(previews.keys) == Set(Rating.allCases))
        for (_, outcome) in previews { #expect(!outcome.displayInterval.isEmpty) }
    }
}

// MARK: - AnkiSchema mapping

@Suite struct AnkiSchemaTests {
    @Test func fieldsRoundTrip() {
        let joined = AnkiSchema.joinedFields(front: "表", back: "おもて")
        #expect(joined == "表\u{1f}おもて")
        let split = AnkiSchema.splitFields(joined)
        #expect(split.front == "表")
        #expect(split.back == "おもて")
    }

    @Test func easeToFactor() {
        #expect(AnkiSchema.factor(fromEase: 2.5) == 2500)
        #expect(AnkiSchema.factor(fromEase: 1.3) == 1300)
    }

    @Test func typeAndQueueMapping() {
        #expect(AnkiSchema.typeAndQueue(for: .new).type == 0)
        #expect(AnkiSchema.typeAndQueue(for: .learning) == (1, 1))
        #expect(AnkiSchema.typeAndQueue(for: .review) == (2, 2))
    }
}

// MARK: - Protobuf codec

@Suite struct ProtobufTests {
    @Test func varintRoundTrip() {
        let fields = [PBField(field: 3, wire: 0, varint: 2),
                      PBField(field: 4, wire: 0, varint: 300)]
        let bytes = Protobuf.serialize(fields)
        #expect(Protobuf.varintField(3, in: bytes) == 2)
        #expect(Protobuf.varintField(4, in: bytes) == 300)   // multi-byte varint
        #expect(Protobuf.varintField(9, in: bytes) == nil)
    }

    @Test func configIDFromNestedKindBlob() {
        let normal = Protobuf.serialize([PBField(field: 1, wire: 0, varint: 5)])       // Normal.config_id = 5
        let kind = Protobuf.serialize([PBField(field: 1, wire: 2, bytes: normal)])     // KindContainer.normal
        #expect(Protobuf.configID(fromKind: kind) == 5)
    }

    @Test func lengthDelimitedRoundTrip() {
        let payload: [UInt8] = [0x7b, 0x7d] // "{}"
        let bytes = Protobuf.serialize([PBField(field: 255, wire: 2, bytes: payload)])
        let parsed = Protobuf.fields(bytes)
        #expect(parsed.first?.field == 255)
        #expect(parsed.first?.bytes == payload)
    }
}

// MARK: - Media stored-zip reader

@Suite struct MediaZipTests {
    /// Builds a single Stored (uncompressed) local-file-header entry.
    private func entry(name: String, data: [UInt8]) -> [UInt8] {
        let nameBytes = Array(name.utf8)
        func le32(_ v: Int) -> [UInt8] { [UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff), UInt8((v >> 24) & 0xff)] }
        func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xff), UInt8((v >> 8) & 0xff)] }
        var out: [UInt8] = [0x50, 0x4b, 0x03, 0x04]        // PK\3\4
        out += [20, 0, 0, 0, 0, 0]                          // version, flags, method (0 = stored)
        out += [0, 0, 0, 0]                                 // mod time + date
        out += [0, 0, 0, 0]                                 // crc32
        out += le32(data.count)                            // compressed size
        out += le32(data.count)                            // uncompressed size
        out += le16(nameBytes.count)                       // name length
        out += le16(0)                                     // extra length
        out += nameBytes
        out += data
        return out
    }

    @Test func extractsStoredEntriesByMeta() {
        let meta = Array(#"{"0":"kana.mp3"}"#.utf8)
        var zip = entry(name: "0", data: Array("AUDIO".utf8))
        zip += entry(name: "_meta", data: meta)
        let out = MediaZip.extract(Data(zip))
        #expect(out["kana.mp3"] == Data("AUDIO".utf8))
        #expect(out.count == 1)
    }

    @Test func chunkedSplitsEvenly() {
        #expect([1, 2, 3, 4, 5].chunked(into: 2) == [[1, 2], [3, 4], [5]])
        #expect([Int]().chunked(into: 3) == [])
    }
}

// MARK: - Queue counting

@Suite struct QueueCountTests {
    private func card(_ state: CardState, dueOffset: TimeInterval = 0) -> Card {
        let c = Card(front: "q", back: "a")
        c.state = state
        c.due = Date().addingTimeInterval(dueOffset)
        return c
    }

    @Test func bucketsByStateWithDueReviewOnly() {
        let cards = [
            card(.new), card(.new),
            card(.learning, dueOffset: 600),           // learning counts regardless of due
            card(.review, dueOffset: -60),             // due now → counts
            card(.review, dueOffset: 86_400),          // due tomorrow → excluded
        ]
        let counts = cards.queueCounts()
        #expect(counts.new == 2)
        #expect(counts.learning == 1)
        #expect(counts.review == 1)
        #expect(counts.total == 4)
    }

    @Test func queueCountsAddition() {
        let a = QueueCounts(new: 1, learning: 2, review: 3)
        let b = QueueCounts(new: 10, learning: 20, review: 30)
        let sum = a + b
        #expect(sum.new == 11 && sum.learning == 22 && sum.review == 33)
    }
}
