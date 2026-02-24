//
//  SegmentAnalysisView.swift
//  PitchMVP
//
//  Created by victor on 24/02/26.
//

// SegmentAnalysisView.swift
// PitchMVP
//
// Tela de análise segmentada por notas.
// Fluxo: botão importar WAV → análise → lista de segmentos → detalhe por nota

import SwiftUI
import UniformTypeIdentifiers

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SegmentAnalysisView (Root)
// ─────────────────────────────────────────────────────────────────────────────

struct SegmentAnalysisView: View {

    @StateObject private var vm = SegmentAnalysisViewModel()
    @State private var showFilePicker = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                    content
                }
            }
            .navigationBarHidden(true)
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [UTType.audio, .wav, .mp3],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                // Obtém acesso ao Security-Scoped Resource
                let accessing = url.startAccessingSecurityScopedResource()
                vm.analyze(url: url)
                if accessing { url.stopAccessingSecurityScopedResource() }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ANÁLISE")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(.secondary)
                Text("Por Notas")
                    .font(.system(size: 28, weight: .thin, design: .rounded))
            }

            Spacer()

            Button {
                showFilePicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 13, weight: .medium))
                    Text("Importar")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color.primary)
                .foregroundStyle(Color(.systemBackground))
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    // MARK: - Content Router

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .idle:
            idleState

        case .loading(let progress):
            loadingState(progress: progress)

        case .done:
            if let selected = vm.selectedSegment {
                analyzedContent(selected: selected)
            }

        case .empty:
            emptyResultState

        case .error(let msg):
            errorState(message: msg)
        }
    }

    // ── Estados de UI ─────────────────────────────────────────────────────────

    private var idleState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "music.note.list")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(.tertiary)
            Text("Importe um arquivo WAV")
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(.secondary)
            Text("O app detecta e analisa\ncada nota automaticamente")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func loadingState(progress: Double) -> some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .scaleEffect(1.4)
                .tint(.secondary)
            Text("Analisando notas...")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyResultState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "waveform.slash")
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(.tertiary)
            Text("Nenhuma nota detectada")
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(.secondary)
            Text("Verifique se o arquivo contém\nvoz ou instrumento melódico")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36, weight: .thin))
                .foregroundStyle(.orange)
            Text("Erro ao processar")
                .font(.system(size: 15, weight: .medium, design: .rounded))
            Text(message)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    // ── Layout principal após análise ─────────────────────────────────────────

    private func analyzedContent(selected: NoteSegment) -> some View {
        VStack(spacing: 0) {

            // Resumo geral
            if let summary = vm.summary {
                SummaryBannerView(summary: summary)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }

            // Scroll list de segmentos + detalhe
            ScrollView {
                VStack(spacing: 12) {

                    // Detalhe do segmento selecionado
                    SegmentDetailCard(segment: selected)
                        .padding(.horizontal, 20)

                    // Timeline de segmentos detectados
                    VStack(alignment: .leading, spacing: 10) {
                        Text("NOTAS DETECTADAS")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .tracking(2)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 20)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(vm.segments) { segment in
                                    SegmentPill(
                                        segment: segment,
                                        isSelected: segment.id == selected.id
                                    )
                                    .onTapGesture { vm.select(segment) }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.top, 8)

                    Spacer(minLength: 40)
                }
                .padding(.top, 4)
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SummaryBannerView
// ─────────────────────────────────────────────────────────────────────────────

private struct SummaryBannerView: View {
    let summary: SegmentSummary

    var body: some View {
        HStack(spacing: 0) {
            BannerCell(
                value: "\(summary.totalNotes)",
                label: "NOTAS"
            )
            divider
            BannerCell(
                value: String(format: "%.0f%%", summary.averageStability),
                label: "ESTAB."
            )
            divider
            BannerCell(
                value: String(format: "%.1f¢", summary.averageCentsDeviation),
                label: "DESVIO"
            )
            divider
            BannerCell(
                value: "\(summary.vibratoCount)",
                label: "VIBRATO"
            )
        }
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Color(.separator).opacity(0.5))
            .frame(width: 0.5)
            .padding(.vertical, 8)
    }
}

private struct BannerCell: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .light, design: .rounded))
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
// MARK: - SegmentDetailCard
// ─────────────────────────────────────────────────────────────────────────────

/// Card expandido com análise completa do segmento selecionado.
struct SegmentDetailCard: View {

    let segment: NoteSegment

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            // ── Nota + duração ────────────────────────────────────────────────
            HStack(alignment: .firstTextBaseline) {
                Text(segment.noteName)
                    .font(.system(size: 56, weight: .thin, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.2f Hz", segment.medianFrequency))
                        .font(.system(size: 15, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.2fs", segment.durationSeconds))
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }

            Divider()

            // ── Métricas de estabilidade ──────────────────────────────────────
            HStack(spacing: 0) {
                DetailMetric(
                    icon: "scope",
                    label: "AFINADO",
                    value: String(format: "%.0f%%", segment.stabilityPercentage),
                    color: stabilityColor
                )
                Spacer()
                DetailMetric(
                    icon: "plusminus",
                    label: "DESVIO MÉD.",
                    value: String(format: "%.1f¢", segment.averageCentsDeviation),
                    color: .secondary
                )
                Spacer()
                DetailMetric(
                    icon: "arrow.up.and.down",
                    label: "DESVIO MÁX.",
                    value: String(format: "%.1f¢", segment.maxCentsDeviation),
                    color: .secondary
                )
            }

            // ── Gráfico de curva de pitch ─────────────────────────────────────
            PitchCurveView(segment: segment)

            // ── Análise de vibrato ────────────────────────────────────────────
            VibratoCard(vibrato: segment.vibrato)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var stabilityColor: Color {
        switch segment.stabilityPercentage {
        case 80...: return .green
        case 60..<80: return .orange
        default: return .red
        }
    }
}

private struct DetailMetric: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color.opacity(0.8))
            Text(value)
                .font(.system(size: 22, weight: .light, design: .rounded))
                .foregroundStyle(color == .secondary ? Color.primary : color)
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(.tertiary)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - VibratoCard
// ─────────────────────────────────────────────────────────────────────────────

private struct VibratoCard: View {
    let vibrato: VibratoAnalysis?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            HStack {
                Label {
                    Text("VIBRATO")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(.tertiary)
                } icon: {
                    Image(systemName: "waveform")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if let v = vibrato {
                    Text(v.quality.rawValue)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(qualityBg(v.quality))
                        .foregroundStyle(qualityFg(v.quality))
                        .clipShape(Capsule())
                } else {
                    Text("Não detectado")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }

            if let v = vibrato {
                HStack(spacing: 0) {
                    VibratoMetric(label: "TAXA", value: String(format: "%.1f Hz", v.rateHz))
                    Spacer()
                    VibratoMetric(label: "PROFUND.", value: String(format: "%.0f¢", v.depthCents))
                    Spacer()
                    VibratoMetric(label: "REGULAR.", value: String(format: "%.0f%%", v.regularity * 100))
                }

                // Barra de regularidade
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(.tertiarySystemFill))
                            .frame(height: 4)
                        Capsule()
                            .fill(qualityFg(v.quality))
                            .frame(width: geo.size.width * CGFloat(v.regularity), height: 4)
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.tertiarySystemFill).opacity(0.5))
        )
    }

    private func qualityBg(_ q: VibratoQuality) -> Color {
        switch q {
        case .excellent: return .green.opacity(0.15)
        case .irregular: return .orange.opacity(0.15)
        case .offRate:   return .red.opacity(0.12)
        case .shallow:   return .blue.opacity(0.12)
        case .none:      return Color(.tertiarySystemFill)
        }
    }

    private func qualityFg(_ q: VibratoQuality) -> Color {
        switch q {
        case .excellent: return .green
        case .irregular: return .orange
        case .offRate:   return .red
        case .shallow:   return .blue
        case .none:      return .secondary
        }
    }
}

private struct VibratoMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(.quaternary)
            Text(value)
                .font(.system(size: 15, weight: .medium, design: .rounded))
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SegmentPill
// ─────────────────────────────────────────────────────────────────────────────

/// Pílula clicável que representa um segmento na timeline horizontal.
private struct SegmentPill: View {

    let segment: NoteSegment
    let isSelected: Bool

    private var stabilityColor: Color {
        switch segment.stabilityPercentage {
        case 80...:    return .green
        case 60..<80:  return .orange
        default:       return .red
        }
    }

    var body: some View {
        VStack(spacing: 5) {
            Text(segment.noteName)
                .font(.system(size: 16, weight: isSelected ? .medium : .light, design: .rounded))
                .foregroundStyle(isSelected ? Color(.systemBackground) : Color.primary)

            // Barra de estabilidade visual
            RoundedRectangle(cornerRadius: 2)
                .fill(isSelected ? Color(.systemBackground).opacity(0.6) : stabilityColor.opacity(0.6))
                .frame(width: 28, height: 3)

            Text(String(format: "%.0f%%", segment.stabilityPercentage))
                .font(.system(size: 9, design: .rounded))
                .foregroundStyle(isSelected ? Color(.systemBackground).opacity(0.7) : Color.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.primary : Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isSelected ? Color.clear : stabilityColor.opacity(0.3),
                    lineWidth: 1
                )
        )
        .animation(.spring(duration: 0.25), value: isSelected)
    }
}