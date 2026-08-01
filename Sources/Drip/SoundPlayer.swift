import AVFoundation
import DripCore

/// Ambient sound cues, synthesized on the fly (no audio assets): brook, rain, chime, birds, pop, breeze.
final class SoundPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.6
    }

    var volume: Float {
        get { engine.mainMixerNode.outputVolume }
        set { engine.mainMixerNode.outputVolume = max(0, min(1, newValue)) }
    }

    func play(_ cue: SoundCue, seconds: Double) {
        guard let buffer = Self.render(cue, seconds: seconds, format: format) else { return }
        // The engine stops itself on output-device changes (headphones, AirPods) and sometimes on sleep.
        do {
            if !engine.isRunning { try engine.start() }
        } catch { return }
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: [])
        player.play()
    }

    func stop() { player.stop() }

    // MARK: Synthesis

    static func render(_ cue: SoundCue, seconds: Double, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
        let n = AVAudioFrameCount(seconds * rate)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: n), let out = buf.floatChannelData?[0] else { return nil }
        buf.frameLength = n
        var rng = SystemRandomNumberGenerator()
        var lp1: Float = 0, lp2: Float = 0
        // Sparse events (bubbles, drips, chirps, bells): (start sample, kind-specific pitch)
        var events: [(Int, Float)] = []
        func sprinkle(_ perSecond: Double, _ pitch: ClosedRange<Float>) {
            var t = 0.2
            while t < seconds - 0.3 {
                events.append((Int(t * rate), Float.random(in: pitch, using: &rng)))
                t += Double.random(in: 0.3...1.7, using: &rng) / perSecond
            }
        }
        switch cue {
        case .brook: sprinkle(3, 350...900)
        case .rain: sprinkle(9, 1800...4200)
        case .chime:
            let notes: [(Double, Float)] = [(0, 1046.5), (0.35, 1318.5), (0.7, 1568.0)]   // C6 E6 G6
            for start in stride(from: 0.3, to: seconds - 1.5, by: 3.0) {
                for (offset, pitch) in notes { events.append((Int((start + offset) * rate), pitch)) }
            }
        case .birds: sprinkle(1.6, 2400...3800)
        case .pop: sprinkle(2.2, 500...900)
        case .breeze: break
        }

        for i in 0..<Int(n) {
            let t = Float(i) / Float(rate)
            let white = Float.random(in: -1...1, using: &rng)
            var v: Float = 0
            switch cue {
            case .brook:
                lp1 += 0.08 * (white - lp1)
                lp2 += 0.3 * (lp1 - lp2)
                let swirl = 0.6 + 0.4 * sin(t * 1.3) * sin(t * 0.37 + 1)
                v = (lp1 - lp2) * 3.2 * swirl
            case .rain:
                lp1 += 0.35 * (white - lp1)
                v = lp1 * 0.35
            case .breeze:
                lp1 += 0.02 * (white - lp1)
                let breath = 0.5 - 0.5 * cos(t * 2 * .pi / 10)   // ~4s in, ~6s out
                v = lp1 * 5 * (0.25 + 0.75 * breath)
            default:
                v = 0
            }
            out[i] = v
        }

        for (start, pitch) in events {
            let len: Int
            switch cue {
            case .chime: len = Int(1.6 * rate)
            case .birds: len = Int(0.18 * rate)
            case .rain: len = Int(0.03 * rate)
            default: len = Int(0.09 * rate)
            }
            var phase: Float = 0
            for k in 0..<len where start + k < Int(n) {
                let x = Float(k) / Float(len)
                let s: Float
                switch cue {
                case .chime:
                    phase += 2 * .pi * pitch / Float(rate)
                    s = (sin(phase) + 0.3 * sin(phase * 2.76)) * exp(-x * 5) * 0.35
                case .birds:
                    let f = pitch * (1 + 0.35 * sin(x * .pi * 3)) * (1 + x * 0.3)
                    phase += 2 * .pi * f / Float(rate)
                    s = sin(phase) * sin(x * .pi) * 0.25
                case .rain:
                    phase += 2 * .pi * pitch / Float(rate)
                    s = sin(phase) * exp(-x * 9) * 0.18
                case .brook, .pop:
                    let f = cue == .pop ? pitch * (1.6 - x) : pitch * (0.6 + x * 0.9)   // pops fall, bubbles rise
                    phase += 2 * .pi * f / Float(rate)
                    s = sin(phase) * sin(x * .pi) * (cue == .pop ? 0.4 : 0.22)
                case .breeze:
                    s = 0
                }
                out[start + k] += s
            }
        }

        // Fade in/out so cues never click.
        let fadeIn = Int(0.5 * rate), fadeOut = Int(1.0 * rate)
        for i in 0..<Int(n) {
            var g: Float = 1
            if i < fadeIn { g = Float(i) / Float(fadeIn) }
            if i > Int(n) - fadeOut { g = min(g, Float(Int(n) - i) / Float(fadeOut)) }
            out[i] = max(-1, min(1, out[i] * g))
        }
        return buf
    }
}
