import Foundation
import SwiftUI

final class TunerLabViewModel: ObservableObject {
    
    struct PitchTestResult: Identifiable {
        let id = UUID()
        let targetFrequency: Double
        let detectedFrequency: Double
        let note: String
        let cents: Double
        let pass: Bool
    }
    
    @Published var results: [PitchTestResult] = []
    
    private let detector = VocalPitchDetector()
    
    // Frequências de teste (Hz)
    let testFrequencies: [Double] = [110, 130.81, 220, 261.63, 440] // A2, C3, A3, C4, A4
    
    // Limite de tolerância (em cents)
    private let toleranceCents = 20.0
    
    func runPitchTests() {
        results.removeAll()
        
        for freq in testFrequencies {
            // Gerar buffer senoidal simples
            let sampleRate = 44100.0
            let duration = 1.0 // 1 segundo
            let samples = generateSineWave(frequency: freq, sampleRate: sampleRate, duration: duration)
            
            // Detectar pitch
            let detected = detector.detect(buffer: samples, sampleRate: sampleRate)
            
            // Converter para nota
            let (note, cents) = frequencyToNote(detected?.frequency ?? 0.0)
            
            // Validar tolerância
            let pass = abs(cents) <= toleranceCents
            
            // Salvar resultado
            let result = PitchTestResult(
                targetFrequency: freq,
                detectedFrequency: detected?.frequency ?? 0.0,
                note: note,
                cents: cents,
                pass: pass
            )
            
            results.append(result)
        }
    }
    
    // MARK: - Helpers
    
    private func generateSineWave(frequency: Double, sampleRate: Double, duration: Double) -> [Float] {
        let totalSamples = Int(sampleRate * duration)
        return (0..<totalSamples).map { i in
            Float(sin(2.0 * .pi * frequency * Double(i) / sampleRate))
        }
    }
    
    private func frequencyToNote(_ frequency: Double) -> (String, Double) {
        let a4 = 440.0
        let noteNumber = 12 * log2(frequency / a4) + 69
        let roundedNote = round(noteNumber)
        let cents = (noteNumber - roundedNote) * 100
        
        let noteNames = ["C", "C#", "D", "D#", "E", "F",
                         "F#", "G", "G#", "A", "A#", "B"]
        let index = Int(roundedNote) % 12
        let octave = Int(roundedNote) / 12 - 1
        
        return (noteNames[index] + "\(octave)", cents)
    }
}