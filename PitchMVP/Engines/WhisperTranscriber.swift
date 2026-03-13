// WhisperTranscriber.swift
// PitchMVP
//
// Transcrição via API REST própria (Render.com + faster-whisper).
//
// Fluxo simplificado com URL do Supabase:
//   iOS monta a URL pública do arquivo → envia JSON ao servidor
//   Servidor baixa o áudio direto do Supabase → transcreve → retorna palavras
//
// Vantagens vs. upload de arquivo:
//   • Sem upload de áudio pelo iOS (economiza banda e tempo)
//   • Sem timeout de upload em redes lentas
//   • Payload mínimo: JSON com uma string de URL

import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - TranscriptionConfig
// ─────────────────────────────────────────────────────────────────────────────

enum TranscriptionConfig {
    /// URL base do servidor Render após o deploy.
    /// Substitua pela URL gerada no dashboard do Render.com.
    static let serverURL = "https://pitchmvp-transcribe.onrender.com"

    /// Timeout total: 5min — cobre cold start (~30s) + download + transcrição
    static let timeoutSeconds: TimeInterval = 300
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - WhisperTranscriber
// ─────────────────────────────────────────────────────────────────────────────

actor WhisperTranscriber {

    static let shared = WhisperTranscriber()
    private init() {}

    // MARK: - API Pública

    /// Transcreve o áudio identificado pela URL pública do Supabase.
    /// - Parameter audioURL: URL local do cache (usada para extrair bucket/path)
    func transcribe(audioURL: URL) -> AsyncStream<TranscriptionProgress> {
        AsyncStream { continuation in
            Task {
                do {
                    let fileName = audioURL.lastPathComponent
                    print("[Transcribe] Iniciando — \(fileName)")
                    continuation.yield(.loadingModel)

                    // Monta URL pública do Supabase a partir do nome do arquivo em cache
                    let supabaseURL = buildSupabaseURL(from: audioURL)
                    print("[Transcribe] URL Supabase: \(supabaseURL)")

                    // Estima duração pelo tamanho do arquivo em cache
                    let duration       = estimatedDuration(url: audioURL)
                    let estimatedTotal = max(1, Int(ceil(duration / 30.0)))
                    continuation.yield(.transcribing(segment: 0, estimatedTotal: estimatedTotal))

                    // Progresso simulado durante processamento no servidor
                    let progressTask = Task {
                        var tick = 0
                        while !Task.isCancelled {
                            try? await Task.sleep(nanoseconds: 4_000_000_000)
                            guard !Task.isCancelled else { break }
                            tick += 1
                            let simDone = min(tick, max(1, estimatedTotal - 1))
                            continuation.yield(
                                .transcribing(segment: simDone, estimatedTotal: estimatedTotal)
                            )
                            print("[Transcribe] Aguardando servidor... \(simDone)/\(estimatedTotal)")
                        }
                    }

                    let words = try await callAPI(supabaseURL: supabaseURL)
                    progressTask.cancel()

                    print("[Transcribe] \(words.count) palavras recebidas")

                    guard !words.isEmpty else {
                        continuation.yield(.failed(TranscriptionError.emptyTranscript))
                        continuation.finish()
                        return
                    }

                    continuation.yield(.done(words: words))
                    continuation.finish()

                } catch {
                    print("[Transcribe] ERRO: \(error.localizedDescription)")
                    continuation.yield(.failed(error))
                    continuation.finish()
                }
            }
        }
    }

    var isModelReady: Bool { true }
    static func isModelCached() -> Bool { true }
    func unload() {}

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Monta URL Pública do Supabase
    // ─────────────────────────────────────────────────────────────────────────

    /// Converte o path do cache local para a URL pública do Supabase.
    ///
    /// Cache local:  .../SupabaseAudioCache/references_user_001_myimmortal.wav
    /// URL Supabase: https://...supabase.co/storage/v1/object/references/user_001/myimmortal.wav
    ///
    /// Convenção do cache (SupabaseStorageClient):
    ///   cacheKey = "\(bucket)_\(userFolder)_\(fileName)"
    private func buildSupabaseURL(from localURL: URL) -> String {
        let cacheKey = localURL.deletingPathExtension().lastPathComponent
        // cacheKey ex: "references_user_001_myimmortal"
        // ext ex: ".wav"
        let ext = "." + (localURL.pathExtension.isEmpty ? "wav" : localURL.pathExtension)
        let fullKey = cacheKey + ext  // "references_user_001_myimmortal.wav"

        // Separa bucket, userFolder e fileName
        // Formato: {bucket}_{userFolder}_{fileName}
        // user_001 tem underscore, então split no primeiro _ e segundo _
        let parts = fullKey.components(separatedBy: "_")

        // parts[0] = bucket (references ou performances)
        // parts[1] = "user"
        // parts[2] = "001"  (ou número)
        // parts[3...] = nome do arquivo (pode ter underscores)
        guard parts.count >= 4 else {
            // Fallback: tenta usar o nome direto
            return "\(SupabaseConfig.objectURL)/\(fullKey)"
        }

        let bucket     = parts[0]
        let userFolder = parts[1] + "_" + parts[2]  // "user_001"
        let fileName   = parts[3...].joined(separator: "_")  // resto

        return SupabaseConfig.downloadURL(
            bucket:     bucket,
            userFolder: userFolder,
            fileName:   fileName
        )
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Chamada à API
    // ─────────────────────────────────────────────────────────────────────────

    private func callAPI(supabaseURL: String) async throws -> [TimedWord] {
        guard let url = URL(string: "\(TranscriptionConfig.serverURL)/transcribe") else {
            throw TranscriptionAPIError.invalidURL
        }

        // Body JSON: { "audio_url": "https://...", "anon_key": "..." }
        let body = try JSONEncoder().encode([
            "audio_url": supabaseURL,
            "anon_key":  SupabaseConfig.anonKey
        ])

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody   = body
        request.timeoutInterval = TranscriptionConfig.timeoutSeconds

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let detail = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.detail
                ?? String(data: data, encoding: .utf8)
                ?? "Erro \(http.statusCode)"
            throw TranscriptionAPIError.serverError(statusCode: http.statusCode, detail: detail)
        }

        let apiResponse = try JSONDecoder().decode(TranscribeAPIResponse.self, from: data)
        return apiResponse.words.compactMap { w -> TimedWord? in
            let text = w.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return TimedWord(text: text, startTime: w.start)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Helper
    // ─────────────────────────────────────────────────────────────────────────

    private func estimatedDuration(url: URL) -> Double {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int ?? 0
        return Double(size) / 88200.0  // WAV 44100Hz mono ≈ 88200 bytes/s
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Modelos de Resposta
// ─────────────────────────────────────────────────────────────────────────────

private struct TranscribeAPIResponse: Decodable {
    let words:    [APIWord]
    let language: String?
    let duration: Double?
}

private struct APIWord: Decodable {
    let text:  String
    let start: Double
    let end:   Double?
}

private struct APIErrorResponse: Decodable {
    let detail: String
}

enum TranscriptionAPIError: LocalizedError {
    case invalidURL
    case serverError(statusCode: Int, detail: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "URL do servidor inválida. Verifique TranscriptionConfig.serverURL."
        case .serverError(let code, let detail):
            return "Servidor retornou erro \(code): \(detail)"
        }
    }
}