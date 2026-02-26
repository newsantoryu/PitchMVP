// MelodicAligner.swift
// PitchMVP
//
// FIX v4 — Cross-gender 100% determinístico via hints obrigatórios:
//
// MUDANÇAS:
// 1. VoiceRangeHint removeu .automatic — só .male e .female existem.
//    Elimina completamente o fallback por mediana MIDI que causava falsos positivos.
//
// 2. CrossGenderContext.analyze usa EXCLUSIVAMENTE os hints:
//    .male × .female → isCrossGender = true
//    .male × .male   → isCrossGender = false
//    .female × .female → isCrossGender = false
//    Mediana MIDI usada apenas para estimativa de registro vocal (diagnóstico/UI).
//
// 3. VoiceRangeHint.frequencyRange mantido para passar ao YIN como expectedRange.

import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - VoiceRangeHint  (sem .automatic)
// ─────────────────────────────────────────────────────────────────────────────

/// Declaração obrigatória do registro vocal antes de comparar.
/// Sem .automatic — o usuário deve escolher Masc. ou Fem. explicitamente.
/// Isso garante que isCrossGender seja determinístico e nunca dependa de inferência.
enum VoiceRangeHint {

    /// Vozes masculinas: Baixo (~80 Hz) a Tenor agudo (~520 Hz)
    case male

    /// Vozes femininas: Contralto (~160 Hz) a Soprano agudo (~1050 Hz)
    case female

    /// Faixa personalizada em Hz — instrumentos ou casos especiais
    case custom(ClosedRange<Float>)

    /// Faixa de frequências para passar ao YIN como expectedRange
    var frequencyRange: ClosedRange<Float>? {
        switch self {
        case .male:              return 80...520
        case .female:            return 160...1050
        case .custom(let range): return range
        }
    }

    /// true se o hint foi selecionado (sempre true agora que .automatic foi removido)
    var isSelected: Bool { true }

    /// Label para exibição no picker
    var label: String {
        switch self {
        case .male:   return "Masc."
        case .female: return "Fem."
        case .custom: return "Custom"
        }
    }

    /// Ícone SF Symbols
    var icon: String {
        switch self {
        case .male:   return "arrow.down.circle"
        case .female: return "arrow.up.circle"
        case .custom: return "slider.horizontal.3"
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - MelodicAligner
// ─────────────────────────────────────────────────────────────────────────────

final class MelodicAligner {

    private let timeWindowSeconds: Float
    private let minimumMatchScore: Float
    private let pitchClassMismatchPenalty: Float

    init(
        timeWindowSeconds: Float = 3.0,
        minimumMatchScore: Float = 0.15,
        pitchClassMismatchPenalty: Float = 0.4
    ) {
        self.timeWindowSeconds         = timeWindowSeconds
        self.minimumMatchScore         = minimumMatchScore
        self.pitchClassMismatchPenalty = pitchClassMismatchPenalty
    }

    func align(user: [NoteSegment], reference: [NoteSegment]) -> [NoteComparison] {

        if user.isEmpty && reference.isEmpty { return [] }
        if user.isEmpty {
            return reference.enumerated().map { i, ref in
                NoteComparison(index: i, userSegment: nil, referenceSegment: ref)
            }
        }
        if reference.isEmpty {
            return user.enumerated().map { i, u in
                NoteComparison(index: i, userSegment: u, referenceSegment: nil)
            }
        }

        var availableUserIndices = Set(user.indices)
        var pairs: [(refIndex: Int, userIndex: Int?, score: Float)] = []

        for (refIdx, refSeg) in reference.enumerated() {
            let candidates = availableUserIndices.compactMap { userIdx -> (index: Int, score: Float)? in
                let score = matchScore(user: user[userIdx], reference: refSeg)
                guard score >= minimumMatchScore else { return nil }
                return (index: userIdx, score: score)
            }

            if let best = candidates.max(by: { $0.score < $1.score }) {
                pairs.append((refIndex: refIdx, userIndex: best.index, score: best.score))
                availableUserIndices.remove(best.index)
            } else {
                pairs.append((refIndex: refIdx, userIndex: nil, score: 0))
            }
        }

        var comparisons: [NoteComparison] = []
        for (pairIdx, pair) in pairs.enumerated() {
            comparisons.append(NoteComparison(
                index: pairIdx,
                userSegment: pair.userIndex.map { user[$0] },
                referenceSegment: reference[pair.refIndex]
            ))
        }

        let baseIndex = comparisons.count
        for (extraIdx, userIdx) in availableUserIndices.sorted().enumerated() {
            comparisons.append(NoteComparison(
                index: baseIndex + extraIdx,
                userSegment: user[userIdx],
                referenceSegment: nil
            ))
        }

        return comparisons
    }

    private func matchScore(user: NoteSegment, reference: NoteSegment) -> Float {
        let timeDiff = abs(user.startTime - reference.startTime)
        guard timeDiff <= timeWindowSeconds else { return 0 }

        let temporalScore: Float    = 1.0 - (timeDiff / timeWindowSeconds)
        let userPC                  = MusicTheory.pitchClass(from: user.noteName)
        let refPC                   = MusicTheory.pitchClass(from: reference.noteName)
        let pitchClassScore: Float  = (userPC == refPC) ? 1.0 : (1.0 - pitchClassMismatchPenalty)

        return (temporalScore * 0.5) + (pitchClassScore * 0.5)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - CrossGenderContext  (determinístico — sem inferência por MIDI)
// ─────────────────────────────────────────────────────────────────────────────

struct CrossGenderContext {

    let medianOctaveShift: Float
    /// Determinado exclusivamente pelos hints — nunca por inferência de áudio.
    let isCrossGender: Bool
    let lowerVoice: VoiceRole
    let estimatedUserVoiceType: VocalRange
    let estimatedReferenceVoiceType: VocalRange

    enum VoiceRole { case user, reference }

    /// Factory principal — hints obrigatórios, sem fallback por MIDI.
    static func analyze(
        userHint: VoiceRangeHint,
        referenceHint: VoiceRangeHint,
        userSegments: [NoteSegment],
        referenceSegments: [NoteSegment]
    ) -> CrossGenderContext {

        let userMedianMidi = medianMidi(of: userSegments)
        let refMedianMidi  = medianMidi(of: referenceSegments)
        let shift          = abs(userMedianMidi - refMedianMidi)

        // Lógica 100% determinística — apenas os hints decidem
        let isCrossGender: Bool
        switch (userHint, referenceHint) {
        case (.male, .female), (.female, .male):
            isCrossGender = true
        default:
            // .male × .male, .female × .female, .custom × qualquer → false
            isCrossGender = false
        }

        return CrossGenderContext(
            medianOctaveShift: shift,
            isCrossGender: isCrossGender,
            lowerVoice: userMedianMidi <= refMedianMidi ? .user : .reference,
            estimatedUserVoiceType: VocalRange.classify(midiMedian: userMedianMidi),
            estimatedReferenceVoiceType: VocalRange.classify(midiMedian: refMedianMidi)
        )
    }

    private static func medianMidi(of segments: [NoteSegment]) -> Float {
        guard !segments.isEmpty else { return 60 }
        let sorted = segments.map(\.midiNote).sorted()
        let mid    = sorted.count / 2
        return sorted.count % 2 == 0
            ? (sorted[mid - 1] + sorted[mid]) / 2
            : sorted[mid]
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - VocalRange
// ─────────────────────────────────────────────────────────────────────────────

enum VocalRange: String {
    case bass      = "Baixo"
    case baritone  = "Barítono"
    case tenor     = "Tenor"
    case contralto = "Contralto"
    case mezzo     = "Mezzo-soprano"
    case soprano   = "Soprano"
    case unknown   = "Indefinido"

    static func classify(midiMedian: Float) -> VocalRange {
        switch midiMedian {
        case ..<45:   return .bass
        case 45..<50: return .baritone
        case 50..<56: return .tenor
        case 56..<60: return .contralto
        case 60..<65: return .mezzo
        case 65...:   return .soprano
        default:      return .unknown
        }
    }

    var systemImage: String {
        switch self {
        case .bass, .baritone: return "arrow.down.circle"
        case .tenor:           return "arrow.right.circle"
        case .contralto:       return "arrow.right.circle"
        case .mezzo:           return "arrow.up.circle"
        case .soprano:         return "arrow.up.circle.fill"
        case .unknown:         return "questionmark.circle"
        }
    }
}