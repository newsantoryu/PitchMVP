//
//  SessionHistoryView.swift
//  PitchMVP
//
//  Created by victor on 23/02/26.
//

// SessionHistoryView.swift
// PitchMVP

import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - MentorViewModel atualizado com gravação de sessão
// ─────────────────────────────────────────────────────────────────────────────

/// Extensão do MentorViewModel para integrar o SessionRecorder.
/// Cole este código no MentorViewModel.swift existente.
extension MentorViewModel {

    // MARK: Como integrar no MentorViewModel.swift:
    //
    // 1. Adicione como propriedade:
    //    let sessionRecorder = SessionRecorder()
    //    let sessionService  = SessionHistoryService()
    //
    // 2. No update(detectedFrequency:), adicione ao final:
    //    if let feedback = self.feedback {
    //        sessionRecorder.record(feedback: feedback)
    //    }
    //
    // 3. Crie uma função para finalizar a sessão:
    //    func finishSession() {
    //        guard let session = sessionRecorder.finish(
    //            targetNote: targetNote,
    //            targetFrequency: targetFrequency,
    //            simulationMode: "Simulado"
    //        ) else { return }
    //        sessionService.save(session: session)
    //    }
    //
    // 4. Chame finishSession() no .onDisappear da MentorView
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SessionHistoryView
// ─────────────────────────────────────────────────────────────────────────────

struct SessionHistoryView: View {

    @StateObject private var viewModel = SessionHistoryViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                VStack(spacing: 0) {

                    // MARK: Header
                    VStack(spacing: 4) {
                        Text("HISTÓRICO")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .tracking(3)
                            .foregroundStyle(.secondary)

                        Text("Sessões")
                            .font(.system(size: 28, weight: .thin, design: .rounded))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 20)

                    // MARK: Estatísticas gerais
                    if viewModel.statistics.totalSessions > 0 {
                        StatsCard(stats: viewModel.statistics)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                    }

                    // MARK: Lista de sessões
                    if viewModel.sessions.isEmpty {
                        emptyState
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                ForEach(viewModel.sessions) { session in
                                    SessionCard(session: session)
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                viewModel.delete(session: session)
                                            } label: {
                                                Label("Apagar", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 32)
                        }
                    }
                }
                .padding(.top, 16)
            }
            .navigationBarHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !viewModel.sessions.isEmpty {
                        Button("Limpar") {
                            viewModel.clearAll()
                        }
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(.red)
                    }
                }
            }
        }
        .onAppear { viewModel.load() }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(.tertiary)

            Text("Nenhuma sessão ainda")
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(.tertiary)

            Text("Pratique no Mentor para ver\nseu histórico aqui.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.quaternary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 60)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SessionCard
// ─────────────────────────────────────────────────────────────────────────────

private struct SessionCard: View {

    let session: PracticeSession

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        f.locale = Locale(identifier: "pt_BR")
        return f.string(from: session.date)
    }

    private var formattedDuration: String {
        let minutes = Int(session.durationSeconds) / 60
        let seconds = Int(session.durationSeconds) % 60
        return minutes > 0 ? "\(minutes)m \(seconds)s" : "\(seconds)s"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Cabeçalho
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.targetNote)
                        .font(.system(size: 22, weight: .light, design: .rounded))
                    Text(formattedDate)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text(session.rating.emoji + " " + session.rating.rawValue)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(ratingBackground)
                    .clipShape(Capsule())
            }

            Divider()

            // Métricas
            HStack(spacing: 0) {
                MetricCell(
                    label: "AFINADO",
                    value: String(format: "%.0f%%", session.inTunePercentage)
                )
                Spacer()
                MetricCell(
                    label: "DESVIO MÉD.",
                    value: String(format: "%.1f¢", session.averageCents)
                )
                Spacer()
                MetricCell(
                    label: "DURAÇÃO",
                    value: formattedDuration
                )
                Spacer()
                MetricCell(
                    label: "MODO",
                    value: session.simulationMode
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var ratingBackground: Color {
        switch session.rating {
        case .excellent:  return Color.green.opacity(0.15)
        case .good:       return Color.blue.opacity(0.12)
        case .fair:       return Color.orange.opacity(0.12)
        case .needsWork:  return Color.red.opacity(0.10)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - StatsCard
// ─────────────────────────────────────────────────────────────────────────────

private struct StatsCard: View {
    let stats: SessionStatistics

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("VISÃO GERAL")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(2)
                .foregroundStyle(.tertiary)

            HStack(spacing: 0) {
                MetricCell(label: "SESSÕES", value: "\(stats.totalSessions)")
                Spacer()
                MetricCell(
                    label: "AFINADO MÉD.",
                    value: String(format: "%.0f%%", stats.averageInTunePercentage)
                )
                Spacer()
                MetricCell(
                    label: "DESVIO MÉD.",
                    value: String(format: "%.1f¢", stats.averageCentsDeviation)
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Helpers
// ─────────────────────────────────────────────────────────────────────────────

private struct MetricCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SessionHistoryViewModel
// ─────────────────────────────────────────────────────────────────────────────

final class SessionHistoryViewModel: ObservableObject {

    @Published var sessions: [PracticeSession] = []
    @Published var statistics: SessionStatistics = .empty

    private let service = SessionHistoryService()

    func load() {
        sessions = service.loadAll()
        statistics = service.statistics()
    }

    func delete(session: PracticeSession) {
        service.delete(sessionID: session.id)
        load()
    }

    func clearAll() {
        service.clearAll()
        load()
    }
}