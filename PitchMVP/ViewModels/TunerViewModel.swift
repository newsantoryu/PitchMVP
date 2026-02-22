//
//  TunerViewModel.swift
//  PitchMVP
//
//  Created by victor on 21/02/26.
//

import Foundation

final class TunerViewModel: ObservableObject {
    
    @Published var pitch: PitchResult?
    
    private let audioService = OfflineAudioFileService()
    private let detector = VocalPitchDetector()
    
    func analyzeFile(url: URL) {
        
        do {
            let result = try audioService.loadSamples(from: url)
            
            let pitchResult = detector.detect(
                buffer: result.samples,
                sampleRate: result.sampleRate
            )
            
            DispatchQueue.main.async {
                self.pitch = pitchResult
            }
            
        } catch {
            print("Erro ao processar arquivo:", error)
        }
    }
}