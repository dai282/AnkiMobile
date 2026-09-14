//
//  AudioPlayer.swift
//  AnkiMobile
//
//  Plays a card's answer audio from the local media store. Kept tiny and shared so the
//  player outlives the tap that starts it.
//

import AVFoundation

@MainActor
final class AudioPlayer {
    static let shared = AudioPlayer()
    private var player: AVAudioPlayer?

    /// Plays the first of the given media filenames that exists locally. Returns false if
    /// none are present yet (media not downloaded — see V2.7b).
    @discardableResult
    func play(filenames: [String]) -> Bool {
        guard let url = filenames.lazy.compactMap({ MediaStore.existingURL(for: $0) }).first else {
            return false
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            self.player = player
            player.play()
            return true
        } catch {
            print("[audio] playback failed: \(error.localizedDescription)")
            return false
        }
    }
}
