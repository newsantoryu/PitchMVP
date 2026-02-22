//
//  PitchFeedback.swift
//  PitchMVP
//
//  Created by victor on 22/02/26.
//

import Foundation

struct PitchFeedback {
    let detectedFrequency: Float
    let targetFrequency: Float
    let note: String
    let cents: Double

    var isInTune: Bool {
        abs(cents) < 5
    }

    var nomalizedOffset: Double {
        max(min(cents / 50, 1), -1)
    }
}