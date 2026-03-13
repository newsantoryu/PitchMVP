//
//  TranscriptPostProcessor.swift
//  PitchMVP
//
//  Created by victor on 13/03/26.
//

// TranscriptPostProcessor.swift
// PitchMVP
//
// Responsabilidade única: limpar e estruturar o texto bruto retornado pelo Whisper.
//
// Separado do WhisperTranscriber para:
//   • Facilitar testes unitários (puro, sem dependência de WhisperKit)
//   • Trocar lógica de pós-processamento sem tocar no pipeline de transcrição
//   • Manter o WhisperTranscriber focado em I/O de modelo

import Foundation
import WhisperKit

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - TranscriptPostProcessor
// ─────────────────────────────────────────────────────────────────────────────

struct TranscriptPostProcessor {

    // MARK: - API Principal

    /// Extrai [TimedWord] dos segmentos brutos do Whisper.
    ///
    /// Prioridade:
    ///   1. wordTimestamps do segmento (precisão máxima — palavra por palavra)
    ///   2. Timestamp do segmento distribuído linearmente pelas palavras (fallback)
    func extractTimedWords(from results: [TranscriptionResult]) -> [TimedWord] {
        var output: [TimedWord] = []

        for result in results {
            for segment in result.segments {
                let words = extractWords(from: segment)
                output.append(contentsOf: words)
            }
        }

        return output
    }

    /// Estima o total de segmentos para cálculo de progresso preciso.
    /// Baseado na duração do áudio: Whisper processa em chunks de ~30s.
    func estimatedSegmentCount(audioDurationSeconds: Double) -> Int {
        max(1, Int(ceil(audioDurationSeconds / 30.0)))
    }

    // MARK: - Extração por Segmento

    private func extractWords(from segment: TranscriptionSegment) -> [TimedWord] {
        // Caminho 1: wordTimestamps disponíveis → precisão máxima
        if let wordTokens = segment.words, !wordTokens.isEmpty {
            return wordTokens.compactMap { token -> TimedWord? in
                let text = clean(token.word)
                guard !text.isEmpty else { return nil }
                return TimedWord(text: text, startTime: Double(token.start))
            }
        }

        // Caminho 2: fallback — distribui timestamp do segmento pelas palavras
        let rawWords = clean(segment.text)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }

        guard !rawWords.isEmpty else { return [] }

        let segStart    = Double(segment.start)
        let segEnd      = Double(segment.end)
        let segDuration = max(0.1, segEnd - segStart)
        let timePerWord = segDuration / Double(rawWords.count)

        return rawWords.enumerated().map { i, word in
            TimedWord(text: word, startTime: segStart + Double(i) * timePerWord)
        }
    }

    // MARK: - Limpeza de Texto

    /// Remove artefatos que o Whisper insere em músicas:
    ///   [MUSIC], [BLANK_AUDIO], [NOISE]  — tokens de ambiente
    ///   (applause), (laughing)           — anotações de ruído
    ///   ♪ ♫                              — símbolos musicais
    ///   Pontuação inicial/final          — não faz sentido por palavra
    private func clean(_ text: String) -> String {
        var s = text

        // Tokens entre colchetes
        s = s.replacingOccurrences(of: #"\[.*?\]"#, with: "", options: .regularExpression)
        // Tokens entre parênteses
        s = s.replacingOccurrences(of: #"\(.*?\)"#, with: "", options: .regularExpression)
        // Símbolos musicais
        s = s.replacingOccurrences(of: "♪", with: "")
        s = s.replacingOccurrences(of: "♫", with: "")
        // Colapsa espaços múltiplos
        s = s.components(separatedBy: .whitespacesAndNewlines)
              .filter { !$0.isEmpty }
              .joined(separator: " ")

        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}