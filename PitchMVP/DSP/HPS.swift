//
//  HPS.swift
//  PitchMVP
//
//  Created by victor on 21/02/26.
//
struct HarmonicProductSpectrum {

    static func apply(
        to magnitudes: [Float],
        harmonics: Int = 3
    ) -> [Float] {

        var hps = magnitudes

        for h in 2...harmonics {
            for i in 0..<magnitudes.count {
                
                let harmonicIndex = i * h
                
                if harmonicIndex < magnitudes.count {
                    hps[i] *= magnitudes[harmonicIndex]
                } else {
                    break
                }
            }
        }

        return hps
    }
}