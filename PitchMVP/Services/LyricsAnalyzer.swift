// LyricsAnalyzer.swift
// PitchMVP
//
// v2 — Alinhamento por timestamp (Whisper wordTimestamps + NoteSegment.startTime):
//
// ANTES (v1):
//   Distribuía palavras proporcionalmente por índice — sem base temporal.
//   Funcionava apenas como aproximação quando não havia letra do usuário.
//
// AGORA (v2):
//   Whisper retorna wordTimestamps: cada palavra tem startTime em segundos.
//   NoteSegment também tem startTime em segundos.
//   → O alinhamento busca o NoteSegment mais próximo temporalmente de cada palavra.
//   → Precisão muito maior: "tired" em 0.8s → segmento A3 em 0.75s → nota A3.
//
// Fallback (se wordTimestamps não disponíveis):
//   Distribuição proporcional por índice (comportamento v1) — mantido como safety net.

import Foundation

// TimedWord está definido em TranscriptionModels.swift

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - LyricsAnalyzer
// ─────────────────────────────────────────────────────────────────────────────

struct LyricsAnalyzer {

    private let profileAnalyzer = VocalProfileAnalyzer()

    // MARK: - API Principal (com timestamps)

    /// Constrói o LyricsAnalysis alinhando palavras com timestamp aos NoteSegments.
    ///
    /// - Parameters:
    ///   - timedWords:    Palavras extraídas do Whisper com startTime por palavra
    ///   - segments:      NoteSegments detectados pelo NoteSegmenter
    ///   - audioFileName: Nome do arquivo (para metadados)
    func analyze(
        timedWords: [TimedWord],
        segments: [NoteSegment],
        audioFileName: String
    ) -> LyricsAnalysis? {

        guard !timedWords.isEmpty, !segments.isEmpty else { return nil }

        // 1. Alinha cada palavra ao segmento mais próximo temporalmente
        let alignedWords = alignByTimestamp(words: timedWords, segments: segments)

        // 2. Agrupa em linhas (por quebras de linha inseridas pelo TranscriptionService)
        var lines = groupIntoLines(words: alignedWords, timedWords: timedWords)

        // 3. Calcula perfil vocal
        guard var profile = profileAnalyzer.buildProfile(from: segments) else { return nil }

        // 4. Marca fronteiras de frase (mudança de nota entre palavras adjacentes)
        lines = markPhraseBoundaries(lines: lines)

        // 5. Aplica dificuldade
        profileAnalyzer.applyDifficulty(to: &lines, profile: profile)

        // 6. Encontra frase mais aguda
        profile = attachHighestPhrase(profile: profile, lines: lines)

        return LyricsAnalysis(
            lines: lines,
            vocalProfile: profile,
            audioFileName: audioFileName,
            analyzedAt: Date()
        )
    }

    // MARK: - API Fallback (sem timestamps — texto puro)

    /// Versão fallback para quando wordTimestamps não estão disponíveis.
    /// Distribui palavras proporcionalmente pelos segmentos (comportamento v1).
    func analyze(
        plainText: String,
        segments: [NoteSegment],
        audioFileName: String
    ) -> LyricsAnalysis? {

        guard !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard !segments.isEmpty else { return nil }

        var lines = parseLines(from: plainText)
        lines = alignProportionally(lines: lines, segments: segments)
        lines = markPhraseBoundaries(lines: lines)

        guard var profile = profileAnalyzer.buildProfile(from: segments) else { return nil }
        profileAnalyzer.applyDifficulty(to: &lines, profile: profile)
        profile = attachHighestPhrase(profile: profile, lines: lines)

        return LyricsAnalysis(
            lines: lines,
            vocalProfile: profile,
            audioFileName: audioFileName,
            analyzedAt: Date()
        )
    }

    // MARK: - Alinhamento por Timestamp

    /// Para cada TimedWord, encontra o NoteSegment cuja janela temporal é mais próxima.
    ///
    /// Estratégia nearest-neighbor:
    ///   Para cada palavra em t_word, escolhe o segmento s onde:
    ///   |s.startTime - t_word| é mínimo E t_word <= s.startTime + s.durationSeconds
    ///
    /// Se a palavra cair em um gap (silêncio entre notas), usa o segmento anterior.
    private func alignByTimestamp(
        words: [TimedWord],
        segments: [NoteSegment]
    ) -> [LyricWord] {

        words.map { timedWord in
            let t = Float(timedWord.startTime)

            // Procura o segmento que contém o timestamp da palavra
            let containing = segments.first { seg in
                t >= seg.startTime && t <= seg.startTime + seg.durationSeconds
            }

            // Se nenhum contém, pega o mais próximo por distância
            let best = containing ?? segments.min(by: { a, b in
                abs(a.startTime - t) < abs(b.startTime - t)
            })

            return LyricWord(
                text:     timedWord.text,
                noteName: best?.noteName,
                midiNote: best?.midiNote
            )
        }
    }

    // MARK: - Agrupamento em Linhas

    /// Reconstrói a estrutura de linhas a partir dos LyricWords e do texto original
    /// que contém quebras de linha inseridas pelo TranscriptionService.
    private func groupIntoLines(words: [LyricWord], timedWords: [TimedWord]) -> [LyricLine] {
        // Reconstrói o texto original com quebras de linha para saber os grupos
        // A quebra foi inserida pelo VoiceTranscriptionService a cada N palavras
        // Usa o índice de palavra para identificar a linha
        let wordsPerLine = 8   // deve bater com o wordsPerLine do TranscriptionService

        var lines: [LyricLine] = []
        var i = 0
        while i < words.count {
            let slice = Array(words[i..<min(i + wordsPerLine, words.count)])
            let rawText = slice.map(\.text).joined(separator: " ")
            lines.append(LyricLine(rawText: rawText, words: slice))
            i += wordsPerLine
        }
        return lines
    }

    // MARK: - Fallback: Alinhamento Proporcional

    private func parseLines(from text: String) -> [LyricLine] {
        text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { line in
                let words = line
                    .components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
                    .map { LyricWord(text: $0, noteName: nil, midiNote: nil) }
                return LyricLine(rawText: line, words: words)
            }
    }

    private func alignProportionally(lines: [LyricLine], segments: [NoteSegment]) -> [LyricLine] {
        var allWords = lines.flatMap(\.words)
        let totalWords    = allWords.count
        let totalSegments = segments.count
        guard totalWords > 0 else { return lines }

        for idx in 0..<totalWords {
            let segIdx  = min(Int(Float(idx) / Float(totalWords) * Float(totalSegments)), totalSegments - 1)
            let seg     = segments[segIdx]
            allWords[idx] = LyricWord(text: allWords[idx].text, noteName: seg.noteName, midiNote: seg.midiNote)
        }

        var cursor = 0
        return lines.map { line in
            let count = line.words.count
            let slice = Array(allWords[cursor..<min(cursor + count, allWords.count)])
            cursor += count
            return LyricLine(rawText: line.rawText, words: slice)
        }
    }

    // MARK: - Fronteiras de Frase

    private func markPhraseBoundaries(lines: [LyricLine]) -> [LyricLine] {
        lines.map { line in
            var lastNote: String? = nil
            let updated = line.words.map { word -> LyricWord in
                var w = word
                if word.noteName != lastNote {
                    w.isPhraseBoundary = true
                    lastNote = word.noteName
                }
                return w
            }
            return LyricLine(rawText: line.rawText, words: updated)
        }
    }

    // MARK: - Highest Phrase

    private func attachHighestPhrase(profile: VocalProfile, lines: [LyricLine]) -> VocalProfile {
        let best = lines.max {
            ($0.words.compactMap(\.midiNote).max() ?? 0) <
            ($1.words.compactMap(\.midiNote).max() ?? 0)
        }
        return VocalProfile(
            lowestNote:         profile.lowestNote,
            highestNote:        profile.highestNote,
            lowestMidi:         profile.lowestMidi,
            highestMidi:        profile.highestMidi,
            tessituraLow:       profile.tessituraLow,
            tessituraHigh:      profile.tessituraHigh,
            tessituraLowMidi:   profile.tessituraLowMidi,
            tessituraHighMidi:  profile.tessituraHighMidi,
            highIntensityNotes: profile.highIntensityNotes,
            highestPhrase:      best?.rawText
        )
    }
}