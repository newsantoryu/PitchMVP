//
//  SimulationMode.swift
//  PitchMVP
//
//  Created by victor on 22/02/26.
//

enum SimulationMode: String, CaseIterable, Identifiable {
    case grave = "Grave"
    case agudo = "Agudo"
    case instavel = "Instável"
    case estavel = "Estável"
    
    var id: String { rawValue }
}