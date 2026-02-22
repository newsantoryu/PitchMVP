//
//  MentorView.swift
//  PitchMVP
//
//  Created by victor on 22/02/26.
//

import SwiftUI

struct MentorView: View {
    
    @StateObject private var mentorVM = MentorViewModel()
    @StateObject private var simulator = SimulatedMentorEngine()
    
    // MARK: Training Notes
    
    private let trainingNotes: [TrainingNote] = [
        TrainingNote(name: "C4", frequency: 261.63),
        TrainingNote(name: "D4", frequency: 293.66),
        TrainingNote(name: "E4", frequency: 329.63),
        TrainingNote(name: "F4", frequency: 349.23),
        TrainingNote(name: "G4", frequency: 392.00),
        TrainingNote(name: "A4", frequency: 440.00),
        TrainingNote(name: "B4", frequency: 493.88),
        TrainingNote(name: "C5", frequency: 523.25)
    ]
    
    @State private var selectedNote: TrainingNote
    @State private var selectedMode: SimulationMode = .instavel
    
    // MARK: Init
    
    init() {
        let defaultNote = TrainingNote(name: "A4", frequency: 440.00)
        _selectedNote = State(initialValue: defaultNote)
    }
    
    var body: some View {
        VStack(spacing: 30) {
            
            // MARK: Note Selection
            
            Picker("Nota", selection: $selectedNote) {
                ForEach(trainingNotes) { note in
                    Text(note.name).tag(note)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedNote) { newNote in
                updateTarget(note: newNote)
            }
            
            // MARK: Simulation Mode
            
            Picker("Modo", selection: $selectedMode) {
                ForEach(SimulationMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedMode) { newMode in
                simulator.mode = newMode
            }
            
            // MARK: Target Note
            
            Text(mentorVM.targetNote)
                .font(.system(size: 60, weight: .bold))
            
            // MARK: Pitch Meter
            
            PitchMeterView(feedback: mentorVM.feedback)
            
            // MARK: Cents
            
            if let cents = mentorVM.feedback?.cents {
                Text(String(format: "%.1f cents", cents))
                    .font(.title2)
                    .foregroundStyle(mentorVM.feedback?.isInTune == true ? .green : .orange)
            }
        }
        .padding()
        .onAppear {
            updateTarget(note: selectedNote)
            simulator.start()
        }
        .onReceive(simulator.$simulatedFrequency) { freq in
            mentorVM.update(detectedFrequency: freq)
        }
    }
    
    private func updateTarget(note: TrainingNote) {
        mentorVM.targetFrequency = note.frequency
        mentorVM.targetNote = note.name
        simulator.targetFrequency = note.frequency
    }
}