import Foundation
import SwiftUI


    

final class TunerLabViewModel: ObservableObject {
    
        struct PitchTestResult: Identifiable {
        let id = UUID()
        let label: String
        let targetFrequency: Float
        let detectedFrequency: Float
        let note: String
        let cents: Double
        let pass: Bool
    }

    @Published var results: [PitchTestResult] = []
    
    private let detector = VocalPitchDetector()
    
    let maleFrequencies: [Float] = [110, 123.47, 130.81]
    let femaleFrequencies: [Float] = [261.63, 293.66, 329.63]
    
    private let toleranceCents = 20.0
    private let maleRange: ClosedRange<Float> = 85...180
    private let femaleRange: ClosedRange<Float> = 165...400
    
    func runPitchTests() {
        results.removeAll()
        let sampleRate: Float = 44100.0
        
        for freq in maleFrequencies {
            simulateVoiceTest(freq: freq, label: "Male", sampleRate: sampleRate, range: maleRange)
        }
        
        for freq in femaleFrequencies {
            simulateVoiceTest(freq: freq, label: "Female", sampleRate: sampleRate, range: femaleRange)
        }
    }
    
    private func simulateVoiceTest(freq: Float, label: String, sampleRate: Float, range: ClosedRange<Float>) {
        let variations: [Float] = [-5, 0, 5]
        
        for varFreq in variations {
            let testFreq = freq + varFreq
            let samples = generateSineWave(frequency: testFreq, sampleRate: sampleRate, duration: 1.0)
            
            guard let detected = detector.detect(buffer: samples, sampleRate: sampleRate, expectedRange: range) else { continue }
            
            let pass = abs(detected.cents) <= Float(toleranceCents)     
                   
            var result = PitchTestResult(
                label: "\(label) ±\(Int(varFreq))Hz",
                targetFrequency: testFreq,
                detectedFrequency: detected.frequency,
                note: detected.noteName,
                cents: Double(detected.cents),
                pass: pass
            )
            
            results.append(result)
        }
    }
    
    private func generateSineWave(frequency: Float, sampleRate: Float, duration: Float) -> [Float] {
        let totalSamples = Int(sampleRate * duration)
        return (0..<totalSamples).map { i in
            Float(sin(2.0 * .pi * frequency * Float(i) / sampleRate))
        }
    }
}
