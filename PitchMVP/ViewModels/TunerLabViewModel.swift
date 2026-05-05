// TunerLabViewModel.swift
// PitchMVP

import Foundation
import SwiftUI
import VocalCore

/// ViewModel da tela de Lab — executa testes automatizados de detecção de pitch
/// usando ondas senoidais sintéticas como entrada, sem necessidade de microfone.
///
/// Objetivo: validar a precisão do `VocalPitchDetector` em frequências conhecidas
/// para vozes masculinas e femininas, com variações de ±5Hz.
final class TunerLabViewModel: ObservableObject {

    // MARK: - Modelo de Resultado

    /// Resultado de um teste individual de detecção de pitch.
    struct PitchTestResult: Identifiable {

        let id = UUID()

        /// Identificador legível do teste (ex: "Male ±0Hz")
        let label: String

        /// Frequência que foi usada para gerar o sinal sintético
        let targetFrequency: Float

        /// Frequência detectada pelo `VocalPitchDetector`
        let detectedFrequency: Float

        /// Nome da nota detectada (ex: "A3", "E4")
        let note: String

        /// Desvio em cents entre frequência detectada e alvo
        /// Positivo = agudo, Negativo = grave
        let cents: Double

        /// Indica se o teste passou dentro da tolerância definida
        let pass: Bool

        // MARK: Computed — usados pela View para feedback visual

        /// Instrução de direção baseada no desvio em cents
        var direction: String {
            if cents > 5  { return "🔽 Desça um pouco..." }
            if cents < -5 { return "🔼 Suba um pouco..." }
            return "🎯 Perfeito"
        }

        /// Considera afinado quando desvio é menor que 5 cents (limiar perceptível)
        var isInTune: Bool {
            abs(cents) < 5
        }

        /// Dica de intensidade de ajuste baseada no desvio absoluto
        var intensityHint: String {
            switch abs(cents) {
            case 0..<5:  return "Excelente controle"
            case 5..<15: return "Quase lá"
            case 15..<30: return "Ajuste moderado"
            default:     return "Grande ajuste necessário"
            }
        }
    }

    // MARK: - Output Publicado

    /// Lista de resultados exibida pela View após execução dos testes
    @Published var results: [PitchTestResult] = []

    // MARK: - Dependências

    /// Detector de pitch — reutilizado para todos os testes
    private let detector = VocalPitchDetector()

    // MARK: - Configuração dos Testes

    /// Frequências representativas de vozes masculinas (Hz)
    let maleFrequencies: [Float] = [110, 123.47, 130.81]   // A2, B2, C3

    /// Frequências representativas de vozes femininas (Hz)
    let femaleFrequencies: [Float] = [261.63, 293.66, 329.63] // C4, D4, E4

    /// Tolerância máxima em cents para considerar um teste como aprovado
    private let toleranceCents = 20.0

    /// Faixa esperada de frequência para vozes masculinas — usada para corrigir sub-harmônicos
    private let maleRange: ClosedRange<Float> = 85...180

    /// Faixa esperada de frequência para vozes femininas — usada para corrigir sub-harmônicos
    private let femaleRange: ClosedRange<Float> = 165...400

    // MARK: - API Pública

    /// Executa todos os testes de pitch e popula `results`.
    /// Cada frequência é testada com 3 variações: -5Hz, 0Hz, +5Hz.
    func runPitchTests() {
        results.removeAll()
        let sampleRate: Float = 44100.0

        for freq in maleFrequencies {
            simulateVoiceTest(freq: freq, label: "Male", sampleRate: sampleRate, range: maleRange)
        }

        for freq in femaleFrequencies {
            simulateVoiceTest(freq: freq, label: "Female", sampleRate: sampleRate, range: femaleRange)
        }
    }

    // MARK: - Privado

    /// Gera e testa uma frequência com variações de -5, 0 e +5Hz.
    /// - Parameters:
    ///   - freq: Frequência base do teste em Hz
    ///   - label: Prefixo do label (ex: "Male", "Female")
    ///   - sampleRate: Taxa de amostragem usada na geração do sinal
    ///   - range: Faixa esperada para correção de sub-harmônicos no detector
    private func simulateVoiceTest(
        freq: Float,
        label: String,
        sampleRate: Float,
        range: ClosedRange<Float>
    ) {
        // Testa a frequência exata e com desvios de ±5Hz para verificar robustez
        let variations: [Float] = [-5, 0, 5]

        for varFreq in variations {
            let testFreq = freq + varFreq

            // Gera onda senoidal pura — entrada ideal para o detector
            let samples = generateSineWave(frequency: testFreq, sampleRate: sampleRate, duration: 1.0)

            // Detecta a frequência — `nil` indica buffer insuficiente ou falha do HPS
            guard let detected = detector.detect(
                buffer: samples,
                sampleRate: sampleRate,
                expectedRange: range
            ) else { continue }

            let pass = abs(detected.cents) <= Float(toleranceCents)

            let result = PitchTestResult(
                label: "\(label) ±\(Int(varFreq))Hz",
                targetFrequency: testFreq,
                detectedFrequency: detected.frequency,
                note: detected.noteName,
                cents: Double(detected.cents),
                pass: pass
            )

            results.append(result)
        }
    }

    /// Gera um array de amostras de onda senoidal pura.
    /// - Parameters:
    ///   - frequency: Frequência da onda em Hz
    ///   - sampleRate: Taxa de amostragem (ex: 44100)
    ///   - duration: Duração em segundos
    /// - Returns: Array de Float com as amostras normalizadas em [-1, 1]
    private func generateSineWave(frequency: Float, sampleRate: Float, duration: Float) -> [Float] {
        let totalSamples = Int(sampleRate * duration)

        // sin(2π * f * t) onde t = i / sampleRate
        return (0..<totalSamples).map { i in
            Float(sin(2.0 * .pi * frequency * Float(i) / sampleRate))
        }
    }
}
