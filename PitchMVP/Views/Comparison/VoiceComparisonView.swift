// VoiceComparisonView.swift
// PitchMVP
//
// FIX v6 — Security-scoped URL gerenciada pelo ViewModel:
//
// ANTES:
//   O fileImporter chamava startAccessing → selectExternal → stopAccessing
//   na mesma closure. O stop era prematuro — quando startComparison() rodava
//   depois, a URL já estava inacessível (erro silencioso de leitura de arquivo).
//
// AGORA:
//   A View apenas repassa a URL para o ViewModel via selectUserExternal /
//   selectReferenceExternal. O ViewModel é responsável por iniciar, manter
//   e encerrar o acesso security-scoped no momento correto (após loadSamples).

import SwiftUI
import UniformTypeIdentifiers

struct VoiceComparisonView: View {

    @Environment(\.dismiss) private var dismiss

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
                    case .idle:        selectionContent
                    case .analyzing:   analyzingView
                    case .done:
                        if let result = vm.result { resultContent(result: result) }
                    case .empty:       emptyResult
                    case .error(let msg): errorView(msg)
                    }
                }
            }
            .navigationBarHidden(true)
        }
        // FIX: a closure do fileImporter apenas repassa a URL ao ViewModel.
        // Não chama mais start/stop — o ViewModel gerencia o acesso completo.
        .fileImporter(isPresented: $showUserPicker,
                      allowedContentTypes: [UTType.audio, .wav, .mp3],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                vm.selectUserExternal(url: url)
            }
        }
        .fileImporter(isPresented: $showRefPicker,
                      allowedContentTypes: [UTType.audio, .wav, .mp3],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                vm.selectReferenceExternal(url: url)
            }
        }
        .task { await vm.loadRemoteFiles() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .bottom) {

            // Botão de voltar — sempre visível, limpa seleção antes de sair
            Button {
                vm.clearSelection()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("COMPARAÇÃO")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .tracking(3).foregroundStyle(.secondary)
                Text("Vocal")
                    .font(.system(size: 28, weight: .thin, design: .rounded))
            }
            .padding(.leading, 4)

            Spacer()

            if vm.state == .done {
                // Resultado visível → volta para seleção mantendo arquivos/hints
                Button { withAnimation { vm.reset() } } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Circle())
                }
            } else if vm.state == .idle,
                      vm.userSource != nil || vm.referenceSource != nil {
                // Seleção em andamento → limpa tudo e reinicia do zero
                Button { withAnimation { vm.clearSelection() } } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Circle())
                }
                .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 16)
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
            .padding(.bottom, 16)

            VoiceRegistryCard(
                userHint: $vm.userVoiceHint,
                referenceHint: $vm.referenceVoiceHint
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

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
                    onRefreshRemote:  {
                        vm.clearSelection()
                        Task { await vm.loadRemoteFiles() }
                    }
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
                    onRefreshRemote:  {
                        vm.clearSelection()
                        Task { await vm.loadRemoteFiles() }
                    }
                )
            }

            Spacer()
            compareButton
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
        }
    }

    private var compareButton: some View {
        VStack(spacing: 8) {
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

            if let reason = vm.compareBlockReason {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 10, weight: .semibold))
                    Text(reason)
                        .font(.system(size: 12, design: .rounded))
                }
                .foregroundStyle(.orange)
                .transition(.opacity)
                .animation(.easeOut, value: reason)
            }
        }
    }

    // MARK: - Analisando

    private var analyzingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView().scaleEffect(1.5).tint(.secondary)
            Text(vm.state.stepMessage)
                .font(.system(size: 14, design: .rounded)).foregroundStyle(.secondary)
                .animation(.easeOut, value: vm.state.stepMessage)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Resultado

    private func resultContent(result: ComparisonResult) -> some View {
        ScrollView {
            VStack(spacing: 16) {

                CrossGenderBanner(context: vm.crossGenderContext)
                    .padding(.horizontal, 20)

                ComparisonSummaryBanner(
                    result: result,
                    crossGenderContext: vm.crossGenderContext
                )
                .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 10) {
                    Text("NOTA A NOTA")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(2).foregroundStyle(.tertiary)
                        .padding(.horizontal, 20)

                    ForEach(result.comparisons) { comparison in
                        NoteComparisonCard(
                            comparison: comparison,
                            crossGenderContext: vm.crossGenderContext
                        )
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
// MARK: - SelectionStatusBar
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
                Text(label).font(.system(size: 9, weight: .semibold, design: .rounded)).tracking(1).foregroundStyle(.tertiary)
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
// MARK: - VoiceTabPicker
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
// MARK: - ComparisonSummaryBanner
// ─────────────────────────────────────────────────────────────────────────────

private struct ComparisonSummaryBanner: View {
    let result: ComparisonResult
    let crossGenderContext: CrossGenderContext?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label(result.userFileName, systemImage: "mic.fill")
                    .font(.system(size: 12, design: .rounded)).foregroundStyle(.orange).lineLimit(1)
                Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(.tertiary)
                Label(result.referenceFileName, systemImage: "star.fill")
                    .font(.system(size: 12, design: .rounded)).foregroundStyle(.blue).lineLimit(1)
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 10)

            CrossGenderSummaryRow(context: crossGenderContext)

            hdivider

            sectionLabel("AVALIAÇÃO POR NOTA")
            HStack(spacing: 0) {
                SummaryMetric(value: "\(result.excellentCount)",  label: "EXCELENTE",  valueColor: .green)
                vdivider
                SummaryMetric(value: "\(result.goodCount)",       label: "BOM",        valueColor: .blue)
                vdivider
                SummaryMetric(value: "\(result.fairCount)",       label: "REGULAR",    valueColor: .orange)
                vdivider
                SummaryMetric(value: "\(result.needsWorkCount)",  label: "MELHORAR",   valueColor: .red)
                vdivider
                SummaryMetric(value: "\(result.incompleteCount)", label: "INCOMPLETO", valueColor: Color(.tertiaryLabel))
            }
            .padding(.vertical, 12)

            hdivider

            sectionLabel("DESVIO MÉD. DO USUÁRIO — FAIXAS")
            HStack(spacing: 0) {
                SummaryMetric(value: "\(result.inTuneCount)",    label: "< 10¢  AFINADO",  valueColor: .green)
                vdivider
                SummaryMetric(value: "\(result.nearTuneCount)",  label: "10–30¢  ATENÇÃO",  valueColor: .orange)
                vdivider
                SummaryMetric(value: "\(result.outOfTuneCount)", label: "> 30¢  FORA",      valueColor: .red)
                vdivider
                SummaryMetric(
                    value: String(format: "%.1f¢", result.userAverageIntonation),
                    label: "MÉDIA GERAL",
                    valueColor: result.userAverageIntonation < 15 ? .green : .orange
                )
            }
            .padding(.vertical, 10)

            sectionLabel("DESVIO MÉD. DO USUÁRIO — DIREÇÃO")
            HStack(spacing: 0) {
                SummaryMetric(value: "\(result.sharpCount)",    label: "AGUDO  ↑",    valueColor: .purple)
                vdivider
                SummaryMetric(value: "\(result.flatCount)",     label: "GRAVE  ↓",    valueColor: .indigo)
                vdivider
                SummaryMetric(value: "\(result.centeredCount)", label: "CENTRADO  ·", valueColor: .green)
            }
            .padding(.vertical, 10)

            hdivider

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

            HStack(spacing: 4) {
                Image(systemName: "info.circle").font(.system(size: 9))
                if let ctx = crossGenderContext, ctx.isCrossGender {
                    Text("Desvio medido individualmente — oitavas diferentes são normais")
                        .font(.system(size: 10, design: .rounded))
                } else {
                    Text("Desvio medido individualmente por voz em relação à nota alvo")
                        .font(.system(size: 10, design: .rounded))
                }
            }
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 16).padding(.bottom, 14)
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .tracking(1.5).foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.bottom, 4)
    }
    private var hdivider: some View { Divider().padding(.horizontal, 16) }
    private var vdivider: some View {
        Rectangle().fill(Color(.separator).opacity(0.5)).frame(width: 0.5).padding(.vertical, 6)
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
    let value: String; let label: String; var valueColor: Color = .primary
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 17, weight: .light, design: .rounded)).monospacedDigit().foregroundStyle(valueColor)
            Text(label).font(.system(size: 8, weight: .semibold, design: .rounded)).tracking(1.5).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    VoiceComparisonView()
}