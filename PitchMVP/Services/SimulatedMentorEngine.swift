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

    var mode: SimulationMode = .instavel
    
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
    
    var centsOffset: Double = 0
    
    switch mode {
        
    case .grave:
        centsOffset = -25 + sin(time * 4) * 5
        
    case .agudo:
        centsOffset = 25 + sin(time * 4) * 5
        
    case .instavel:
        centsOffset = sin(time * 3) * 20
        
    case .estavel:
        centsOffset = sin(time * 6) * 2
    }
    
    simulatedFrequency = targetFrequency * pow(2, Float(centsOffset) / 1200)
}
}