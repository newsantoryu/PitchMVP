//
//  SimulationMode.swift
//  PitchMVP
//
//  Created by victor on 22/02/26.
//
import SwiftUI
/// Define o comportamento do `SimulatedMentorEngine`.
/// Cada modo aplica uma função diferente de desvio em cents ao longo do tempo.
enum SimulationMode: String, CaseIterable, Identifiable {
    case grave    = "Grave"     // Sempre abaixo do alvo com leve oscilação
    case agudo    = "Agudo"     // Sempre acima do alvo com leve oscilação
    case instavel = "Instável"  // Oscila entre ±20 cents — difícil de afinar
    case estavel  = "Estável"   // Oscila apenas ±2 cents — voz controlada

    var id: String { rawValue }
}
