// DSP.swift
// PitchMVP — Pipeline de detecção de pitch
//
// Fluxo completo:
// Buffer PCM → Windowing (Hann) → FFT → magnitude → HPS → FrequencyEstimator
//           → correção de sub-harmônicos → MusicTheory.analyze → PitchResult

import Accelerate
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Windowing
// ─────────────────────────────────────────────────────────────────────────────

struct Windowing {

    static func applyHann(to buffer: inout [Float]) {
        var window = [Float](repeating: 0, count: buffer.count)
        vDSP_hann_window(&window, vDSP_Length(buffer.count), Int32(vDSP_HANN_NORM))
        vDSP_vmul(buffer, 1, window, 1, &buffer, 1, vDSP_Length(buffer.count))
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - FFTProcessor
// ─────────────────────────────────────────────────────────────────────────────

final class FFTProcessor {

    private let fftSetup: FFTSetup
    private let log2n: vDSP_Length
    private let fftSize: Int
    private let halfSize: Int

    init(size: Int) {
        self.fftSize  = size
        self.halfSize = size / 2
        self.log2n    = vDSP_Length(log2(Float(size)))

        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            fatalError("[FFTProcessor] Falha ao alocar FFT setup para tamanho \(size)")
        }
        self.fftSetup = setup
    }

    deinit { vDSP_destroy_fftsetup(fftSetup) }

    func performFFT(input: [Float]) -> [Float] {
        var real = input
        var imag = [Float](repeating: 0, count: fftSize)
        var splitComplex = DSPSplitComplex(realp: &real, imagp: &imag)
        vDSP_fft_zip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))

        var magnitudes = [Float](repeating: 0, count: halfSize)
        vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfSize))
        return magnitudes
    }

    func computeMagnitudes(real: [Float], imag: [Float]) -> [Float] {
        zip(real, imag).map { r, i in sqrt(r * r + i * i) }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - HarmonicProductSpectrum
// ─────────────────────────────────────────────────────────────────────────────

struct HarmonicProductSpectrum {

    static func apply(to magnitudes: [Float], harmonics: Int = 4) -> [Float] {
        var hps = magnitudes

        for h in 2...harmonics {
            for i in 0..<magnitudes.count {
                let harmonicIndex = i * h
                guard harmonicIndex < magnitudes.count else { break }
                hps[i] *= magnitudes[harmonicIndex]
            }
        }
        return hps
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - FrequencyEstimator
// ─────────────────────────────────────────────────────────────────────────────

/// Localiza o bin de maior magnitude dentro da faixa completa de vozes humanas.
///
/// CORREÇÃO: faixa anterior (120–400 Hz) cortava sopranos e mezzosopranos,
/// causando falhas no fallback FFT para referências femininas acima de 400 Hz.
/// Nova faixa (80–1100 Hz) cobre:
///   - Baixo profundo: ~80 Hz
///   - Soprano agudo:  ~1050 Hz
final class FrequencyEstimator {

    // ✅ CORRIGIDO: era 120–400 Hz — não cobria vozes femininas agudas
    private let minFrequency: Float = 80
    private let maxFrequency: Float = 1100

    func estimate(magnitudes: [Float], fftSize: Int, sampleRate: Float) -> Float? {

        guard !magnitudes.isEmpty else { return nil }

        let binResolution = sampleRate / Float(fftSize)
        let minIndex = max(1, Int(minFrequency / binResolution))
        let maxIndex = min(Int(maxFrequency / binResolution), magnitudes.count - 1)

        guard minIndex < maxIndex else { return nil }

        var maxMagnitude: Float = 0
        var peakIndex: Int = minIndex

        for i in minIndex...maxIndex {
            if magnitudes[i] > maxMagnitude {
                maxMagnitude = magnitudes[i]
                peakIndex = i
            }
        }

        guard maxMagnitude > 0 else { return nil }
        return Float(peakIndex) * binResolution
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - MusicTheory
// ─────────────────────────────────────────────────────────────────────────────

struct MusicTheory {

    private static let noteNames = [
        "C", "C#", "D", "D#",
        "E", "F", "F#",
        "G", "G#", "A",
        "A#", "B"
    ]

    static func analyze(frequency: Float) -> PitchResult? {
        guard frequency > 0 else { return nil }

        let midi        = 69 + 12 * log2(frequency / 440)
        let roundedMidi = round(midi)
        let cents       = (midi - roundedMidi) * 100

        let noteIndex = ((Int(roundedMidi) % 12) + 12) % 12  // guard negativo
        let octave    = Int(roundedMidi) / 12 - 1
        let name      = noteNames[noteIndex] + "\(octave)"

        return PitchResult(
            frequency: frequency,
            midNote: midi,
            noteName: name,
            cents: cents
        )
    }

    /// Retorna apenas o nome da nota sem oitava (ex: "C#" de "C#3").
    /// Usado no alinhamento por grau melódico para comparar vozes em oitavas diferentes.
    static func pitchClass(from noteName: String) -> String {
        // Remove dígitos e sinal negativo da oitava — mantém só a nota (ex: "C#", "A")
        return noteName.components(separatedBy: CharacterSet.decimalDigits.union(CharacterSet(charactersIn: "-"))).first ?? noteName
    }
}