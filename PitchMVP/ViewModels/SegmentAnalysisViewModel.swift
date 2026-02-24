// SegmentAnalysisViewModel.swift
// PitchMVP

import Foundation
import SwiftUI
import UniformTypeIdentifiers

final class SegmentAnalysisViewModel: ObservableObject {

    // MARK: - Estado Publicado

    @Published var segments: [NoteSegment] = []
    @Published var state: AnalysisState = .idle
    @Published var selectedSegment: NoteSegment? = nil
    @Published var currentFileName: String = ""

    // MARK: - WAVs do Bundle (mesma lista do TunerViewModel)

    let bundleFiles: [String] = ["voz", "voz2", "vozm1", "voz3", "voz5"]

    // MARK: - Dependências

    private let audioService = OfflineAudioFileService()
    private let segmenter = NoteSegmenter()

    // MARK: - Computed

    var hasResults: Bool { !segments.isEmpty }

    var summary: SegmentSummary? {
        guard !segments.isEmpty else { return nil }
        return SegmentSummary(segments: segments)
    }

    // MARK: - API Pública

    /// Analisa um WAV do Bundle pelo nome (sem extensão).
    func analyzeFromBundle(named name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else {
            state = .error("Arquivo '\(name).wav' não encontrado no Bundle.")
            return
        }
        currentFileName = "\(name).wav"
        analyze(url: url)
    }

    /// Analisa qualquer URL (Bundle ou importação externa).
    func analyze(url: URL) {
        state = .loading(progress: 0)
        segments = []
        selectedSegment = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            do {
                let (samples, sampleRate) = try self.audioService.loadSamples(from: url)

                DispatchQueue.main.async {
                    self.state = .loading(progress: 0.4)
                }

                let result = self.segmenter.analyze(samples: samples, sampleRate: sampleRate)

                DispatchQueue.main.async {
                    self.segments = result
                    self.selectedSegment = result.first
                    self.state = result.isEmpty ? .empty : .done
                }

            } catch {
                DispatchQueue.main.async {
                    self.state = .error(error.localizedDescription)
                }
            }
        }
    }

    func select(_ segment: NoteSegment) {
        withAnimation(.spring(duration: 0.3)) {
            selectedSegment = segment
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - AnalysisState
// ─────────────────────────────────────────────────────────────────────────────

enum AnalysisState: Equatable {
    case idle
    case loading(progress: Double)
    case done
    case empty
    case error(String)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SegmentSummary
// ─────────────────────────────────────────────────────────────────────────────

/// Estatísticas agregadas de todos os segmentos detectados na gravação.
struct SegmentSummary {

    let totalNotes: Int
    let uniqueNotes: Int
    let totalDuration: Float
    let averageStability: Float
    let averageCentsDeviation: Float
    let vibratoCount: Int
    let mostStableSegment: NoteSegment?
    let leastStableSegment: NoteSegment?

    init(segments: [NoteSegment]) {
        totalNotes = segments.count
        uniqueNotes = Set(segments.map(\.noteName)).count
        totalDuration = segments.map(\.durationSeconds).reduce(0, +)
        averageStability = segments.map(\.stabilityPercentage).reduce(0, +) / Float(segments.count)
        averageCentsDeviation = segments.map(\.averageCentsDeviation).reduce(0, +) / Float(segments.count)
        vibratoCount = segments.filter { $0.vibrato != nil }.count
        mostStableSegment = segments.max(by: { $0.stabilityPercentage < $1.stabilityPercentage })
        leastStableSegment = segments.min(by: { $0.stabilityPercentage < $1.stabilityPercentage })
    }
}