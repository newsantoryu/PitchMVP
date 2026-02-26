// VoiceComparisonViewModel+Supabase.swift
// PitchMVP
//
// FIX v4:
// • userVoiceHint e referenceVoiceHint agora são Optional<VoiceRangeHint>
//   nil = não selecionado ainda
// • canCompare exige fonte + hint selecionados em ambos os lados
// • CrossGenderContext.analyze recebe hints explícitos — sem inferência por MIDI

import Foundation
import SwiftUI

final class VoiceComparisonViewModel: ObservableObject {

    // MARK: - Seleção de arquivos

    @Published var userSource: AudioSource?      = nil
    @Published var referenceSource: AudioSource? = nil

    // MARK: - Hints de registro vocal (Optional — nil = não selecionado)
    // O botão Comparar fica desabilitado enquanto qualquer hint for nil.
    // Isso elimina o fallback por inferência de áudio que causava falsos positivos.

    @Published var userVoiceHint: VoiceRangeHint?      = nil
    @Published var referenceVoiceHint: VoiceRangeHint? = nil

    // MARK: - Estado

    @Published var state: ComparisonState    = .idle
    @Published var result: ComparisonResult? = nil
    @Published var activeTab: Int = 0

    @Published var crossGenderContext: CrossGenderContext? = nil

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
    private let aligner      = MelodicAligner()

    // MARK: - Computed

    /// Requer: arquivo + hint selecionados nos dois lados.
    var canCompare: Bool {
        userSource != nil && referenceSource != nil
        && userVoiceHint != nil && referenceVoiceHint != nil
    }

    /// Mensagem explicativa para o botão desabilitado — exibida na UI.
    var compareBlockReason: String? {
        if userSource == nil       { return "Selecione sua voz" }
        if referenceSource == nil  { return "Selecione a referência" }
        if userVoiceHint == nil    { return "Selecione o registro da sua voz" }
        if referenceVoiceHint == nil { return "Selecione o registro da referência" }
        return nil
    }

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

    func selectUser(remote file: RemoteAudioFile)  { userSource = .remote(file); withAnimation { activeTab = 1 } }
    func selectReference(remote file: RemoteAudioFile) { referenceSource = .remote(file) }
    func selectUserFromBundle(_ name: String)       { userSource = .bundle(name); withAnimation { activeTab = 1 } }
    func selectReferenceFromBundle(_ name: String)  { referenceSource = .bundle(name) }
    func selectUserExternal(url: URL)               { userSource = .external(url); withAnimation { activeTab = 1 } }
    func selectReferenceExternal(url: URL)          { referenceSource = .external(url) }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Comparação
    // ─────────────────────────────────────────────────────────────────────────

    func startComparison() {
        guard let userSrc = userSource,
              let refSrc  = referenceSource,
              let uHint   = userVoiceHint,
              let rHint   = referenceVoiceHint
        else { return }

        state  = .analyzing(step: "Preparando arquivos...")
        result = nil
        crossGenderContext = nil

        Task { @MainActor in
            do {
                state = .analyzing(step: "Baixando referência...")
                let refURL = try await resolveURL(for: refSrc)

                state = .analyzing(step: "Baixando sua voz...")
                let userURL = try await resolveURL(for: userSrc)

                state = .analyzing(step: "Analisando referência...")
                let (refSamples, refRate) = try audioService.loadSamples(from: refURL)
                let refSegments = segmenter.analyze(
                    samples: refSamples,
                    sampleRate: refRate
                )

                state = .analyzing(step: "Analisando sua voz...")
                let (userSamples, userRate) = try audioService.loadSamples(from: userURL)
                let userSegments = segmenter.analyze(
                    samples: userSamples,
                    sampleRate: userRate
                )

                // 100% determinístico — sem inferência por áudio
                let cgContext = CrossGenderContext.analyze(
                    userHint: uHint,
                    referenceHint: rHint,
                    userSegments: userSegments,
                    referenceSegments: refSegments
                )
                crossGenderContext = cgContext

                #if DEBUG
                print("[VM] isCrossGender=\(cgContext.isCrossGender) | \(uHint.label) × \(rHint.label) | shift=\(String(format: "%.1f", cgContext.medianOctaveShift))st")
                #endif

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
        result             = nil
        state              = .idle
        crossGenderContext = nil
        // Mantém hints — usuário provavelmente repete o mesmo par de registros
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
        case .external(let url): return url
        case .remote(let file):  return try await repository.download(file)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Alinhamento
    // ─────────────────────────────────────────────────────────────────────────

    private func buildComparisons(
        user: [NoteSegment],
        reference: [NoteSegment]
    ) -> [NoteComparison] {
        var comparisons = aligner.align(user: user, reference: reference)
        comparisons = injectMelodicContour(into: comparisons)
        return comparisons
    }

    private func injectMelodicContour(into comparisons: [NoteComparison]) -> [NoteComparison] {
        var result = comparisons
        for i in result.indices {
            var comp = result[i]
            if i == 0 {
                comp.userContourDirection      = .unset
                comp.referenceContourDirection = .unset
            } else {
                let prev = result[i - 1]
                comp.userContourDirection      = contourDirection(from: prev.userSegment?.midiNote,      to: comp.userSegment?.midiNote)
                comp.referenceContourDirection = contourDirection(from: prev.referenceSegment?.midiNote, to: comp.referenceSegment?.midiNote)
            }
            result[i] = comp
        }
        return result
    }

    private func contourDirection(from prev: Float?, to current: Float?) -> ContourDirection {
        guard let p = prev, let c = current else { return .unset }
        let rp = round(p), rc = round(c)
        if rc > rp { return .up   }
        if rc < rp { return .down }
        return .same
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - AudioSource / ComparisonState
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
