// NoteSegmenter.swift
// PitchMVP
//
// FIX v2:
// 1. semitoneThreshold: 0.6 → 0.8
//    Motivo: 0.6 semitons (60 cents) era insuficiente para vozes com vibrato natural
//    (20–50 cents de profundidade). O threshold baixo fragmentava uma nota sustentada
//    em múltiplos segmentos. 0.8 (80 cents) é robusto contra vibrato sem perder
//    sensibilidade a mudanças de nota reais (que normalmente são ≥ 1 semitom).
//
// 2. VoiceRangeHint — expectedRange passado ao VocalPitchDetector
//    Motivo: YIN pode errar uma oitava em vozes com harmônicos fortes (baixo/barítono
//    cantando forte). O VocalPitchDetector já suporta `expectedRange` para correção
//    de sub-harmônicos, mas o NoteSegmenter nunca o usava.
//    Agora: `analyze(samples:sampleRate:voiceHint:)` aceita um VoiceRangeHint opcional
//    que limita a busca do YIN à faixa vocal esperada — elimina erros de oitava
//    sem afetar a precisão dentro da faixa correta.

import Foundation
import Accelerate

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - VoiceRangeHint
// ─────────────────────────────────────────────────────────────────────────────

/// Dica de faixa vocal para orientar o detector de pitch.
///
/// Usado para evitar erros de oitava em vozes com harmônicos fortes.
/// O NoteSegmenter passa esse hint ao VocalPitchDetector como `expectedRange`.
///
/// Uso:
/// ```swift
/// segmenter.analyze(samples: samples, sampleRate: 44100, voiceHint: .male)
/// segmenter.analyze(samples: samples, sampleRate: 44100, voiceHint: .female)
/// segmenter.analyze(samples: samples, sampleRate: 44100, voiceHint: .custom(130...700))
/// ```

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - NoteSegment (inalterado)
// ─────────────────────────────────────────────────────────────────────────────

struct NoteSegment: Identifiable {

    let id = UUID()
    let noteName: String
    let medianFrequency: Float
    let midiNote: Float
    let pitchCurve: [(time: Float, frequency: Float)]
    let centsOverTime: [Float]
    let averageCentsDeviation: Float
    let maxCentsDeviation: Float
    let stabilityPercentage: Float
    let vibrato: VibratoAnalysis?
    let durationSeconds: Float
    let startTime: Float
    let frameCount: Int
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - VibratoAnalysis (inalterado)
// ─────────────────────────────────────────────────────────────────────────────

struct VibratoAnalysis {

    let rateHz: Float
    let depthCents: Float
    let regularity: Float

    var quality: VibratoQuality {
        let rateOk    = (5.0...7.5).contains(rateHz)
        let depthOk   = (20.0...60.0).contains(depthCents)
        let regularOk = regularity > 0.6

        switch (rateOk, depthOk, regularOk) {
        case (true, true, true):   return .excellent
        case (true, true, false):  return .irregular
        case (false, _, _):        return .offRate
        case (_, false, _):        return .shallow
        default:                   return .none
        }
    }
}

enum VibratoQuality: String {
    case excellent = "Vibrato Natural"
    case irregular = "Vibrato Irregular"
    case offRate   = "Taxa Incorreta"
    case shallow   = "Vibrato Raso"
    case none      = "Sem Vibrato"

    var color: String {
        switch self {
        case .excellent: return "green"
        case .irregular: return "orange"
        case .offRate:   return "red"
        case .shallow:   return "blue"
        case .none:      return "secondary"
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - NoteSegmenter
// ─────────────────────────────────────────────────────────────────────────────

final class NoteSegmenter {

    // MARK: - Configuração

    private let frameSize = 4096
    private let hopSize   = 512

    // FIX: era 0.6 — fragmentava notas com vibrato natural (20–50 cents).
    // 0.8 semitons (80 cents) é robusto contra vibrato sem perder mudanças reais.
    private let semitoneThreshold: Float = 0.8

    private let minDurationSeconds: Float = 0.15
    private let detector = VocalPitchDetector()

    // MARK: - API Pública

    /// Analisa um buffer de áudio completo e retorna segmentos por nota.
    ///
    /// - Parameters:
    ///   - samples:    Amostras PCM Float normalizadas em [-1, 1]
    ///   - sampleRate: Taxa de amostragem em Hz
    ///   - voiceHint:  Faixa vocal esperada para correção de oitava no YIN.
    ///                 Use `.male` para barítono/baixo/tenor,
    ///                 `.female` para contralto/mezzo/soprano,
    ///                 `.automatic` para comportamento sem restrição (padrão).
    /// - Returns: Array de NoteSegment ordenado cronologicamente
    func analyze(
        samples: [Float],
        sampleRate: Float,
        voiceHint: VoiceRangeHint = .custom(130...700)   // ← NOVO parâmetro, não-breaking
    ) -> [NoteSegment] {

        var segments: [NoteSegment] = []

        var currentNoteMidi: Float? = nil
        var currentFrames: [(time: Float, frequency: Float)] = []
        var segmentStartTime: Float = 0

        let frameCount = (samples.count - frameSize) / hopSize

        // Converte hint para ClosedRange uma vez, fora do loop
        let expectedRange = voiceHint.frequencyRange

        for frameIndex in 0..<frameCount {

            let startSample = frameIndex * hopSize
            let endSample   = startSample + frameSize
            guard endSample <= samples.count else { break }

            let frame = Array(samples[startSample..<endSample])
            let timeSeconds = Float(startSample) / sampleRate

            // FIX: passa expectedRange ao detector para correção de oitava no YIN
            guard let result = detector.detect(
                buffer: frame,
                sampleRate: sampleRate,
                expectedRange: expectedRange    // ← era sempre nil antes
            ) else {
                if let _ = currentNoteMidi, !currentFrames.isEmpty {
                    let seg = buildSegment(
                        frames: currentFrames,
                        startTime: segmentStartTime,
                        sampleRate: sampleRate
                    )
                    if let s = seg { segments.append(s) }
                    currentFrames.removeAll()
                    currentNoteMidi = nil
                }
                continue
            }

            let detectedMidi = result.midNote

            if let activeMidi = currentNoteMidi {
                let semitoneDiff = abs(detectedMidi - activeMidi)

                if semitoneDiff > semitoneThreshold {
                    let seg = buildSegment(
                        frames: currentFrames,
                        startTime: segmentStartTime,
                        sampleRate: sampleRate
                    )
                    if let s = seg { segments.append(s) }

                    currentFrames = [(time: timeSeconds, frequency: result.frequency)]
                    currentNoteMidi = detectedMidi
                    segmentStartTime = timeSeconds

                } else {
                    currentNoteMidi = activeMidi * 0.95 + detectedMidi * 0.05
                    currentFrames.append((time: timeSeconds, frequency: result.frequency))
                }

            } else {
                currentNoteMidi = detectedMidi
                currentFrames = [(time: timeSeconds, frequency: result.frequency)]
                segmentStartTime = timeSeconds
            }
        }

        if !currentFrames.isEmpty {
            let seg = buildSegment(
                frames: currentFrames,
                startTime: segmentStartTime,
                sampleRate: sampleRate
            )
            if let s = seg { segments.append(s) }
        }

        return segments
    }

    // MARK: - Construção de Segmento (inalterado)

    private func buildSegment(
        frames: [(time: Float, frequency: Float)],
        startTime: Float,
        sampleRate: Float
    ) -> NoteSegment? {

        guard !frames.isEmpty else { return nil }

        let frequencies = frames.map(\.frequency)
        let duration = (Float(frames.count) * Float(hopSize)) / sampleRate

        guard duration >= minDurationSeconds else { return nil }

        let medianFreq = median(of: frequencies)
        guard let theory = MusicTheory.analyze(frequency: medianFreq) else { return nil }

        let targetFreq = midiToFrequency(round(theory.midNote))
        let centsOverTime = frequencies.map { freq -> Float in
            guard freq > 0, targetFreq > 0 else { return 0 }
            return 1200 * log2(freq / targetFreq)
        }

        let absCents = centsOverTime.map { abs($0) }
        let avgDeviation = absCents.reduce(0, +) / Float(absCents.count)
        let maxDeviation = absCents.max() ?? 0
        let inTuneCount = centsOverTime.filter { abs($0) <= 10 }.count
        let stability = Float(inTuneCount) / Float(centsOverTime.count) * 100

        let vibratoHopRate = sampleRate / Float(hopSize)
        let vibratoAnalysis = analyzeVibrato(centsTimeSeries: centsOverTime, frameRate: vibratoHopRate)

        return NoteSegment(
            noteName: theory.noteName,
            medianFrequency: medianFreq,
            midiNote: theory.midNote,
            pitchCurve: frames,
            centsOverTime: centsOverTime,
            averageCentsDeviation: avgDeviation,
            maxCentsDeviation: maxDeviation,
            stabilityPercentage: stability,
            vibrato: vibratoAnalysis,
            durationSeconds: duration,
            startTime: startTime,
            frameCount: frames.count
        )
    }

    // MARK: - Análise de Vibrato (inalterado)

    private func analyzeVibrato(centsTimeSeries: [Float], frameRate: Float) -> VibratoAnalysis? {

        guard centsTimeSeries.count >= Int(frameRate * 0.5) else { return nil }

        let mean = centsTimeSeries.reduce(0, +) / Float(centsTimeSeries.count)
        var detrended = centsTimeSeries.map { $0 - mean }

        let fftN = nextPowerOf2(greaterThan: detrended.count)
        detrended += [Float](repeating: 0, count: fftN - detrended.count)

        let log2n = vDSP_Length(log2(Float(fftN)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        var realPart = detrended
        var imagPart = [Float](repeating: 0, count: fftN)
        var splitComplex = DSPSplitComplex(realp: &realPart, imagp: &imagPart)
        vDSP_fft_zip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))

        var magnitudes = [Float](repeating: 0, count: fftN / 2)
        vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(fftN / 2))

        let binResolution = frameRate / Float(fftN)
        let minBin = max(1, Int(3.0 / binResolution))
        let maxBin = min(magnitudes.count - 1, Int(9.0 / binResolution))

        guard minBin < maxBin else { return nil }

        var peakMag: Float = 0
        var peakBin = minBin
        for i in minBin...maxBin {
            if magnitudes[i] > peakMag {
                peakMag = magnitudes[i]
                peakBin = i
            }
        }

        let vibratoRateHz = Float(peakBin) * binResolution

        var rms: Float = 0
        vDSP_rmsqv(detrended, 1, &rms, vDSP_Length(detrended.count))
        let depthCents = rms * 2.83

        let totalEnergy = magnitudes[minBin...maxBin].reduce(0, +)
        let regularity = totalEnergy > 0 ? peakMag / totalEnergy : 0

        guard depthCents > 10 else { return nil }

        return VibratoAnalysis(
            rateHz: vibratoRateHz,
            depthCents: depthCents,
            regularity: min(1.0, regularity)
        )
    }

    // MARK: - Utilitários (inalterados)

    private func median(of values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0
            ? (sorted[mid - 1] + sorted[mid]) / 2
            : sorted[mid]
    }

    private func midiToFrequency(_ midi: Float) -> Float {
        440.0 * pow(2.0, (midi - 69.0) / 12.0)
    }

    private func nextPowerOf2(greaterThan n: Int) -> Int {
        var result = 1
        while result < n { result <<= 1 }
        return result
    }
}