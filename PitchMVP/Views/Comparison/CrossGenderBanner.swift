//
//  CrossGenderBanner.swift
//  PitchMVP
//
//  Created by victor on 26/02/26.
//

// CrossGenderBadge.swift
// PitchMVP
//
// Componentes visuais para indicar e contextualizar comparações cross-gender na UI.
//
// USO:
//   1. CrossGenderBanner — banner informativo no topo dos resultados quando detectado
//   2. OctaveShiftTag — tag inline no NoteComparisonCard quando notas diferem por oitava
//   3. VoiceTypeLabel — label compacto com ícone do registro vocal estimado
//
// Todos os componentes são noop quando não há cross-gender — seguros para uso incondicional.

import SwiftUI

/// Banner informativo que aparece SOMENTE em comparações cross-gender.
/// Explica ao aluno/professor que oitavas diferentes são esperadas e normais.
///
/// ```swift
/// CrossGenderBanner(context: vm.crossGenderContext)
/// ```
struct CrossGenderBanner: View {

    let context: CrossGenderContext?

    var body: some View {
        if let ctx = context, ctx.isCrossGender {
            HStack(spacing: 12) {
                Image(systemName: "person.2.wave.2.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.purple)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Comparação Cross-Gender")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Text("~\(Int(ctx.medianOctaveShift)) semitons de diferença")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Text("Barítono × Soprano é normal. Cada voz é avaliada na SUA nota — oitavas diferentes não penalizam.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.purple.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.purple.opacity(0.20), lineWidth: 1)
                    )
            )
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - OctaveShiftTag
// ─────────────────────────────────────────────────────────────────────────────

/// Tag inline que aparece no NoteComparisonCard quando user e ref estão em oitavas diferentes.
/// Exibe o intervalo real entre as notas (ex: "8ª acima") para contexto pedagógico.
///
/// ```swift
/// OctaveShiftTag(userNote: comparison.userSegment, referenceNote: comparison.referenceSegment)
/// ```
struct OctaveShiftTag: View {

    let userNote: NoteSegment?
    let referenceNote: NoteSegment?

    private var octaveInfo: (label: String, color: Color)? {
        guard let u = userNote, let r = referenceNote else { return nil }
        let diff = r.midiNote - u.midiNote
        let absDiff = abs(diff)

        // Só exibe quando há diferença >= 5 semitons (evita ruído para variações pequenas)
        guard absDiff >= 5 else { return nil }

        let direction = diff > 0 ? "abaixo" : "acima"
        let semitons = Int(absDiff.rounded())

        // Formato educativo: "1 oitava abaixo" ou "7 semitons acima"
        let label: String
        if (11...13).contains(semitons) {
            label = "1 oitava \(direction)"
        } else if semitons >= 14 {
            label = "2 oitavas \(direction)"
        } else {
            label = "\(semitons) semitons \(direction)"
        }

        return (label: label, color: diff > 0 ? .indigo : .purple)
    }

    var body: some View {
        if let info = octaveInfo {
            HStack(spacing: 4) {
                Image(systemName: info.color == .indigo ? "arrow.down" : "arrow.up")
                    .font(.system(size: 8, weight: .bold))
                Text(info.label)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(info.color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(info.color.opacity(0.10))
            .clipShape(Capsule())
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - VoiceTypeLabel
// ─────────────────────────────────────────────────────────────────────────────

/// Label compacto com ícone do registro vocal estimado.
/// Exibido no topo de cada coluna (REF / VOCÊ) no ComparisonSummaryBanner.
///
/// ```swift
/// VoiceTypeLabel(voiceType: ctx.estimatedUserVoiceType, role: "VOCÊ", color: .orange)
/// ```
struct VoiceTypeLabel: View {

    let voiceType: VocalRange
    let role: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: voiceType.systemImage)
                .font(.system(size: 10))
            Text("\(role): \(voiceType.rawValue)")
                .font(.system(size: 10, weight: .medium, design: .rounded))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.10))
        .clipShape(Capsule())
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - CrossGenderSummaryRow
// ─────────────────────────────────────────────────────────────────────────────

/// Row opcional no ComparisonSummaryBanner exibindo os registros vocais detectados.
/// Aparece somente quando isCrossGender = true.
///
/// ```swift
/// CrossGenderSummaryRow(context: vm.crossGenderContext)
/// ```
struct CrossGenderSummaryRow: View {

    let context: CrossGenderContext?

    var body: some View {
        if let ctx = context, ctx.isCrossGender {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 10))
                    .foregroundStyle(.purple)

                VoiceTypeLabel(
                    voiceType: ctx.estimatedReferenceVoiceType,
                    role: "REF",
                    color: .blue
                )

                Image(systemName: "arrow.right")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)

                VoiceTypeLabel(
                    voiceType: ctx.estimatedUserVoiceType,
                    role: "VOCÊ",
                    color: .orange
                )

                Spacer()

                Text("oitavas não penalizam")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Preview
// ─────────────────────────────────────────────────────────────────────────────

#if DEBUG
private struct CrossGenderPreview: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Cross-Gender Components").font(.headline)

                // Simula contexto cross-gender detectado
                let mockContext = CrossGenderContext(
                    medianOctaveShift: 12,
                    isCrossGender: true,
                    lowerVoice: .user,
                    estimatedUserVoiceType: .baritone,
                    estimatedReferenceVoiceType: .soprano
                )

                CrossGenderBanner(context: mockContext)

                CrossGenderSummaryRow(context: mockContext)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                HStack {
                    VoiceTypeLabel(voiceType: .baritone, role: "VOCÊ", color: .orange)
                    VoiceTypeLabel(voiceType: .soprano,  role: "REF",  color: .blue)
                    VoiceTypeLabel(voiceType: .tenor,    role: "VOCÊ", color: .orange)
                }

                // OctaveShiftTag não pode ser previewed sem NoteSegment real
                // mas exibe como ficaria com Text mock
                HStack(spacing: 6) {
                    Text("C3")
                        .font(.system(size: 20, weight: .light, design: .rounded))
                    Image(systemName: "arrow.up")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.purple)
                    Text("1 oitava acima")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.purple)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.purple.opacity(0.10))
                        .clipShape(Capsule())
                }
            }
            .padding(20)
        }
    }
}

#Preview { CrossGenderPreview() }
#endif