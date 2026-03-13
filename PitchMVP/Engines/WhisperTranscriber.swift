//
//  WhisperTranscriber.swift
//  PitchMVP
//
//  Created by victor on 13/03/26.
//

// WhisperTranscriber.swift
// PitchMVP
//
// Actor responsável exclusivamente por:
//   1. Carregar e cachear o modelo WhisperKit em memória
//   2. Executar a transcrição emitindo progresso real via AsyncStream
//
// Correções críticas em relação à versão anterior:
//
// PROBLEMA 1 — sampleLength: 224 (era o principal causador de travamento em 95%)
//   • sampleLength controla quantos tokens o decoder gera por chunk de 30s.
//   • Com 224, músicas longas excediam o limite → Whisper entrava em loop
//     tentando completar → progredia até 95% e parava.
//   • Correção: sampleLength = 448 (máximo recomendado para small.en).
//
// PROBLEMA 2 — progresso estimado incorreto
//   • O cálculo anterior (segmentCount * 0.05) capeia em 0.95 e não reflete
//     o progresso real. Com arquivos de 3–5min (6–10 segmentos), o progresso
//     pula muito rápido para 95% e fica parado.
//   • Correção: TranscriptPostProcessor.estimatedSegmentCount() calcula o
//     total esperado baseado na duração do áudio → progresso proporcional real.
//
// PROBLEMA 3 — Neural Engine indisponível no simulador
//   • .cpuAndNeuralEngine trava o simulador (sem ANE).
//   • Correção: detecta simulador em compile-time e usa .cpuOnly no sim,
//     .cpuAndNeuralEngine em device físico.

import Foundation
import WhisperKit
import AVFoundation

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - WhisperTranscriber
// ─────────────────────────────────────────────────────────────────────────────

actor WhisperTranscriber {

    // MARK: - Singleton

    static let shared = WhisperTranscriber()

    // MARK: - Configuração

    /// small.en: melhor custo-benefício para inglês vocal.
    /// Sem overhead multilingual, mais preciso que tiny/base em músicas.
    private let modelVariant = "openai_whisper-small.en"

    /// sampleLength = 448 — máximo para small.en.
    /// FIX: era 224 → causava loop/travamento em músicas longas.
    private var decodingOptions: DecodingOptions {
        var opts = DecodingOptions()
        opts.task                   = .transcribe
        opts.language               = "en"
        opts.temperature            = 0.0
        opts.temperatureFallbackCount = 2      // menos fallbacks = mais rápido
        opts.sampleLength           = 448      // FIX: era 224, travava em 95%
        opts.usePrefillPrompt       = true
        opts.usePrefillCache        = true
        opts.suppressBlank          = true
        opts.withoutTimestamps      = false
        opts.wordTimestamps         = true     // necessário para TimedWord
        opts.clipTimestamps         = []
        return opts
    }

    // MARK: - Estado

    private var kit: WhisperKit?
    private var isLoaded = false
    private let postProcessor = TranscriptPostProcessor()

    // MARK: - Init

    private init() {}

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - API Pública
    // ─────────────────────────────────────────────────────────────────────────

    /// Transcreve um arquivo de áudio emitindo progresso real via AsyncStream.
    ///
    /// - Parameter audioURL: URL local do arquivo (já baixado do Supabase)
    /// - Returns: AsyncStream<TranscriptionProgress>
    func transcribe(audioURL: URL) -> AsyncStream<TranscriptionProgress> {
        AsyncStream { continuation in
            Task {
                do {
                    // 1. Modelo
                    continuation.yield(.loadingModel)
                    let whisper = try await self.loadModel()

                    // 2. Estima total de segmentos para progresso proporcional
                    let duration         = audioDuration(url: audioURL)
                    let estimatedTotal   = postProcessor.estimatedSegmentCount(
                        audioDurationSeconds: duration
                    )
                    var segmentsDone = 0

                    continuation.yield(.transcribing(segment: 0, estimatedTotal: estimatedTotal))

                    // 3. Transcreve com callback por segmento
                    let options = self.decodingOptions
                    let results = try await whisper.transcribe(
                        audioPath: audioURL.path,
                        decodeOptions: options
                    ) { _ -> Bool? in
                        segmentsDone += 1
                        continuation.yield(
                            .transcribing(segment: segmentsDone, estimatedTotal: estimatedTotal)
                        )
                        return true   // continua processando
                    }

                    // 4. Extrai TimedWords
                    let timedWords = postProcessor.extractTimedWords(from: results)

                    guard !timedWords.isEmpty else {
                        continuation.yield(.failed(TranscriptionError.emptyTranscript))
                        continuation.finish()
                        return
                    }

                    continuation.yield(.done(words: timedWords))
                    continuation.finish()

                } catch {
                    continuation.yield(.failed(error))
                    continuation.finish()
                }
            }
        }
    }

    // MARK: - Utilitários Públicos

    /// true se o modelo já está em memória (sem download ou load necessário).
    var isModelReady: Bool { isLoaded && kit != nil }

    /// Verifica se o modelo está cacheado em disco — sem rede.
    static func isModelCached() -> Bool {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml")
        return FileManager.default.fileExists(atPath: base.path)
    }

    /// Libera o modelo da memória RAM (útil em background prolongado).
    func unload() {
        kit      = nil
        isLoaded = false
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Carregamento do Modelo
    // ─────────────────────────────────────────────────────────────────────────

    private func loadModel() async throws -> WhisperKit {
        if let existing = kit, isLoaded { return existing }

        // FIX: simulador não tem Neural Engine — .cpuAndNeuralEngine trava o sim.
        // Em device físico usa ANE para máxima velocidade.
        #if targetEnvironment(simulator)
        let compute = ModelComputeOptions(
            audioEncoderCompute: .cpuOnly,
            textDecoderCompute:  .cpuOnly
        )
        #else
        let compute = ModelComputeOptions(
            audioEncoderCompute: .cpuAndNeuralEngine,
            textDecoderCompute:  .cpuAndNeuralEngine
        )
        #endif

        let config = WhisperKitConfig(
            model:          modelVariant,
            computeOptions: compute,
            verbose:        false,
            logLevel:       .error,
            prewarm:        true,
            load:           true,
            download:       true
        )

        let loaded = try await WhisperKit(config)
        kit      = loaded
        isLoaded = true
        return loaded
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Helper: duração do áudio
    // ─────────────────────────────────────────────────────────────────────────

    /// Lê a duração do arquivo de áudio sem carregar samples em memória.
    /// Usado para calcular o total de segmentos esperados.
    private func audioDuration(url: URL) -> Double {
        let asset = AVURLAsset(url: url)
        let duration = asset.duration
        guard duration.isNumeric else { return 180 }  // fallback 3min
        return CMTimeGetSeconds(duration)
    }
}