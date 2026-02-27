// CrossGenderBadge.swift
// PitchMVP
//
// v5 — VoiceRegistryCard sempre visível acima das abas:
// • VoiceRegistryCard: card fixo com os dois pickers lado a lado, sempre na tela
// • VoiceHintPicker: versão compacta para uso inline no card
// • Badges de resultado mantêm visibilidade condicional via isCrossGender

import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - VoiceRegistryCard  (NOVO — card fixo sempre visível)
// ─────────────────────────────────────────────────────────────────────────────

/// Card com os dois seletores de registro lado a lado.
/// Posicionado ACIMA das abas de arquivo — impossível de ignorar.
/// Exibe estado de completude: verde quando ambos selecionados, laranja quando falta.
///
/// ```swift
/// VoiceRegistryCard(userHint: $vm.userVoiceHint, referenceHint: $vm.referenceVoiceHint)
/// ```
struct VoiceRegistryCard: View {

    @Binding var userHint: VoiceRangeHint?
    @Binding var referenceHint: VoiceRangeHint?

    private var bothSelected: Bool { userHint != nil && referenceHint != nil }

    var body: some View {
        VStack(spacing: 10) {

            // Cabeçalho do card
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: bothSelected ? "checkmark.circle.fill" : "circle.dotted")
                        .font(.system(size: 11))
                        .foregroundStyle(bothSelected ? Color.green : Color.orange)
                    Text("REGISTRO DAS VOZES")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(1.5)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !bothSelected {
                    Text("Obrigatório para comparar")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.orange)
                }
            }

            // Dois pickers lado a lado
            HStack(spacing: 10) {
                VoiceHintPicker(hint: $userHint, label: "Sua voz", color: .orange)
                    .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(Color(.separator).opacity(0.5))
                    .frame(width: 0.5)
                    .padding(.vertical, 4)

                VoiceHintPicker(hint: $referenceHint, label: "Referência", color: .blue)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            bothSelected ? Color.green.opacity(0.25) : Color.orange.opacity(0.30),
                            lineWidth: 1
                        )
                )
        )
        .animation(.easeOut(duration: 0.2), value: bothSelected)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - VoiceHintPicker  (compacto, sem Auto)
// ─────────────────────────────────────────────────────────────────────────────

/// Picker compacto para uso dentro do VoiceRegistryCard.
/// Apenas Masculino e Feminino — sem Auto.
struct VoiceHintPicker: View {

    @Binding var hint: VoiceRangeHint?
    let label: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {

            Text(label.uppercased())
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(hint == nil ? .orange : .brown)

            HStack(spacing: 5) {
                hintButton(.male,   icon: "arrow.down.circle", title: "Masc.")
                hintButton(.female, icon: "arrow.up.circle",   title: "Fem.")
            }
        }
    }

    private func hintButton(_ target: VoiceRangeHint, icon: String, title: String) -> some View {
        let isSelected = hint?.matches(target) ?? false

        return Button {
            withAnimation(.spring(duration: 0.2)) { hint = target }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isSelected ? "\(icon).fill" : icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(isSelected ? color.opacity(0.12) : Color(.tertiarySystemFill))
            .foregroundStyle(isSelected ? color : Color.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isSelected ? color.opacity(0.5) : (hint == nil ? Color.orange.opacity(0.3) : Color.clear),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

extension VoiceRangeHint {
    func matches(_ other: VoiceRangeHint) -> Bool {
        switch (self, other) {
        case (.male, .male), (.female, .female): return true
        default: return false
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - CrossGenderBanner
// ─────────────────────────────────────────────────────────────────────────────

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
                        Text("~\(Int(ctx.medianOctaveShift)) semitons")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Text("Cada voz é avaliada na SUA nota — oitavas diferentes não penalizam.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.purple.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.purple.opacity(0.20), lineWidth: 1))
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - OctaveShiftTag
// ─────────────────────────────────────────────────────────────────────────────

struct OctaveShiftTag: View {

    let userNote: NoteSegment?
    let referenceNote: NoteSegment?
    let crossGenderContext: CrossGenderContext?

    var body: some View {
        if let ctx = crossGenderContext, ctx.isCrossGender, let info = octaveInfo {
            HStack(spacing: 4) {
                Image(systemName: info.direction == "acima" ? "arrow.up" : "arrow.down")
                    .font(.system(size: 8, weight: .bold))
                Text(info.label)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(info.color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(info.color.opacity(0.10))
            .clipShape(Capsule())
        }
    }

    private var octaveInfo: (label: String, direction: String, color: Color)? {
        guard let u = userNote, let r = referenceNote else { return nil }
        let diff    = r.midiNote - u.midiNote
        let absDiff = abs(diff)
        guard absDiff >= 5 else { return nil }

        let direction = diff > 0 ? "abaixo" : "acima"
        let semitons  = Int(absDiff.rounded())
        let label: String
        if (11...13).contains(semitons)  { label = "1 oitava \(direction)" }
        else if semitons >= 14           { label = "2 oitavas \(direction)" }
        else                             { label = "\(semitons) st \(direction)" }

        return (label: label, direction: direction, color: diff > 0 ? .indigo : .purple)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - CrossGenderSummaryRow
// ─────────────────────────────────────────────────────────────────────────────

struct CrossGenderSummaryRow: View {

    let context: CrossGenderContext?

    var body: some View {
        if let ctx = context, ctx.isCrossGender {
            HStack(spacing: 8) {
                Image(systemName: "waveform").font(.system(size: 10)).foregroundStyle(.purple)
                voiceLabel(type: ctx.estimatedReferenceVoiceType, role: "REF",  color: .blue)
                Image(systemName: "arrow.right").font(.system(size: 9)).foregroundStyle(.tertiary)
                voiceLabel(type: ctx.estimatedUserVoiceType,      role: "VOCÊ", color: .orange)
                Spacer()
                Text("oitavas não penalizam")
                    .font(.system(size: 9, design: .rounded)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
    }

    private func voiceLabel(type: VocalRange, role: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: type.systemImage).font(.system(size: 10))
            Text("\(role): \(type.rawValue)")
                .font(.system(size: 10, weight: .medium, design: .rounded))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(color.opacity(0.10))
        .clipShape(Capsule())
    }
}