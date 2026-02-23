// OfflineAudioFileService.swift
// PitchMVP

import AVFoundation

/// Serviço que carrega amostras de áudio de um arquivo local de forma síncrona.
/// Diferente do AudioEngineService (que usa AVAudioEngine com renderização manual),
/// este serviço lê o arquivo diretamente via AVAudioFile — mais simples e adequado
/// para análise offline de arquivos curtos.
final class OfflineAudioFileService {

    // MARK: - API Pública

    /// Carrega todas as amostras de um arquivo de áudio em memória.
    /// - Parameter url: URL local do arquivo (ex: obtida via Bundle.main.url)
    /// - Returns: Tupla com array de amostras Float (canal 0) e sample rate em Hz
    /// - Throws: Erros de leitura do AVAudioFile ou alocação de buffer
    func loadSamples(from url: URL) throws -> (samples: [Float], sampleRate: Float) {

        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = UInt32(file.length)

        // Aloca buffer com capacidade exata para o arquivo inteiro
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            // Retorno seguro em vez de fatalError — permite tratamento no caller
            return ([], 0)
        }

        // Leitura síncrona de todos os frames em uma única operação
        try file.read(into: buffer)

        guard let channelData = buffer.floatChannelData else {
            return ([], 0)
        }

        // Usa apenas canal 0 (mono ou canal esquerdo do estéreo)
        let samples = Array(UnsafeBufferPointer(
            start: channelData[0],
            count: Int(buffer.frameLength)
        ))

        return (samples, Float(format.sampleRate))
    }
}