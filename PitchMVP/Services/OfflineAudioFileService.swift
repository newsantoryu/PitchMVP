// OfflineAudioFileService.swift
// PitchMVP
//
// CORREÇÕES:
// 1. Suporte completo a arquivos estéreo (downmix L+R → mono) via AVAudioConverter
// 2. Normalização para 44100 Hz — garante que YIN e FFT operem com sample rate
//    consistente independentemente do formato original do arquivo
// 3. Tratamento de erros mais granular para facilitar debugging
//
// FIX v2:
// 4. Removido dead code no downmix estéreo: `AVAudioChannelLayout` era criado
//    mas nunca aplicado ao converter. `converter.downmix = true` é suficiente
//    e já faz a média L+R → mono corretamente via AVAudioConverter.

import AVFoundation

final class OfflineAudioFileService {

    // Sample rate alvo: YIN e FFT foram projetados e calibrados para 44100 Hz.
    // Arquivos gravados em 48000 Hz (câmeras, alguns apps) seriam analisados
    // com frequências ~9% erradas sem essa normalização.
    private let targetSampleRate: Double = 44100
    private let targetChannels: AVAudioChannelCount = 1  // sempre mono

    // MARK: - API Pública

    /// Carrega todas as amostras de um arquivo de áudio em memória,
    /// convertendo para mono 44100 Hz independentemente do formato original.
    ///
    /// Suporta:
    /// - Mono WAV/MP3/M4A (caminho direto, sem conversão)
    /// - Estéreo WAV/MP3/M4A (downmix L+R → mono com média via AVAudioConverter)
    /// - Sample rates diferentes (48000, 22050, etc.) → resample para 44100
    ///
    /// - Parameter url: URL local do arquivo
    /// - Returns: Tupla (amostras Float normalizadas [-1,1], sample rate = 44100)
    /// - Throws: `AudioLoadError` com descrição clara do problema
    func loadSamples(from url: URL) throws -> (samples: [Float], sampleRate: Float) {

        // 1. Abre o arquivo original no formato nativo
        let sourceFile: AVAudioFile
        do {
            sourceFile = try AVAudioFile(forReading: url)
        } catch {
            throw AudioLoadError.fileNotReadable(url: url, underlying: error)
        }

        let sourceFormat = sourceFile.processingFormat

        // 2. Define o formato alvo: mono, 44100 Hz, float32
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: targetChannels,
            interleaved: false
        ) else {
            throw AudioLoadError.formatCreationFailed
        }

        // 3. Verifica se conversão é necessária
        let needsConversion = sourceFormat.sampleRate != targetSampleRate
                           || sourceFormat.channelCount != targetChannels

        if !needsConversion {
            // Caminho rápido: lê diretamente sem converter
            return try readDirect(file: sourceFile)
        } else {
            // Caminho completo: usa AVAudioConverter para resample + downmix
            return try readWithConversion(
                file: sourceFile,
                sourceFormat: sourceFormat,
                targetFormat: targetFormat
            )
        }
    }

    // MARK: - Caminho Direto (mono + sample rate correto)

    private func readDirect(file: AVAudioFile) throws -> (samples: [Float], sampleRate: Float) {

        let frameCount = UInt32(file.length)

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: frameCount
        ) else {
            throw AudioLoadError.bufferAllocationFailed(frames: Int(frameCount))
        }

        do {
            try file.read(into: buffer)
        } catch {
            throw AudioLoadError.readFailed(underlying: error)
        }

        guard let channelData = buffer.floatChannelData else {
            throw AudioLoadError.noChannelData
        }

        let samples = Array(UnsafeBufferPointer(
            start: channelData[0],
            count: Int(buffer.frameLength)
        ))

        return (samples, Float(file.processingFormat.sampleRate))
    }

    // MARK: - Caminho com Conversão (estéreo e/ou sample rate diferente)

    private func readWithConversion(
        file: AVAudioFile,
        sourceFormat: AVAudioFormat,
        targetFormat: AVAudioFormat
    ) throws -> (samples: [Float], sampleRate: Float) {

        // Cria o converter — lida com downmix e resample automaticamente
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw AudioLoadError.converterCreationFailed(
                from: sourceFormat,
                to: targetFormat
            )
        }

        // FIX: apenas `downmix = true` é necessário para L+R → mono (média dos canais).
        // A criação de AVAudioChannelLayout que existia antes era dead code —
        // a variável era criada mas nunca atribuída ao converter.
        if sourceFormat.channelCount > 1 {
            converter.downmix = true
        }

        // Calcula tamanho estimado do buffer de saída após resample
        let ratio = targetSampleRate / sourceFormat.sampleRate
        let estimatedOutputFrames = AVAudioFrameCount(Double(file.length) * ratio) + 1024

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: estimatedOutputFrames
        ) else {
            throw AudioLoadError.bufferAllocationFailed(frames: Int(estimatedOutputFrames))
        }

        // Buffer de leitura do arquivo fonte — 4096 frames por chunk
        let inputChunkSize: AVAudioFrameCount = 4096
        var inputExhausted = false

        let status = try converter.convert(to: outputBuffer, error: nil) { _, outStatus in
            if inputExhausted {
                outStatus.pointee = .noDataNow
                return nil
            }

            guard let inputBuffer = AVAudioPCMBuffer(
                pcmFormat: sourceFormat,
                frameCapacity: inputChunkSize
            ) else {
                outStatus.pointee = .noDataNow
                return nil
            }

            do {
                try file.read(into: inputBuffer, frameCount: inputChunkSize)
            } catch {
                inputExhausted = true
                if inputBuffer.frameLength == 0 {
                    outStatus.pointee = .endOfStream
                    return nil
                }
            }

            if inputBuffer.frameLength == 0 {
                inputExhausted = true
                outStatus.pointee = .endOfStream
                return nil
            }

            outStatus.pointee = .haveData
            return inputBuffer
        }

        guard status == .haveData || outputBuffer.frameLength > 0 else {
            throw AudioLoadError.conversionFailed(status: status)
        }

        guard let channelData = outputBuffer.floatChannelData else {
            throw AudioLoadError.noChannelData
        }

        let samples = Array(UnsafeBufferPointer(
            start: channelData[0],
            count: Int(outputBuffer.frameLength)
        ))

        return (samples, Float(targetSampleRate))
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - AudioLoadError
// ─────────────────────────────────────────────────────────────────────────────

enum AudioLoadError: LocalizedError {

    case fileNotReadable(url: URL, underlying: Error)
    case formatCreationFailed
    case bufferAllocationFailed(frames: Int)
    case readFailed(underlying: Error)
    case noChannelData
    case converterCreationFailed(from: AVAudioFormat, to: AVAudioFormat)
    case conversionFailed(status: AVAudioConverterOutputStatus)

    var errorDescription: String? {
        switch self {
        case .fileNotReadable(let url, let err):
            return "Não foi possível ler '\(url.lastPathComponent)': \(err.localizedDescription)"
        case .formatCreationFailed:
            return "Falha ao criar formato de áudio alvo (mono 44100 Hz)."
        case .bufferAllocationFailed(let frames):
            return "Falha ao alocar buffer para \(frames) frames."
        case .readFailed(let err):
            return "Erro durante leitura do arquivo: \(err.localizedDescription)"
        case .noChannelData:
            return "Buffer sem dados de canal após leitura."
        case .converterCreationFailed(let from, let to):
            return "Não foi possível criar conversor de \(from.sampleRate)Hz/\(from.channelCount)ch → \(to.sampleRate)Hz/\(to.channelCount)ch."
        case .conversionFailed(let status):
            return "Conversão de áudio falhou com status \(status.rawValue)."
        }
    }
}