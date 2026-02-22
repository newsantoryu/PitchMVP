//
//  MentorViewModel.swift
//  PitchMVP
//
//  Created by victor on 22/02/26.
//

import SwiftUI

final class MentorViewModel: ObservableObject {
    
    @Published var targetFrequency: Double = 440.0
    @Published var targetNote: String = "A4"
    
    @Published var feedback: PitchFeedback?
    
    func update(detectedFrequency: Double) {
        
        guard detectedFrequency > 0 else { return }
        
        let cents = 1200 * log2((detectedFrequency / targetFrequency))
        
        feedback = PitchFeedback(
            detectedFrequency: detectedFrequency,
            targetFrequency: targetFrequency,
            note: targetNote,
            cents: cents
        )
    }
}
