//
//  PitchLabView.swift
//  PitchMVP
//
//  Created by victor on 23/02/26.
//

// PitchLabView.swift
// PitchMVP — Refatorado

import SwiftUI

struct PitchLabView: View {

    @StateObject private var labViewModel = TunerLabViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {

                        // MARK: Header
                        VStack(spacing: 4) {
                            Text("LAB")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .tracking(3)
                                .foregroundStyle(.secondary)

                            Text("Teste Profissional")
                                .font(.system(size: 28, weight: .thin, design: .rounded))
                                .foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                        // MARK: Run Button
                        Button {
                            labViewModel.runPitchTests()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Executar Testes")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.primary)
                            .foregroundStyle(Color(.systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .padding(.horizontal, 20)

                        // MARK: Results
                        if labViewModel.results.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "waveform.path.ecg")
                                    .font(.system(size: 36, weight: .thin))
                                    .foregroundStyle(.tertiary)
                                Text("Nenhum teste executado")
                                    .font(.system(size: 14, design: .rounded))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 48)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(labViewModel.results, id: \.id) { result in
                                    LabResultCard(result: result)
                                }
                            }
                            .padding(.horizontal, 20)
                        }

                        Spacer(minLength: 32)
                    }
                    .padding(.top, 16)
                }
            }
            .navigationBarHidden(true)
        }
    }
}

// MARK: LabResultCard

struct LabResultCard: View {
    let result: TunerLabViewModel.PitchTestResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Cabeçalho do card
            HStack {
                Text(result.label)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer()
                StatusPill(isInTune: result.isInTune)
            }

            Divider()

            // Frequências
            HStack(spacing: 0) {
                FreqCell(label: "ALVO", value: String(format: "%.2f Hz", result.targetFrequency))
                Spacer()
                FreqCell(label: "DETECTADO", value: String(format: "%.2f Hz", result.detectedFrequency))
                Spacer()
                FreqCell(label: "NOTA", value: result.note)
            }

            // Cents e direção
            HStack(spacing: 8) {
                Text(String(format: "%.1f¢", result.cents))
                    .font(.system(size: 22, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(result.isInTune ? .green : .primary)

                Text("·")
                    .foregroundStyle(.tertiary)

                Text(result.direction)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer()

                if !result.intensityHint.isEmpty {
                    Text(result.intensityHint)
                        .font(.system(size: 11, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Capsule())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

private struct StatusPill: View {
    let isInTune: Bool

    var body: some View {
        Text(isInTune ? "AFINADO" : "DESAFINADO")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isInTune ? Color.green.opacity(0.15) : Color.orange.opacity(0.12))
            .foregroundStyle(isInTune ? .green : .orange)
            .clipShape(Capsule())
    }
}

private struct FreqCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
        }
    }
}


// ─────────────────────────────────────────────────────────
// WAVAnalyzerView.swift
// PitchMVP — Refatorado
// ─────────────────────────────────────────────────────────

struct WAVAnalyzerView: View {

    @StateObject private var viewModel = TunerViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                VStack(spacing: 0) {

                    // MARK: Header
                    VStack(spacing: 4) {
                        Text("ANALISADOR")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .tracking(3)
                            .foregroundStyle(.secondary)

                        Text("WAV")
                            .font(.system(size: 28, weight: .thin, design: .rounded))
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 40)

                    // MARK: Frequência detectada
                    VStack(spacing: 6) {
                        Text("FREQUÊNCIA DETECTADA")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .tracking(2)
                            .foregroundStyle(.tertiary)

                        Text(String(format: "%.2f", viewModel.pitch?.frequency ?? 0.0))
                            .font(.system(size: 72, weight: .thin, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                            .animation(.easeOut(duration: 0.2), value: viewModel.pitch?.frequency)

                        Text("Hz")
                            .font(.system(size: 18, weight: .light, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 56)

                    // MARK: Arquivo atual
                    HStack(spacing: 8) {
                        Image(systemName: "doc.waveform")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Text("\(viewModel.musics[viewModel.currentIndex]).wav")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(Capsule())
                    .padding(.bottom, 32)

                    // MARK: Botões
                    VStack(spacing: 12) {
                        Button {
                            if let url = Bundle.main.url(
                                forResource: viewModel.musics[viewModel.currentIndex],
                                withExtension: "wav"
                            ) {
                                viewModel.analyzeFile(url: url)
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "waveform.badge.magnifyingglass")
                                    .font(.system(size: 14, weight: .medium))
                                Text("Analisar Arquivo")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.primary)
                            .foregroundStyle(Color(.systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }

                        Button {
                            viewModel.nextItem()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "arrow.right.circle")
                                    .font(.system(size: 14, weight: .medium))
                                Text("Próximo Arquivo")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color(.secondarySystemBackground))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(Color(.separator), lineWidth: 1)
                            )
                        }
                    }
                    .padding(.horizontal, 20)

                    Spacer()
                }
                .padding(.top, 16)
            }
            .navigationBarHidden(true)
        }
    }
}