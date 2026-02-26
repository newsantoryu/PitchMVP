//
//  MelodicAligner.swift
//  PitchMVP
//
//  Created by victor on 26/02/26.
//

// MelodicAligner.swift
// PitchMVP
//
// Alinhamento melódico inteligente para comparação cross-gender (masculino × feminino).
//
// PROBLEMA RESOLVIDO:
//   O pareamento posicional ingênuo (nota[i] com nota[i]) falha quando as vozes
//   produzem contagens de segmentos diferentes — comum em cross-gender porque
//   diferentes timbres/registros causam segmentação distinta no NoteSegmenter.
//
// SOLUÇÃO — Alinhamento por Janela Temporal + Pitch Class:
//   1. Para cada nota da referência, busca a nota do usuário dentro de uma janela
//      temporal configurável (padrão ±1.5s).
//   2. Dentro da janela, prioriza candidatos com pitch class idêntico (ignora oitava).
//   3. Candidatos sem pitch class match são aceitos com penalidade de score.
//   4. Notas sem par ficam como "ausentes" (userSegment/referenceSegment = nil).
//
// CROSS-GENDER AWARENESS:
//   • Barítono C3 (130 Hz) × Soprano C4 (261 Hz) → pitchClassMatch = true ✅
//   • centsDelta avalia o desvio de CADA VOZ na SUA nota — não a distância entre elas.
//   • `octaveDifference` é exportado por par para uso na UI (badge visual).
//
// COMPATIBILIDADE:
//   Drop-in replacement para o bloco `buildComparisons` do ViewModel.
//   Não altera nenhum modelo existente — apenas cria NoteComparison com melhor semântica.


final class MelodicAligner {

    // MARK: - Configuração

    /// Janela temporal máxima (segundos) para busca de par.
    /// Valor conservador: cobre rubato natural e diferenças de timing de gravação.
    private let timeWindowSeconds: Float

    /// Score mínimo para aceitar um par (0–1). Abaixo disso, considera "sem par".
    private let minimumMatchScore: Float

    /// Penalidade aplicada ao score quando o pitch class NÃO bate (0–1).
    /// Ex: 0.4 → par com grau errado pontua no máximo 0.6.
    private let pitchClassMismatchPenalty: Float

    // MARK: - Init

    init(
        timeWindowSeconds: Float = 1.5,
        minimumMatchScore: Float = 0.25,
        pitchClassMismatchPenalty: Float = 0.4
    ) {
        self.timeWindowSeconds         = timeWindowSeconds
        self.minimumMatchScore         = minimumMatchScore
        self.pitchClassMismatchPenalty = pitchClassMismatchPenalty
    }

    // MARK: - API Pública

    /// Alinha dois arrays de NoteSegment produzindo NoteComparison pareados.
    ///
    /// - Parameters:
    ///   - user: Segmentos detectados na voz do usuário.
    ///   - reference: Segmentos detectados na voz de referência.
    /// - Returns: Array de NoteComparison com melhor alinhamento possível.
    func align(user: [NoteSegment], reference: [NoteSegment]) -> [NoteComparison] {

        // Caso trivial: sem dados de um dos lados
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

        // ── Passo 1: Busca gulosa — ancora na referência ──────────────────────
        // Cada nota da referência tenta encontrar o melhor candidato no usuário
        // dentro da janela temporal. Candidatos já "usados" são removidos do pool.

        var availableUserIndices = Set(user.indices)
        var pairs: [(refIndex: Int, userIndex: Int?, score: Float)] = []

        for (refIdx, refSeg) in reference.enumerated() {

            // Candidatos dentro da janela temporal
            let candidates = availableUserIndices.compactMap { userIdx -> (index: Int, score: Float)? in
                let userSeg = user[userIdx]
                let score = matchScore(user: userSeg, reference: refSeg)
                guard score >= minimumMatchScore else { return nil }
                return (index: userIdx, score: score)
            }

            if let best = candidates.max(by: { $0.score < $1.score }) {
                pairs.append((refIndex: refIdx, userIndex: best.index, score: best.score))
                availableUserIndices.remove(best.index)
            } else {
                // Referência sem par — usuário não cantou essa nota
                pairs.append((refIndex: refIdx, userIndex: nil, score: 0))
            }
        }

        // ── Passo 2: Notas do usuário sem par (cantou a mais) ─────────────────
        let unpairedUserIndices = availableUserIndices.sorted()

        // ── Passo 3: Monta NoteComparison na ordem cronológica da referência ──
        var comparisons: [NoteComparison] = []

        for (pairIdx, pair) in pairs.enumerated() {
            let refSeg  = reference[pair.refIndex]
            let userSeg = pair.userIndex.map { user[$0] }

            comparisons.append(NoteComparison(
                index: pairIdx,
                userSegment: userSeg,
                referenceSegment: refSeg
            ))
        }

        // Notas extras do usuário vão ao final — para sinalizar ao professor
        // que o aluno cantou mais notas do que a referência.
        let baseIndex = comparisons.count
        for (extraIdx, userIdx) in unpairedUserIndices.enumerated() {
            comparisons.append(NoteComparison(
                index: baseIndex + extraIdx,
                userSegment: user[userIdx],
                referenceSegment: nil
            ))
        }

        return comparisons
    }

    // MARK: - Score de Compatibilidade

    /// Calcula score (0–1) de compatibilidade entre duas notas.
    ///
    /// Componentes:
    ///  • Proximidade temporal (peso 0.5): quão próximos estão os inícios
    ///  • Pitch class match (peso 0.5): mesmo grau independente de oitava
    ///
    /// Score > 0.25 = par aceitável.
    /// Score > 0.70 = par de alta confiança.
    private func matchScore(user: NoteSegment, reference: NoteSegment) -> Float {

        // ── Componente 1: Proximidade temporal ────────────────────────────────
        let timeDiff = abs(user.startTime - reference.startTime)
        guard timeDiff <= timeWindowSeconds else { return 0 }

        // Score temporal: 1.0 em diff=0, 0.0 em diff=timeWindowSeconds
        let temporalScore = 1.0 - (timeDiff / timeWindowSeconds)

        // ── Componente 2: Pitch class match (tolerante a oitavas) ─────────────
        let userPitchClass = MusicTheory.pitchClass(from: user.noteName)
        let refPitchClass  = MusicTheory.pitchClass(from: reference.noteName)
        let pitchClassScore: Float = (userPitchClass == refPitchClass) ? 1.0 : (1.0 - pitchClassMismatchPenalty)

        // ── Score final (média ponderada) ─────────────────────────────────────
        return (temporalScore * 0.5) + (pitchClassScore * 0.5)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - CrossGenderContext
// ─────────────────────────────────────────────────────────────────────────────

/// Contexto de comparação cross-gender para exibição na UI e logging.
///
/// Detecta automaticamente se a comparação envolve vozes em registros diferentes
/// (ex: barítono × soprano) a partir da mediana de MIDI de cada voz.
struct CrossGenderContext {

    /// Diferença mediana de semitons entre as vozes (valor absoluto).
    let medianOctaveShift: Float

    /// true se as vozes estão consistentemente em oitavas diferentes (shift ≥ 5 semitons).
    let isCrossGender: Bool

    /// Voz mais grave (usuário ou referência)
    let lowerVoice: VoiceRole

    /// Estimativa do registro vocal do usuário
    let estimatedUserVoiceType: VocalRange

    /// Estimativa do registro vocal da referência
    let estimatedReferenceVoiceType: VocalRange

    enum VoiceRole { case user, reference }

    // ── Factory ───────────────────────────────────────────────────────────────

    static func analyze(
        userSegments: [NoteSegment],
        referenceSegments: [NoteSegment]
    ) -> CrossGenderContext {

        let userMedianMidi = medianMidi(of: userSegments)
        let refMedianMidi  = medianMidi(of: referenceSegments)
        let shift = abs(userMedianMidi - refMedianMidi)

        return CrossGenderContext(
            medianOctaveShift: shift,
            isCrossGender: shift >= 5,
            lowerVoice: userMedianMidi <= refMedianMidi ? .user : .reference,
            estimatedUserVoiceType: VocalRange.classify(midiMedian: userMedianMidi),
            estimatedReferenceVoiceType: VocalRange.classify(midiMedian: refMedianMidi)
        )
    }

    private static func medianMidi(of segments: [NoteSegment]) -> Float {
        guard !segments.isEmpty else { return 60 }
        let sorted = segments.map(\.midiNote).sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0
            ? (sorted[mid - 1] + sorted[mid]) / 2
            : sorted[mid]
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - VocalRange
// ─────────────────────────────────────────────────────────────────────────────

/// Classificação de registro vocal baseada na nota MIDI mediana.
///
/// Faixas aproximadas (MIDI):
///   Baixo:      E2–E4  (40–64)
///   Barítono:   A2–A4  (45–69)
///   Tenor:      C3–C5  (48–72)
///   Contralto:  F3–F5  (53–77)
///   Mezzosoprano: A3–A5 (57–81)
///   Soprano:    C4–C6  (60–84)
enum VocalRange: String {

    case bass       = "Baixo"
    case baritone   = "Barítono"
    case tenor      = "Tenor"
    case contralto  = "Contralto"
    case mezzo      = "Mezzo-soprano"
    case soprano    = "Soprano"
    case unknown    = "Indefinido"

    /// Classifica com base na nota MIDI mediana da voz.
    static func classify(midiMedian: Float) -> VocalRange {
        switch midiMedian {
        case ..<45: return .bass
        case 45..<50: return .baritone
        case 50..<56: return .tenor
        case 56..<60: return .contralto
        case 60..<65: return .mezzo
        case 65...: return .soprano
        default: return .unknown
        }
    }

    /// Ícone SF Symbols representando o registro
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

    /// Cor associada ao registro para uso em UI
    var uiColorName: String {
        switch self {
        case .bass, .baritone: return "blue"
        case .tenor:           return "cyan"
        case .contralto:       return "orange"
        case .mezzo:           return "pink"
        case .soprano:         return "red"
        case .unknown:         return "secondary"
        }
    }
}