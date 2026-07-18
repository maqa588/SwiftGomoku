import AVFoundation
import Foundation

/// Synthesizes a short stone-on-wood impact in real time. No audio assets are used.
@MainActor
final class StoneSoundEngine {
    private let engine = AVAudioEngine()
    private let voices = (0..<4).map { _ in AVAudioPlayerNode() }
    private let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
    private var nextVoice = 0

    init() {
        #if os(iOS)
        Task.detached(priority: .background) {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.ambient, options: [])
                try session.setActive(true)
            } catch {
                print("Failed to set up AVAudioSession: \(error)")
            }
        }
        #endif
        for voice in voices {
            engine.attach(voice)
            engine.connect(voice, to: engine.mainMixerNode, format: format)
        }
        engine.prepare()
    }

    func play(
        stone: Stone,
        at point: BoardPoint,
        boardSize: Int,
        material: BoardMaterial,
        volume: Double
    ) {
        guard volume > 0, let buffer = makeBuffer(
            stone: stone,
            at: point,
            boardSize: boardSize,
            material: material,
            volume: volume
        ) else { return }

        if !engine.isRunning {
            do { try engine.start() }
            catch { return }
        }

        let voice = voices[nextVoice]
        nextVoice = (nextVoice + 1) % voices.count
        voice.stop()
        voice.scheduleBuffer(buffer, at: nil, options: .interrupts)
        voice.play()
    }

    func stop() {
        voices.forEach { $0.stop() }
        engine.stop()
    }

    func makeBuffer(
        stone: Stone,
        at point: BoardPoint,
        boardSize: Int,
        material: BoardMaterial,
        volume: Double
    ) -> AVAudioPCMBuffer? {
        let profile = material.acousticProfile
        let lastIndex = max(boardSize - 1, 1)
        let edgeDistance = min(point.x, point.y, lastIndex - point.x, lastIndex - point.y)
        let centerAmount = min(max(Double(edgeDistance) * 2 / Double(lastIndex), 0), 1)
        let horizontalPosition = Double(point.x) / Double(lastIndex) * 2 - 1

        let duration = profile.baseDuration + centerAmount * 0.020
        let frameCount = AVAudioFrameCount(duration * format.sampleRate)
        guard
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
            let channels = buffer.floatChannelData
        else { return nil }
        buffer.frameLength = frameCount

        var generator = SystemRandomNumberGenerator()
        let stonePitch = stone == .black ? 0.985 : 1.015
        let positionPitch = 1.030 - centerAmount * 0.030
        let pitchJitter = Double.random(in: 0.985...1.015, using: &generator)
        let pitchScale = stonePitch * positionPitch * pitchJitter
        let strikeStrength = Double.random(in: 0.88...1.08, using: &generator)
        let pan = horizontalPosition * 0.24
        let panAngle = (pan + 1) * .pi / 4
        let leftGain = cos(panAngle)
        let rightGain = sin(panAngle)
        let modePhases = profile.frequencies.map { _ in Double.random(in: 0...(2 * .pi), using: &generator) }
        let mainContactDelay = Double.random(in: 0.0165...0.0205, using: &generator)
        let reboundDelay = mainContactDelay + Double.random(in: 0.014...0.018, using: &generator)
        let lateContactDelay = mainContactDelay + Double.random(in: 0.032...0.038, using: &generator)
        let sampleRate = format.sampleRate
        var previousNoise = 0.0

        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / sampleRate
            let whiteNoise = Double.random(in: -1...1, using: &generator)
            let brightNoise = whiteNoise - previousNoise
            previousNoise = whiteNoise

            // The reference has a small preliminary touch, then its main impact
            // about 19 ms later, followed by two much quieter rebounds.
            var sample = brightNoise * exp(-time / 0.0012) * 0.13

            if time >= mainContactDelay {
                let impactTime = time - mainContactDelay
                sample += brightNoise * exp(-impactTime / 0.00135) * profile.contactGain

                for index in profile.frequencies.indices {
                    let frequency = profile.frequencies[index] * pitchScale
                    let decay = profile.decays[index] * (0.94 + centerAmount * 0.12)
                    sample += sin(2 * .pi * frequency * impactTime + modePhases[index])
                        * profile.gains[index] * exp(-impactTime / decay)
                }
            }

            if time >= reboundDelay {
                let reboundTime = time - reboundDelay
                sample += brightNoise * exp(-reboundTime / 0.0014) * 0.15
            }

            if time >= lateContactDelay {
                let lateTime = time - lateContactDelay
                sample += brightNoise * exp(-lateTime / 0.0012) * 0.055
            }

            sample *= strikeStrength * min(max(volume, 0), 1)
            let saturated = tanh(sample * 1.35) / tanh(1.35)
            channels[0][frame] = Float(saturated * leftGain)
            channels[1][frame] = Float(saturated * rightGain)
        }

        return buffer
    }
}

private struct AcousticProfile {
    let frequencies: [Double]
    let decays: [Double]
    let gains: [Double]
    let contactGain: Double
    let baseDuration: Double
}

private extension BoardMaterial {
    var acousticProfile: AcousticProfile {
        switch self {
        case .kaya:
            AcousticProfile(
                frequencies: [2_080, 2_940, 3_720, 4_660],
                decays: [0.0065, 0.0052, 0.0038, 0.0026],
                gains: [0.070, 0.17, 0.14, 0.16],
                contactGain: 1.05,
                baseDuration: 0.095
            )
        case .katsura:
            AcousticProfile(
                frequencies: [2_180, 3_080, 3_920, 4_920],
                decays: [0.0058, 0.0047, 0.0034, 0.0023],
                gains: [0.060, 0.16, 0.14, 0.17],
                contactGain: 1.08,
                baseDuration: 0.090
            )
        case .shinKaya:
            AcousticProfile(
                frequencies: [2_320, 3_260, 4_180, 5_300],
                decays: [0.0052, 0.0041, 0.0030, 0.0020],
                gains: [0.052, 0.15, 0.14, 0.18],
                contactGain: 1.12,
                baseDuration: 0.086
            )
        }
    }
}
