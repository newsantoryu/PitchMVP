//
//  BaseNote.swift
//  PitchMVP
//
//  Created by victor on 22/02/26.
//

import Foundation

struct BaseNote: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let baseFrequency: Float // frequência na oitava 4
}