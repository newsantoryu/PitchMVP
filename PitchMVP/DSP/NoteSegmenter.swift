//
//  NoteSegmenter.swift
//  PitchMVP
//
//  Created by victor on 24/02/26.
//

// NoteSegmenter.swift
// PitchMVP
//
// Detecta automaticamente mudanças de nota em um stream de pitches,
// agrupa amostras em segmentos e calcula métricas por nota.
//
// Pipeline:
//   [Float] amostras → VocalPitchDetector (frame a frame) → NoteSegmenter
//   → [NoteSegment] com pitchCurve, vibrato, estabilidade, comparação com alvo

import Foundation
import Accelerate

/// Um segmento de nota detectado automaticamente na gravação.
/// Contém toda a análise musical daquela nota sustentada.
struct NoteSegment: Identifiable {

    let id = UUID()

    /// Nome da nota detectada (ex: "A4", "C#3")
    let noteName: String

    /// Frequência mediana do segmento (Hz) — mais robusta que média contra outliers
    let medianFrequency: Float

    /// MIDI number da nota (float para preservar desvio)
    let midiNote: Float

    /// Curva de pitch ao longo do tempo: array de (tempo em segundos, frequência em Hz)
    let pitchCurve: [(time: Float, frequency: Float)]

    /// Desvio em cents de cada amostra em relação à nota alvo
    let centsOverTime: [Float]

    /// Desvio médio absoluto em cents — estabilidade geral
    let averageCentsDeviation: Float

    /// Desvio máximo absoluto em cents
    let maxCentsDeviation: Float

    /// % do tempo em que estava dentro de ±10 cents da nota alvo
    let stabilityPercentage: Float

    /// Análise de vibrato detectado (nil se não houver vibrato)
    let vibrato: VibratoAnalysis?

    /// Duração do segmento em segundos
    let durationSeconds: Float

    /// Timestamp de início no arquivo (segundos desde o começo)
    let startTime: Float

    /// Número de frames analisados neste segmento
    let frameCount: Int
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - VibratoAnalysis
// ─────────────────────────────────────────────────────────────────────────────

/// Resultado da análise de vibrato para um segmento de nota.
/// Vibrato é uma oscilação periódica do pitch — característica expressiva do canto.
struct VibratoAnalysis {

    /// Taxa do vibrato em Hz (oscilações por segundo) — voz treinada: 5–7 Hz
    let rateHz: Float

    /// Profundidade do vibrato em cents (amplitude pico a pico) — voz treinada: 20–50 cents
    let depthCents: Float

    /// Regularidade do vibrato (0–1) — quão consistente é a oscilação
    let regularity: Float

    /// Classifica a qualidade do vibrato
    var quality: VibratoQuality {
        // Vibrato vocal ideal: 5–7 Hz, 20–50 cents, alta regularidade
        let rateOk = (5.0...7.5).contains(rateHz)
        let depthOk = (20.0...60.0).contains(depthCents)
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
    case excellent  = "Vibrato Natural"
    case irregular  = "Vibrato Irregular"
    case offRate    = "Taxa Incorreta"
    case shallow    = "Vibrato Raso"
    case none       = "Sem Vibrato"

    var color: String {
        switch self {
        case .excellent:  return "green"
        case .irregular:  return "orange"
        case .offRate:    return "red"
        case .shallow:    return "blue"
        case .none:       return "secondary"
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - NoteSegmenter
// ─────────────────────────────────────────────────────────────────────────────

/// Processa um buffer de áudio completo e retorna segmentos por nota detectada.
///
/// Algoritmo de segmentação:
/// 1. Frame a frame (hop de 512 samples) detecta pitch com VocalPitchDetector
/// 2. Cada pitch é quantizado para a nota MIDI mais próxima
/// 3. Silêncio (nil) ou mudança de nota > `semitoneThreshold` encerra segmento atual
/// 4. Segmentos menores que `minDurationSeconds` são descartados (consoantes, transientes)
/// 5. Para cada segmento: calcula curva de pitch, cents, estabilidade e vibrato
final class NoteSegmenter {

    // MARK: - Configuração

    /// Tamanho do frame de análise por YIN — 4096 samples ≈ 93ms @ 44100Hz
    private let frameSize = 4096

    /// Hop entre frames — 512 samples ≈ 11.6ms @ 44100Hz
    /// Overlap generoso para capturar variações rápidas de pitch
    private let hopSize = 512

    /// Limiar de mudança de nota: distância em semitons para considerar nota diferente
    /// 0.5 semitom = 50 cents — robusto contra vibrato e fluctuações naturais
    private let semitoneThreshold: Float = 0.6

    /// Duração mínima de um segmento para ser considerado nota (não ruído/transiente)
    private let minDurationSeconds: Float = 0.15

    /// Detector de pitch reutilizado em todos os frames
    private let detector = VocalPitchDetector()

    // MARK: - API Pública

    /// Analisa um buffer de áudio completo e retorna segmentos por nota.
    /// - Parameters:
    ///   - samples: Amostras PCM Float normalizadas em [-1, 1]
    ///   - sampleRate: Taxa de amostragem em Hz
    /// - Returns: Array de NoteSegment ordenado cronologicamente
    func analyze(samples: [Float], sampleRate: Float) -> [NoteSegment] {

        var segments: [NoteSegment] = []

        // Acumuladores para o segmento em construção
        var currentNoteMidi: Float? = nil
        var currentFrames: [(time: Float, frequency: Float)] = []
        var segmentStartTime: Float = 0

        let frameCount = (samples.count - frameSize) / hopSize

        for frameIndex in 0..<frameCount {

            let startSample = frameIndex * hopSize
            let endSample   = startSample + frameSize
            guard endSample <= samples.count else { break }

            let frame = Array(samples[startSample..<endSample])
            let timeSeconds = Float(startSample) / sampleRate

            // Detecta pitch do frame atual
            guard let result = detector.detect(buffer: frame, sampleRate: sampleRate) else {
                // Silêncio ou sinal não periódico — finaliza segmento se havia um em curso
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
                // Verifica se mudou de nota (distância em semitons)
                let semitoneDiff = abs(detectedMidi - activeMidi)

                if semitoneDiff > semitoneThreshold {
                    // Nota mudou — finaliza segmento anterior
                    let seg = buildSegment(
                        frames: currentFrames,
                        startTime: segmentStartTime,
                        sampleRate: sampleRate
                    )
                    if let s = seg { segments.append(s) }

                    // Inicia novo segmento
                    currentFrames = [(time: timeSeconds, frequency: result.frequency)]
                    currentNoteMidi = detectedMidi
                    segmentStartTime = timeSeconds

                } else {
                    // Mesma nota — acumula frame
                    // Suaviza o MIDI ativo com média exponencial para evitar falsos splits
                    currentNoteMidi = activeMidi * 0.95 + detectedMidi * 0.05
                    currentFrames.append((time: timeSeconds, frequency: result.frequency))
                }

            } else {
                // Primeiro frame — inicia segmento
                currentNoteMidi = detectedMidi
                currentFrames = [(time: timeSeconds, frequency: result.frequency)]
                segmentStartTime = timeSeconds
            }
        }

        // Finaliza último segmento em aberto
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

    // MARK: - Construção de Segmento

    /// Compila as métricas de um segmento a partir dos frames acumulados.
    private func buildSegment(
        frames: [(time: Float, frequency: Float)],
        startTime: Float,
        sampleRate: Float
    ) -> NoteSegment? {

        guard !frames.isEmpty else { return nil }

        let frequencies = frames.map(\.frequency)
        let duration = (Float(frames.count) * Float(hopSize)) / sampleRate

        // Descarta segmentos muito curtos (transientes, consoantes, glitches)
        guard duration >= minDurationSeconds else { return nil }

        // Frequência mediana — robusta contra outliers de detecção
        let medianFreq = median(of: frequencies)
        guard let theory = MusicTheory.analyze(frequency: medianFreq) else { return nil }

        // Cents em relação à nota alvo (nota quantizada mais próxima)
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

        // Análise de vibrato sobre a curva de cents
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

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Análise de Vibrato
    // ─────────────────────────────────────────────────────────────────────────

    /// Detecta e mede vibrato em uma série temporal de cents.
    ///
    /// Método:
    /// 1. Remove tendência linear (detrend) para isolar a oscilação
    /// 2. Aplica FFT sobre a série de cents
    /// 3. Busca pico de energia na faixa 3–9 Hz (vibrato vocal)
    /// 4. Mede profundidade (amplitude pico a pico) e regularidade (energia do pico / total)
    ///
    /// - Parameters:
    ///   - centsTimeSeries: Array de desvios em cents ao longo do tempo
    ///   - frameRate: Taxa de frames por segundo (sampleRate / hopSize)
    /// - Returns: VibratoAnalysis ou nil se não há vibrato detectável
    private func analyzeVibrato(centsTimeSeries: [Float], frameRate: Float) -> VibratoAnalysis? {

        // Mínimo de ~0.5s de dados para detectar vibrato confiável
        guard centsTimeSeries.count >= Int(frameRate * 0.5) else { return nil }

        // 1. Detrend: subtrai a média para centralizar
        let mean = centsTimeSeries.reduce(0, +) / Float(centsTimeSeries.count)
        var detrended = centsTimeSeries.map { $0 - mean }

        // 2. FFT sobre a série de cents (para detectar periodicidade)
        // Redimensiona para potência de 2 mais próxima
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

        // 3. Busca pico na faixa de vibrato vocal (3–9 Hz)
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

        // 4. Profundidade = 2 * RMS dos cents detrendados → escala para pico a pico
        var rms: Float = 0
        vDSP_rmsqv(detrended, 1, &rms, vDSP_Length(detrended.count))
        let depthCents = rms * 2.83  // ≈ 2√2 para sinal sinusoidal puro

        // 5. Regularidade = energia do pico / energia total na faixa de vibrato
        let totalEnergy = magnitudes[minBin...maxBin].reduce(0, +)
        let regularity = totalEnergy > 0 ? peakMag / totalEnergy : 0

        // Vibrato só é válido se tiver profundidade mínima perceptível (> 10 cents)
        guard depthCents > 10 else { return nil }

        return VibratoAnalysis(
            rateHz: vibratoRateHz,
            depthCents: depthCents,
            regularity: min(1.0, regularity)
        )
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Utilitários
    // ─────────────────────────────────────────────────────────────────────────

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