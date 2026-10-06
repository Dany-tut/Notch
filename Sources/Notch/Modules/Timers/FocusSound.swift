import AVFoundation
import Synchronization

/// Фоновый звук на время таймера: дождь, шум, гул кафе.
///
/// Файлов нет — всё синтезируется на лету. Шум не повторяется: петля из
/// файла через пару минут узнаётся на слух, и вместо фона получается
/// метроном. Да и бандл не толстеет на десятки мегабайт ради шипения.
enum FocusSound: String, CaseIterable, Identifiable, Sendable {
    case off, rain, cafe, white, pink, brown

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .off: return "speaker.slash"
        case .rain: return "cloud.rain"
        case .cafe: return "cup.and.saucer"
        case .white: return "wind"
        case .pink: return "waveform"
        case .brown: return "water.waves"
        }
    }

    var titleKey: L10n.Key {
        switch self {
        case .off: return .timersSoundOff
        case .rain: return .timersSoundRain
        case .cafe: return .timersSoundCafe
        case .white: return .timersSoundWhite
        case .pink: return .timersSoundPink
        case .brown: return .timersSoundBrown
        }
    }
}

/// Играет `FocusSound`. Каждый звук — свой движок: смена звука на ходу
/// гасит старый и поднимает новый, и на полсекунды они звучат вместе —
/// это и есть переход, отдельной смеси не нужно.
@MainActor
final class FocusSoundPlayer {
    private struct Voice {
        let sound: FocusSound
        let engine: AVAudioEngine
        let generator: NoiseGenerator
    }

    private var voice: Voice?

    /// Сколько ждать после затухания, прежде чем глушить движок.
    private static let releaseDelay: Duration = .seconds(1.6)

    var isPlaying: Bool { voice != nil }

    func play(_ sound: FocusSound, volume: Double) {
        guard sound != .off else { return stop() }
        if let voice, voice.sound == sound {
            voice.generator.setGain(Self.gain(volume))
            return
        }
        stop()

        let engine = AVAudioEngine()
        let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        guard rate > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else { return }
        let generator = NoiseGenerator(sound: sound, sampleRate: Float(rate))
        let node = Self.sourceNode(format: format, generator: generator)
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
        } catch {
            return
        }
        generator.setGain(Self.gain(volume))
        voice = Voice(sound: sound, engine: engine, generator: generator)
    }

    func setVolume(_ volume: Double) {
        voice?.generator.setGain(Self.gain(volume))
    }

    /// Затухание, а движок глушится потом: оборванный на полуслове шум
    /// щёлкает в наушниках.
    func stop() {
        guard let voice else { return }
        self.voice = nil
        voice.generator.setGain(0)
        Task {
            try? await Task.sleep(for: Self.releaseDelay)
            voice.engine.stop()
        }
    }

    /// Узел собирается вне главного актора нарочно: замыкание, написанное
    /// внутри метода `@MainActor`, наследует его изоляцию, и Swift 6 роняет
    /// приложение проверкой актора при первом же вызове с аудиопотока.
    private nonisolated static func sourceNode(format: AVAudioFormat, generator: NoiseGenerator) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frames, buffers in
            generator.render(frames: Int(frames), into: UnsafeMutableAudioBufferListPointer(buffers))
            return noErr
        }
    }

    /// Громкость на слух растёт не линейно: квадрат делает середину
    /// ползунка серединой, а не почти полной громкостью.
    private static func gain(_ volume: Double) -> Float {
        let clamped = Float(min(max(volume, 0), 1))
        return clamped * clamped
    }
}

/// Синтез шума. Живёт на аудиопотоке: никаких выделений памяти и блокировок
/// внутри `render`, общий с главным потоком только целевой уровень — он
/// атомарный.
final class NoiseGenerator: @unchecked Sendable {
    private let sound: FocusSound
    private let sampleRate: Float

    /// Куда едет громкость. Битами `Float` — атомарных дробных чисел нет.
    private let target = Atomic<UInt32>(0)
    /// Где громкость сейчас. Подъезжает к цели за полсекунды-секунду —
    /// это и есть плавное появление и затухание.
    private var gain: Float = 0
    private let glide: Float

    private var seed: UInt64 = 0x9E37_79B9_7F4A_7C15

    // Розовый шум (Пол Келлет): семь фильтров разной инерции.
    private var pink = (Float(0), Float(0), Float(0), Float(0), Float(0), Float(0), Float(0))
    private var brown: Float = 0

    /// Однополюсные фильтры: дождь и кафе — это окрашенный шум.
    private var low: Float = 0
    private var high: Float = 0
    private var lowB: Float = 0

    /// Капли и звон — короткие затухающие всплески. Пул фиксированный.
    private struct Burst {
        var level: Float = 0
        var decay: Float = 0
        var phase: Float = 0
        var step: Float = 0
        var pan: Float = 0.5
        var tonal = false
    }
    private var bursts = [Burst](repeating: Burst(), count: 24)
    private var nextBurst = 0

    /// Гул голосов: медленные огибающие, как слоги в чужом разговоре.
    private var murmur: (phase: Float, rate: Float, depth: Float) = (0, 0.7, 0.4)
    private var murmurB: (phase: Float, rate: Float) = (0, 0.23)

    init(sound: FocusSound, sampleRate: Float) {
        self.sound = sound
        self.sampleRate = sampleRate
        glide = 1 - exp(-1 / (0.28 * sampleRate))
    }

    func setGain(_ value: Float) {
        target.store(value.bitPattern, ordering: .relaxed)
    }

    func render(frames: Int, into buffers: UnsafeMutableAudioBufferListPointer) {
        let goal = Float(bitPattern: target.load(ordering: .relaxed))
        let left = buffers[0].mData?.assumingMemoryBound(to: Float.self)
        let right = buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil

        for frame in 0..<frames {
            gain += (goal - gain) * glide
            var l: Float = 0
            var r: Float = 0
            if gain > 0.000_01 {
                (l, r) = sample()
                l *= gain
                r *= gain
            }
            left?[frame] = l
            right?[frame] = r
        }
    }

    // MARK: - Источники

    private func sample() -> (Float, Float) {
        switch sound {
        case .off:
            return (0, 0)
        case .white:
            let value = white() * 0.25
            return (value, value)
        case .pink:
            let value = pinkNoise() * 1.0
            return (value, value)
        case .brown:
            let value = brownNoise() * 1.0
            return (value, value)
        case .rain:
            return rain()
        case .cafe:
            return cafe()
        }
    }

    /// Ровный дождь — розовый шум без низа и без самого верха: шелест, а не
    /// гул. Поверх — отдельные капли со своим местом в стереопанораме.
    private func rain() -> (Float, Float) {
        let base = pinkNoise()
        low += (base - low) * coefficient(5_200)
        high += (low - high) * coefficient(420)
        let wash = (low - high) * 1.3

        // Около тридцати капель в секунду, по Пуассону.
        if uniform() < 30 / sampleRate {
            spawn(
                level: 0.12 + uniform() * 0.3,
                seconds: 0.004 + uniform() * 0.02,
                frequency: 0,
                tonal: false
            )
        }
        let (dropL, dropR) = renderBursts()
        return (wash + dropL, wash + dropR)
    }

    /// Кафе — бурый шум в полосе голоса, дышащий медленными огибающими,
    /// и редкий звон посуды.
    private func cafe() -> (Float, Float) {
        let base = brownNoise() * 0.6 + pinkNoise() * 0.4
        lowB += (base - lowB) * coefficient(1_300)
        high += (lowB - high) * coefficient(220)
        let voice = lowB - high

        murmur.phase += murmur.rate / sampleRate
        if murmur.phase >= 1 {
            murmur.phase -= 1
            // Каждый «слог» — новый темп и глубина: ровная волна читалась
            // бы как сирена, а не как разговор.
            murmur.rate = 0.5 + uniform() * 2.5
            murmur.depth = 0.2 + uniform() * 0.45
        }
        murmurB.phase += murmurB.rate / sampleRate
        if murmurB.phase >= 1 { murmurB.phase -= 1 }
        let envelope = 1
            - murmur.depth * (0.5 + 0.5 * sin(2 * .pi * murmur.phase))
            - 0.15 * (0.5 + 0.5 * sin(2 * .pi * murmurB.phase))
        let hum = voice * envelope * 3.2

        if uniform() < 0.35 / sampleRate {
            spawn(
                level: 0.04 + uniform() * 0.06,
                seconds: 0.08 + uniform() * 0.18,
                frequency: 1_800 + uniform() * 2_600,
                tonal: true
            )
        }
        let (clinkL, clinkR) = renderBursts()
        return (hum + clinkL, hum + clinkR)
    }

    // MARK: - Всплески

    private func spawn(level: Float, seconds: Float, frequency: Float, tonal: Bool) {
        bursts[nextBurst] = Burst(
            level: level,
            decay: exp(-1 / (seconds * sampleRate)),
            phase: 0,
            step: frequency / sampleRate,
            pan: 0.15 + uniform() * 0.7,
            tonal: tonal
        )
        nextBurst = (nextBurst + 1) % bursts.count
    }

    private func renderBursts() -> (Float, Float) {
        var l: Float = 0
        var r: Float = 0
        for index in bursts.indices where bursts[index].level > 0.000_1 {
            var burst = bursts[index]
            let value: Float
            if burst.tonal {
                burst.phase += burst.step
                if burst.phase >= 1 { burst.phase -= 1 }
                // Основной тон и неровная гармоника — стекло, а не камертон.
                value = sin(2 * .pi * burst.phase) + 0.4 * sin(2 * .pi * burst.phase * 2.76)
            } else {
                value = white()
            }
            let out = value * burst.level
            l += out * (1 - burst.pan)
            r += out * burst.pan
            burst.level *= burst.decay
            bursts[index] = burst
        }
        return (l, r)
    }

    // MARK: - Шум

    private func coefficient(_ frequency: Float) -> Float {
        1 - exp(-2 * .pi * frequency / sampleRate)
    }

    /// xorshift: быстрый и без блокировок, в отличие от системного генератора.
    private func uniform() -> Float {
        seed ^= seed << 13
        seed ^= seed >> 7
        seed ^= seed << 17
        return Float(seed >> 40) / Float(1 << 24)
    }

    private func white() -> Float { uniform() * 2 - 1 }

    private func pinkNoise() -> Float {
        let w = white()
        pink.0 = 0.99886 * pink.0 + w * 0.0555179
        pink.1 = 0.99332 * pink.1 + w * 0.0750759
        pink.2 = 0.96900 * pink.2 + w * 0.1538520
        pink.3 = 0.86650 * pink.3 + w * 0.3104856
        pink.4 = 0.55000 * pink.4 + w * 0.5329522
        pink.5 = -0.7616 * pink.5 - w * 0.0168980
        let value = pink.0 + pink.1 + pink.2 + pink.3 + pink.4 + pink.5 + pink.6 + w * 0.5362
        pink.6 = w * 0.115926
        return value * 0.11
    }

    private func brownNoise() -> Float {
        brown = (brown + 0.02 * white()) / 1.02
        return brown * 3.5
    }
}
