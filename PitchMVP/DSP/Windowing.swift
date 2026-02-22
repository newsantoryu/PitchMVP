//
//  Windowing.swift
//  PitchMVP
//
//  Created by victor on 21/02/26.
//

import Accelerate

struct Windowing {
    
    static func applyHann(to buffer: inout [Float]) {
        
        var window = [Float](repeating: 0, count: buffer.count)
        
        vDSP_hann_window(
            &window,
            vDSP_Length(buffer.count),
            Int32(vDSP_HANN_NORM)
        )
        
        vDSP_vmul(
            buffer,
            1,
            window,
            1,
            &buffer,
            1,
            vDSP_Length(buffer.count)
        )
    }
}