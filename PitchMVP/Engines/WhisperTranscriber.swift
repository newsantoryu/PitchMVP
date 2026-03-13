// WhisperTranscriber.swift
// PitchMVP
//
// FIX: transcribe() trava no último segmento no simulador.
//
// CAUSA RAIZ: WhisperKit no simulador (cpuOnly) às vezes entra em loop
// no último chunk de áudio — o método nunca retorna.
//
// SOLUÇÃO: withTimeout() — se transcribe() não retornar em (duração * 1.5 + 30)s,
// cancela a task e retorna [] → LyricsAnalyzer usa fallback proporcional.
// No device físico o timeout é generoso (duração * 2 + 60s) para não cortar
// músicas longas em hardware lento.

import Foundation
import WhisperKit
import AVFoundation

actor WhisperTranscriber {

    static let shared = WhisperTranscriber()

    #if targetEnvironment(simulator)
    private let modelVariant = "openai_whisper-tiny.en"
    #else
    private let modelVariant = "openai_whisper-small.en"
    #endif

    private var decodingOptions: DecodingOptions {
        var opts = DecodingOptions()
        opts.task                     = .transcribe
        opts.language                 = "en"
        opts.temperature              = 0.0
        opts.temperatureFallbackCount = 2
        opts.sampleLength             = 448
        opts.usePrefillPrompt         = true
        opts.usePrefillCache          = true
        opts.suppressBlank            = true
        opts.withoutTimestamps        = false
        opts.wordTimestamps           = true
        opts.clipTimestamps           = []
        return opts
    }

    private var kit: WhisperKit?
    private var isLoaded = false
    private let postProcessor = TranscriptPostProcessor()

    private init() {}

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - API Pública
    // ─────────────────────────────────────────────────────────────────────────

    func transcribe(audioURL: URL) -> AsyncStream<TranscriptionProgress> {
        AsyncStream { continuation in
            Task {
                do {
                    print("[Whisper] Iniciando — \(audioURL.lastPathComponent)")

                    continuation.yield(.loadingModel)
                    let whisper = try await self.loadModel()
                    print("[Whisper] Modelo '\(self.modelVariant)' carregado")

                    let duration       = self.audioDuration(url: audioURL)
                    let estimatedTotal = self.postProcessor.estimatedSegmentCount(
                        audioDurationSeconds: duration
                    )
                    print("[Whisper] Duração: \(Int(duration))s — ~\(estimatedTotal) segmentos")
                    continuation.yield(.transcribing(segment: 0, estimatedTotal: estimatedTotal))

                    // Timeout: 1.5x a duração do áudio + 30s de folga
                    // No simulador é mais generoso porque cpuOnly é lento
                    #if targetEnvironment(simulator)
                    let timeoutSeconds = duration * 2.0 + 60.0
                    #else
                    let timeoutSeconds = duration * 1.5 + 30.0
                    #endif
                    print("[Whisper] Timeout configurado: \(Int(timeoutSeconds))s")

                    // Progresso simulado
                    let progressTask = Task {
                        var tick = 0
                        while !Task.isCancelled {
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                            guard !Task.isCancelled else { break }
                            tick += 1
                            let simDone = min(tick, max(1, estimatedTotal - 1))
                            continuation.yield(
                                .transcribing(segment: simDone, estimatedTotal: estimatedTotal)
                            )
                        }
                    }

                    // Transcreve com timeout
                    let options = self.decodingOptions
                    print("[Whisper] Transcrevendo (timeout: \(Int(timeoutSeconds))s)...")

                    let results = try await withTimeout(seconds: timeoutSeconds) {
                        try await whisper.transcribe(
                            audioPath: audioURL.path,
                            decodeOptions: options
                        )
                    }

                    progressTask.cancel()

                    let segCount = results?.flatMap { $0.segments }.count ?? 0
                    print("[Whisper] Concluído — \(segCount) segmento(s)")

                    let timedWords = self.postProcessor.extractTimedWords(from: results ?? [])
                    print("[Whisper] \(timedWords.count) palavras extraídas")

                    // Aceita resultado mesmo que vazio — LyricsAnalyzer usa fallback
                    if timedWords.isEmpty {
                        print("[Whisper] Nenhuma palavra extraída — usando fallback proporcional")
                    }

                    continuation.yield(.done(words: timedWords))
                    continuation.finish()

                } catch {
                    print("[Whisper] ERRO: \(error.localizedDescription)")
                    continuation.yield(.failed(error))
                    continuation.finish()
                }
            }
        }
    }

    // MARK: - Utilitários

    var isModelReady: Bool { isLoaded && kit != nil }

    static func isModelCached() -> Bool {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml")
        return FileManager.default.fileExists(atPath: base.path)
    }

    func unload() {
        kit      = nil
        isLoaded = false
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Carregamento
    // ─────────────────────────────────────────────────────────────────────────

    private func loadModel() async throws -> WhisperKit {
        if let existing = kit, isLoaded {
            print("[Whisper] Reutilizando modelo em memória")
            return existing
        }

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
            prewarm:        false,
            load:           true,
            download:       true
        )

        let loaded = try await WhisperKit(config)
        kit      = loaded
        isLoaded = true
        return loaded
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - withTimeout
    // ─────────────────────────────────────────────────────────────────────────

    /// Executa `operation` com timeout. Retorna nil se exceder o tempo.
    /// Não lança erro no timeout — retorna nil para que o caller use fallback.
    private func withTimeout<T: Sendable>(
        seconds: Double,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T? {
        let nanoseconds = UInt64(seconds * 1_000_000_000)

        return try await withThrowingTaskGroup(of: T?.self) { group in
            // Task principal
            group.addTask {
                try await operation()
            }

            // Task de timeout
            group.addTask {
                try await Task.sleep(nanoseconds: nanoseconds)
                print("[Whisper] ⚠️ Timeout atingido (\(Int(seconds))s) — encerrando transcrição")
                return nil
            }

            // Pega o primeiro que terminar (resultado real ou nil do timeout)
            let result = try await group.next()
            group.cancelAll()
            return result ?? nil
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Helper
    // ─────────────────────────────────────────────────────────────────────────

    private func audioDuration(url: URL) -> Double {
        let asset = AVURLAsset(url: url)
        let d = asset.duration
        guard d.isNumeric else { return 180 }
        return CMTimeGetSeconds(d)
    }
}