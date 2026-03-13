//
//  Created by victor on 12/03/26.
//
// LyricsModels.swift
// PitchMVP
//
// Modelos de dados para a feature de análise de lyrics.
// Separados do domínio de comparação (NoteComparison) para manter coesão:
//   • LyricWord      — palavra com nota detectada e dificuldade
//   • LyricLine      — linha da letra com palavras anotadas
//   • VocalProfile   — perfil vocal calculado (Range, Tessitura, High Intensity)
//   • LyricsAnalysis — resultado completo de uma análise

import Foundation
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - NoteDifficulty
// ─────────────────────────────────────────────────────────────────────────────

/// Classifica a dificuldade vocal de uma nota em relação à Tessitura do arquivo.
/// Tessitura = região onde a voz passa a maior parte do tempo (percentil 20–80).
enum NoteDifficulty {
    case comfortable   // 🟢 dentro da tessitura
    case moderate      // 🟡 fora da tessitura, ainda no range
    case difficult     // 🔴 extremo do range (acima do percentil 85)

    var color: Color {
        switch self {
        case .comfortable: return .green
        case .moderate:    return Color(red: 0.95, green: 0.75, blue: 0.0)
        case .difficult:   return Color(red: 1.0,  green: 0.3,  blue: 0.3)
        }
    }

    var emoji: String {
        switch self {
        case .comfortable: return "🟢"
        case .moderate:    return "🟡"
        case .difficult:   return "🔴"
        }
    }

    var label: String {
        switch self {
        case .comfortable: return "Confortável"
        case .moderate:    return "Médio"
        case .difficult:   return "Difícil"
        }
    }

    /// Cor para uso no PDF (CMYK-safe hex)
    var pdfHex: String {
        switch self {
        case .comfortable: return "#2ECC71"
        case .moderate:    return "#F1C40F"
        case .difficult:   return "#E74C3C"
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - LyricWord
// ─────────────────────────────────────────────────────────────────────────────

/// Palavra da letra associada à nota detectada no áudio.
struct LyricWord: Identifiable {
    let id = UUID()

    /// Texto da palavra (ex: "tired")
    let text: String

    /// Nome da nota mais próxima (ex: "A3") — nil se não mapeada
    let noteName: String?

    /// MIDI contínuo — usado para calcular dificuldade e construir o perfil
    let midiNote: Float?

    /// Dificuldade calculada pelo VocalProfileAnalyzer
    var difficulty: NoteDifficulty = .comfortable

    /// true se esta palavra inicia uma nova frase musical
    var isPhraseBoundary: Bool = false
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - LyricLine
// ─────────────────────────────────────────────────────────────────────────────

/// Uma linha da letra com palavras anotadas.
struct LyricLine: Identifiable {
    let id = UUID()

    /// Texto original da linha
    let rawText: String

    /// Palavras enriquecidas com notas e dificuldades
    let words: [LyricWord]

    /// Nota dominante da linha (moda das notas)
    var dominantNote: String? {
        let notes = words.compactMap(\.noteName)
        guard !notes.isEmpty else { return nil }
        return notes
            .reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
            .max(by: { $0.value < $1.value })?.key
    }

    /// true se a linha contém alguma nota de alta dificuldade
    var hasHighIntensity: Bool {
        words.contains { $0.difficulty == .difficult }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - VocalProfile
// ─────────────────────────────────────────────────────────────────────────────

/// Perfil vocal calculado a partir dos NoteSegments detectados.
///
/// Algoritmo:
///   Range       = [min(midi), max(midi)]
///   Tessitura   = [percentil 20, percentil 80] dos MIDIs
///   High Intensity = notas acima do percentil 85
struct VocalProfile {

    let lowestNote:         String
    let highestNote:        String
    let lowestMidi:         Float
    let highestMidi:        Float

    let tessituraLow:       String
    let tessituraHigh:      String
    let tessituraLowMidi:   Float
    let tessituraHighMidi:  Float

    let highIntensityNotes: [String]

    /// Frase/linha que contém a nota mais aguda
    var highestPhrase: String?

    // MARK: - Computed helpers

    var rangeLabel:     String { "\(lowestNote) – \(highestNote)" }
    var tessituraLabel: String { "\(tessituraLow) – \(tessituraHigh)" }
    var rangeInSemitones: Int  { Int(highestMidi - lowestMidi) }

    var highIntensityLabel: String {
        highIntensityNotes.isEmpty ? "—" : highIntensityNotes.joined(separator: ", ")
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - LyricsAnalysis
// ─────────────────────────────────────────────────────────────────────────────

/// Resultado completo de uma análise de lyrics + áudio.
struct LyricsAnalysis {

    let lines:        [LyricLine]
    let vocalProfile: VocalProfile
    let audioFileName: String
    let analyzedAt:   Date

    // MARK: - Computed

    var allWords: [LyricWord]    { lines.flatMap(\.words) }
    var mappedWords: [LyricWord] { allWords.filter { $0.noteName != nil } }

    var comfortableCount: Int { allWords.filter { $0.difficulty == .comfortable }.count }
    var moderateCount:    Int { allWords.filter { $0.difficulty == .moderate    }.count }
    var difficultCount:   Int { allWords.filter { $0.difficulty == .difficult   }.count }

    var difficultyPercentage: Float {
        guard !mappedWords.isEmpty else { return 0 }
        return Float(difficultCount) / Float(mappedWords.count) * 100
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - LyricsAnalysisState
// ─────────────────────────────────────────────────────────────────────────────

enum LyricsAnalysisState: Equatable {
    case idle
    case analyzing(step: String)
    case done
    case error(String)

    var isAnalyzing: Bool {
        if case .analyzing = self { return true }
        return false
    }

    var stepMessage: String {
        if case .analyzing(let msg) = self { return msg }
        return ""
    }
}