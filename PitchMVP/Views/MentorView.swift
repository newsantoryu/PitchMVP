// MentorView.swift
// PitchMVP — Refatorado

import SwiftUI

struct MentorView: View {

    @StateObject private var mentorVM = MentorViewModel()
    @StateObject private var simulator = SimulatedMentorEngine()

    private let baseNotes = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    private let octaves = [2, 3, 4, 5]

    @State private var selectedBaseNote: String = "A"
    @State private var selectedOctave: Int = 4
    @State private var selectedMode: SimulationMode = .instavel

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                VStack(spacing: 0) {

                    // MARK: Header
                    VStack(spacing: 4) {
                        Text("Mentor")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .tracking(3)
                            .foregroundStyle(.secondary)

                        Text(mentorVM.targetNote)
                            .font(.system(size: 96, weight: .thin, design: .rounded))
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(.spring(duration: 0.3), value: mentorVM.targetNote)
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 32)

                    // MARK: Pitch Meter
                    PitchMeterView(feedback: mentorVM.feedback)
                        .padding(.bottom, 24)

                    // MARK: Cents + Direction
                    Group {
                        if let feedback = mentorVM.feedback {
                            VStack(spacing: 6) {
                                Text(String(format: "%.1f¢", feedback.cents))
                                    .font(.system(size: 28, weight: .light, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(feedback.isInTune ? Color.green : Color.primary)
                                    .animation(.easeOut(duration: 0.1), value: feedback.cents)

                                Text(directionText(from: feedback))
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .tracking(2)
                                    .foregroundStyle(directionColor(from: feedback))
                            }
                        } else {
                            VStack(spacing: 6) {
                                Text("—")
                                    .font(.system(size: 28, weight: .light, design: .rounded))
                                    .foregroundStyle(.tertiary)
                                Text("AGUARDANDO")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .tracking(2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .frame(height: 64)
                    .padding(.bottom, 40)

                    Divider().padding(.horizontal, 32)

                    // MARK: Controls
                    VStack(spacing: 0) {
                        PickerRow(label: "NOTA") {
                            Picker("Nota", selection: $selectedBaseNote) {
                                ForEach(baseNotes, id: \.self) { note in
                                    Text(note).tag(note)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.primary)
                        }
                        .onChange(of: selectedBaseNote) { _ in updateTarget() }

                        Divider().padding(.leading, 16)

                        PickerRow(label: "OITAVA") {
                            Picker("Oitava", selection: $selectedOctave) {
                                ForEach(octaves, id: \.self) { octave in
                                    Text("\(octave)").tag(octave)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.primary)
                        }
                        .onChange(of: selectedOctave) { _ in updateTarget() }

                        Divider().padding(.leading, 16)

                        PickerRow(label: "MODO") {
                            Picker("Modo", selection: $selectedMode) {
                                ForEach(SimulationMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.primary)
                        }
                        .onChange(of: selectedMode) { newMode in
                            simulator.mode = newMode
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 24)

                    Spacer()
                }
            }
            .navigationBarHidden(true)
        }
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

    // MARK: Helpers

    private func directionText(from feedback: PitchFeedback) -> String {
        if feedback.isInTune { return "AFINADO" }
        return feedback.cents < 0 ? "GRAVE" : "AGUDO"
    }

    private func directionColor(from feedback: PitchFeedback) -> Color {
        if feedback.isInTune { return .green }
        return feedback.cents < 0 ? Color(.systemBlue) : Color(.systemOrange)
    }

    private func updateTarget() {
        let noteName = "\(selectedBaseNote)\(selectedOctave)"
        let frequency = frequencyFor(note: selectedBaseNote, octave: selectedOctave)
        mentorVM.targetNote = noteName
        mentorVM.targetFrequency = frequency
        simulator.targetFrequency = frequency
    }

    private func frequencyFor(note: String, octave: Int) -> Double {
        let noteOffsets: [String: Int] = [
            "C": -9, "C#": -8, "D": -7, "D#": -6, "E": -5,
            "F": -4, "F#": -3, "G": -2, "G#": -1,
            "A":  0, "A#":  1, "B":  2
        ]
        guard let offset = noteOffsets[note] else { return 440 }
        let semitones = offset + (octave - 4) * 12
        return 440 * pow(2, Double(semitones) / 12)
    }
}

// MARK: PickerRow helper

struct PickerRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(.secondary)
            Spacer()
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}