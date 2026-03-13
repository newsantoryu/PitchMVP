// LyricsAnalysisView.swift
// PitchMVP
//
// v2 — Sem input manual de letra:
//   • Usuário seleciona arquivo do Supabase
//   • Seleciona registro vocal
//   • App transcreve automaticamente via Whisper + detecta notas via YIN
//   • Mostra progresso granular (download modelo, transcrição, notas, alinhamento)
//   • Exibe cifra animada + Vocal Profile
//   • Exporta PDF

import SwiftUI

struct LyricsAnalysisView: View {

    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = LyricsAnalysisViewModel()

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                header

                switch vm.state {
                case .idle:        setupContent
                case .analyzing:   analyzingView
                case .done:
                    if let analysis = vm.analysis { resultContent(analysis: analysis) }
                case .error(let msg): errorView(msg)
                }
            }
        }
        .task { await vm.loadRemoteFiles() }
        .sheet(isPresented: $vm.showShareSheet) {
            if let data = vm.pdfData, let file = vm.selectedFile {
                PDFShareSheet(pdfData: data, fileName: "\(file.displayName)_cifra.pdf")
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .bottom) {
            Button { vm.clearAll(); dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("CIFRA")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .tracking(3).foregroundStyle(.secondary)
                Text("Análise de Letra")
                    .font(.system(size: 28, weight: .thin, design: .rounded))
            }
            .padding(.leading, 4)

            Spacer()

            if vm.state == .done {
                HStack(spacing: 8) {
                    Button { withAnimation { vm.reset() } } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(8)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(Circle())
                    }
                    Button { vm.generateAndSharePDF() } label: {
                        Group {
                            if vm.isGeneratingPDF {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 14, weight: .medium))
                            }
                        }
                        .foregroundStyle(.primary)
                        .padding(8)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Circle())
                    }
                    .disabled(vm.isGeneratingPDF)
                }
                .transition(.opacity.combined(with: .scale))
                .animation(.easeOut, value: vm.state == .done)
            }
        }
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 16)
    }

    // MARK: - Setup (Idle)

    private var setupContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // ── Aviso modelo Whisper ──────────────────────────────────────
                if vm.needsModelDownload {
                    modelDownloadWarning
                }

                // ── Registro Vocal ────────────────────────────────────────────
                setupCard {
                    VStack(alignment: .leading, spacing: 10) {
                        cardLabel("REGISTRO VOCAL", icon: "person.wave.2")
                        HStack(spacing: 10) {
                            voiceHintButton(.male,   icon: "arrow.down.circle", title: "Masculino")
                            voiceHintButton(.female, icon: "arrow.up.circle",   title: "Feminino")
                        }
                    }
                }

                // ── Arquivo Supabase ──────────────────────────────────────────
                setupCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            cardLabel("ARQUIVO DE VINDO", icon: "icloud.and.arrow.down")
                            Spacer()
                            Button { Task { await vm.loadRemoteFiles() } } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                        }
                        filePickerContent
                    }
                }

                // ── Como funciona ─────────────────────────────────────────────
                howItWorksCard

                // ── Botão ─────────────────────────────────────────────────────
                analyzeButton
                    .padding(.bottom, 32)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
        }
    }

    // MARK: - Aviso Modelo Whisper

    private var modelDownloadWarning: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.purple)

            VStack(alignment: .leading, spacing: 3) {
                Text("Primeira análise requer download")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text("O modelo Whisper (~466 MB) será baixado automaticamente e cacheado. Necessário apenas uma vez.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.purple.opacity(0.07))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.purple.opacity(0.2), lineWidth: 1))
        )
    }

    // MARK: - Como Funciona

    private var howItWorksCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardLabel("COMO FUNCIONA", icon: "info.circle")
                .padding(.horizontal, 14).padding(.top, 12)

            Divider().padding(.horizontal, 14)

            VStack(alignment: .leading, spacing: 8) {
                stepRow(n: "1", icon: "icloud.and.arrow.down", text: "Baixa o áudio do Supabase")
                stepRow(n: "2", icon: "waveform",              text: "Detecta as notas musicais (YIN)")
                stepRow(n: "3", icon: "mic.badge.ai",          text: "Transcreve a letra (Whisper Small)")
                stepRow(n: "4", icon: "music.note.list",       text: "Alinha letra ↔ notas por timestamp")
                stepRow(n: "5", icon: "doc.text",              text: "Gera cifra com dificuldade vocal")
            }
            .padding(.horizontal, 14).padding(.bottom, 12)
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func stepRow(n: String, icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Text(n)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
                .frame(width: 14)
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.purple)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - File Picker Content

    @ViewBuilder
    private var filePickerContent: some View {
        if vm.isLoadingFiles {
            HStack { Spacer(); ProgressView().padding(.vertical, 14); Spacer() }
        } else if let error = vm.remoteLoadError {
            remoteErrorBanner(error)
        } else if vm.remoteFiles.isEmpty {
            emptyFilesBanner
        } else {
            fileList
        }
    }

    private var fileList: some View {
        VStack(spacing: 1) {
            ForEach(vm.remoteFiles) { file in
                let isSelected = vm.selectedFile?.id == file.id
                RemoteFileRow(file: file, isSelected: isSelected, accentColor: .purple)
                    .onTapGesture { vm.selectFile(file) }
                if file != vm.remoteFiles.last {
                    Divider().padding(.leading, 52)
                }
            }
        }
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var emptyFilesBanner: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "tray").font(.system(size: 22, weight: .thin)).foregroundStyle(.tertiary)
                Text("Nenhum arquivo disponível").font(.system(size: 12, design: .rounded)).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 18)
            Spacer()
        }
    }

    private func remoteErrorBanner(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash").foregroundStyle(.orange)
            Text(error).font(.system(size: 11, design: .rounded)).foregroundStyle(.secondary).lineLimit(2)
            Spacer()
            Button("Tentar") { Task { await vm.loadRemoteFiles() } }
                .font(.system(size: 12, design: .rounded)).foregroundStyle(.purple)
        }
        .padding(12)
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Analisando

    private var analyzingView: some View {
        VStack(spacing: 28) {
            Spacer()

            // Ícone animado
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.08))
                    .frame(width: 80, height: 80)
                Image(systemName: "waveform.badge.magnifyingglass")
                    .font(.system(size: 32, weight: .thin))
                    .foregroundStyle(.purple)
            }

            VStack(spacing: 12) {
                // Mensagem de progresso
                Text(vm.progressMessage)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .animation(.easeOut, value: vm.progressMessage)

                // Barra de progresso
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.tertiarySystemFill))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.purple)
                            .frame(width: geo.size.width * vm.progressValue, height: 4)
                            .animation(.easeOut(duration: 0.3), value: vm.progressValue)
                    }
                }
                .frame(height: 4)
                .padding(.horizontal, 40)

                Text(String(format: "%.0f%%", vm.progressValue * 100))
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            // Nota sobre primeira execução (modelo sendo baixado/carregado)
            if vm.progressMessage.contains("Carregando modelo") {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle").font(.system(size: 11)).foregroundStyle(.tertiary)
                    Text("Primeira vez pode demorar — modelo sendo carregado")
                        .font(.system(size: 11, design: .rounded)).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 40)
            }

            Button {
                withAnimation { vm.cancelAnalysis() }
            } label: {
                Text("Cancelar")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24).padding(.vertical, 11)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Capsule())
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
    }

    // MARK: - Resultado

    private func resultContent(analysis: LyricsAnalysis) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {

                    // Vocal Profile
                    VocalProfileCard(profile: analysis.vocalProfile)
                        .padding(.horizontal, 20)

                    // Resumo de dificuldade
                    DifficultyBadgeRow(analysis: analysis)
                        .padding(.horizontal, 20)

                    // Controles
                    playbackControls

                    // Cifra
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("CIFRA")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .tracking(2).foregroundStyle(.tertiary)
                            Spacer()
                            Text("\(analysis.lines.count) linhas")
                                .font(.system(size: 10, design: .rounded)).foregroundStyle(.quaternary)
                        }
                        .padding(.horizontal, 20)

                        ForEach(Array(analysis.lines.enumerated()), id: \.element.id) { idx, line in
                            LyricLineCard(
                                line: line,
                                isActive: vm.isPlaying && vm.activeLineIndex == idx
                            )
                            .id(idx)
                            .padding(.horizontal, 16)
                        }
                    }

                    Spacer(minLength: 48)
                }
                .padding(.top, 4)
                .onChange(of: vm.activeLineIndex) { _, newIdx in
                    withAnimation(.easeInOut(duration: 0.4)) {
                        proxy.scrollTo(newIdx, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Playback Controls

    private var playbackControls: some View {
        HStack(spacing: 10) {
            Button {
                if vm.isPlaying { vm.stopPlayback() }
                else            { vm.startPlayback() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: vm.isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 12))
                    Text(vm.isPlaying ? "Parar" : "Animar Letra")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(vm.isPlaying ? Color.red : Color.primary)
                .padding(.horizontal, 18).padding(.vertical, 11)
                .background(vm.isPlaying ? Color.red.opacity(0.1) : Color(.secondarySystemBackground))
                .clipShape(Capsule())
                .animation(.easeOut(duration: 0.2), value: vm.isPlaying)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Erro

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36, weight: .thin)).foregroundStyle(.orange)
            Text("Erro na análise")
                .font(.system(size: 15, weight: .medium, design: .rounded))
            Text(msg)
                .font(.system(size: 12, design: .rounded)).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
            HStack(spacing: 12) {
                Button { withAnimation { vm.reset() } } label: {
                    Text("Voltar")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Capsule())
                }
                Button { vm.startAnalysis() } label: {
                    Text("Tentar novamente")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .background(Color.orange)
                        .clipShape(Capsule())
                }
            }
            Spacer()
        }
    }

    // MARK: - Botão Analisar

    private var analyzeButton: some View {
        VStack(spacing: 8) {
            Button { vm.startAnalysis() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "waveform.badge.magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Transcrever e Analisar")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(vm.canAnalyze ? Color.purple : Color(.tertiarySystemFill))
                .foregroundStyle(vm.canAnalyze ? Color.white : Color.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .disabled(!vm.canAnalyze)
            .animation(.easeOut(duration: 0.2), value: vm.canAnalyze)

            if let reason = vm.blockReason {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up").font(.system(size: 10, weight: .semibold))
                    Text(reason).font(.system(size: 12, design: .rounded))
                }
                .foregroundStyle(.orange)
                .transition(.opacity)
            }
        }
    }

    // MARK: - Voice Hint Button

    private func voiceHintButton(_ hint: VoiceRangeHint, icon: String, title: String) -> some View {
        let isSelected = vm.voiceHint?.matches(hint) ?? false
        return Button {
            withAnimation(.spring(duration: 0.2)) { vm.voiceHint = hint }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "\(icon).fill" : icon).font(.system(size: 12))
                Text(title).font(.system(size: 13, weight: .medium, design: .rounded))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(isSelected ? Color.purple.opacity(0.12) : Color(.tertiarySystemFill))
            .foregroundStyle(isSelected ? Color.purple : Color.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? Color.purple.opacity(0.4) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - UI Helpers

    private func setupCard<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(14)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func cardLabel(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .tracking(1.5).foregroundStyle(.secondary)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - VocalProfileCard
// ─────────────────────────────────────────────────────────────────────────────

private struct VocalProfileCard: View {
    let profile: VocalProfile

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("VOCAL PROFILE", systemImage: "waveform.badge.magnifyingglass")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1.5).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 12)

            Divider().padding(.horizontal, 16)

            HStack(spacing: 0) {
                metricCell("RANGE",      profile.rangeLabel)
                vdivider
                metricCell("TESSITURA",  profile.tessituraLabel)
                vdivider
                metricCell("SEMITÔNIOS", "\(profile.rangeInSemitones) st")
            }
            .padding(.vertical, 12)

            if !profile.highIntensityNotes.isEmpty {
                Divider().padding(.horizontal, 16)
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill").font(.system(size: 11)).foregroundStyle(.red)
                    Text("HIGH INTENSITY")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .tracking(1.5).foregroundStyle(.tertiary)
                    Spacer()
                    ForEach(profile.highIntensityNotes.prefix(6), id: \.self) { note in
                        Text(note)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(red: 1, green: 0.3, blue: 0.3))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color.red.opacity(0.08))
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }

            if let phrase = profile.highestPhrase {
                Divider().padding(.horizontal, 16)
                HStack(spacing: 8) {
                    Image(systemName: "text.quote").font(.system(size: 10)).foregroundStyle(.secondary)
                    Text("FRASE MAIS AGUDA").font(.system(size: 9, weight: .semibold, design: .rounded)).tracking(1.5).foregroundStyle(.tertiary)
                    Spacer()
                    Text("\"\(phrase)\"").font(.system(size: 11, design: .rounded)).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
    }

    private func metricCell(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(label).font(.system(size: 8, weight: .semibold, design: .rounded)).tracking(1.2).foregroundStyle(.tertiary)
            Text(value).font(.system(size: 14, weight: .light, design: .rounded)).foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
    }

    private var vdivider: some View {
        Rectangle().fill(Color(.separator).opacity(0.4)).frame(width: 0.5).padding(.vertical, 6)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - DifficultyBadgeRow
// ─────────────────────────────────────────────────────────────────────────────

private struct DifficultyBadgeRow: View {
    let analysis: LyricsAnalysis

    var body: some View {
        HStack(spacing: 8) {
            badge("🟢", count: analysis.comfortableCount, label: "Confortável", color: .green)
            badge("🟡", count: analysis.moderateCount,    label: "Médio",       color: Color(red: 0.9, green: 0.7, blue: 0))
            badge("🔴", count: analysis.difficultCount,   label: "Difícil",     color: Color(red: 1, green: 0.3, blue: 0.3))
        }
    }

    private func badge(_ emoji: String, count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Text(emoji).font(.system(size: 11))
                Text("\(count)").font(.system(size: 16, weight: .light, design: .rounded)).foregroundStyle(color)
            }
            Text(label).font(.system(size: 9, weight: .semibold, design: .rounded)).tracking(0.5).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background(color.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - LyricLineCard
// ─────────────────────────────────────────────────────────────────────────────

private struct LyricLineCard: View {
    let line: LyricLine
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NoteAboveLineView(words: line.words)
                .padding(.horizontal, 14).padding(.top, 12)

            lyricTextLine
                .padding(.horizontal, 14).padding(.top, 2)

            emojiLine
                .padding(.horizontal, 14).padding(.top, 1).padding(.bottom, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isActive ? Color.purple.opacity(0.08) : Color(.secondarySystemBackground))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isActive ? Color.purple.opacity(0.3) : Color.clear, lineWidth: 1))
        )
        .animation(.easeOut(duration: 0.25), value: isActive)
    }

    private var lyricTextLine: some View {
        line.words.reduce(Text("")) { acc, word in
            acc + Text(word.text + " ")
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emojiLine: some View {
        line.words.reduce(Text("")) { acc, word in
            acc + Text(word.difficulty.emoji + " ").font(.system(size: 10))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - NoteAboveLineView
// ─────────────────────────────────────────────────────────────────────────────

private struct NoteAboveLineView: View {
    let words: [LyricWord]

    var body: some View {
        words.reduce(Text("")) { acc, word in
            guard word.isPhraseBoundary, let note = word.noteName else {
                let spaces = String(repeating: " ", count: word.text.count + 1)
                return acc + Text(spaces).font(.system(size: 9, design: .monospaced))
            }
            let pad    = max(0, word.text.count - note.count)
            let padded = note + String(repeating: " ", count: pad + 1)
            return acc + Text(padded)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(word.difficulty.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Preview

#Preview { LyricsAnalysisView() }