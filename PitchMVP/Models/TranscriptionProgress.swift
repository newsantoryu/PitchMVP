//
//  Created by victor on 13/03/26.
//
// TranscriptionModels.swift
// PitchMVP
//
// Tipos compartilhados pelo pipeline de transcrição:
//   TranscriptionProgress  — estados emitidos via AsyncStream para a UI
//   TranscriptionError     — erros tipados com mensagem localizada
//   TimedWord              — palavra com timestamp para alinhamento nota←→letra
//   TranscriptionResult    — resultado final consolidado

import Foundation
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - TranscriptionProgress
// ─────────────────────────────────────────────────────────────────────────────

enum TranscriptionProgress: Sendable {
    case loadingModel
    case transcribing(segment: Int, estimatedTotal: Int)
    case done(words: [TimedWord])
    case failed(Error)

    var progressValue: Double {
        switch self {
        case .loadingModel:                             return 0.05
        case .transcribing(let s, let total):
            guard total > 0 else { return 0.1 }
            // Mapeia segmento atual para 0.10 → 0.95
            return 0.10 + min(0.85, Double(s) / Double(total) * 0.85)
        case .done:                                     return 1.0
        case .failed:                                   return 0.0
        }
    }

    var message: String {
        switch self {
        case .loadingModel:
            return "Carregando modelo Whisper..."
        case .transcribing(let s, let total):
            if total > 0 { return "Transcrevendo... trecho \(s)/\(total)" }
            return "Transcrevendo trecho \(s)..."
        case .done:
            return "Transcrição concluída"
        case .failed:
            return "Erro na transcrição"
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - TranscriptionError
// ─────────────────────────────────────────────────────────────────────────────

enum TranscriptionError: LocalizedError {
    case modelLoadFailed(String)
    case transcriptionFailed(String)
    case emptyTranscript
    case audioTooShort

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let m):     return "Falha ao carregar Whisper: \(m)"
        case .transcriptionFailed(let m): return "Transcrição falhou: \(m)"
        case .emptyTranscript:            return "Nenhuma letra detectada no áudio."
        case .audioTooShort:              return "Áudio muito curto (mínimo 2s)."
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - TimedWord
// ─────────────────────────────────────────────────────────────────────────────

/// Palavra com timestamp (segundos) extraída do Whisper wordTimestamps.
/// Usada pelo LyricsAnalyzer para alinhar letra → NoteSegment por tempo.
struct TimedWord: Sendable {
    let text:      String
    let startTime: Double   // segundos desde o início do áudio
}