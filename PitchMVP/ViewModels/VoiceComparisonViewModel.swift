//
//  VoiceComparisonViewModel.swift
//  PitchMVP
//
//  Created by victor on 24/02/26.
//

// VoiceComparisonViewModel.swift
// PitchMVP
//
// Orquestra o fluxo completo de comparação:
//   1. Usuário seleciona "Minha Voz" (Bundle ou externo)
//   2. Usuário seleciona "Referência" (Bundle ou externo)
//   3. Toca "Comparar" → analisa referência → analisa voz → gera ComparisonResult

import Foundation
import SwiftUI

final class VoiceComparisonViewModel: ObservableObject {

    // MARK: - Seleção de arquivos

    /// Arquivo da voz do usuário (nome sem extensão se Bundle, nil se não selecionado)
    @Published var userFileName: String? = nil
    @Published var userFileURL: URL? = nil

    /// Arquivo de referência
    @Published var referenceFileName: String? = nil
    @Published var referenceFileURL: URL? = nil

    // MARK: - Estado da análise

    @Published var state: ComparisonState = .idle
    @Published var result: ComparisonResult? = nil

    // MARK: - Aba ativa (0 = Minha Voz, 1 = Referência)
    @Published var activeTab: Int = 0

    // MARK: - WAVs do Bundle
    let bundleFiles: [String] = ["voz", "voz2", "vozm1", "voz3", "voz5"]

    // MARK: - Dependências
    private let audioService = OfflineAudioFileService()
    private let segmenter    = NoteSegmenter()

    // MARK: - Computed

    var canCompare: Bool {
        resolvedUserURL != nil && resolvedReferenceURL != nil
    }

    var userDisplayName: String  { userFileName ?? "Não selecionado" }
    var refDisplayName: String   { referenceFileName ?? "Não selecionado" }

    private var resolvedUserURL: URL? {
        if let url = userFileURL { return url }
        if let name = userFileName {
            return Bundle.main.url(forResource: name, withExtension: "wav")
        }
        return nil
    }

    private var resolvedReferenceURL: URL? {
        if let url = referenceFileURL { return url }
        if let name = referenceFileName {
            return Bundle.main.url(forResource: name, withExtension: "wav")
        }
        return nil
    }

    // MARK: - Seleção Bundle

    func selectUserFromBundle(_ name: String) {
        userFileName = name
        userFileURL  = nil
        // Auto-avança para aba de referência
        withAnimation { activeTab = 1 }
    }

    func selectReferenceFromBundle(_ name: String) {
        referenceFileName = name
        referenceFileURL  = nil
    }

    // MARK: - Seleção Externa

    func selectUserExternal(url: URL) {
        userFileURL   = url
        userFileName  = url.deletingPathExtension().lastPathComponent
        withAnimation { activeTab = 1 }
    }

    func selectReferenceExternal(url: URL) {
        referenceFileURL   = url
        referenceFileName  = url.deletingPathExtension().lastPathComponent
    }

    // MARK: - Comparação

    /// Executa o pipeline completo de comparação em background.
    func startComparison() {
        guard let userURL = resolvedUserURL,
              let refURL  = resolvedReferenceURL else { return }

        state  = .analyzing(step: "Analisando referência...")
        result = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            do {
                // ── Passo 1: analisa referência ──────────────────────────────
                let (refSamples, refRate) = try self.audioService.loadSamples(from: refURL)
                let refSegments = self.segmenter.analyze(samples: refSamples, sampleRate: refRate)

                DispatchQueue.main.async {
                    self.state = .analyzing(step: "Analisando sua voz...")
                }

                // ── Passo 2: analisa voz do usuário ──────────────────────────
                let (userSamples, userRate) = try self.audioService.loadSamples(from: userURL)
                let userSegments = self.segmenter.analyze(samples: userSamples, sampleRate: userRate)

                DispatchQueue.main.async {
                    self.state = .analyzing(step: "Comparando notas...")
                }

                // ── Passo 3: casa notas por ordem cronológica ─────────────────
                let comparisons = self.buildComparisons(
                    user: userSegments,
                    reference: refSegments
                )

                let compResult = ComparisonResult(
                    comparisons: comparisons,
                    userSegments: userSegments,
                    referenceSegments: refSegments,
                    userFileName: self.userDisplayName,
                    referenceFileName: self.refDisplayName
                )

                DispatchQueue.main.async {
                    self.result = compResult
                    self.state  = compResult.totalPairs == 0 ? .empty : .done
                }

            } catch {
                DispatchQueue.main.async {
                    self.state = .error(error.localizedDescription)
                }
            }
        }
    }

    func reset() {
        result = nil
        state  = .idle
    }

    // MARK: - Matching por ordem cronológica

    /// Emparelha segmentos pelo índice: user[0] ↔ ref[0], user[1] ↔ ref[1], ...
    /// Se uma das listas for maior, os extras ficam com o par nil.
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