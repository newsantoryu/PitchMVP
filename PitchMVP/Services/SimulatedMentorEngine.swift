//
//  SimulatedMentorEngine.swift
//  PitchMVP
//
//  Created by victor on 22/02/26.
//

import Foundation
import Combine

final class SimulatedMentorEngine: ObservableObject {
    
    @Published var simulatedFrequency: Float = 0
    
    private var timer: Timer?
    private var time: Double = 0
    
    var targetFrequency: Float = 440.0
    
    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            self.tick()
        }
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
    }
    
    private func tick() {
        time += 0.05
        
        // aproximação gradual
        let approach = sin(time * 0.5) * 10
        
        // oscilação natural leve
        let vibrato = sin(time * 6) * 3
        
        // começa desafinado e converge
        let drift = max(0, 30 - time * 5)
        
        let centsOffset = approach + vibrato - drift
        
        simulatedFrequency = targetFrequency * pow(2, Float(centsOffset) / 1200)
    }
}