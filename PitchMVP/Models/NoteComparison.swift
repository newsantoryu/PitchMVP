//
//  NoteComparison.swift
//  PitchMVP
//
//  Created by victor on 24/02/26.
//


// ComparisonModels.swift
// PitchMVP
//
// Modelos de dados para o sistema de comparação de voz.
// Conecta NoteSegment da voz do usuário com NoteSegment da referência,
// calculando métricas de diferença nota a nota (por ordem cronológica).

import Foundation

/// Resultado da comparação entre UMA nota do usuário e a nota correspondente
/// na referência (mesmo índice cronológico).
struct NoteComparison: Identifiable {

    let id = UUID()

    /// Índice da nota na sequência (0 = primeira nota detectada)
    let index: Int

    /// Segmento da voz do usuário (pode ser nil se referência tem mais notas)
    let userSegment: NoteSegment?

    /// Segmento da voz de referência (pode ser nil se usuário tem mais notas)
    let referenceSegment: NoteSegment?

    // MARK: - Métricas de Comparação

    /// Diferença de desvio médio em cents (usuário - referência).
    /// Positivo = usuário mais agudo que referência, negativo = mais grave.
    var centsDelta: Float? {
        guard let u = userSegment, let r = referenceSegment else { return nil }
        return u.averageCentsDeviation - r.averageCentsDeviation
    }

    /// Diferença de estabilidade em pontos percentuais (usuário - referência).
    /// Positivo = usuário mais estável.
    var stabilityDelta: Float? {
        guard let u = userSegment, let r = referenceSegment else { return nil }
        return u.stabilityPercentage - r.stabilityPercentage
    }

    /// Nome da nota (prefere o da referência como "nota alvo")
    var noteName: String {
        referenceSegment?.noteName ?? userSegment?.noteName ?? "?"
    }

    /// Avaliação geral da comparação para esta nota
    var grade: ComparisonGrade {
        guard let stab = stabilityDelta, let cents = centsDelta else { return .incomplete }
        let absStab = abs(stab)
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
// MARK: - ComparisonGrade
// ─────────────────────────────────────────────────────────────────────────────

enum ComparisonGrade {
    case excellent
    case good
    case fair
    case needsWork
    case incomplete  // uma das vozes não tem nota nesse índice

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

    var colorName: String {
        switch self {
        case .excellent:  return "green"
        case .good:       return "blue"
        case .fair:       return "orange"
        case .needsWork:  return "red"
        case .incomplete: return "secondary"
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - ComparisonResult
// ─────────────────────────────────────────────────────────────────────────────

/// Resultado completo da comparação entre duas gravações.
struct ComparisonResult {

    /// Lista de comparações nota a nota (ordem cronológica)
    let comparisons: [NoteComparison]

    /// Segmentos brutos da voz do usuário
    let userSegments: [NoteSegment]

    /// Segmentos brutos da referência
    let referenceSegments: [NoteSegment]

    /// Nome do arquivo do usuário
    let userFileName: String

    /// Nome do arquivo de referência
    let referenceFileName: String

    // MARK: - Agregados

    var totalPairs: Int { comparisons.filter { $0.userSegment != nil && $0.referenceSegment != nil }.count }

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

    var excellentCount: Int { comparisons.filter { $0.grade == .excellent }.count }
    var goodCount:      Int { comparisons.filter { $0.grade == .good }.count }
    var fairCount:      Int { comparisons.filter { $0.grade == .fair }.count }
    var needsWorkCount: Int { comparisons.filter { $0.grade == .needsWork }.count }

    /// Nota geral da sessão (0–100)
    var overallScore: Int {
        guard totalPairs > 0 else { return 0 }
        let weighted = excellentCount * 100 + goodCount * 75 + fairCount * 50 + needsWorkCount * 25
        return weighted / totalPairs
    }
}