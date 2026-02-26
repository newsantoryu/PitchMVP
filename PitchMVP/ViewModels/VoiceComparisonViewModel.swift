// VoiceComparisonViewModel+Supabase.swift
// PitchMVP
//
// ALINHAMENTO: cronológico com tolerância de oitava.
// A 1ª nota do usuário pareia com a 1ª da referência, a 2ª com a 2ª, etc.
// Se estiverem no mesmo grau (ex: C3 vs C4), não penaliza — é considerado correto.
// Sem reordenamento: a ordem da música é respeitada.

import Foundation
import SwiftUI

final class VoiceComparisonViewModel: ObservableObject {

    // MARK: - Seleção de arquivos

    @Published var userSource: AudioSource?      = nil
    @Published var referenceSource: AudioSource? = nil

    // MARK: - Estado

    @Published var state: ComparisonState    = .idle
    @Published var result: ComparisonResult? = nil
    @Published var activeTab: Int = 0

    // MARK: - Repositório Supabase

    @Published var performanceFiles: [RemoteAudioFile] = []
    @Published var referenceFiles:   [RemoteAudioFile] = []
    @Published var isLoadingFiles    = false
    @Published var remoteLoadError: String? = nil

    let bundleFiles: [String] = ["voz", "voz2", "vozm1", "voz3", "voz5"]

    // MARK: - Dependências

    private let repository   = SupabaseAudioRepository.shared
    private let audioService = OfflineAudioFileService()
    private let segmenter    = NoteSegmenter()

    // MARK: - Computed

    var canCompare: Bool { userSource != nil && referenceSource != nil }
    var userDisplayName: String { userSource?.displayName     ?? "Não selecionado" }
    var refDisplayName:  String { referenceSource?.displayName ?? "Não selecionado" }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Carregar arquivos remotos
    // ─────────────────────────────────────────────────────────────────────────

    @MainActor
    func loadRemoteFiles() async {
        isLoadingFiles  = true
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

    func selectReference(remote file: RemoteAudioFile) { referenceSource = .remote(file) }

    func selectUserFromBundle(_ name: String) {
        userSource = .bundle(name)
        withAnimation { activeTab = 1 }
    }

    func selectReferenceFromBundle(_ name: String) { referenceSource = .bundle(name) }

    func selectUserExternal(url: URL) {
        userSource = .external(url)
        withAnimation { activeTab = 1 }
    }

    func selectReferenceExternal(url: URL) { referenceSource = .external(url) }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Comparação
    // ─────────────────────────────────────────────────────────────────────────

    func startComparison() {
        guard let userSrc = userSource, let refSrc = referenceSource else { return }

        state  = .analyzing(step: "Preparando arquivos...")
        result = nil

        Task { @MainActor in
            do {
                state = .analyzing(step: "Baixando referência...")
                let refURL = try await resolveURL(for: refSrc)

                state = .analyzing(step: "Baixando sua voz...")
                let userURL = try await resolveURL(for: userSrc)

                state = .analyzing(step: "Analisando referência...")
                let (refSamples, refRate) = try audioService.loadSamples(from: refURL)
                let refSegments = segmenter.analyze(samples: refSamples, sampleRate: refRate)

                state = .analyzing(step: "Analisando sua voz...")
                let (userSamples, userRate) = try audioService.loadSamples(from: userURL)
                let userSegments = segmenter.analyze(samples: userSamples, sampleRate: userRate)

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
    // MARK: - Resolve URL
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
            return try await repository.download(file)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Alinhamento Cronológico com Tolerância de Oitava
    // ─────────────────────────────────────────────────────────────────────────
    //
    // Regras:
    //  • A N-ésima nota do usuário pareia com a N-ésima da referência.
    //    A ordem da melodia é sempre preservada — sem reordenamento.
    //
    //  • Se a referência tiver mais notas, as extras ficam com userSegment = nil
    //    (usuário não cantou essa nota).
    //
    //  • Se o usuário tiver mais notas, as extras ficam com referenceSegment = nil
    //    (cantou notas a mais).
    //
    //  • Tolerância de oitava: C3 vs C4 é reconhecido como "grau correto"
    //    (pitchClassMatch = true) mas NÃO afeta o cálculo de centsDelta —
    //    cada voz é sempre avaliada em relação à sua própria nota alvo.
    //
    private func buildComparisons(
        user: [NoteSegment],
        reference: [NoteSegment]
    ) -> [NoteComparison] {

        let maxCount = max(user.count, reference.count)

        var comparisons = (0..<maxCount).map { i in
            NoteComparison(
                index: i,
                userSegment:      i < user.count      ? user[i]      : nil,
                referenceSegment: i < reference.count ? reference[i] : nil
            )
        }

        // Injeta direções de contorno melódico após montar todos os pares
        comparisons = injectMelodicContour(into: comparisons)

        return comparisons
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Contorno Melódico
    // ─────────────────────────────────────────────────────────────────────────

    /// Calcula a direção melódica de cada nota (subiu/desceu/igual) em relação
    /// à nota anterior e injeta nas comparações.
    ///
    /// Usa MIDI arredondado para comparar direção — variações de cents dentro
    /// da mesma nota não contam como mudança de direção.
    /// Oitavas SÃO consideradas: C3→D3 e C4→D4 são ambas "subiu".
    private func injectMelodicContour(into comparisons: [NoteComparison]) -> [NoteComparison] {

        var result = comparisons

        for i in result.indices {
            var comp = result[i]

            if i == 0 {
                comp.userContourDirection      = .unset
                comp.referenceContourDirection = .unset
            } else {
                let prev = result[i - 1]

                comp.userContourDirection = contourDirection(
                    from: prev.userSegment?.midiNote,
                    to:   comp.userSegment?.midiNote
                )

                comp.referenceContourDirection = contourDirection(
                    from: prev.referenceSegment?.midiNote,
                    to:   comp.referenceSegment?.midiNote
                )
            }

            result[i] = comp
        }

        return result
    }

    /// Calcula a direção entre dois MIDI notes usando nota inteira (ignora cents).
    private func contourDirection(from prev: Float?, to current: Float?) -> ContourDirection {
        guard let p = prev, let c = current else { return .unset }
        let rp = round(p), rc = round(c)
        if rc > rp { return .up   }
        if rc < rp { return .down }
        return .same
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - AudioSource
// ─────────────────────────────────────────────────────────────────────────────

enum AudioSource: Equatable {
    case bundle(String)
    case remote(RemoteAudioFile)
    case external(URL)

    var displayName: String {
        switch self {
        case .bundle(let name):  return "\(name).wav"
        case .remote(let file):  return file.displayName
        case .external(let url): return url.lastPathComponent
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