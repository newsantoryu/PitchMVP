// NoteComparison.swift
// PitchMVP
//
// FIX v2 — overallScore reformulado:
//
// ANTES:
//   overallScore = média ponderada de grades (excellent×100 + good×75 + ...) / totalPairs
//   Problema: não incorporava pitchClassMatchScore nem melodicContourScore —
//   dois alunos com mesma afinação mas melodias completamente diferentes
//   recebiam o mesmo score.
//
// AGORA:
//   overallScore = (intonationScore × 0.40) + (pitchClassScore × 0.35) + (contourScore × 0.25)
//
//   • intonationScore (40%): quão afinado o usuário está NA SUA nota.
//     Baseado em userAverageIntonation — independente da referência, correto para cross-gender.
//     100 pts = desvio médio 0¢, 0 pts = desvio ≥ 50¢ (mapeado linearmente).
//
//   • pitchClassScore (35%): % de notas em que cantou o grau certo (ignora oitava).
//     Diretamente pitchClassMatchScore (0–100).
//
//   • contourScore (25%): % de movimentos melódicos na direção certa.
//     Diretamente melodicContourScore (0–100).
//
// O peso maior em intonação (40%) reflete que afinar a nota é a habilidade
// mais básica e mais relevante pedagogicamente. Grau correto (35%) penaliza
// erros de nota sem punir oitavas diferentes. Contorno (25%) avalia musicalidade.
//
// overallGrade: novo computed que mapeia o score numérico para uma avaliação textual.

import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - NoteComparison (inalterado)
// ─────────────────────────────────────────────────────────────────────────────

struct NoteComparison: Identifiable {

    let id = UUID()
    let index: Int
    let userSegment: NoteSegment?
    let referenceSegment: NoteSegment?

    var userContourDirection:      ContourDirection = .unset
    var referenceContourDirection: ContourDirection = .unset

    // ── Afinação Individual ──────────────────────────────────────────────────

    var centsDelta: Float? {
        guard let u = userSegment, let r = referenceSegment else { return nil }
        return u.averageCentsDeviation - r.averageCentsDeviation
    }

    var userIntonation: Float? { userSegment?.averageCentsDeviation }
    var referenceIntonation: Float? { referenceSegment?.averageCentsDeviation }

    var stabilityDelta: Float? {
        guard let u = userSegment, let r = referenceSegment else { return nil }
        return u.stabilityPercentage - r.stabilityPercentage
    }

    // ── Grau Melódico ────────────────────────────────────────────────────────

    var referencePitchClass: String? {
        referenceSegment.map { MusicTheory.pitchClass(from: $0.noteName) }
    }

    var userPitchClass: String? {
        userSegment.map { MusicTheory.pitchClass(from: $0.noteName) }
    }

    var pitchClassMatch: Bool {
        guard let u = userPitchClass, let r = referencePitchClass else { return false }
        return u == r
    }

    // ── Contorno Melódico ────────────────────────────────────────────────────

    var melodicContourMatch: Bool? {
        guard userContourDirection      != .unset,
              referenceContourDirection != .unset else { return nil }
        if userContourDirection == .same || referenceContourDirection == .same { return true }
        return userContourDirection == referenceContourDirection
    }

    // ── Tempo ────────────────────────────────────────────────────────────────

    var startTimeFormatted: String {
        let t = userSegment?.startTime ?? referenceSegment?.startTime ?? 0
        let minutes = Int(t) / 60
        let seconds = Int(t) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var startTimeSeconds: Float {
        userSegment?.startTime ?? referenceSegment?.startTime ?? 0
    }

    var noteName: String {
        referenceSegment?.noteName ?? userSegment?.noteName ?? "?"
    }

    // ── Grade por nota (inalterado) ───────────────────────────────────────────

    var grade: ComparisonGrade {
        guard let stab = stabilityDelta, let cents = centsDelta else { return .incomplete }
        let absStab  = abs(stab)
        let absCents = abs(cents)

        switch (absCents, absStab) {
        case (..<5,   ..<10):  return .excellent
        case (..<15,  ..<20):  return .good
        case (..<30,  ..<35):  return .fair
        default:               return .needsWork
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - ContourDirection / ComparisonGrade (inalterados)
// ─────────────────────────────────────────────────────────────────────────────

enum ContourDirection: Equatable {
    case up, down, same, unset
}

enum ComparisonGrade {
    case excellent, good, fair, needsWork, incomplete

    var label: String {
        switch self {
        case .excellent:  return "Excelente"
        case .good:       return "Bom"
        case .fair:       return "Regular"
        case .needsWork:  return "Melhorar"
        case .incomplete: return "—"
        }
    }

    var systemImage: String {
        switch self {
        case .excellent:  return "checkmark.seal.fill"
        case .good:       return "checkmark.circle.fill"
        case .fair:       return "exclamationmark.circle"
        case .needsWork:  return "xmark.circle"
        case .incomplete: return "minus.circle"
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - ComparisonResult (overallScore reformulado)
// ─────────────────────────────────────────────────────────────────────────────

struct ComparisonResult {

    let comparisons: [NoteComparison]
    let userSegments: [NoteSegment]
    let referenceSegments: [NoteSegment]
    let userFileName: String
    let referenceFileName: String

    // ── Pares válidos ─────────────────────────────────────────────────────────

    var totalPairs: Int {
        comparisons.filter { $0.userSegment != nil && $0.referenceSegment != nil }.count
    }

    // ── Afinação (inalterado) ─────────────────────────────────────────────────

    var userAverageIntonation: Float {
        let valid = comparisons.compactMap(\.userIntonation)
        guard !valid.isEmpty else { return 0 }
        return valid.reduce(0, +) / Float(valid.count)
    }

    var referenceAverageIntonation: Float {
        let valid = comparisons.compactMap(\.referenceIntonation)
        guard !valid.isEmpty else { return 0 }
        return valid.reduce(0, +) / Float(valid.count)
    }

    var averageCentsDelta: Float {
        let valid = comparisons.compactMap(\.centsDelta)
        guard !valid.isEmpty else { return 0 }
        return valid.map { abs($0) }.reduce(0, +) / Float(valid.count)
    }

    var averageStabilityDelta: Float {
        let valid = comparisons.compactMap(\.stabilityDelta)
        guard !valid.isEmpty else { return 0 }
        return valid.reduce(0, +) / Float(valid.count)
    }

    // ── Grau e Contorno (inalterado) ──────────────────────────────────────────

    var pitchClassMatchScore: Float {
        let valid = comparisons.filter { $0.userSegment != nil && $0.referenceSegment != nil }
        guard !valid.isEmpty else { return 0 }
        return Float(valid.filter(\.pitchClassMatch).count) / Float(valid.count) * 100
    }

    var melodicContourScore: Float {
        let valid = comparisons.compactMap(\.melodicContourMatch)
        guard !valid.isEmpty else { return 0 }
        return Float(valid.filter { $0 }.count) / Float(valid.count) * 100
    }

    // ── Grade breakdown (inalterado) ──────────────────────────────────────────

    var excellentCount:  Int { comparisons.filter { $0.grade == .excellent  }.count }
    var goodCount:       Int { comparisons.filter { $0.grade == .good       }.count }
    var fairCount:       Int { comparisons.filter { $0.grade == .fair       }.count }
    var needsWorkCount:  Int { comparisons.filter { $0.grade == .needsWork  }.count }
    var incompleteCount: Int { comparisons.filter { $0.grade == .incomplete }.count }

    // ── Faixas de desvio (inalterado) ─────────────────────────────────────────

    var inTuneCount: Int {
        comparisons.compactMap(\.userIntonation).filter { $0 < 10 }.count
    }

    var nearTuneCount: Int {
        comparisons.compactMap(\.userIntonation).filter { $0 >= 10 && $0 < 30 }.count
    }

    var outOfTuneCount: Int {
        comparisons.compactMap(\.userIntonation).filter { $0 >= 30 }.count
    }

    var sharpCount: Int {
        comparisons.compactMap(\.centsDelta).filter { $0 > 0 }.count
    }

    var flatCount: Int {
        comparisons.compactMap(\.centsDelta).filter { $0 < 0 }.count
    }

    var centeredCount: Int {
        comparisons.compactMap(\.centsDelta).filter { $0 == 0 }.count
    }

    // ── overallScore REFORMULADO ──────────────────────────────────────────────
    //
    // Fórmula:
    //   overallScore = (intonationScore × 0.40) + (pitchClassScore × 0.35) + (contourScore × 0.25)
    //
    // intonationScore: mapeia desvio médio (0–50¢) para 0–100 pts.
    //   0¢  desvio = 100 pts
    //   50¢ desvio =   0 pts (acima de 50¢ = cronicamente desafinado)
    //   Fórmula: max(0, 100 - (avgIntonation / 50) * 100)
    //
    // pitchClassScore: % de notas com grau correto (0–100, direto).
    //
    // contourScore: % de movimentos melódicos corretos (0–100, direto).
    //   Se não há dados de contorno (música muito curta), peso redistribuído
    //   para intonação e grau proporcionalmente.

    var overallScore: Int {
        guard totalPairs > 0 else { return 0 }

        // Componente 1: Afinação (40%)
        let intonationScore = max(0, 100 - (userAverageIntonation / 50) * 100)

        // Componente 2: Grau correto (35%)
        let pitchScore = pitchClassMatchScore

        // Componente 3: Contorno melódico (25%)
        // Se não há dados de contorno, redistribui peso proporcionalmente
        let contourSamples = comparisons.compactMap(\.melodicContourMatch).count
        let hasContourData = contourSamples >= 2

        let score: Float
        if hasContourData {
            score = (intonationScore * 0.40) + (pitchScore * 0.35) + (melodicContourScore * 0.25)
        } else {
            // Sem contorno: redistribui 25% proporcionalmente entre afinação e grau
            // intonação fica com 40 + 25*(40/75) ≈ 53.3%, grau com 46.7%
            score = (intonationScore * 0.533) + (pitchScore * 0.467)
        }

        return Int(score.rounded())
    }

    // ── overallGrade — novo: avaliação textual do score ───────────────────────

    var overallGrade: OverallGrade {
        switch overallScore {
        case 90...: return .outstanding
        case 75...: return .proficient
        case 60...: return .developing
        case 40...: return .beginner
        default:    return .needsAttention
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - OverallGrade — novo tipo para avaliação global
// ─────────────────────────────────────────────────────────────────────────────

enum OverallGrade {
    case outstanding    // 90–100: excelente em todas as dimensões
    case proficient     // 75–89:  sólido, pequenos ajustes necessários
    case developing     // 60–74:  em desenvolvimento, áreas claras de melhora
    case beginner       // 40–59:  iniciante, requer prática focada
    case needsAttention // 0–39:   dificuldades fundamentais

    var label: String {
        switch self {
        case .outstanding:    return "Excelente"
        case .proficient:     return "Proficiente"
        case .developing:     return "Desenvolvendo"
        case .beginner:       return "Iniciante"
        case .needsAttention: return "Atenção necessária"
        }
    }

    var systemImage: String {
        switch self {
        case .outstanding:    return "star.fill"
        case .proficient:     return "checkmark.seal.fill"
        case .developing:     return "arrow.up.circle.fill"
        case .beginner:       return "book.fill"
        case .needsAttention: return "exclamationmark.triangle.fill"
        }
    }

    var color: String {
        switch self {
        case .outstanding:    return "yellow"
        case .proficient:     return "green"
        case .developing:     return "blue"
        case .beginner:       return "orange"
        case .needsAttention: return "red"
        }
    }

    /// Mensagem pedagógica para exibir ao aluno/professor
    var feedbackMessage: String {
        switch self {
        case .outstanding:
            return "Performance excepcional. Afinação precisa, melodia correta e musicalidade consistente."
        case .proficient:
            return "Boa performance. Pequenos ajustes de afinação ou contorno melódico podem elevar ainda mais."
        case .developing:
            return "Em desenvolvimento. Foque nos graus com avaliação 'Regular' ou 'Melhorar'."
        case .beginner:
            return "Prática focada recomendada. Comece pelas notas com maior desvio de afinação."
        case .needsAttention:
            return "Dificuldades em múltiplas dimensões. Trabalhe uma nota por vez com o professor."
        }
    }
}