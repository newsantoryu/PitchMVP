// VoiceComparisonViewModel+Supabase.swift
// PitchMVP
//
// FIX v5 — Security-scoped URL gerenciada corretamente:
//
// PROBLEMA ANTERIOR:
//   VoiceComparisonView chamava url.stopAccessingSecurityScopedResource()
//   imediatamente após selectUserExternal/selectReferenceExternal. Como o
//   fluxo é assíncrono (usuário ainda precisa escolher o registro e clicar
//   Comparar), a URL ficava inacessível quando loadSamples() era chamado,
//   causando falha silenciosa na leitura do arquivo externo.
//
// SOLUÇÃO:
//   O ViewModel é responsável pelo ciclo de vida do acesso security-scoped.
//   • selectUserExternal/selectReferenceExternal chamam startAccessingSecurityScopedResource
//     e armazenam a URL no set securityScopedURLs.
//   • stopAllSecurityAccess() é chamado pelo ViewModel em dois momentos:
//     1. após loadSamples() completar (dentro de startComparison)
//     2. em reset(), para limpar qualquer acesso pendente
//   • A View NÃO gerencia mais o acesso — apenas chama o fileImporter e
//     repassa a URL pura para o ViewModel.
//
// FIX v4 (mantidos):
//   • userVoiceHint e referenceVoiceHint são Optional<VoiceRangeHint>
//   • canCompare exige fonte + hint selecionados em ambos os lados
//   • CrossGenderContext.analyze recebe hints explícitos

import Foundation
import SwiftUI

final class VoiceComparisonViewModel: ObservableObject {

    // MARK: - Seleção de arquivos

    @Published var userSource: AudioSource?      = nil
    @Published var referenceSource: AudioSource? = nil

    // MARK: - Hints de registro vocal

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

    // MARK: - Security-Scoped URL Management
    //
    // URLs externas (fileImporter) requerem startAccessingSecurityScopedResource()
    // para serem lidas. O acesso deve ser mantido até que loadSamples() complete.
    // Este set garante que as URLs permaneçam acessíveis durante toda a comparação.

    private var securityScopedURLs: Set<URL> = []

    // MARK: - Dependências

    private let repository   = SupabaseAudioRepository.shared
    private let audioService = OfflineAudioFileService()
    private let segmenter    = NoteSegmenter()
    private let aligner      = MelodicAligner()

    // MARK: - Computed

    var canCompare: Bool {
        userSource != nil && referenceSource != nil
        && userVoiceHint != nil && referenceVoiceHint != nil
    }

    var compareBlockReason: String? {
        if userSource == nil          { return "Selecione sua voz" }
        if referenceSource == nil     { return "Selecione a referência" }
        if userVoiceHint == nil       { return "Selecione o registro da sua voz" }
        if referenceVoiceHint == nil  { return "Selecione o registro da referência" }
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

    /// FIX: inicia e mantém o acesso security-scoped.
    /// A View NÃO deve chamar stop — o ViewModel gerencia o ciclo completo.
    func selectUserExternal(url: URL) {
        stopSecurityAccess(for: userSource) // libera acesso anterior se havia outro externo
        if url.startAccessingSecurityScopedResource() {
            securityScopedURLs.insert(url)
        }
        userSource = .external(url)
        withAnimation { activeTab = 1 }
    }

    /// FIX: idem para a referência externa.
    func selectReferenceExternal(url: URL) {
        stopSecurityAccess(for: referenceSource)
        if url.startAccessingSecurityScopedResource() {
            securityScopedURLs.insert(url)
        }
        referenceSource = .external(url)
    }

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
                    sampleRate: refRate,
                    voiceHint: rHint
                )

                state = .analyzing(step: "Analisando sua voz...")
                let (userSamples, userRate) = try audioService.loadSamples(from: userURL)
                let userSegments = segmenter.analyze(
                    samples: userSamples,
                    sampleRate: userRate,
                    voiceHint: uHint
                )

                // FIX: libera acesso security-scoped após loadSamples() completar.
                // Neste ponto os dados já estão em memória — a URL não é mais necessária.
                stopAllSecurityAccess()

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
                stopAllSecurityAccess() // garante liberação mesmo em caso de erro
                state = .error(error.localizedDescription)
            }
        }
    }

    /// Reinicia o resultado e volta para a tela de seleção,
    /// mantendo os arquivos e hints — o usuário só quis ver o resultado de novo.
    func reset() {
        stopAllSecurityAccess()
        result             = nil
        state              = .idle
        crossGenderContext = nil
    }

    /// Limpa toda a pré-seleção: arquivos, hints e aba ativa.
    /// Chamado pelo botão Atualizar — força o usuário a refazer a seleção do zero.
    func clearSelection() {
        stopAllSecurityAccess()
        userSource         = nil
        referenceSource    = nil
        userVoiceHint      = nil
        referenceVoiceHint = nil
        activeTab          = 0
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Security-Scoped URL Helpers
    // ─────────────────────────────────────────────────────────────────────────

    /// Para o acesso security-scoped de uma source externa específica.
    /// Usado ao trocar a seleção — libera o acesso anterior antes de iniciar o novo.
    private func stopSecurityAccess(for source: AudioSource?) {
        guard case .external(let url) = source else { return }
        url.stopAccessingSecurityScopedResource()
        securityScopedURLs.remove(url)
    }

    /// Para todos os acessos security-scoped pendentes.
    /// Chamado após loadSamples() completar ou em reset().
    private func stopAllSecurityAccess() {
        securityScopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
        securityScopedURLs.removeAll()
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