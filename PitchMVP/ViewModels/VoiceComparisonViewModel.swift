// VoiceComparisonViewModel+Supabase.swift
// PitchMVP
//
// Extensão do VoiceComparisonViewModel para integrar com Supabase.
// Substitui o VoiceComparisonViewModel.swift existente por esta versão completa.

import Foundation
import SwiftUI

final class VoiceComparisonViewModel: ObservableObject {

    // MARK: - Seleção de arquivos

    /// Arquivo selecionado para "Minha Voz" (pode ser remoto ou local Bundle)
    @Published var userSource: AudioSource? = nil

    /// Arquivo selecionado para "Referência"
    @Published var referenceSource: AudioSource? = nil

    // MARK: - Estado

    @Published var state: ComparisonState = .idle
    @Published var result: ComparisonResult? = nil
    @Published var activeTab: Int = 0

    // MARK: - Repositório Supabase

    @Published var performanceFiles: [RemoteAudioFile] = []
    @Published var referenceFiles:   [RemoteAudioFile] = []
    @Published var isLoadingFiles = false
    @Published var remoteLoadError: String? = nil

    // MARK: - Bundle fallback (arquivos locais)
    let bundleFiles: [String] = ["voz", "voz2", "vozm1", "voz3", "voz5"]

    // MARK: - Dependências

    private let repository  = SupabaseAudioRepository.shared
    private let audioService = OfflineAudioFileService()
    private let segmenter    = NoteSegmenter()

    // MARK: - Computed

    var canCompare: Bool { userSource != nil && referenceSource != nil }

    var userDisplayName:  String { userSource?.displayName  ?? "Não selecionado" }
    var refDisplayName:   String { referenceSource?.displayName ?? "Não selecionado" }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Carregar arquivos remotos
    // ─────────────────────────────────────────────────────────────────────────

    @MainActor
    func loadRemoteFiles() async {
        isLoadingFiles = true
        remoteLoadError = nil

        await repository.loadAllFiles()

        performanceFiles = repository.performanceFiles
        referenceFiles   = repository.referenceFiles
        isLoadingFiles   = repository.isLoading
        remoteLoadError  = repository.loadError
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Seleção
    // ─────────────────────────────────────────────────────────────────────────

    func selectUser(remote file: RemoteAudioFile) {
        userSource = .remote(file)
        withAnimation { activeTab = 1 }
    }

    func selectReference(remote file: RemoteAudioFile) {
        referenceSource = .remote(file)
    }

    func selectUserFromBundle(_ name: String) {
        userSource = .bundle(name)
        withAnimation { activeTab = 1 }
    }

    func selectReferenceFromBundle(_ name: String) {
        referenceSource = .bundle(name)
    }

    func selectUserExternal(url: URL) {
        userSource = .external(url)
        withAnimation { activeTab = 1 }
    }

    func selectReferenceExternal(url: URL) {
        referenceSource = .external(url)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Comparação
    // ─────────────────────────────────────────────────────────────────────────

    func startComparison() {
        guard let userSrc = userSource, let refSrc = referenceSource else { return }

        state  = .analyzing(step: "Preparando arquivos...")
        result = nil

        Task { @MainActor in
            do {
                // ── Resolve URLs (baixa se necessário) ───────────────────────
                state = .analyzing(step: "Baixando referência...")
                let refURL = try await resolveURL(for: refSrc)

                state = .analyzing(step: "Baixando sua voz...")
                let userURL = try await resolveURL(for: userSrc)

                // ── Analisa referência ────────────────────────────────────────
                state = .analyzing(step: "Analisando referência...")
                let (refSamples, refRate) = try audioService.loadSamples(from: refURL)
                let refSegments = segmenter.analyze(samples: refSamples, sampleRate: refRate)

                // ── Analisa voz do usuário ────────────────────────────────────
                state = .analyzing(step: "Analisando sua voz...")
                let (userSamples, userRate) = try audioService.loadSamples(from: userURL)
                let userSegments = segmenter.analyze(samples: userSamples, sampleRate: userRate)

                // ── Casa por ordem cronológica ────────────────────────────────
                state = .analyzing(step: "Comparando notas...")
                let comparisons = buildComparisons(user: userSegments, reference: refSegments)

                let compResult = ComparisonResult(
                    comparisons: comparisons,
                    userSegments: userSegments,
                    referenceSegments: refSegments,
                    userFileName: userDisplayName,
                    referenceFileName: refDisplayName
                )

                result = compResult
                state  = compResult.totalPairs == 0 ? .empty : .done

            } catch {
                state = .error(error.localizedDescription)
            }
        }
    }

    func reset() {
        result = nil
        state  = .idle
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Resolve URL (Bundle / Remoto / Externo)
    // ─────────────────────────────────────────────────────────────────────────

    @MainActor
    private func resolveURL(for source: AudioSource) async throws -> URL {
        switch source {

        case .bundle(let name):
            guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else {
                throw SupabaseStorageError.invalidURL
            }
            return url

        case .external(let url):
            return url

        case .remote(let file):
            // Usa cache se disponível, caso contrário baixa
            return try await repository.download(file)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Matching cronológico
    // ─────────────────────────────────────────────────────────────────────────

    private func buildComparisons(
        user: [NoteSegment],
        reference: [NoteSegment]
    ) -> [NoteComparison] {
        let maxCount = max(user.count, reference.count)
        return (0..<maxCount).map { i in
            NoteComparison(
                index: i,
                userSegment:      i < user.count      ? user[i]      : nil,
                referenceSegment: i < reference.count ? reference[i] : nil
            )
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - AudioSource
// ─────────────────────────────────────────────────────────────────────────────

/// Abstrai a origem de um arquivo de áudio — Bundle, remoto ou externo.
enum AudioSource: Equatable {
    case bundle(String)           // nome sem extensão no Bundle
    case remote(RemoteAudioFile)  // arquivo do Supabase
    case external(URL)            // arquivo importado pelo file picker

    var displayName: String {
        switch self {
        case .bundle(let name):   return "\(name).wav"
        case .remote(let file):   return file.displayName
        case .external(let url):  return url.lastPathComponent
        }
    }

    static func == (lhs: AudioSource, rhs: AudioSource) -> Bool {
        switch (lhs, rhs) {
        case (.bundle(let a),   .bundle(let b)):   return a == b
        case (.remote(let a),   .remote(let b)):   return a == b
        case (.external(let a), .external(let b)): return a == b
        default: return false
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - ComparisonState
// ─────────────────────────────────────────────────────────────────────────────

enum ComparisonState: Equatable {
    case idle
    case analyzing(step: String)
    case done
    case empty
    case error(String)

    var isAnalyzing: Bool {
        if case .analyzing = self { return true }
        return false
    }

    var stepMessage: String {
        if case .analyzing(let msg) = self { return msg }
        return ""
    }
}