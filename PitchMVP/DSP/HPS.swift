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

/// Aplica funções de janelamento a buffers de amostras antes da FFT.
/// Janelamento reduz o vazamento espectral (spectral leakage) causado
/// pelo truncamento do sinal em blocos finitos.
struct Windowing {

    /// Aplica a janela de Hann ao buffer in-place usando vDSP (SIMD otimizado).
    /// Hann é a escolha padrão para análise de pitch — bom equilíbrio entre
    /// resolução de frequência e supressão de lóbulos laterais.
    /// - Parameter buffer: Buffer de amostras — modificado in-place
    static func applyHann(to buffer: inout [Float]) {
        var window = [Float](repeating: 0, count: buffer.count)

        // vDSP_hann_window gera a janela normalizada diretamente
        vDSP_hann_window(&window, vDSP_Length(buffer.count), Int32(vDSP_HANN_NORM))

        // Multiplicação elemento a elemento: buffer[i] *= window[i]
        vDSP_vmul(buffer, 1, window, 1, &buffer, 1, vDSP_Length(buffer.count))
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - FFTProcessor
// ─────────────────────────────────────────────────────────────────────────────

/// Calcula a FFT de um sinal de áudio usando Accelerate (vDSP) para performance SIMD.
/// Retorna o espectro de magnitudes (power spectrum) da metade positiva da FFT.
///
/// Thread-safety: não é thread-safe — crie uma instância por thread se necessário.
final class FFTProcessor {

    // MARK: Propriedades

    /// Setup pré-alocado da FFT — reutilizado em todas as chamadas para evitar overhead
    private let fftSetup: FFTSetup

    /// Log2 do tamanho da FFT — parâmetro interno do vDSP
    private let log2n: vDSP_Length

    /// Tamanho total da janela de análise (deve ser potência de 2)
    private let fftSize: Int

    /// Metade do tamanho — número de bins úteis (frequências positivas)
    private let halfSize: Int

    // MARK: Init / Deinit

    /// - Parameter size: Tamanho da FFT. **Deve ser potência de 2** (ex: 2048, 4096).
    ///   Tamanhos maiores = maior resolução de frequência, menor resolução temporal.
    init(size: Int) {
        self.fftSize = size
        self.halfSize = size / 2
        self.log2n = vDSP_Length(log2(Float(size)))

        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            fatalError("[FFTProcessor] Falha ao alocar FFT setup para tamanho \(size)")
        }

        self.fftSetup = setup
    }

    deinit {
        // Libera memória do setup vDSP alocada no init
        vDSP_destroy_fftsetup(fftSetup)
    }

    // MARK: API Pública

    /// Executa FFT forward e retorna o espectro de magnitudes quadráticas (power spectrum).
    /// - Parameter input: Array de amostras reais com tamanho == `fftSize`
    /// - Returns: Array de `halfSize` magnitudes² — índice i corresponde à frequência `i * (sampleRate / fftSize)`
    func performFFT(input: [Float]) -> [Float] {
        // A FFT do vDSP opera in-place no formato split-complex (real + imag separados)
        var real = input
        var imag = [Float](repeating: 0, count: fftSize)

        var splitComplex = DSPSplitComplex(realp: &real, imagp: &imag)

        // FFT forward in-place
        vDSP_fft_zip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))

        // Calcula magnitudes²: mag[i] = real[i]² + imag[i]²
        var magnitudes = [Float](repeating: 0, count: halfSize)
        vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfSize))

        return magnitudes
    }

    /// Calcula magnitudes a partir de componentes real e imaginário já separados.
    /// Alternativa ao `performFFT` quando os componentes já estão disponíveis.
    /// - Note: Implementação escalar — use `performFFT` para performance máxima.
    func computeMagnitudes(real: [Float], imag: [Float]) -> [Float] {
        zip(real, imag).map { r, i in sqrt(r * r + i * i) }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - HarmonicProductSpectrum
// ─────────────────────────────────────────────────────────────────────────────

/// Técnica de estimativa de pitch que reforça a frequência fundamental
/// multiplicando o espectro por versões decimadas de si mesmo.
///
/// Intuição: a fundamental e seus harmônicos (2f, 3f, 4f...) se reforçam
/// quando o espectro é multiplicado pelas versões sub-amostradas,
/// enquanto ruído e parciais não-harmônicos se cancelam.
struct HarmonicProductSpectrum {

    /// Aplica HPS ao espectro de magnitudes.
    /// - Parameters:
    ///   - magnitudes: Espectro de entrada (output do FFTProcessor)
    ///   - harmonics: Número de harmônicos a considerar (padrão: 3)
    /// - Returns: Espectro processado — pico principal corresponde à fundamental
    static func apply(to magnitudes: [Float], harmonics: Int = 3) -> [Float] {
        var hps = magnitudes

        // Para cada harmônico h (2, 3, ... harmonics):
        // hps[i] *= magnitudes[i * h]  — multiplica pelo bin do h-ésimo harmônico
        for h in 2...harmonics {
            for i in 0..<magnitudes.count {
                let harmonicIndex = i * h

                // Interrompe ao sair dos limites do array (bins de alta frequência)
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

/// Localiza o bin de maior magnitude dentro de uma faixa de frequência esperada.
/// Usado após o HPS para identificar a frequência fundamental dominante.
final class FrequencyEstimator {

    // Faixa de busca padrão — cobre a maioria das vozes humanas
    private let minFrequency: Float = 120
    private let maxFrequency: Float = 400

    /// Estima a frequência fundamental pelo método do pico máximo.
    /// - Parameters:
    ///   - magnitudes: Espectro de magnitudes (output do HPS)
    ///   - fftSize: Tamanho da FFT usada para gerar o espectro
    ///   - sampleRate: Taxa de amostragem do sinal original (Hz)
    /// - Returns: Frequência estimada em Hz, ou `nil` se nenhum pico válido for encontrado
    func estimate(magnitudes: [Float], fftSize: Int, sampleRate: Float) -> Float? {

        guard !magnitudes.isEmpty else { return nil }

        // Resolução por bin: quantos Hz cada índice representa
        let binResolution = sampleRate / Float(fftSize)

        // Converte frequências min/max para índices de bin
        let minIndex = Int(minFrequency / binResolution)
        let maxIndex = min(Int(maxFrequency / binResolution), magnitudes.count - 1)

        // Busca o bin de maior magnitude dentro da faixa de interesse
        var maxMagnitude: Float = 0
        var peakIndex: Int = 0

        for i in minIndex...maxIndex {
            if magnitudes[i] > maxMagnitude {
                maxMagnitude = magnitudes[i]
                peakIndex = i
            }
        }

        guard maxMagnitude > 0 else { return nil }

        // Converte índice de bin para frequência em Hz
        return Float(peakIndex) * binResolution
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - MusicTheory
// ─────────────────────────────────────────────────────────────────────────────

/// Converte uma frequência em Hz para sua representação musical (nota + oitava + cents).
/// Usa o sistema de temperamento igual com A4 = 440 Hz como referência.
struct MusicTheory {

    private static let noteNames = [
        "C", "C#", "D", "D#",
        "E", "F", "F#",
        "G", "G#", "A",
        "A#", "B"
    ]

    /// Analisa uma frequência e retorna a nota mais próxima com desvio em cents.
    /// - Parameter frequency: Frequência em Hz (deve ser > 0)
    /// - Returns: `PitchResult` com nota, MIDI e desvio, ou `nil` para frequência inválida
    static func analyze(frequency: Float) -> PitchResult? {

        guard frequency > 0 else { return nil }

        // Número MIDI contínuo: A4 = 69, cada semitom = 1 unidade
        // midi = 69 + 12 * log2(f / 440)
        let midi = 69 + 12 * log2(frequency / 440)
        let roundedMidi = round(midi)

        // Desvio em cents em relação à nota MIDI mais próxima
        let cents = (midi - roundedMidi) * 100

        // Extrai nome da nota e oitava a partir do MIDI arredondado
        let noteIndex = Int(roundedMidi) % 12
        let octave    = Int(roundedMidi) / 12 - 1
        let name      = noteNames[noteIndex] + "\(octave)"

        return PitchResult(
            frequency: frequency,
            midNote: midi,
            noteName: name,
            cents: cents
        )
    }
}
