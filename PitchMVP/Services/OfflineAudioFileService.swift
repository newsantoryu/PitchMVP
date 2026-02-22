//
//  OfflineAudioFileService.swift
//  PitchMVP
//
//  Created by victor on 21/02/26.
//

import AVFoundation

final class OfflineAudioFileService {
    
    func loadSamples(from url: URL) throws -> (samples: [Float], sampleRate: Float) {
        
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = UInt32(file.length)
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: frameCount) else {
            return ([], 0)
        }
        
        try file.read(into: buffer)
        
        guard let channelData = buffer.floatChannelData else {
            return ([], 0)
        }
        
        let samples = Array(UnsafeBufferPointer(
            start: channelData[0],
            count: Int(buffer.frameLength)
        ))
        
        return (samples, Float(format.sampleRate))
    }
}