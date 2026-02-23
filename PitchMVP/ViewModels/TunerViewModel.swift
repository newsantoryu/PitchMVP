// TunerViewModel.swift
// PitchMVP

import Foundation

/// ViewModel da tela WAV Analyzer.
/// Gerencia a seleção de arquivos de áudio do Bundle e
/// coordena a análise de pitch usando `OfflineAudioFileService` + `VocalPitchDetector`.
///
/// Fluxo: usuário seleciona arquivo → `analyzeFile` → `OfflineAudioFileService.loadSamples`
///        → `VocalPitchDetector.detect` → publica `pitch` na main thread
final class TunerViewModel: ObservableObject {

    // MARK: - Output Publicado

    /// Resultado da última análise de pitch. `nil` enquanto nenhum arquivo foi analisado.
    @Published var pitch: PitchResult?

    /// Índice do arquivo atualmente selecionado na lista `musics`
    @Published var currentIndex = 0

    // MARK: - Catálogo de Arquivos

    /// Lista de nomes de arquivos WAV disponíveis no Bundle (sem extensão)
    let musics: [String] = ["voz", "voz2", "vozm1", "voz3", "voz5"]

    // MARK: - Dependências

    /// Carrega samples de arquivos de áudio locais
    private let audioService = OfflineAudioFileService()

    /// Detecta frequência fundamental a partir de um buffer de amostras
    private let detector = VocalPitchDetector()

    // MARK: - API Pública

    /// Analisa um arquivo de áudio e atualiza `pitch` com o resultado.
    /// A detecção roda de forma síncrona (potencialmente pesada para arquivos longos),
    /// mas publica o resultado na main thread para atualizar a UI com segurança.
    /// - Parameter url: URL local do arquivo WAV
    func analyzeFile(url: URL) {
        do {
            let result = try audioService.loadSamples(from: url)

            let pitchResult = detector.detect(
                buffer: result.samples,
                sampleRate: result.sampleRate
            )

            // Garante atualização da UI na thread principal
            DispatchQueue.main.async {
                self.pitch = pitchResult
            }

        } catch {
            print("[TunerViewModel] ❌ Erro ao processar arquivo:", error)
        }
    }

    /// Avança para o próximo arquivo da lista (circular) e o analisa automaticamente.
    func nextItem() {
        // Navegação circular: volta ao índice 0 após o último item
        currentIndex = (currentIndex + 1) % musics.count

        guard let url = Bundle.main.url(
            forResource: musics[currentIndex],
            withExtension: "wav"
        ) else {
            print("[TunerViewModel] ❌ Arquivo '\(musics[currentIndex]).wav' não encontrado no Bundle.")
            return
        }

        analyzeFile(url: url)
    }
}