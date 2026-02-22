//
//  MentorViewModel.swift
//  PitchMVP
//
//  Created by victor on 22/02/26.
//

import SwiftUI

final class MentorViewModel: ObservableObject {
    
    @Published var targetFrequency: Float = 440.0
    @Published var targetNote: String = "A4"
    
    @Published var feedback: PitchFeedback?
    
    func update(detectedFrequency: Float) {
        
        guard detectedFrequency > 0 else { return }
        
        let cents = 1200 * log2(Double(detectedFrequency / targetFrequency))
        
        feedback = PitchFeedback(
            detectedFrequency: detectedFrequency,
            targetFrequency: targetFrequency,
            note: targetNote,
            cents: cents
        )
    }
}