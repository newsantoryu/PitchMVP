// LyricsAnalysisViewModel.swift
// PitchMVP
//
// Pipeline completo:
//   Supabase download
//     → OfflineAudioFileService  (samples Float[])
//     → NoteSegmenter            (NoteSegments com startTime) — Task.detached
//     → WhisperTranscriber       (TimedWords via AsyncStream)  — sequencial após segmenter
//     → LyricsAnalyzer           (alinha TimedWord ↔ NoteSegment por timestamp)
//     → LyricsAnalysis           (linhas + VocalProfile)
//     → LyricsPDFExporter        (PDF em formato cifra)

import Foundation
import SwiftUI

@MainActor
final class LyricsAnalysisViewModel: ObservableObject {

    // MARK: - Seleção
    @Published var selectedFile: RemoteAudioFile? = nil
    @Published var voiceHint: VoiceRangeHint?     = nil

    // MARK: - Estado
    @Published var state: LyricsAnalysisState     = .idle
    @Published var analysis: LyricsAnalysis?      = nil

    // MARK: - Progresso
    @Published var progressMessage: String  = ""
    @Published var progressValue: Double    = 0.0
    @Published var needsModelDownload: Bool = false

    // MARK: - Playback
    @Published var activeLineIndex: Int = 0
    @Published var isPlaying: Bool      = false

    // MARK: - PDF
    @Published var pdfData: Data?        = nil
    @Published var showShareSheet: Bool  = false
    @Published var isGeneratingPDF: Bool = false

    // MARK: - Arquivos Remotos
    @Published var remoteFiles: [RemoteAudioFile] = []
    @Published var isLoadingFiles: Bool            = false
    @Published var remoteLoadError: String?        = nil

    // MARK: - Dependências
    private let repository     = SupabaseAudioRepository.shared
    private let audioService   = OfflineAudioFileService()
    private let segmenter      = NoteSegmenter()
    private let transcriber    = WhisperTranscriber.shared
    private let lyricsAnalyzer = LyricsAnalyzer()
    private let pdfExporter    = LyricsPDFExporter()

    // MARK: - Tasks
    private var analysisTask: Task<Void, Never>?
    private var playbackTask: Task<Void, Never>?

    // MARK: - Computed
    var canAnalyze: Bool {
        selectedFile != nil && voiceHint != nil
    }

    var blockReason: String? {
        if selectedFile == nil { return "Selecione um arquivo do Supabase" }
        if voiceHint == nil    { return "Selecione o registro vocal" }
        return nil
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Carregar Arquivos
    // ─────────────────────────────────────────────────────────────────────────

    func loadRemoteFiles() async {
        isLoadingFiles  = true
        remoteLoadError = nil
        await repository.loadAllFiles()
        remoteFiles     = repository.referenceFiles + repository.performanceFiles
        isLoadingFiles  = false
        remoteLoadError = repository.loadError
        needsModelDownload = !WhisperTranscriber.isModelCached()
    }

    func selectFile(_ file: RemoteAudioFile) {
        selectedFile = file
        if analysis?.audioFileName != file.displayName {
            analysis = nil
            pdfData  = nil
            state    = .idle
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Pipeline Principal
    // ─────────────────────────────────────────────────────────────────────────

    func startAnalysis() {
        guard let file = selectedFile,
              let hint = voiceHint else { return }

        analysisTask?.cancel()

        state           = .analyzing(step: "Iniciando...")
        progressValue   = 0.0
        progressMessage = "Iniciando..."
        analysis        = nil
        pdfData         = nil

        analysisTask = Task { [weak self] in
            guard let self else { return }
            do {
                // ── 1. Download ───────────────────────────────────────────────
                self.setProgress("Baixando áudio...", 0.05)
                let audioURL = try await self.repository.download(file)
                try Task.checkCancellation()

                // ── 2. Samples ────────────────────────────────────────────────
                self.setProgress("Carregando áudio...", 0.10)
                let (samples, sampleRate) = try self.audioService.loadSamples(from: audioURL)
                try Task.checkCancellation()

                guard Float(samples.count) / sampleRate >= 2.0 else {
                    throw TranscriptionError.audioTooShort
                }

                // ── 3. NoteSegmenter (off main thread) ────────────────────────
                self.setProgress("Detectando notas...", 0.15)
                let seg = self.segmenter
                let segments: [NoteSegment] = await Task.detached(priority: .userInitiated) {
                    seg.analyze(samples: samples, sampleRate: sampleRate, voiceHint: hint)
                }.value
                try Task.checkCancellation()

                guard !segments.isEmpty else {
                    throw TranscriptionError.transcriptionFailed(
                        "Nenhuma nota detectada. Verifique o registro vocal."
                    )
                }

                // ── 4. Whisper ────────────────────────────────────────────────
                self.setProgress("Carregando modelo Whisper...", 0.25)
                let timedWords = try await self.runWhisper(audioURL: audioURL)
                try Task.checkCancellation()

                // ── 5. Alinhamento ────────────────────────────────────────────
                // Se timedWords vazio (timeout Whisper) → fallback proporcional
                self.setProgress("Alinhando letra e notas...", 0.92)
                let analyzer = self.lyricsAnalyzer
                let result: LyricsAnalysis?
                if !timedWords.isEmpty {
                    print("[Lyrics] Alinhando por timestamp (\(timedWords.count) palavras)")
                    result = analyzer.analyze(
                        timedWords: timedWords,
                        segments: segments,
                        audioFileName: file.displayName
                    )
                } else {
                    print("[Lyrics] Whisper timeout — fallback: só perfil vocal, sem letra")
                    // Sem transcrição: gera análise só com perfil vocal
                    // Os LyricWords ficam com texto "·" para indicar nota sem letra
                    let placeholderText = segments
                        .prefix(80)
                        .map { _ in "·" }
                        .joined(separator: " ")
                    result = analyzer.analyze(
                        plainText: placeholderText,
                        segments: segments,
                        audioFileName: file.displayName
                    )
                }
                guard let result else {
                    self.state = .error("Não foi possível gerar a análise.")
                    return
                }

                self.setProgress("Concluído", 1.0)
                self.analysis = result
                self.state    = .done

            } catch is CancellationError {
                self.state           = .idle
                self.progressValue   = 0
                self.progressMessage = ""
            } catch {
                self.state = .error(error.localizedDescription)
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Whisper Runner
    // ─────────────────────────────────────────────────────────────────────────

    /// Consome o AsyncStream do WhisperTranscriber e atualiza a UI com progresso real.
    /// Retorna [TimedWord] com timestamps reais por palavra vindos do Whisper.
    private func runWhisper(audioURL: URL) async throws -> [TimedWord] {
        let progressStart = 0.27
        let progressEnd   = 0.90

        for await event in await transcriber.transcribe(audioURL: audioURL) {
            switch event {

            case .loadingModel:
                setProgress("Carregando modelo Whisper...", progressStart)

            case .transcribing(let done, let total):
                let fraction = total > 0 ? Double(done) / Double(total) : 0
                let mapped   = progressStart + fraction * (progressEnd - progressStart)
                let pct      = Int(fraction * 100)
                setProgress("Transcrevendo... \(pct)% (\(done)/\(total) trechos)", min(mapped, progressEnd))

            case .done(let words):
                setProgress("Transcrição concluída", progressEnd)
                return words   // ← retorna TimedWords reais, sem parseTimedWords

            case .failed(let error):
                throw error
            }
        }

        return []   // fallback — LyricsAnalyzer trata vazio com proporcional
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Controles
    // ─────────────────────────────────────────────────────────────────────────

    func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask    = nil
        state           = .idle
        progressValue   = 0
        progressMessage = ""
    }

    func reset() {
        analysisTask?.cancel()
        stopPlayback()
        state           = .idle
        analysis        = nil
        pdfData         = nil
        progressValue   = 0
        progressMessage = ""
    }

    func clearAll() {
        reset()
        selectedFile = nil
        voiceHint    = nil
        remoteFiles  = []
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Playback
    // ─────────────────────────────────────────────────────────────────────────

    func startPlayback() {
        guard let analysis, !analysis.lines.isEmpty else { return }
        isPlaying       = true
        activeLineIndex = 0

        playbackTask = Task { [weak self] in
            guard let self else { return }
            for (i, line) in analysis.lines.enumerated() {
                guard !Task.isCancelled else { break }
                self.activeLineIndex = i
                let duration = max(1.5, Double(line.words.count) * 0.38)
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            }
            self.isPlaying = false
        }
    }

    func stopPlayback() {
        playbackTask?.cancel()
        playbackTask    = nil
        isPlaying       = false
        activeLineIndex = 0
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - PDF
    // ─────────────────────────────────────────────────────────────────────────

    func generateAndSharePDF() {
        guard let analysis else { return }
        isGeneratingPDF = true

        Task {
            let exporter = self.pdfExporter
            let data = await Task.detached(priority: .userInitiated) {
                exporter.export(analysis: analysis)
            }.value
            self.pdfData         = data
            self.isGeneratingPDF = false
            self.showShareSheet  = true
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Helper
    // ─────────────────────────────────────────────────────────────────────────

    private func setProgress(_ message: String, _ value: Double) {
        progressMessage = message
        progressValue   = value
        state           = .analyzing(step: message)
    }
}