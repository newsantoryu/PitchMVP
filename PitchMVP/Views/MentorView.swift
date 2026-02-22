//
//  MentorView.swift
//  PitchMVP
//

import SwiftUI

struct MentorView: View {
    
    @StateObject private var mentorVM = MentorViewModel()
    @StateObject private var simulator = SimulatedMentorEngine()
    
    // MARK: Notas completas
    
    private let baseNotes = [
        "C", "C#", "D", "D#", "E",
        "F", "F#", "G", "G#", "A", "A#", "B"
    ]
    
    private let octaves = [2, 3, 4, 5]
    
    @State private var selectedBaseNote: String = "A"
    @State private var selectedOctave: Int = 4
    @State private var selectedMode: SimulationMode = .instavel
    
    var body: some View {
        VStack(spacing: 6) {
            
            // MARK: Nota
            
            Picker("Nota", selection: $selectedBaseNote) {
                ForEach(baseNotes, id: \.self) { note in
                    Text(note).tag(note)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedBaseNote) { _ in
                updateTarget()
            }
            
            // MARK: Oitava
            
            Picker("Oitava", selection: $selectedOctave) {
                ForEach(octaves, id: \.self) { octave in
                    Text("\(octave)").tag(octave)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedOctave) { _ in
                updateTarget()
            }
            
            // MARK: Modo
            
            Picker("Modo", selection: $selectedMode) {
                ForEach(SimulationMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedMode) { newMode in
                simulator.mode = newMode
            }
            
            // MARK: Target
            
            Text(mentorVM.targetNote)
                .font(.system(size: 60, weight: .bold))
            
            PitchMeterView(feedback: mentorVM.feedback)
            
            // MARK: Cents
            
            if let feedback = mentorVM.feedback {
                
                Text(String(format: "%.1f cents", feedback.cents))
                    .font(.title2)
                    .foregroundStyle(feedback.isInTune ? .green : .orange)
                
                Text(directionText(from: feedback))
                    .font(.headline)
                    .foregroundStyle(directionColor(from: feedback))
            }
        }
        .padding()
        .onAppear {
            updateTarget()
            simulator.start()
        }
        .onReceive(simulator.$simulatedFrequency) { freq in
            mentorVM.update(detectedFrequency: freq)
        }
        .onDisappear {
        simulator.stop()
         }
    }
    
    // MARK: Direção
    
    private func directionText(from feedback: PitchFeedback) -> String {
        if feedback.isInTune {
            return "Afinado 🎯"
        } else if feedback.cents < 0 {
            return "Grave ↓"
        } else {
            return "Agudo ↑"
        }
    }
    
    private func directionColor(from feedback: PitchFeedback) -> Color {
        if feedback.isInTune {
            return .green
        } else if feedback.cents < 0 {
            return .blue
        } else {
            return .red
        }
    }
    
    // MARK: Update Target
    
    private func updateTarget() {
        let noteName = "\(selectedBaseNote)\(selectedOctave)"
        let frequency = frequencyFor(note: selectedBaseNote, octave: selectedOctave)
        
        mentorVM.targetNote = noteName
        mentorVM.targetFrequency = frequency
        simulator.targetFrequency = frequency
    }
    
    // MARK: Frequency Calculation (com sustenidos)
    
    private func frequencyFor(note: String, octave: Int) -> Double {
        
        let noteOffsets: [String: Int] = [
            "C": -9,  "C#": -8,
            "D": -7,  "D#": -6,
            "E": -5,
            "F": -4,  "F#": -3,
            "G": -2,  "G#": -1,
            "A": 0,   "A#": 1,
            "B": 2
        ]
        
        guard let semitoneOffset = noteOffsets[note] else {
            return 440
        }
        
        let octaveOffset = (octave - 4) * 12
        let totalSemitones = semitoneOffset + octaveOffset
        
        return 440 * pow(2, Double(totalSemitones) / 12)
    }
}
