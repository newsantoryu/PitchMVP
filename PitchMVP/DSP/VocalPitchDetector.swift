//
//  VocalPitchDetector.swift
//  PitchMVP
//
//  Created by victor on 21/02/26.
//
//
//  VocalPitchDetector.swift
//  PitchMVP
//

import SwiftUI

final class VocalPitchDetector {
    
    private let fftSize = 4096
    private let fftProcessor: FFTProcessor
    private let estimator = FrequencyEstimator()
    
    init() {
        self.fftProcessor = FFTProcessor(size: fftSize)
    }
    
    func detect(buffer: [Float], sampleRate: Float) -> PitchResult? {
        
        guard buffer.count >= fftSize else { return nil }
        
        // 🔹 Pegando frame do meio (melhor para offline)
        let startIndex = buffer.count / 2
        let safeStart = max(0, startIndex - fftSize / 2)
        var slice = Array(buffer[safeStart..<safeStart + fftSize])
        
        // 🔹 Aplicar janela
        Windowing.applyHann(to: &slice)
        
        // 🔹 FFT (retorna power spectrum)
        var magnitudes = fftProcessor.performFFT(input: slice)
        
        // 🔹 Converter power → magnitude real
        magnitudes = magnitudes.map { sqrt($0) }
        
        // 🔹 Aplicar HPS (corrige sub-harmônico)
        let hpsMagnitudes = HarmonicProductSpectrum.apply(
            to: magnitudes,
            harmonics: 3
        )
        
        // 🔹 Estimar frequência
        guard let frequency = estimator.estimate(
            magnitudes: hpsMagnitudes,
            fftSize: fftSize,
            sampleRate: sampleRate
        ) else {
            return nil
        }
        
        return MusicTheory.analyze(frequency: frequency)
    }
}