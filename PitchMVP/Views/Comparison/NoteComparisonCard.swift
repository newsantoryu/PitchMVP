// NoteComparisonCard.swift
// PitchMVP
//
// v3 — Original restaurado + espaçamento corrigido:
//
// MANTIDO do original:
//   • Estrutura HStack de 1 linha: índice | noteInfo | pitchMetrics | Spacer | time | grade | chevron
//   • noteInfo: nota grande (size 20) + pitch class match + OctaveShiftTag
//   • pitchMetrics: centsDelta + ícones de contorno + check
//   • timeChip, gradeBadge, chevron no lado direito
//
// CORRIGIDO:
//   • noteInfo: removido frame(width: 110) fixo que cortava conteúdo em telas menores.
//     Substituído por frame(minWidth: 90, maxWidth: 130) — dá espaço mínimo garantido
//     para "C#4 + Grau correto" sem desperdiçar espaço em notas curtas.
//   • pitchMetrics: adicionado fixedSize(horizontal: true, vertical: false) para que
//     cents e ícones de contorno nunca sejam truncados pelo Spacer.
//   • HStack spacing: 14 → 10 para respira melhor em iPhone SE.
//
// Dependências externas (já existem no projeto):
//   • NoteComparison, NoteSegment, ComparisonGrade, ContourDirection  → NoteComparison.swift
//   • CrossGenderContext                                               → MelodicAligner.swift
//   • VibratoAnalysis, VibratoQuality                                 → NoteSegmenter.swift
//   • OverlappedPitchCurveView                                        → OverlappedPitchCurveView.swift
//   • OctaveShiftTag                                                   → CrossGenderBadge.swift

import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - NoteComparisonCard
// ─────────────────────────────────────────────────────────────────────────────

struct NoteComparisonCard: View {

    let comparison: NoteComparison
    let crossGenderContext: CrossGenderContext?

    @State private var expanded = false

    private var gradeColor: Color {
        switch comparison.grade {
        case .excellent:  return .green
        case .good:       return .blue
        case .fair:       return .orange
        case .needsWork:  return .red
        case .incomplete: return Color(.tertiaryLabel)
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            rowHeader
            if expanded { expandedContent }
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
    }

    // MARK: - Row Header

    private var rowHeader: some View {
        Button {
            withAnimation(.spring(duration: 0.3)) { expanded.toggle() }
        } label: {
            HStack(spacing: 10) {                                          // era 14 — mais ar

                // ── Índice ──────────────────────────────────────────────
                Text("\(comparison.index + 1)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .frame(width: 20, alignment: .trailing)

                // ── Nota + grau + octave shift ──────────────────────────
                noteInfo

                // ── Cents + contorno ────────────────────────────────────
                pitchMetrics

                Spacer()

                // ── Tempo ───────────────────────────────────────────────
                timeChip

                // ── Grade ───────────────────────────────────────────────
                gradeBadge

                // ── Chevron ─────────────────────────────────────────────
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - noteInfo

    // FIX: era frame(width: 110) — número fixo cortava "Grau errado (C#)" em iPhones menores.
    // frame(minWidth:maxWidth:) garante espaço mínimo sem desperdiçar espaço em notas curtas.
    private var noteInfo: some View {
        VStack(alignment: .leading, spacing: 2) {

            Text(comparison.noteName)
                .font(.system(size: 20, weight: .light, design: .rounded))

            if comparison.userSegment != nil && comparison.referenceSegment != nil {
                HStack(spacing: 3) {
                    Image(systemName: comparison.pitchClassMatch
                          ? "checkmark.circle.fill"
                          : "xmark.circle.fill")
                        .font(.system(size: 8))
                    Text(comparison.pitchClassMatch
                         ? "Grau correto"
                         : "Grau errado (\(comparison.userPitchClass ?? "?"))")
                        .font(.system(size: 9, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundStyle(comparison.pitchClassMatch ? Color.green : Color.red)
            }

            OctaveShiftTag(
                userNote: comparison.userSegment,
                referenceNote: comparison.referenceSegment,
                crossGenderContext: crossGenderContext
            )
        }
        .frame(minWidth: 90, maxWidth: 130, alignment: .leading)   // FIX: era frame(width: 110)
    }

    // MARK: - pitchMetrics

    // FIX: fixedSize garante que cents e ícones não sejam espremidos pelo Spacer().
    private var pitchMetrics: some View {
        VStack(alignment: .leading, spacing: 2) {

            if let cents = comparison.centsDelta {
                Text(String(format: "%+.1f¢", cents))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(abs(cents) < 10 ? Color.green : Color.primary)
            }

            if let match = comparison.melodicContourMatch {
                HStack(spacing: 3) {
                    contourIcon(comparison.userContourDirection,      color: .orange)
                    contourIcon(comparison.referenceContourDirection, color: .blue)
                    Text(match ? "✓" : "✗")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(match ? Color.green : Color.red)
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)              // FIX: nunca truncado
    }

    // MARK: - timeChip

    private var timeChip: some View {
        VStack(spacing: 1) {
            Image(systemName: "clock")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
            Text(comparison.startTimeFormatted)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - gradeBadge

    private var gradeBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: comparison.grade.systemImage)
                .font(.system(size: 12))
            Text(comparison.grade.label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(gradeColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(gradeColor.opacity(0.1))
        .clipShape(Capsule())
    }

    // MARK: - expandedContent

    private var expandedContent: some View {
        VStack(spacing: 16) {
            Divider().padding(.horizontal, 16)

            NoteComparisonMetricsGrid(
                comparison: comparison,
                isCrossGender: crossGenderContext?.isCrossGender ?? false
            )
            .padding(.horizontal, 16)

            OverlappedPitchCurveView(comparison: comparison)
                .padding(.horizontal, 16)

            if comparison.userSegment?.vibrato != nil
                || comparison.referenceSegment?.vibrato != nil {
                NoteVibratoComparisonRow(comparison: comparison)
                    .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 16)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Helpers

    private func contourIcon(_ direction: ContourDirection, color: Color) -> some View {
        let icon: String
        switch direction {
        case .up:    icon = "arrow.up"
        case .down:  icon = "arrow.down"
        case .same:  icon = "minus"
        case .unset: icon = "circle"
        }
        return Image(systemName: icon)
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(color)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - NoteComparisonMetricsGrid
// ─────────────────────────────────────────────────────────────────────────────

struct NoteComparisonMetricsGrid: View {

    let comparison: NoteComparison
    let isCrossGender: Bool

    var body: some View {
        VStack(spacing: 10) {

            if isCrossGender,
               let u = comparison.userSegment,
               let r = comparison.referenceSegment,
               abs(u.midiNote - r.midiNote) > 6 {
                crossGenderBanner
            }

            metricRow(
                label: "Afinação",
                userValue: comparison.userSegment
                    .map { String(format: "%.1f¢", $0.averageCentsDeviation) } ?? "—",
                refValue: comparison.referenceSegment
                    .map { String(format: "%.1f¢", $0.averageCentsDeviation) } ?? "—",
                delta: comparison.centsDelta
                    .map { String(format: "%+.1f¢", $0) }
            )

            metricRow(
                label: "Estável",
                userValue: comparison.userSegment
                    .map { String(format: "%.0f%%", $0.stabilityPercentage) } ?? "—",
                refValue: comparison.referenceSegment
                    .map { String(format: "%.0f%%", $0.stabilityPercentage) } ?? "—",
                delta: comparison.stabilityDelta
                    .map { String(format: "%+.0f%%", $0) }
            )

            metricRow(
                label: "Duração",
                userValue: comparison.userSegment
                    .map { String(format: "%.2fs", $0.durationSeconds) } ?? "—",
                refValue: comparison.referenceSegment
                    .map { String(format: "%.2fs", $0.durationSeconds) } ?? "—",
                delta: nil
            )

            if let u = comparison.userSegment,
               let r = comparison.referenceSegment {
                noteNameRow(user: u, reference: r)
            }
        }
    }

    private var crossGenderBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text("Vozes em oitavas diferentes — desvio medido individualmente")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemFill).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func metricRow(
        label: String,
        userValue: String,
        refValue: String,
        delta: String?
    ) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            Spacer()

            VStack(spacing: 1) {
                Text("REF").font(.system(size: 8, weight: .semibold, design: .rounded))
                    .tracking(1).foregroundStyle(Color.blue.opacity(0.7))
                Text(refValue).font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.blue)
            }.frame(width: 56)

            VStack(spacing: 1) {
                Text("VOCÊ").font(.system(size: 8, weight: .semibold, design: .rounded))
                    .tracking(1).foregroundStyle(Color.orange.opacity(0.7))
                Text(userValue).font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.orange)
            }.frame(width: 56)

            if let d = delta {
                Text(d)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(d.hasPrefix("+") ? Color.green : Color.red)
                    .frame(width: 52, alignment: .trailing)
            } else {
                Spacer().frame(width: 52)
            }
        }
    }

    private func noteNameRow(user: NoteSegment, reference: NoteSegment) -> some View {
        HStack {
            Text("Nota")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            Spacer()

            VStack(spacing: 1) {
                Text("REF").font(.system(size: 8, weight: .semibold, design: .rounded))
                    .tracking(1).foregroundStyle(Color.blue.opacity(0.7))
                Text(reference.noteName).font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.blue)
            }.frame(width: 56)

            VStack(spacing: 1) {
                Text("VOCÊ").font(.system(size: 8, weight: .semibold, design: .rounded))
                    .tracking(1).foregroundStyle(Color.orange.opacity(0.7))
                Text(user.noteName).font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.orange)
            }.frame(width: 56)

            Image(systemName: comparison.pitchClassMatch
                  ? "checkmark.circle.fill" : "xmark.circle")
                .font(.system(size: 14))
                .foregroundStyle(comparison.pitchClassMatch ? Color.green : Color.red)
                .frame(width: 52, alignment: .trailing)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - NoteVibratoComparisonRow
// ─────────────────────────────────────────────────────────────────────────────

struct NoteVibratoComparisonRow: View {

    let comparison: NoteComparison

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("VIBRATO")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(2)
                .foregroundStyle(.tertiary)

            HStack(spacing: 12) {
                vibratoCell(label: "REF",  vibrato: comparison.referenceSegment?.vibrato, color: .blue)
                vibratoCell(label: "VOCÊ", vibrato: comparison.userSegment?.vibrato,      color: .orange)
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemFill).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func vibratoCell(label: String, vibrato: VibratoAnalysis?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(color.opacity(0.7))

            if let v = vibrato {
                HStack(spacing: 12) {
                    vibratoStat("TAXA",  value: String(format: "%.1fHz", v.rateHz))
                    vibratoStat("PROF.", value: String(format: "%.0f¢",  v.depthCents))
                    vibratoStat("REG.",  value: String(format: "%.0f%%", v.regularity * 100))
                }
                Text(v.quality.rawValue)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(color)
            } else {
                Text("Não detectado")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func vibratoStat(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 8, design: .rounded))
                .foregroundStyle(.quaternary)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .rounded))
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Preview
// ─────────────────────────────────────────────────────────────────────────────

#if DEBUG
#Preview("Lista completa") {
    let make = { (note: String, midi: Float, freq: Float, dev: Float, stab: Float, time: Float, vib: VibratoAnalysis?) -> NoteSegment in
        NoteSegment(
            noteName: note, medianFrequency: freq, midiNote: midi,
            pitchCurve: [],
            centsOverTime: (0..<20).map { Float($0) * (dev / 20) },
            averageCentsDeviation: dev, maxCentsDeviation: dev * 1.5,
            stabilityPercentage: stab, vibrato: vib,
            durationSeconds: 0.9, startTime: time, frameCount: 90
        )
    }

    let pairs: [(NoteSegment?, NoteSegment?, ContourDirection)] = [
        (make("A3", 57, 220,    4.2, 92, 0.5, nil),
         make("A4", 69, 440,    2.1, 95, 0.5, VibratoAnalysis(rateHz: 5.8, depthCents: 35, regularity: 0.82)), .up),
        (make("B3", 59, 246.9, 22.0, 61, 1.4, nil),
         make("B4", 71, 493.9,  3.0, 93, 1.4, nil), .up),
        (make("C#4", 61, 277.2,  8.5, 78, 2.3, nil),
         make("C#4", 61, 277.2,  3.5, 91, 2.3, nil), .down),
        (nil,
         make("D4", 62, 293.7,  2.0, 94, 3.1, nil), .up),
        (make("E4", 64, 329.6, 35.0, 45, 4.0, nil),
         make("E4", 64, 329.6,  4.0, 90, 4.0, nil), .down),
    ]

    let ctx = CrossGenderContext(
        medianOctaveShift: 12, isCrossGender: true,
        lowerVoice: .user,
        estimatedUserVoiceType: .baritone,
        estimatedReferenceVoiceType: .soprano
    )

    let comparisons: [NoteComparison] = pairs.enumerated().map { i, pair in
        var c = NoteComparison(index: i, userSegment: pair.0, referenceSegment: pair.1)
        c.userContourDirection      = i == 0 ? .unset : pair.2
        c.referenceContourDirection = i == 0 ? .unset : pair.2
        return c
    }

    return ScrollView {
        VStack(spacing: 8) {
            Text("NOTA A NOTA")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(2).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)

            ForEach(comparisons) { comp in
                NoteComparisonCard(comparison: comp, crossGenderContext: ctx)
                    .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 16)
    }
    .background(Color(.systemGroupedBackground))
}
#endif