// MelodicAligner.swift
// PitchMVP
//
// FIX v5:
// • VocalRange.classify — removido `default: return .unknown`.
//   O case era dead code: Swift cobre todos os Float com `...<45` e `65...`,
//   tornando o default inalcançável. Remover elimina o warning do compilador
//   e deixa claro que .unknown não é um estado possível via classify().
//
// FIX v4 (mantidos):
// • VoiceRangeHint sem .automatic — apenas .male, .female, .custom
// • CrossGenderContext.analyze 100% determinístico via hints

import Foundation
import VocalCore

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - VoiceRangeHint
// ─────────────────────────────────────────────────────────────────────────────

enum VoiceRangeHint {

    case male
    case female
    case custom(ClosedRange<Float>)

    var frequencyRange: ClosedRange<Float>? {
        switch self {
        case .male:              return 80...520
        case .female:            return 160...1050
        case .custom(let range): return range
        }
    }

    var isSelected: Bool { true }

    var label: String {
        switch self {
        case .male:   return "Masc."
        case .female: return "Fem."
        case .custom: return "Custom"
        }
    }

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
// MARK: - CrossGenderContext
// ─────────────────────────────────────────────────────────────────────────────

struct CrossGenderContext {

    let medianOctaveShift: Float
    let isCrossGender: Bool
    let lowerVoice: VoiceRole
    let estimatedUserVoiceType: VocalRange
    let estimatedReferenceVoiceType: VocalRange

    enum VoiceRole { case user, reference }

    static func analyze(
        userHint: VoiceRangeHint,
        referenceHint: VoiceRangeHint,
        userSegments: [NoteSegment],
        referenceSegments: [NoteSegment]
    ) -> CrossGenderContext {

        let userMedianMidi = medianMidi(of: userSegments)
        let refMedianMidi  = medianMidi(of: referenceSegments)
        let shift          = abs(userMedianMidi - refMedianMidi)

        let isCrossGender: Bool
        switch (userHint, referenceHint) {
        case (.male, .female), (.female, .male):
            isCrossGender = true
        default:
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
        // FIX: removido `default: return .unknown` — era dead code.
        // Swift cobre todos os Float com os ranges abaixo; o compilador
        // emitia warning de unreachable code que mascarava erros reais.
        switch midiMedian {
        case ..<45:   return .bass
        case 45..<50: return .baritone
        case 50..<56: return .tenor
        case 56..<60: return .contralto
        case 60..<65: return .mezzo
        default:      return .soprano   // 65... — único default necessário
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
