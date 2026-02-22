//
//  FFTProcessor.swift
//  PitchMVP
//
//  Created by victor on 21/02/26.
//

import Accelerate
import Foundation

final class FFTProcessor {
    
    private let fftSetup: FFTSetup
    private let log2n: vDSP_Length
    private let fftSize: Int
    private let halfSize: Int
    
    init(size: Int) {
        self.fftSize = size
        self.halfSize = size / 2
        self.log2n = vDSP_Length(log2(Float(size)))
        
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            fatalError("Erro ao criar FFT setup")
        }
        
        self.fftSetup = setup
    }
    
    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }
    
    func performFFT(input: [Float]) -> [Float] {
        
        var real = input
        var imag = [Float](repeating: 0, count: fftSize)
        
        var splitComplex = DSPSplitComplex(
            realp: &real,
            imagp: &imag
        )
        
        // Executa FFT in-place
        vDSP_fft_zip(
            fftSetup,
            &splitComplex,
            1,
            log2n,
            FFTDirection(FFT_FORWARD)
        )
        
        // Magnitude (power spectrum)
        var magnitudes = [Float](repeating: 0, count: halfSize)
        
        vDSP_zvmags(
            &splitComplex,
            1,
            &magnitudes,
            1,
            vDSP_Length(halfSize)
        )
        
        return magnitudes
    }

    func computeMagnitudes(real: [Float], imag: [Float]) -> [Float] {

    var magnitudes: [Float] = []

    for i in 0..<real.count {
        let mag = sqrt(real[i] * real[i] + imag[i] * imag[i])
        magnitudes.append(mag)
    }

    return magnitudes
}
}