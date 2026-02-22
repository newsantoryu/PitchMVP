//
//  AudioEngineService.swift
//  PitchMVP
//
//  Created by victor on 21/02/26.
//

import AVFoundation

final class AudioEngineService {
    
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    
    var onBuffer: (([Float]) -> Void)?
    
    func processFileOffline(named name: String, withExtension ext: String) {
        
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            print("Arquivo não encontrado")
            return
        }
        
        do {
            let file = try AVAudioFile(forReading: url)
            
            engine.attach(player)
            engine.connect(player,
                           to: engine.mainMixerNode,
                           format: file.processingFormat)
            
            try engine.enableManualRenderingMode(.offline,
                                                 format: file.processingFormat,
                                                 maximumFrameCount: 1024)
            
            player.scheduleFile(file, at: nil)
            try engine.start()
            player.play()
            
            let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat,
                                          frameCapacity: 1024)!
            
            while engine.manualRenderingSampleTime < file.length {
                
                let framesToRender = min(buffer.frameCapacity,
                                         AVAudioFrameCount(file.length - engine.manualRenderingSampleTime))
                
                let status = try engine.renderOffline(framesToRender, to: buffer)
                
                if status == .success,
                   let channelData = buffer.floatChannelData?[0] {
                    
                    let frameLength = Int(buffer.frameLength)
                    let samples = Array(UnsafeBufferPointer(start: channelData,
                                                            count: frameLength))
                    
                    onBuffer?(samples)
                }
            }
            
            engine.stop()
            
        } catch {
            print("Erro:", error)
        }
    }
}