//
//  Created by victor on 12/03/26.
//
// VocalProfileAnalyzer.swift
// PitchMVP
//
// Service puro (sem estado) que:
//   1. Calcula o VocalProfile a partir de [NoteSegment]
//   2. Classifica cada LyricWord em NoteDifficulty
//
// Depende apenas de NoteSegment (NoteSegmenter.swift) e LyricsModels.
// Não tem dependências de UI nem de Supabase — testável de forma isolada.

import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - VocalProfileAnalyzer
// ─────────────────────────────────────────────────────────────────────────────

struct VocalProfileAnalyzer {

    // MARK: - Perfil Vocal

    /// Calcula o VocalProfile a partir dos NoteSegments detectados no arquivo.
    ///
    /// - Parameter segments: Segmentos detectados pelo NoteSegmenter
    /// - Returns: VocalProfile completo, ou nil se não houver segmentos válidos
    func buildProfile(from segments: [NoteSegment]) -> VocalProfile? {
        guard !segments.isEmpty else { return nil }

        let midis = segments.map(\.midiNote).sorted()

        // Range: extremos absolutos
        let lowestMidi  = midis.first!
        let highestMidi = midis.last!

        // Tessitura: percentis 20–80 (região onde a voz passa mais tempo)
        let p20Idx = max(0, Int(Float(midis.count) * 0.20))
        let p80Idx = min(midis.count - 1, Int(Float(midis.count) * 0.80))
        let tessLowMidi  = midis[p20Idx]
        let tessHighMidi = midis[p80Idx]

        // High intensity: notas acima do percentil 85
        let p85Idx = min(midis.count - 1, Int(Float(midis.count) * 0.85))
        let hiThreshold = midis[p85Idx]
        let hiNotes = segments
            .filter { $0.midiNote >= hiThreshold }
            .map(\.noteName)
        let hiUnique = Array(Set(hiNotes)).sorted()

        return VocalProfile(
            lowestNote:        midiToNoteName(lowestMidi),
            highestNote:       midiToNoteName(highestMidi),
            lowestMidi:        lowestMidi,
            highestMidi:       highestMidi,
            tessituraLow:      midiToNoteName(tessLowMidi),
            tessituraHigh:     midiToNoteName(tessHighMidi),
            tessituraLowMidi:  tessLowMidi,
            tessituraHighMidi: tessHighMidi,
            highIntensityNotes: hiUnique,
            highestPhrase:     nil   // preenchido pelo LyricsAnalyzer
        )
    }

    // MARK: - Classificação de Dificuldade

    /// Classifica a dificuldade de um MIDI em relação ao perfil vocal.
    ///
    /// Regras:
    ///   • midi < tessituraLow   → moderate (abaixo da tessitura)
    ///   • midi <= tessituraHigh → comfortable (dentro da tessitura)
    ///   • midi > tessituraHigh e <= p85 → moderate
    ///   • midi > p85 → difficult
    func classify(midi: Float, profile: VocalProfile) -> NoteDifficulty {
        // Percentil 85 aproximado: tessituraHigh + 20% do range acima
        let p85 = profile.tessituraHighMidi + (profile.highestMidi - profile.tessituraHighMidi) * 0.6

        if midi >= profile.tessituraLowMidi && midi <= profile.tessituraHighMidi {
            return .comfortable
        } else if midi > p85 {
            return .difficult
        } else {
            return .moderate
        }
    }

    /// Aplica dificuldade a todas as palavras de uma análise já construída.
    func applyDifficulty(to lines: inout [LyricLine], profile: VocalProfile) {
        lines = lines.map { line in
            let updated = line.words.map { word -> LyricWord in
                guard let midi = word.midiNote else { return word }
                var w = word
                w.difficulty = classify(midi: midi, profile: profile)
                return w
            }
            return LyricLine(rawText: line.rawText, words: updated)
        }
    }

    // MARK: - Helper

    private func midiToNoteName(_ midi: Float) -> String {
        let noteNames = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
        let rounded   = Int(midi.rounded())
        let noteIdx   = ((rounded % 12) + 12) % 12
        let octave    = rounded / 12 - 1
        return noteNames[noteIdx] + "\(octave)"
    }
}