// VoiceComparisonViewModel+Supabase.swift
// PitchMVP
//
// ATUALIZADO — Cross-Gender Alignment:
//   • buildComparisons agora usa MelodicAligner (alinhamento por janela temporal + pitch class)
//     em vez do pareamento posicional ingênuo (nota[i] com nota[i]).
//   • crossGenderContext publicado para consumo na UI (badge de registro vocal).
//   • Nenhuma funcionalidade anterior foi removida.
//
// ALINHAMENTO MELÓDICO (novo):
//   Barítono C3 × Soprano C4 → pareados corretamente por pitch class ("C"),
//   mesmo que o número total de segmentos detectados seja diferente entre as vozes.
//
// ALINHAMENTO ANTERIOR (mantido para referência no comentário):
//   Era: nota[0] com nota[0], nota[1] com nota[1], etc.
//   Problema: segmentadores produzem contagens diferentes em cross-gender.

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

    // MARK: - Cross-Gender Context (NOVO)

    /// Publicado após comparação para exibir badge de registro na UI.
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

    /// Aligner com janela temporal de ±1.5s — ajuste conforme o repertório.
    /// Para música mais lenta/livre, aumente para 2.0–3.0s.
    private let aligner = MelodicAligner(
        timeWindowSeconds: 1.5,
        minimumMatchScore: 0.25,
        pitchClassMismatchPenalty: 0.4
    )

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
        crossGenderContext = nil

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

                // ── Cross-gender detection (NOVO) ─────────────────────────────
                let cgContext = CrossGenderContext.analyze(
                    userSegments: userSegments,
                    referenceSegments: refSegments
                )
                crossGenderContext = cgContext

                // Log diagnóstico — visível no console durante desenvolvimento
                if cgContext.isCrossGender {
                    print("""
                    [MelodicAligner] ⚡ Cross-gender detectado
                      Usuário:    \(cgContext.estimatedUserVoiceType.rawValue) (shift médio: \(String(format: "%.1f", cgContext.medianOctaveShift)) semitons)
                      Referência: \(cgContext.estimatedReferenceVoiceType.rawValue)
                      → Usando alinhamento por pitch class + janela temporal
                    """)
                }

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
        crossGenderContext = nil
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
    // MARK: - Alinhamento Melódico (ATUALIZADO)
    // ─────────────────────────────────────────────────────────────────────────
    //
    // Substituição do pareamento posicional por alinhamento inteligente.
    //
    // ANTES (ingênuo — problemático em cross-gender):
    //   note[0] ↔ note[0], note[1] ↔ note[1], ...
    //   → Falha quando as vozes produzem contagens diferentes de segmentos.
    //
    // AGORA (MelodicAligner):
    //   Para cada nota da referência, busca o melhor par no usuário
    //   dentro de ±1.5s por pitch class (ignora oitava).
    //   → Barítono C3 pareia com Soprano C4 corretamente.
    //   → Notas sem par ficam como "ausentes" (educacional para o professor).
    //
    // Regras preservadas (inalteradas):
    //   • pitchClassMatch = true quando graus batem, independente de oitava
    //   • centsDelta = desvio de cada voz NA SUA nota, não distância entre elas
    //   • Notas extras do usuário ficam com referenceSegment = nil
    //   • Notas extras da referência ficam com userSegment = nil
    //
    private func buildComparisons(
        user: [NoteSegment],
        reference: [NoteSegment]
    ) -> [NoteComparison] {

        // Delega ao MelodicAligner — retorna pares na ordem cronológica da referência
        var comparisons = aligner.align(user: user, reference: reference)

        // Injeta direções de contorno melódico (lógica original preservada)
        comparisons = injectMelodicContour(into: comparisons)

        return comparisons
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Contorno Melódico (inalterado)
    // ─────────────────────────────────────────────────────────────────────────

    /// Calcula a direção melódica de cada nota (subiu/desceu/igual) em relação
    /// à nota anterior e injeta nas comparações.
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
// MARK: - AudioSource (inalterado)
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
// MARK: - ComparisonState (inalterado)
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