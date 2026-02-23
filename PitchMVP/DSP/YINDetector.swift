//
//  YINDetector.swift
//  PitchMVP
//
//  Created by victor on 23/02/26.
//

// YINDetector.swift
// PitchMVP
//
// Implementação do algoritmo YIN para detecção de pitch.
// Referência: De Cheveigné & Kawahara (2002) — "YIN, a fundamental frequency estimator"
//
// Vantagens sobre FFT+HPS:
// - Precisão sub-bin (não limitado pela resolução da FFT ~10Hz)
// - Melhor performance em vozes com harmônicos fracos
// - Menos sensível a ruído de fundo
// - Erro típico < 1 cent vs ~5-10 cents do FFT pico máximo

import Accelerate
import Foundation

final class YINDetector {

    // MARK: - Configuração

    /// Tamanho da janela de análise — maior = mais preciso em graves, mais lento
    private let bufferSize: Int

    /// Limiar de confiança do YIN — valores entre 0.10 e 0.15 são recomendados.
    /// Menor = mais restritivo (menos falsos positivos, mais "nil").
    /// Maior = mais permissivo (mais detecções, possíveis erros de oitava).
    private let threshold: Float

    /// Faixa de frequências válidas para busca (Hz)
    private let minFrequency: Float
    private let maxFrequency: Float

    // MARK: - Init

    init(
        bufferSize: Int = 4096,
        threshold: Float = 0.12,
        minFrequency: Float = 80,
        maxFrequency: Float = 1100
    ) {
        self.bufferSize  = bufferSize
        self.threshold   = threshold
        self.minFrequency  = minFrequency
        self.maxFrequency  = maxFrequency
    }

    // MARK: - API Pública

    /// Detecta a frequência fundamental usando o algoritmo YIN.
    /// - Parameters:
    ///   - buffer: Amostras PCM Float normalizadas em [-1, 1]
    ///   - sampleRate: Taxa de amostragem em Hz (ex: 44100)
    /// - Returns: Frequência fundamental em Hz, ou `nil` se não detectada com confiança
    func detect(buffer: [Float], sampleRate: Float) -> Float? {

        guard buffer.count >= bufferSize else { return nil }

        // Usa janela central do buffer para evitar transientes nas bordas
        let start = max(0, buffer.count / 2 - bufferSize / 2)
        let slice = Array(buffer[start..<start + bufferSize])

        // Limites de tau (período em samples) baseados na faixa de frequência
        let tauMin = Int(sampleRate / maxFrequency)
        let tauMax = Int(sampleRate / minFrequency)

        guard tauMax < bufferSize / 2 else { return nil }

        // Passo 1-2: Função de diferença e normalização CMNDF
        let cmndf = computeCMNDF(signal: slice, tauMax: tauMax)

        // Passo 3: Busca do primeiro vale abaixo do threshold
        guard let tau = absoluteThreshold(cmndf: cmndf, tauMin: tauMin, tauMax: tauMax) else {
            return nil
        }

        // Passo 4: Interpolação parabólica para precisão sub-sample
        let refinedTau = parabolicInterpolation(cmndf: cmndf, tau: tau)

        // Converte período (samples) → frequência (Hz)
        let frequency = sampleRate / refinedTau
        return frequency
    }

    // MARK: - Passos do Algoritmo YIN

    /// Passo 1 + 2: Calcula a Cumulative Mean Normalized Difference Function (CMNDF).
    ///
    /// A função de diferença d(τ) mede o quão diferente o sinal é de si mesmo
    /// deslocado por τ samples. Quando τ = período fundamental, d(τ) ≈ 0.
    ///
    /// CMNDF normaliza d(τ) pela sua média acumulada, tornando o threshold
    /// independente da amplitude do sinal.
    private func computeCMNDF(signal: [Float], tauMax: Int) -> [Float] {
        let halfSize = bufferSize / 2
        var diff = [Float](repeating: 0, count: tauMax + 1)

        // d(τ) = Σ (x[t] - x[t+τ])²  usando autocorrelação via vDSP para performance
        // Equivalente a: d(τ) = r(0) + r(0) - 2*r(τ)  onde r é a autocorrelação
        var acf = [Float](repeating: 0, count: halfSize)
        vDSP_conv(signal, 1, signal, 1, &acf, 1, vDSP_Length(halfSize), vDSP_Length(halfSize))

        // r(0) = energia total do sinal
        let r0 = acf[0]

        for tau in 1...tauMax {
            // d(τ) = 2 * (r(0) - r(τ))
            diff[tau] = 2 * (r0 - acf[tau])
        }

        // Normalização CMNDF: d'(τ) = d(τ) / [(1/τ) * Σ d(j), j=1..τ]
        var cmndf = [Float](repeating: 0, count: tauMax + 1)
        cmndf[0] = 1.0  // convenção: CMNDF[0] = 1

        var runningSum: Float = 0
        for tau in 1...tauMax {
            runningSum += diff[tau]
            // Evita divisão por zero quando runningSum é muito pequeno (sinal silencioso)
            guard runningSum > 1e-10 else {
                cmndf[tau] = 1.0
                continue
            }
            cmndf[tau] = diff[tau] / (runningSum / Float(tau))
        }

        return cmndf
    }

    /// Passo 3: Encontra o primeiro mínimo local da CMNDF abaixo do threshold.
    ///
    /// Estratégia: busca o tau onde CMNDF cruza o threshold pela primeira vez
    /// e retorna o mínimo local dentro dessa região — evita detectar sub-harmônicos.
    private func absoluteThreshold(cmndf: [Float], tauMin: Int, tauMax: Int) -> Int? {

        var tau = tauMin

        // Avança até encontrar um ponto abaixo do threshold
        while tau <= tauMax {
            if cmndf[tau] < threshold {
                // Encontrou cruzamento — busca o mínimo local a partir daqui
                var minTau = tau
                var minVal = cmndf[tau]

                while tau + 1 <= tauMax && cmndf[tau + 1] < cmndf[tau] {
                    tau += 1
                    if cmndf[tau] < minVal {
                        minVal = cmndf[tau]
                        minTau = tau
                    }
                }
                return minTau
            }
            tau += 1
        }

        // Sem vale abaixo do threshold — sinal não periódico ou silêncio
        return nil
    }

    /// Passo 4: Interpolação parabólica para refinar o tau com precisão sub-sample.
    ///
    /// Usa os 3 pontos ao redor do mínimo para ajustar uma parábola e encontrar
    /// o mínimo verdadeiro — isso é o que dá ao YIN precisão de < 1 cent.
    private func parabolicInterpolation(cmndf: [Float], tau: Int) -> Float {

        // Garante que temos vizinhos válidos para interpolação
        guard tau > 0, tau < cmndf.count - 1 else { return Float(tau) }

        let s0 = cmndf[tau - 1]
        let s1 = cmndf[tau]
        let s2 = cmndf[tau + 1]

        let denominator = s0 - 2 * s1 + s2

        // Se a parábola é plana (denominador ≈ 0), usa o tau inteiro diretamente
        guard abs(denominator) > 1e-6 else { return Float(tau) }

        // Offset do mínimo da parábola em relação ao tau inteiro
        let offset = (s0 - s2) / (2 * denominator)

        // Clampeia em [-1, 1] para não sair da região de busca
        return Float(tau) + max(-1, min(1, offset))
    }
}