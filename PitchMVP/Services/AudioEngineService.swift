// AudioEngineService.swift
// PitchMVP
//
// FIX v2:
// • AVAudioPlayerNode.attach movido para o init — evita double-attach em
//   chamadas repetidas a processFileOffline, que causava comportamento
//   indefinido e potencial crash no AVAudioEngine.
// • engine.stop() + engine.reset() antes de cada nova renderização —
//   garante estado limpo entre chamadas consecutivas sem recriar o grafo.
// • Formato de conexão agora derivado do arquivo (processingFormat) —
//   mesma lógica anterior, porém aplicada uma única vez no connect.

import AVFoundation

final class AudioEngineService {

    // MARK: - Dependências AVAudio

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()

    // MARK: - Callback

    var onBuffer: (([Float]) -> Void)?

    // MARK: - Init

    /// Constrói o grafo uma única vez.
    /// player → mainMixerNode é reconectado em cada processamento
    /// para suportar arquivos com formatos diferentes entre chamadas.
    init() {
        engine.attach(player)
    }

    // MARK: - API Pública

    /// Processa um arquivo de áudio do Bundle de forma offline.
    /// Seguro para múltiplas chamadas consecutivas.
    func processFileOffline(named name: String, withExtension ext: String) {

        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            print("[AudioEngineService] ❌ Arquivo '\(name).\(ext)' não encontrado no Bundle.")
            return
        }

        do {
            let file = try AVAudioFile(forReading: url)

            // Para e reseta o engine antes de reconfigurar o grafo —
            // necessário para trocar o formato de conexão entre chamadas.
            if engine.isRunning {
                engine.stop()
            }
            engine.reset()

            // Reconecta player com o formato do arquivo atual.
            // engine.reset() desconecta os nós, por isso o connect é repetido aqui.
            engine.connect(player,
                           to: engine.mainMixerNode,
                           format: file.processingFormat)

            try engine.enableManualRenderingMode(
                .offline,
                format: file.processingFormat,
                maximumFrameCount: 1024
            )

            player.scheduleFile(file, at: nil)
            try engine.start()
            player.play()

            let buffer = AVAudioPCMBuffer(
                pcmFormat: engine.manualRenderingFormat,
                frameCapacity: 1024
            )!

            while engine.manualRenderingSampleTime < file.length {

                let remaining = AVAudioFrameCount(
                    file.length - engine.manualRenderingSampleTime
                )
                let framesToRender = min(buffer.frameCapacity, remaining)

                let status = try engine.renderOffline(framesToRender, to: buffer)

                if status == .success,
                   let channelData = buffer.floatChannelData?[0] {

                    let frameLength = Int(buffer.frameLength)
                    let samples = Array(
                        UnsafeBufferPointer(start: channelData, count: frameLength)
                    )
                    onBuffer?(samples)
                }
            }

            engine.stop()

        } catch {
            print("[AudioEngineService] ❌ Erro durante renderização offline:", error)
        }
    }
}