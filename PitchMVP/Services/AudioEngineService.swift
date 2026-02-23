// AudioEngineService.swift
// PitchMVP

import AVFoundation

/// Serviço responsável por processar arquivos de áudio offline usando AVAudioEngine.
/// Usa modo de renderização manual (offline), o que evita latência de hardware
/// e permite análise determinística frame a frame.
final class AudioEngineService {

    // MARK: - Dependências AVAudio

    /// Engine principal — gerencia o grafo de nós de áudio
    private let engine = AVAudioEngine()

    /// Nó player — responsável por alimentar o grafo com o arquivo de áudio
    private let player = AVAudioPlayerNode()

    // MARK: - Callback

    /// Chamado a cada chunk de amostras processado durante a renderização offline.
    /// Recebe um array de Float com as amostras do canal 0 (mono/esquerdo).
    var onBuffer: (([Float]) -> Void)?

    // MARK: - API Pública

    /// Processa um arquivo de áudio do Bundle de forma offline (sem reprodução em tempo real).
    /// - Parameters:
    ///   - name: Nome do recurso no Bundle (sem extensão)
    ///   - ext: Extensão do arquivo (ex: "wav", "mp3")
    func processFileOffline(named name: String, withExtension ext: String) {

        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            print("[AudioEngineService] ❌ Arquivo '\(name).\(ext)' não encontrado no Bundle.")
            return
        }

        do {
            let file = try AVAudioFile(forReading: url)

            // Constrói o grafo: player → mixerNode
            engine.attach(player)
            engine.connect(player,
                           to: engine.mainMixerNode,
                           format: file.processingFormat)

            // Ativa modo offline — renderização manual, sem hardware de áudio
            try engine.enableManualRenderingMode(
                .offline,
                format: file.processingFormat,
                maximumFrameCount: 1024
            )

            // Agenda o arquivo inteiro para reprodução a partir do tempo 0
            player.scheduleFile(file, at: nil)
            try engine.start()
            player.play()

            // Buffer reutilizável para cada chunk de renderização (1024 frames)
            let buffer = AVAudioPCMBuffer(
                pcmFormat: engine.manualRenderingFormat,
                frameCapacity: 1024
            )!

            // Loop de renderização: avança frame a frame até o fim do arquivo
            while engine.manualRenderingSampleTime < file.length {

                // Calcula quantos frames ainda restam para não ultrapassar o arquivo
                let remaining = AVAudioFrameCount(file.length - engine.manualRenderingSampleTime)
                let framesToRender = min(buffer.frameCapacity, remaining)

                let status = try engine.renderOffline(framesToRender, to: buffer)

                // Apenas processa chunks renderizados com sucesso
                if status == .success,
                   let channelData = buffer.floatChannelData?[0] {

                    let frameLength = Int(buffer.frameLength)

                    // Copia ponteiro C para Array Swift de forma segura
                    let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
                    onBuffer?(samples)
                }
            }

            engine.stop()

        } catch {
            print("[AudioEngineService] ❌ Erro durante renderização offline:", error)
        }
    }
}