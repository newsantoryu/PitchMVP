// NoteComparison.swift
// PitchMVP
//
// Modelo de comparação nota a nota.
//
// SEMÂNTICA DE OITAVA:
//   O pareamento é sempre cronológico (1ª com 1ª, 2ª com 2ª).
//   `pitchClassMatch` indica se o GRAU bate, ignorando oitava (C3 vs C4 = true).
//   `centsDelta` compara o desvio individual de cada voz em relação à sua
//   própria nota — correto para cross-gender onde as oitavas diferem.
//
// MÉTRICAS DISPONÍVEIS:
//   • centsDelta          → diferença de qualidade de afinação (desvio vs desvio)
//   • userIntonation      → desvio do usuário na SUA nota (independente da ref.)
//   • referenceIntonation → desvio da referência na SUA nota
//   • pitchClassMatch     → mesmo grau ignorando oitava (C3 vs C4 = true)
//   • melodicContourMatch → movimentos melódicos na mesma direção

import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - NoteComparison
// ─────────────────────────────────────────────────────────────────────────────

struct NoteComparison: Identifiable {

    let id = UUID()
    let index: Int
    let userSegment: NoteSegment?
    let referenceSegment: NoteSegment?

    // Injetado externamente pelo ViewModel após montar todos os pares
    var userContourDirection:      ContourDirection = .unset
    var referenceContourDirection: ContourDirection = .unset

    // ── Afinação Individual ──────────────────────────────────────────────────

    /// Diferença de desvio médio (usuário.desvio − referência.desvio).
    ///
    /// Ambos os desvios são relativos à PRÓPRIA nota de cada voz.
    /// Exemplo: barítono C3 com +5¢, soprano C4 com +3¢ → centsDelta = +2¢.
    /// Isso NÃO significa que cantaram próximos em frequência — significa que
    /// o barítono afinado 2¢ pior que a soprano, cada um na sua nota.
    var centsDelta: Float? {
        guard let u = userSegment, let r = referenceSegment else { return nil }
        return u.averageCentsDeviation - r.averageCentsDeviation
    }

    /// Desvio do usuário em relação à SUA nota alvo (cents). Independe da ref.
    var userIntonation: Float? { userSegment?.averageCentsDeviation }

    /// Desvio da referência em relação à SUA nota alvo (cents).
    var referenceIntonation: Float? { referenceSegment?.averageCentsDeviation }

    /// Diferença de estabilidade em pontos percentuais (usuário − referência).
    var stabilityDelta: Float? {
        guard let u = userSegment, let r = referenceSegment else { return nil }
        return u.stabilityPercentage - r.stabilityPercentage
    }

    // ── Grau Melódico (tolerância de oitava) ────────────────────────────────

    /// Pitch class (grau) da referência sem oitava: "C", "D#", "A", etc.
    var referencePitchClass: String? {
        referenceSegment.map { MusicTheory.pitchClass(from: $0.noteName) }
    }

    /// Pitch class do usuário sem oitava.
    var userPitchClass: String? {
        userSegment.map { MusicTheory.pitchClass(from: $0.noteName) }
    }

    /// true se usuário e referência cantaram o mesmo grau (oitava ignorada).
    /// C3 vs C4 = true. C3 vs D4 = false.
    var pitchClassMatch: Bool {
        guard let u = userPitchClass, let r = referencePitchClass else { return false }
        return u == r
    }

    // ── Contorno Melódico ────────────────────────────────────────────────────

    /// true se ambas as vozes se moveram na mesma direção em relação à nota anterior.
    /// nil se for a primeira nota ou se uma das vozes não tem dados.
    var melodicContourMatch: Bool? {
        guard userContourDirection      != .unset,
              referenceContourDirection != .unset else { return nil }
        // "same" (nota repetida) é considerada neutra — aceita qualquer parceiro
        if userContourDirection == .same || referenceContourDirection == .same { return true }
        return userContourDirection == referenceContourDirection
    }

    // ── Tempo na música ──────────────────────────────────────────────────────

    /// Tempo de início do par no arquivo do usuário, formatado como "m:ss".
    /// Usa o segmento do usuário como referência; se ausente, usa a referência.
    var startTimeFormatted: String {
        let t = userSegment?.startTime ?? referenceSegment?.startTime ?? 0
        let minutes = Int(t) / 60
        let seconds = Int(t) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Tempo de início em segundos (para uso interno).
    var startTimeSeconds: Float {
        userSegment?.startTime ?? referenceSegment?.startTime ?? 0
    }

    // ── Nome para exibição ───────────────────────────────────────────────────

    var noteName: String {
        referenceSegment?.noteName ?? userSegment?.noteName ?? "?"
    }

    // ── Grade ────────────────────────────────────────────────────────────────

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
// MARK: - ContourDirection
// ─────────────────────────────────────────────────────────────────────────────

enum ContourDirection: Equatable {
    case up     // nota subiu em relação à anterior
    case down   // nota desceu em relação à anterior
    case same   // nota igual (repetição)
    case unset  // primeira nota ou dado indisponível
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - ComparisonGrade
// ─────────────────────────────────────────────────────────────────────────────

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
// MARK: - ComparisonResult
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

    // ── Afinação ──────────────────────────────────────────────────────────────

    /// Desvio médio absoluto do USUÁRIO em relação à sua própria nota.
    /// Métrica principal de afinação — não depende da referência.
    var userAverageIntonation: Float {
        let valid = comparisons.compactMap(\.userIntonation)
        guard !valid.isEmpty else { return 0 }
        return valid.reduce(0, +) / Float(valid.count)
    }

    /// Desvio médio absoluto da REFERÊNCIA em relação à sua própria nota.
    var referenceAverageIntonation: Float {
        let valid = comparisons.compactMap(\.referenceIntonation)
        guard !valid.isEmpty else { return 0 }
        return valid.reduce(0, +) / Float(valid.count)
    }

    /// Diferença de desvio médio entre usuário e referência (Δ qualidade).
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

    // ── Grau e Contorno ───────────────────────────────────────────────────────

    /// % de notas em que o grau bate entre as vozes (oitava ignorada).
    /// 100% = cantou todos os graus certos, mesmo que em oitava diferente.
    var pitchClassMatchScore: Float {
        let valid = comparisons.filter { $0.userSegment != nil && $0.referenceSegment != nil }
        guard !valid.isEmpty else { return 0 }
        return Float(valid.filter(\.pitchClassMatch).count) / Float(valid.count) * 100
    }

    /// % de notas em que as vozes se moveram na mesma direção melódica.
    var melodicContourScore: Float {
        let valid = comparisons.compactMap(\.melodicContourMatch)
        guard !valid.isEmpty else { return 0 }
        return Float(valid.filter { $0 }.count) / Float(valid.count) * 100
    }

    // ── Grade breakdown ───────────────────────────────────────────────────────

    var excellentCount: Int { comparisons.filter { $0.grade == .excellent }.count }
    var goodCount:      Int { comparisons.filter { $0.grade == .good      }.count }
    var fairCount:      Int { comparisons.filter { $0.grade == .fair      }.count }
    var needsWorkCount: Int { comparisons.filter { $0.grade == .needsWork }.count }
    var incompleteCount:Int { comparisons.filter { $0.grade == .incomplete }.count }

    // ── Desvio médio por faixa (usuário) ─────────────────────────────────────
    // Baseado no desvio individual do usuário em relação à sua própria nota.
    // <10¢ = afinado (verde), 10–30¢ = atenção (amarelo/laranja), >30¢ = fora (vermelho)

    /// Notas do usuário com desvio < 10¢ (zona afinada)
    var inTuneCount: Int {
        comparisons.compactMap(\.userIntonation).filter { $0 < 10 }.count
    }

    /// Notas do usuário com desvio entre 10¢ e 30¢ (atenção)
    var nearTuneCount: Int {
        comparisons.compactMap(\.userIntonation).filter { $0 >= 10 && $0 < 30 }.count
    }

    /// Notas do usuário com desvio > 30¢ (fora de afinação)
    var outOfTuneCount: Int {
        comparisons.compactMap(\.userIntonation).filter { $0 >= 30 }.count
    }

    // ── Direção do desvio (agudo vs grave) ───────────────────────────────────
    // Usa centsDelta com sinal: positivo = usuário mais agudo que a referência,
    // negativo = usuário mais grave.

    /// Notas em que o usuário ficou acima da referência (desvio positivo)
    var sharpCount: Int {
        comparisons.compactMap(\.centsDelta).filter { $0 > 0 }.count
    }

    /// Notas em que o usuário ficou abaixo da referência (desvio negativo)
    var flatCount: Int {
        comparisons.compactMap(\.centsDelta).filter { $0 < 0 }.count
    }

    /// Notas com desvio de direção zero (ambos igualmente afinados)
    var centeredCount: Int {
        comparisons.compactMap(\.centsDelta).filter { $0 == 0 }.count
    }

    var overallScore: Int {
        guard totalPairs > 0 else { return 0 }
        let weighted = excellentCount * 100 + goodCount * 75 + fairCount * 50 + needsWorkCount * 25
        return weighted / totalPairs
    }
}