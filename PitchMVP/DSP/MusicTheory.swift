//
//  MusicTheory.swift
//  PitchMVP
//
//  Created by victor on 21/02/26.
//

import Foundation

struct MusicTheory {
    
    private static let noteNames = [
        "C", "C#", "D", "D#",
        "E", "F", "F#",
        "G", "G#", "A",
        "A#", "B"
    ]
    
    static func analyze(frequency: Float) -> PitchResult? {
        
        guard frequency > 0 else { return nil }
        
        let midi = 69 + 12 * log2(frequency / 440)
        let roundedMidi = round(midi)
        
        let cents = (midi - roundedMidi) * 100
        
        let noteIndex = Int(roundedMidi) % 12
        let octave = Int(roundedMidi) / 12 - 1
        
        let name = noteNames[noteIndex] + "\(octave)"
        let object = PitchResult(frequency: 0.0, midNote: 0.0, noteName: "#", cents: 0.0 )
        
        return PitchResult(
            frequency: frequency,
            midNote: midi,
            noteName: name,
            cents: cents
        )
    }
}
