import AVFoundation
import Foundation
import StrandAnalytics
import StrandDesign
import SwiftUI

/// A tiny on-device tone player for the opt-in audio pacer. It synthesises a short, soft sine "ding"
/// for each phase (a higher note on the inhale, a lower one on the exhale) and plays it through an
/// **ambient** audio session, so the iOS silent switch mutes it like any other ambient sound and it
/// never interrupts other audio. No bundled assets — the buffers are generated once and reused.
///
/// Self-contained and view-owned: `activate()` spins the engine up when the user opts in, `deactivate()`
/// tears it down when they switch off or leave the screen, so we hold the audio session only while it's
/// actually wanted.
@MainActor
final class BreathTonePlayer: ObservableObject {

    enum Tone { case inhale, exhale }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var inhaleBuffer: AVAudioPCMBuffer?
    private var exhaleBuffer: AVAudioPCMBuffer?
    private var active = false

    /// Phase tone frequencies (Hz). A gentle rising/falling pair — a soft cue, not a chime.
    private let inhaleHz: Double = 440   // A4, brighter for "in"
    private let exhaleHz: Double = 330   // E4, lower for "out"
    private let toneSeconds: Double = 0.45
    private let sampleRate: Double = 44_100

    /// Bring the engine and audio session up. Idempotent — safe to call on every appear.
    func activate() {
        guard !active else { return }
#if os(iOS)
        // Ambient: obeys the silent switch and mixes politely with anything else playing.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true, options: [])
#endif
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        guard let format else { return }

        if inhaleBuffer == nil { inhaleBuffer = makeTone(frequency: inhaleHz, format: format) }
        if exhaleBuffer == nil { exhaleBuffer = makeTone(frequency: exhaleHz, format: format) }

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
            player.play()
            active = true
        } catch {
            // Audio is a nicety, never load-bearing — if it can't start we just stay silent.
            active = false
        }
    }

    /// Stop and release the engine + session so nothing lingers when the pacer is off.
    func deactivate() {
        guard active else { return }
        player.stop()
        engine.stop()
        engine.disconnectNodeOutput(player)
        engine.detach(player)
#if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
#endif
        active = false
    }

    /// Play the phase tone. No-op if the engine isn't up (e.g. start-up race) — the haptic + visual cues
    /// still carry the pace, so a missed tone is harmless.
    func play(_ tone: Tone) {
        guard active else { return }
        let buffer = (tone == .inhale) ? inhaleBuffer : exhaleBuffer
        guard let buffer else { return }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
    }

    /// Generate a single soft sine tone with a short attack/decay envelope so it fades in and out rather
    /// than clicking. Built once per frequency and reused.
    private func makeTone(frequency: Double, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(toneSeconds * sampleRate)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frameCount

        let total = Int(frameCount)
        let attack = Int(0.02 * sampleRate)
        let release = Int(0.18 * sampleRate)
        let peak: Float = 0.28   // kept quiet — a gentle cue, not a beep

        for i in 0..<total {
            let t = Double(i) / sampleRate
            let sample = Float(sin(2.0 * Double.pi * frequency * t))
            // Linear attack, sustain, then a longer linear release so the tail is soft.
            var env: Float = 1.0
            if i < attack {
                env = Float(i) / Float(max(attack, 1))
            } else if i > total - release {
                env = Float(total - i) / Float(max(release, 1))
            }
            channel[i] = sample * env * peak
        }
        return buffer
    }
}
