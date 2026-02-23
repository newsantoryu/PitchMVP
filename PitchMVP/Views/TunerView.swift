import SwiftUI

struct TunerView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            MentorView()
                .tabItem {
                    Label("Mentor", systemImage: "music.note")
                }
                .tag(0)

            PitchLabView()
                .tabItem {
                    Label("Lab", systemImage: "waveform.path.ecg")
                }
                .tag(1)

            WAVAnalyzerView()
                .tabItem {
                    Label("Analisador", systemImage: "waveform")
                }
                .tag(2)
        }
        .tint(Color.accentColor)
    }
}