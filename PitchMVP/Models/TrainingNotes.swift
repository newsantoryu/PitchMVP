//
//  TrainingNotes.swift
//  PitchMVP
//
//  Created by victor on 22/02/26.
//
import Foundation

struct TrainingNote: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let frequency: Float
}