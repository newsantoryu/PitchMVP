//
//  VocalPitchDetector+YIN.swift
//  PitchMVP
//
//  Created by victor on 23/02/26.
//

// VocalPitchDetector+YIN.swift
// PitchMVP
//
// Substitui o detector antigo (FFT+HPS pico máximo) por uma estratégia híbrida:
// - YIN como detector primário (alta precisão sub-cent)
// - FFT+HPS como fallback (mais robusto em sinais com muita energia harmônica)
//
// Como usar: substitua VocalPitchDetector no DSP.swift por esta versão,
// ou adicione este arquivo e remova a classe original do DSP.swift.

import Accelerate
import Foundation
import VocalCore

final class VocalPitchDetector {

    // MARK: - Dependências

    /// Detector YIN — primário, alta precisão
    private let yin: YINDetector

    /// FFT para fallback e validação cruzada
    private let fftSize = 4096
    private let fftProcessor: FFTProcessor
    private let estimator: FrequencyEstimator

    // MARK: - Configuração

    /// Diferença máxima em cents entre YIN e FFT para aceitar YIN como válido.
    /// Se divergirem mais que isso, usa FFT (mais conservador).
    private let maxCrossValidationCents: Float = 50

    // MARK: - Init

    init() {
        self.yin = YINDetector(
            bufferSize: 4096,
            threshold: 0.12,
            minFrequency: 80,   // Cobre vozes masculinas graves (baixo: ~80Hz)
            maxFrequency: 1100  // Cobre vozes femininas agudas (soprano: ~1050Hz)
        )
        self.fftProcessor = FFTProcessor(size: fftSize)
        self.estimator = FrequencyEstimator()
    }

    // MARK: - API Pública (mantém assinatura original)

    /// Detecta a frequência fundamental de um buffer de amostras PCM.
    ///
    /// Estratégia híbrida:
    /// 1. Tenta YIN — mais preciso (< 1 cent de erro típico)
    /// 2. Se YIN falhar, usa FFT+HPS como fallback
    /// 3. Se ambos detectarem, valida por cross-validation em cents
    /// 4. Aplica correção de oitava se `expectedRange` fornecido
    ///
    /// - Parameters:
    ///   - buffer: Amostras PCM Float normalizadas em [-1, 1]
    ///   - sampleRate: Taxa de amostragem em Hz
    ///   - expectedRange: Faixa esperada para correção de sub-harmônicos
    /// - Returns: `PitchResult` com nota e desvio, ou `nil` se não detectado
    func detect(
        buffer: [Float],
        sampleRate: Float,
        expectedRange: ClosedRange<Float>? = nil
    ) -> PitchResult? {

        // --- Caminho 1: YIN (primário) ---
        let yinFrequency = yin.detect(buffer: buffer, sampleRate: sampleRate)

        // --- Caminho 2: FFT+HPS (fallback / validação) ---
        let fftFrequency = detectViaFFT(buffer: buffer, sampleRate: sampleRate)

        // --- Seleção da melhor estimativa ---
        var frequency: Float

        switch (yinFrequency, fftFrequency) {

        case let (yin?, fft?):
            // Ambos detectaram — valida por cross-validation
            let centsDiff = abs(centsDistance(from: yin, to: fft))
            if centsDiff <= maxCrossValidationCents {
                // Concordam — usa YIN (mais preciso)
                frequency = yin
            } else {
                // Divergem muito — usa FFT (mais conservador para vozes harmônicas)
                frequency = fft
            }

        case let (yin?, nil):
            // Só YIN detectou — confia no YIN
            frequency = yin

        case let (nil, fft?):
            // YIN falhou — usa FFT como fallback
            frequency = fft

        case (nil, nil):
            // Nenhum detectou — sinal sem pitch (silêncio, ruído, consoante)
            return nil
        }

        // --- Correção de oitava ---
        // HPS e YIN podem detectar sub-harmônicos (f/2) em certas condições
        if let range = expectedRange {
            while frequency < range.lowerBound { frequency *= 2 }
            while frequency > range.upperBound { frequency /= 2 }
        }

        return MusicTheory.analyze(frequency: frequency)
    }

    // MARK: - Privado

    /// Pipeline FFT+HPS — mantido do detector original para uso como fallback.
    private func detectViaFFT(buffer: [Float], sampleRate: Float) -> Float? {

        guard buffer.count >= fftSize else { return nil }

        let start = max(0, buffer.count / 2 - fftSize / 2)
        var slice = Array(buffer[start..<start + fftSize])

        Windowing.applyHann(to: &slice)

        var magnitudes = fftProcessor.performFFT(input: slice)
        magnitudes = magnitudes.map { sqrt($0) }

        let hps = HarmonicProductSpectrum.apply(to: magnitudes, harmonics: 4) // 4 harmônicos vs 3 antigos

        return estimator.estimate(magnitudes: hps, fftSize: fftSize, sampleRate: sampleRate)
    }

    /// Calcula a distância em cents entre duas frequências.
    /// Positivo = `b` é mais agudo que `a`.
    private func centsDistance(from a: Float, to b: Float) -> Float {
        guard a > 0, b > 0 else { return Float.infinity }
        return 1200 * log2(b / a)
    }
}
