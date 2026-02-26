// VoiceComparisonView.swift
// PitchMVP
//
// ATUALIZADO (cross-gender):
// 1. CrossGenderBanner inserido no topo dos resultados — aparece somente quando detectado
// 2. CrossGenderSummaryRow no ComparisonSummaryBanner — exibe registros vocais detectados
// 3. OctaveShiftTag no NoteComparisonCard — indica diferença de oitava por nota
// 4. Nenhuma funcionalidade anterior foi removida

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
        .task { await vm.loadRemoteFiles() }
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
            if vm.state == .done {
                Button { withAnimation { vm.reset() } } label: {
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

    // MARK: - Seleção

    private var selectionContent: some View {
        VStack(spacing: 0) {
            SelectionStatusBar(
                userFile: vm.userDisplayName,
                refFile:  vm.refDisplayName,
                userSelected: vm.userSource != nil,
                refSelected:  vm.referenceSource != nil
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 20)

            VoiceTabPicker(activeTab: $vm.activeTab)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

            if vm.activeTab == 0 {
                RemoteFilePickerView(
                    title: "Selecione sua voz",
                    accentColor: .orange,
                    remoteFiles: vm.performanceFiles,
                    bundleFiles: vm.bundleFiles,
                    selectedSource: vm.userSource,
                    isLoadingRemote: vm.isLoadingFiles,
                    remoteError: vm.remoteLoadError,
                    onSelectRemote:   { vm.selectUser(remote: $0) },
                    onSelectBundle:   { vm.selectUserFromBundle($0) },
                    onImportExternal: { showUserPicker = true },
                    onRefreshRemote:  { Task { await vm.loadRemoteFiles() } }
                )
            } else {
                RemoteFilePickerView(
                    title: "Selecione a referência",
                    accentColor: .blue,
                    remoteFiles: vm.referenceFiles,
                    bundleFiles: vm.bundleFiles,
                    selectedSource: vm.referenceSource,
                    isLoadingRemote: vm.isLoadingFiles,
                    remoteError: vm.remoteLoadError,
                    onSelectRemote:   { vm.selectReference(remote: $0) },
                    onSelectBundle:   { vm.selectReferenceFromBundle($0) },
                    onImportExternal: { showRefPicker = true },
                    onRefreshRemote:  { Task { await vm.loadRemoteFiles() } }
                )
            }

            Spacer()
            compareButton.padding(.horizontal, 20).padding(.bottom, 32)
        }
    }

    private var compareButton: some View {
        Button { vm.startComparison() } label: {
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

    // MARK: - Analisando

    private var analyzingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView().scaleEffect(1.5).tint(.secondary)
            Text(vm.state.stepMessage)
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(.secondary)
                .animation(.easeOut, value: vm.state.stepMessage)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Resultado (ATUALIZADO: CrossGenderBanner + CrossGenderSummaryRow)

    private func resultContent(result: ComparisonResult) -> some View {
        ScrollView {
            VStack(spacing: 16) {

                // ── NOVO: Banner cross-gender (aparece somente quando detectado) ──
                CrossGenderBanner(context: vm.crossGenderContext)
                    .padding(.horizontal, 20)
                    .transition(.opacity.combined(with: .move(edge: .top)))

                // ── Summary banner com row de registros vocais ─────────────────
                ComparisonSummaryBanner(
                    result: result,
                    crossGenderContext: vm.crossGenderContext  // ← NOVO parâmetro
                )
                .padding(.horizontal, 20)

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

    // MARK: - Estados extras

    private var emptyResult: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "waveform.slash")
                .font(.system(size: 40, weight: .thin)).foregroundStyle(.tertiary)
            Text("Nenhuma nota detectada")
                .font(.system(size: 15, design: .rounded)).foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36, weight: .thin)).foregroundStyle(.orange)
            Text("Erro na análise")
                .font(.system(size: 15, weight: .medium, design: .rounded))
            Text(msg)
                .font(.system(size: 12, design: .rounded)).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
            Spacer()
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SelectionStatusBar (inalterado)
// ─────────────────────────────────────────────────────────────────────────────

private struct SelectionStatusBar: View {
    let userFile: String; let refFile: String
    let userSelected: Bool; let refSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            statusChip(icon: "mic",  label: "Minha voz",  file: userFile, isSelected: userSelected, color: .orange)
            Image(systemName: "arrow.right").font(.system(size: 11)).foregroundStyle(.tertiary)
            statusChip(icon: "star", label: "Referência", file: refFile,  isSelected: refSelected,  color: .blue)
        }
    }

    private func statusChip(icon: String, label: String, file: String, isSelected: Bool, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? color : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 9, weight: .semibold, design: .rounded)).tracking(1).foregroundStyle(.tertiary)
                Text(isSelected ? file : "—")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(isSelected ? .primary : .tertiary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(isSelected ? color.opacity(0.08) : Color(.secondarySystemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isSelected ? color.opacity(0.25) : Color.clear, lineWidth: 1))
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - VoiceTabPicker (inalterado)
// ─────────────────────────────────────────────────────────────────────────────

private struct VoiceTabPicker: View {
    @Binding var activeTab: Int

    var body: some View {
        HStack(spacing: 0) {
            tabButton(title: "Minha Voz",  icon: "mic.fill",  index: 0, color: .orange)
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
                Image(systemName: icon).font(.system(size: 12))
                Text(title).font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 10).fill(isActive ? color.opacity(0.12) : Color.clear))
            .foregroundStyle(isActive ? color : Color.secondary)
        }
        .padding(3)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - ComparisonSummaryBanner (ATUALIZADO: crossGenderContext + CrossGenderSummaryRow)
// ─────────────────────────────────────────────────────────────────────────────

private struct ComparisonSummaryBanner: View {
    let result: ComparisonResult
    let crossGenderContext: CrossGenderContext?  // ← NOVO

    var body: some View {
        VStack(spacing: 0) {

            // ── Cabeçalho: nomes dos arquivos ────────────────────────────────
            HStack(spacing: 8) {
                Label(result.userFileName, systemImage: "mic.fill")
                    .font(.system(size: 12, design: .rounded)).foregroundStyle(.orange).lineLimit(1)
                Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(.tertiary)
                Label(result.referenceFileName, systemImage: "star.fill")
                    .font(.system(size: 12, design: .rounded)).foregroundStyle(.blue).lineLimit(1)
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 10)

            // ── NOVO: Row de registros vocais (somente cross-gender) ──────────
            CrossGenderSummaryRow(context: crossGenderContext)

            hdivider

            // ── Seção 1: Grades ──────────────────────────────────────────────
            sectionLabel("AVALIAÇÃO POR NOTA")

            HStack(spacing: 0) {
                SummaryMetric(value: "\(result.excellentCount)", label: "EXCELENTE", valueColor: .green)
                vdivider
                SummaryMetric(value: "\(result.goodCount)",      label: "BOM",       valueColor: .blue)
                vdivider
                SummaryMetric(value: "\(result.fairCount)",      label: "REGULAR",   valueColor: .orange)
                vdivider
                SummaryMetric(value: "\(result.needsWorkCount)", label: "MELHORAR",  valueColor: .red)
                vdivider
                SummaryMetric(value: "\(result.incompleteCount)",label: "INCOMPLETO",valueColor: Color(.tertiaryLabel))
            }
            .padding(.vertical, 12)

            hdivider

            // ── Seção 2: Faixas de desvio ────────────────────────────────────
            sectionLabel("DESVIO MÉD. DO USUÁRIO — FAIXAS")

            HStack(spacing: 0) {
                SummaryMetric(
                    value: "\(result.inTuneCount)",
                    label: "< 10¢  AFINADO",
                    valueColor: .green
                )
                vdivider
                SummaryMetric(
                    value: "\(result.nearTuneCount)",
                    label: "10–30¢  ATENÇÃO",
                    valueColor: .orange
                )
                vdivider
                SummaryMetric(
                    value: "\(result.outOfTuneCount)",
                    label: "> 30¢  FORA",
                    valueColor: .red
                )
                vdivider
                SummaryMetric(
                    value: String(format: "%.1f¢", result.userAverageIntonation),
                    label: "MÉDIA GERAL",
                    valueColor: result.userAverageIntonation < 15 ? .green : .orange
                )
            }
            .padding(.vertical, 10)

            // ── Seção 2b: Direção do desvio (agudo vs grave) ─────────────────
            sectionLabel("DESVIO MÉD. DO USUÁRIO — DIREÇÃO")

            HStack(spacing: 0) {
                SummaryMetric(
                    value: "\(result.sharpCount)",
                    label: "AGUDO  ↑",
                    valueColor: .purple
                )
                vdivider
                SummaryMetric(
                    value: "\(result.flatCount)",
                    label: "GRAVE  ↓",
                    valueColor: .indigo
                )
                vdivider
                SummaryMetric(
                    value: "\(result.centeredCount)",
                    label: "CENTRADO  ·",
                    valueColor: .green
                )
            }
            .padding(.vertical, 10)

            hdivider

            // ── Seção 3: Métricas gerais ─────────────────────────────────────
            sectionLabel("RESUMO")

            HStack(spacing: 0) {
                SummaryMetric(value: "\(result.totalPairs)", label: "PARES")
                vdivider
                SummaryMetric(
                    value: String(format: "%.0f%%", result.pitchClassMatchScore),
                    label: "GRAU CERTO",
                    valueColor: scoreColor(result.pitchClassMatchScore)
                )
                vdivider
                SummaryMetric(
                    value: String(format: "%.0f%%", result.melodicContourScore),
                    label: "CONTORNO",
                    valueColor: scoreColor(result.melodicContourScore)
                )
                vdivider
                SummaryMetric(
                    value: "\(result.overallScore)",
                    label: "SCORE",
                    valueColor: scoreColor(Float(result.overallScore))
                )
            }
            .padding(.vertical, 12)

            // ── Nota de rodapé (adaptada para cross-gender) ───────────────────
            HStack(spacing: 4) {
                Image(systemName: "info.circle").font(.system(size: 9))
                Text("Desvio medido individualmente por voz — oitavas diferentes são normais")
                    .font(.system(size: 10, design: .rounded))
            }
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 16).padding(.bottom, 14)
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
    }

    // MARK: Helpers (inalterados)

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .tracking(1.5)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
    }

    private var hdivider: some View {
        Divider().padding(.horizontal, 16)
    }

    private var vdivider: some View {
        Rectangle()
            .fill(Color(.separator).opacity(0.5))
            .frame(width: 0.5)
            .padding(.vertical, 6)
    }

    private func scoreColor(_ score: Float) -> Color {
        switch score {
        case 80...: return .green
        case 60...: return .blue
        case 40...: return .orange
        default:    return .red
        }
    }
}

private struct SummaryMetric: View {
    let value: String
    let label: String
    var valueColor: Color = .primary

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 17, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(valueColor)
            Text(label)
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .tracking(1.5).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - NoteComparisonCard (ATUALIZADO: OctaveShiftTag)
// ─────────────────────────────────────────────────────────────────────────────

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
            Button {
                withAnimation(.spring(duration: 0.3)) { expanded.toggle() }
            } label: {
                HStack(spacing: 14) {
                    Text("\(comparison.index + 1)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.tertiary).frame(width: 20, alignment: .trailing)

                    // Nome da nota + grau + OctaveShiftTag (NOVO)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(comparison.noteName)
                            .font(.system(size: 20, weight: .light, design: .rounded))

                        // Indicador se cantou no grau certo (ignora oitava)
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
                            }
                            .foregroundStyle(comparison.pitchClassMatch ? Color.green : Color.red)
                        }

                        // ── NOVO: Tag de diferença de oitava ─────────────────
                        OctaveShiftTag(
                            userNote: comparison.userSegment,
                            referenceNote: comparison.referenceSegment
                        )
                    }
                    .frame(width: 100, alignment: .leading)

                    VStack(alignment: .leading, spacing: 2) {
                        if let cents = comparison.centsDelta {
                            Text(String(format: "%+.1f¢", cents))
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(abs(cents) < 10 ? .green : .primary)
                        }
                        // Contorno melódico
                        if let match = comparison.melodicContourMatch {
                            HStack(spacing: 3) {
                                contourIcon(comparison.userContourDirection, color: .orange)
                                contourIcon(comparison.referenceContourDirection, color: .blue)
                                Text(match ? "✓" : "✗")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundStyle(match ? Color.green : Color.red)
                            }
                        }
                    }

                    Spacer()

                    // Timestamp
                    VStack(spacing: 1) {
                        Image(systemName: "clock")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                        Text(comparison.startTimeFormatted)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    HStack(spacing: 4) {
                        Image(systemName: comparison.grade.systemImage).font(.system(size: 12))
                        Text(comparison.grade.label).font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(gradeColor)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(gradeColor.opacity(0.1))
                    .clipShape(Capsule())

                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(spacing: 16) {
                    Divider().padding(.horizontal, 16)
                    ComparisonMetricsGrid(comparison: comparison).padding(.horizontal, 16)
                    OverlappedPitchCurveView(comparison: comparison).padding(.horizontal, 16)

                    if comparison.userSegment?.vibrato != nil || comparison.referenceSegment?.vibrato != nil {
                        VibratoComparisonRow(comparison: comparison).padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
    }

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
// MARK: - ComparisonMetricsGrid (inalterado)
// ─────────────────────────────────────────────────────────────────────────────

private struct ComparisonMetricsGrid: View {
    let comparison: NoteComparison

    var body: some View {
        VStack(spacing: 10) {

            if let u = comparison.userSegment,
               let r = comparison.referenceSegment,
               abs(u.midiNote - r.midiNote) > 6 {
                HStack(spacing: 6) {
                    Image(systemName: "person.2.fill").font(.system(size: 10)).foregroundStyle(.secondary)
                    Text("Vozes em oitavas diferentes — desvio medido individualmente")
                        .font(.system(size: 10, design: .rounded)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color(.tertiarySystemFill).opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            metricRow(
                label: "Afinação",
                userValue:  comparison.userSegment.map      { String(format: "%.1f¢", $0.averageCentsDeviation) } ?? "—",
                refValue:   comparison.referenceSegment.map { String(format: "%.1f¢", $0.averageCentsDeviation) } ?? "—",
                delta:      comparison.centsDelta.map       { String(format: "%+.1f¢", $0) },
                deltaNote:  "Δ desvio"
            )

            metricRow(
                label: "Estável",
                userValue:  comparison.userSegment.map      { String(format: "%.0f%%", $0.stabilityPercentage) } ?? "—",
                refValue:   comparison.referenceSegment.map { String(format: "%.0f%%", $0.stabilityPercentage) } ?? "—",
                delta:      comparison.stabilityDelta.map   { String(format: "%+.0f%%", $0) },
                deltaNote:  "Δ estab."
            )

            metricRow(
                label: "Duração",
                userValue:  comparison.userSegment.map      { String(format: "%.2fs", $0.durationSeconds) } ?? "—",
                refValue:   comparison.referenceSegment.map { String(format: "%.2fs", $0.durationSeconds) } ?? "—",
                delta:      nil,
                deltaNote:  nil
            )

            if let u = comparison.userSegment, let r = comparison.referenceSegment {
                HStack {
                    Text("Nota")
                        .font(.system(size: 12, design: .rounded)).foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .leading)
                    Spacer()
                    VStack(spacing: 1) {
                        Text("REF").font(.system(size: 8, weight: .semibold, design: .rounded)).tracking(1).foregroundStyle(.blue.opacity(0.7))
                        Text(r.noteName).font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(.blue)
                    }
                    .frame(width: 56)
                    VStack(spacing: 1) {
                        Text("VOCÊ").font(.system(size: 8, weight: .semibold, design: .rounded)).tracking(1).foregroundStyle(.orange.opacity(0.7))
                        Text(u.noteName).font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(.orange)
                    }
                    .frame(width: 56)

                    Image(systemName: comparison.pitchClassMatch ? "checkmark.circle.fill" : "xmark.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(comparison.pitchClassMatch ? Color.green : Color.red)
                        .frame(width: 52, alignment: .trailing)
                }
            }
        }
    }

    private func metricRow(
        label: String,
        userValue: String,
        refValue: String,
        delta: String?,
        deltaNote: String?
    ) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, design: .rounded)).foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Spacer()
            VStack(spacing: 1) {
                Text("REF").font(.system(size: 8, weight: .semibold, design: .rounded)).tracking(1).foregroundStyle(.blue.opacity(0.7))
                Text(refValue).font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(.blue)
            }
            .frame(width: 56)
            VStack(spacing: 1) {
                Text("VOCÊ").font(.system(size: 8, weight: .semibold, design: .rounded)).tracking(1).foregroundStyle(.orange.opacity(0.7))
                Text(userValue).font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(.orange)
            }
            .frame(width: 56)
            if let d = delta {
                Text(d)
                    .font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(d.hasPrefix("+") ? Color.green : Color.red)
                    .frame(width: 52, alignment: .trailing)
            } else {
                Spacer().frame(width: 52)
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - VibratoComparisonRow (inalterado)
// ─────────────────────────────────────────────────────────────────────────────

private struct VibratoComparisonRow: View {
    let comparison: NoteComparison

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("VIBRATO")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(2).foregroundStyle(.tertiary)

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
                .tracking(1.5).foregroundStyle(color.opacity(0.7))
            if let v = vibrato {
                HStack(spacing: 12) {
                    vibratoStat("TAXA",  value: String(format: "%.1fHz", v.rateHz))
                    vibratoStat("PROF.", value: String(format: "%.0f¢",  v.depthCents))
                    vibratoStat("REG.",  value: String(format: "%.0f%%", v.regularity * 100))
                }
                Text(v.quality.rawValue).font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(color)
            } else {
                Text("Não detectado").font(.system(size: 12, design: .rounded)).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func vibratoStat(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 8, design: .rounded)).foregroundStyle(.quaternary)
            Text(value).font(.system(size: 12, weight: .medium, design: .rounded))
        }
    }
}