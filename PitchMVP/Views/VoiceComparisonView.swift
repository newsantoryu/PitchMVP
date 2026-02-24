//
//  VoiceComparisonView.swift
//  PitchMVP
//
//  Created by victor on 24/02/26.
//

// VoiceComparisonView.swift
// PitchMVP
//
// Tela de comparação vocal com 3 estados:
//   • Seleção: abas "Minha Voz" e "Referência" para escolher os WAVs
//   • Análise: progress enquanto processa
//   • Resultado: comparação nota a nota com curvas sobrepostas

import SwiftUI
import UniformTypeIdentifiers

struct VoiceComparisonView: View {

    @StateObject private var vm = VoiceComparisonViewModel()
    @State private var showUserPicker = false
    @State private var showRefPicker  = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    header

                    switch vm.state {
                    case .idle:
                        selectionContent
                    case .analyzing:
                        analyzingView
                    case .done:
                        if let result = vm.result {
                            resultContent(result: result)
                        }
                    case .empty:
                        emptyResult
                    case .error(let msg):
                        errorView(msg)
                    }
                }
            }
            .navigationBarHidden(true)
        }
        // File pickers
        .fileImporter(isPresented: $showUserPicker,
                      allowedContentTypes: [UTType.audio, .wav, .mp3],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                let ok = url.startAccessingSecurityScopedResource()
                vm.selectUserExternal(url: url)
                if ok { url.stopAccessingSecurityScopedResource() }
            }
        }
        .fileImporter(isPresented: $showRefPicker,
                      allowedContentTypes: [UTType.audio, .wav, .mp3],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                let ok = url.startAccessingSecurityScopedResource()
                vm.selectReferenceExternal(url: url)
                if ok { url.stopAccessingSecurityScopedResource() }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("COMPARAÇÃO")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(.secondary)
                Text("Vocal")
                    .font(.system(size: 28, weight: .thin, design: .rounded))
            }

            Spacer()

            // Botão reset (só aparece quando há resultado)
            if vm.state == .done {
                Button {
                    withAnimation { vm.reset() }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Tela de Seleção
    // ─────────────────────────────────────────────────────────────────────────

    private var selectionContent: some View {
        VStack(spacing: 0) {

            // Indicador de status das seleções
            SelectionStatusBar(
                userFile: vm.userDisplayName,
                refFile: vm.refDisplayName,
                userSelected: vm.userFileName != nil || vm.userFileURL != nil,
                refSelected:  vm.referenceFileName != nil || vm.referenceFileURL != nil
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 20)

            // Abas Minha Voz / Referência
            VoiceTabPicker(activeTab: $vm.activeTab)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

            // Conteúdo da aba
            if vm.activeTab == 0 {
                fileListPanel(
                    title: "Selecione sua voz",
                    selectedName: vm.userFileName,
                    highlightColor: .orange,
                    onBundleSelect: { vm.selectUserFromBundle($0) },
                    onImport: { showUserPicker = true }
                )
            } else {
                fileListPanel(
                    title: "Selecione a referência",
                    selectedName: vm.referenceFileName,
                    highlightColor: .blue,
                    onBundleSelect: { vm.selectReferenceFromBundle($0) },
                    onImport: { showRefPicker = true }
                )
            }

            Spacer()

            // Botão Comparar
            compareButton
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
        }
    }

    /// Painel de listagem dos WAVs do Bundle para cada aba.
    private func fileListPanel(
        title: String,
        selectedName: String?,
        highlightColor: Color,
        onBundleSelect: @escaping (String) -> Void,
        onImport: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {

            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 20)

            // Lista de arquivos do Bundle
            VStack(spacing: 1) {
                ForEach(vm.bundleFiles, id: \.self) { name in
                    let isSelected = selectedName == name
                    FileRow(
                        name: "\(name).wav",
                        isSelected: isSelected,
                        accentColor: highlightColor
                    )
                    .onTapGesture { onBundleSelect(name) }

                    if name != vm.bundleFiles.last {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 20)

            // Importar externo
            Button {
                onImport()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 13))
                    Text("Importar arquivo externo")
                        .font(.system(size: 14, design: .rounded))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 20)
        }
    }

    private var compareButton: some View {
        Button {
            vm.startComparison()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 14, weight: .semibold))
                Text("Comparar")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(vm.canCompare ? Color.primary : Color(.tertiarySystemFill))
            .foregroundStyle(vm.canCompare ? Color(.systemBackground) : Color.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .disabled(!vm.canCompare)
        .animation(.easeOut(duration: 0.2), value: vm.canCompare)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Analisando
    // ─────────────────────────────────────────────────────────────────────────

    private var analyzingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
                .tint(.secondary)
            Text(vm.state.stepMessage)
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(.secondary)
                .animation(.easeOut, value: vm.state.stepMessage)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Resultado
    // ─────────────────────────────────────────────────────────────────────────

    private func resultContent(result: ComparisonResult) -> some View {
        ScrollView {
            VStack(spacing: 16) {

                // Banner de resumo geral
                ComparisonSummaryBanner(result: result)
                    .padding(.horizontal, 20)

                // Cards de comparação nota a nota
                VStack(alignment: .leading, spacing: 10) {
                    Text("NOTA A NOTA")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 20)

                    ForEach(result.comparisons) { comparison in
                        NoteComparisonCard(comparison: comparison)
                            .padding(.horizontal, 20)
                    }
                }

                Spacer(minLength: 40)
            }
            .padding(.top, 4)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Estados extras
    // ─────────────────────────────────────────────────────────────────────────

    private var emptyResult: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "waveform.slash")
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(.tertiary)
            Text("Nenhuma nota detectada")
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36, weight: .thin))
                .foregroundStyle(.orange)
            Text("Erro na análise")
                .font(.system(size: 15, weight: .medium, design: .rounded))
            Text(msg)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SelectionStatusBar
// ─────────────────────────────────────────────────────────────────────────────

private struct SelectionStatusBar: View {
    let userFile: String
    let refFile: String
    let userSelected: Bool
    let refSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            statusChip(
                icon: "mic",
                label: "Minha voz",
                file: userFile,
                isSelected: userSelected,
                color: .orange
            )

            Image(systemName: "arrow.right")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            statusChip(
                icon: "star",
                label: "Referência",
                file: refFile,
                isSelected: refSelected,
                color: .blue
            )
        }
    }

    private func statusChip(
        icon: String,
        label: String,
        file: String,
        isSelected: Bool,
        color: Color
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? .primary : .tertiary)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.tertiary)
                Text(isSelected ? file : "—")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(isSelected ? .primary : .tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? color.opacity(0.08) : Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? color.opacity(0.25) : Color.clear, lineWidth: 1)
        )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - VoiceTabPicker
// ─────────────────────────────────────────────────────────────────────────────

private struct VoiceTabPicker: View {
    @Binding var activeTab: Int

    var body: some View {
        HStack(spacing: 0) {
            tabButton(title: "Minha Voz", icon: "mic.fill", index: 0, color: .orange)
            tabButton(title: "Referência", icon: "star.fill", index: 1, color: .blue)
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func tabButton(title: String, icon: String, index: Int, color: Color) -> some View {
        let isActive = activeTab == index
        return Button {
            withAnimation(.spring(duration: 0.25)) { activeTab = index }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isActive ? color.opacity(0.12) : Color.clear)
            )
            .foregroundStyle(isActive ? color : Color.secondary)
        }
        .padding(3)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - FileRow
// ─────────────────────────────────────────────────────────────────────────────

private struct FileRow: View {
    let name: String
    let isSelected: Bool
    let accentColor: Color

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(isSelected ? accentColor.opacity(0.15) : Color(.tertiarySystemFill))
                    .frame(width: 36, height: 36)
                Image(systemName: isSelected ? "waveform" : "doc.waveform")
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? accentColor : Color.secondary)
            }

            Text(name)
                .font(.system(size: 15, weight: isSelected ? .semibold : .regular, design: .rounded))
                .foregroundStyle(isSelected ? .primary : .primary)

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(accentColor)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(isSelected ? accentColor.opacity(0.05) : Color.clear)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - ComparisonSummaryBanner
// ─────────────────────────────────────────────────────────────────────────────

private struct ComparisonSummaryBanner: View {
    let result: ComparisonResult

    var body: some View {
        VStack(spacing: 14) {

            // Arquivos comparados
            HStack(spacing: 8) {
                Label(result.userFileName, systemImage: "mic.fill")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.orange)
                    .lineLimit(1)

                Image(systemName: "arrow.right")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                Label(result.referenceFileName, systemImage: "star.fill")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.blue)
                    .lineLimit(1)
            }

            Divider()

            // Métricas
            HStack(spacing: 0) {
                SummaryMetric(value: "\(result.totalPairs)", label: "PARES")
                divider
                SummaryMetric(
                    value: String(format: "%.1f¢", result.averageCentsDelta),
                    label: "DESVIO MÉD."
                )
                divider
                SummaryMetric(
                    value: String(format: "%+.0f%%", result.averageStabilityDelta),
                    label: "ESTAB. Δ"
                )
                divider
                SummaryMetric(value: "\(result.excellentCount)", label: "EXCELENTE")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Color(.separator).opacity(0.5))
            .frame(width: 0.5)
            .padding(.vertical, 6)
    }
}

private struct SummaryMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .light, design: .rounded))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - NoteComparisonCard
// ─────────────────────────────────────────────────────────────────────────────

/// Card completo de comparação para uma nota (usuário vs referência).
struct NoteComparisonCard: View {

    let comparison: NoteComparison
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Cabeçalho (sempre visível) ────────────────────────────────────
            Button {
                withAnimation(.spring(duration: 0.3)) { expanded.toggle() }
            } label: {
                HStack(spacing: 14) {

                    // Número da nota
                    Text("\(comparison.index + 1)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .frame(width: 20, alignment: .trailing)

                    // Nome da nota
                    Text(comparison.noteName)
                        .font(.system(size: 22, weight: .light, design: .rounded))
                        .foregroundStyle(.primary)
                        .frame(width: 44, alignment: .leading)

                    // Métricas compactas
                    VStack(alignment: .leading, spacing: 2) {
                        if let cents = comparison.centsDelta {
                            Text(String(format: "%+.1f¢", cents))
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(abs(cents) < 10 ? .green : .primary)
                        }
                        if let stab = comparison.stabilityDelta {
                            Text(String(format: "%+.0f%%", stab))
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    // Grade badge
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

                    // Chevron
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            // ── Detalhe expandido ─────────────────────────────────────────────
            if expanded {
                VStack(spacing: 16) {

                    Divider().padding(.horizontal, 16)

                    // Métricas lado a lado: você vs referência
                    ComparisonMetricsGrid(comparison: comparison)
                        .padding(.horizontal, 16)

                    // Gráfico de curvas sobrepostas
                    OverlappedPitchCurveView(comparison: comparison)
                        .padding(.horizontal, 16)

                    // Vibrato comparado
                    if comparison.userSegment?.vibrato != nil || comparison.referenceSegment?.vibrato != nil {
                        VibratoComparisonRow(comparison: comparison)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - ComparisonMetricsGrid
// ─────────────────────────────────────────────────────────────────────────────

private struct ComparisonMetricsGrid: View {
    let comparison: NoteComparison

    var body: some View {
        VStack(spacing: 10) {
            // Linha 1: Desvio médio
            metricRow(
                label: "Desvio médio",
                userValue: comparison.userSegment.map { String(format: "%.1f¢", $0.averageCentsDeviation) } ?? "—",
                refValue:  comparison.referenceSegment.map { String(format: "%.1f¢", $0.averageCentsDeviation) } ?? "—",
                delta: comparison.centsDelta.map { String(format: "%+.1f¢", $0) }
            )
            // Linha 2: Estabilidade
            metricRow(
                label: "Afinado",
                userValue: comparison.userSegment.map { String(format: "%.0f%%", $0.stabilityPercentage) } ?? "—",
                refValue:  comparison.referenceSegment.map { String(format: "%.0f%%", $0.stabilityPercentage) } ?? "—",
                delta: comparison.stabilityDelta.map { String(format: "%+.0f%%", $0) }
            )
            // Linha 3: Duração
            metricRow(
                label: "Duração",
                userValue: comparison.userSegment.map { String(format: "%.2fs", $0.durationSeconds) } ?? "—",
                refValue:  comparison.referenceSegment.map { String(format: "%.2fs", $0.durationSeconds) } ?? "—",
                delta: nil
            )
        }
    }

    private func metricRow(label: String, userValue: String, refValue: String, delta: String?) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            Spacer()

            // Coluna Ref
            VStack(spacing: 1) {
                Text("REF")
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.blue.opacity(0.7))
                Text(refValue)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.blue)
            }
            .frame(width: 56)

            // Coluna Você
            VStack(spacing: 1) {
                Text("VOCÊ")
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.orange.opacity(0.7))
                Text(userValue)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.orange)
            }
            .frame(width: 56)

            // Delta
            if let d = delta {
                Text(d)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(deltaColor(d))
                    .frame(width: 52, alignment: .trailing)
            }
        }
    }

    private func deltaColor(_ delta: String) -> Color {
        if delta.hasPrefix("+") { return .green }
        if delta.hasPrefix("-") { return .red }
        return .secondary
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - VibratoComparisonRow
// ─────────────────────────────────────────────────────────────────────────────

private struct VibratoComparisonRow: View {
    let comparison: NoteComparison

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            Text("VIBRATO")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(2)
                .foregroundStyle(.tertiary)

            HStack(spacing: 12) {
                vibratoCell(
                    label: "REF",
                    vibrato: comparison.referenceSegment?.vibrato,
                    color: .blue
                )
                vibratoCell(
                    label: "VOCÊ",
                    vibrato: comparison.userSegment?.vibrato,
                    color: .orange
                )
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
                    vibratoStat("TAXA",    value: String(format: "%.1fHz", v.rateHz))
                    vibratoStat("PROF.",   value: String(format: "%.0f¢",  v.depthCents))
                    vibratoStat("REG.",    value: String(format: "%.0f%%", v.regularity * 100))
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
