//
//  FrequencyEstimator.swift
//  PitchMVP
//
//  Created by victor on 21/02/26.
//
import Foundation

final class FrequencyEstimator {
    
    private let minFrequency: Float = 120
    private let maxFrequency: Float = 400
    
    func estimate(
        magnitudes: [Float],
        fftSize: Int,
        sampleRate: Float
    ) -> Float? {
        
        guard magnitudes.count > 0 else { return nil }
        
        let binResolution = sampleRate / Float(fftSize)
        
        let minIndex = Int(minFrequency / binResolution)
        let maxIndex = Int(maxFrequency / binResolution)
        
        var maxMagnitude: Float = 0
        var maxIndexFound: Int = 0
        
        let upperBound = min(maxIndex, magnitudes.count - 1)
        
        for i in minIndex...upperBound {
            if magnitudes[i] > maxMagnitude {
                maxMagnitude = magnitudes[i]
                maxIndexFound = i
            }
        }
        
        guard maxMagnitude > 0 else { return nil }
        
        let frequency = Float(maxIndexFound) * binResolution
        
        return frequency
    }
}