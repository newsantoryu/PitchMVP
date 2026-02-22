import Foundation

final class VocalPitchDetector {
    
    private let fftSize = 4096
    private let fftProcessor: FFTProcessor
    private let estimator = FrequencyEstimator()
    
    init() {
        self.fftProcessor = FFTProcessor(size: fftSize)
    }
    
    func detect(buffer: [Float], sampleRate: Float, expectedRange: ClosedRange<Float>? = nil) -> PitchResult? {
        
        guard buffer.count >= fftSize else { return nil }
        
        let startIndex = buffer.count / 2
        let safeStart = max(0, startIndex - fftSize / 2)
        var slice = Array(buffer[safeStart..<safeStart + fftSize])
        
        Windowing.applyHann(to: &slice)
        
        var magnitudes = fftProcessor.performFFT(input: slice)
        magnitudes = magnitudes.map { sqrt($0) }
        
        let hpsMagnitudes = HarmonicProductSpectrum.apply(to: magnitudes, harmonics: 3)
        
        guard var frequency = estimator.estimate(
            magnitudes: hpsMagnitudes,
            fftSize: fftSize,
            sampleRate: sampleRate
        ) else { return nil }
        
        // 🔹 Correção de subharmônicos / faixa esperada
        if let range = expectedRange {
            while frequency < range.lowerBound { frequency *= 2 }
            while frequency > range.upperBound { frequency /= 2 }
        }
        
        return MusicTheory.analyze(frequency: frequency)
    }
}