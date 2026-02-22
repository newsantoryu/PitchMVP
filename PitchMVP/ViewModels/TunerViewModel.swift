//
//  TunerViewModel.swift
//  PitchMVP
//
//  Created by victor on 21/02/26.
//

import Foundation

final class TunerViewModel: ObservableObject {
    
    @Published var pitch: PitchResult?
    @Published  var currentIndex = 0

    let musics:[String] = ["voz", "voz2", "voz3", "voz5"] 

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

        
         func nextItem() {
        // Se estiver no último, volta para o primeiro (0)
        if currentIndex < musics.count - 1 {
            currentIndex += 1
        } else {
            currentIndex = 0
        }
        if let url = Bundle.main.url(
                forResource: musics[currentIndex], 
                withExtension: "wav"
                ) {
                    analyzeFile(url: url) 
                  } else {
                        print("Arquivo não encontrado no Bundle")
                    }
    }
}