import SwiftUI

struct TunerView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
                 VoiceComparisonView()
                .tabItem { Label("Comparar", systemImage: "arrow.triangle.2.circlepath") }
                 .tag(0)
        LyricsAnalysisView()
                .tabItem {
                    Label("Cifra", systemImage: "music.note.list")
                }
                .tag(1)

            WAVAnalyzerView()
                .tabItem {
                    Label("Analisador", systemImage: "waveform")
                }
                .tag(2)
            SessionHistoryView()
                .tabItem {
                    Label("Analisador", systemImage: "clock.arrow.circlepath")
                }
                .tag(3)
            SegmentAnalysisView()
               .tabItem {
                     Label("Notas", systemImage: "music.note.list")
                }
               .tag(4)

                        MentorView()
                .tabItem {
                    Label("Mentor", systemImage: "music.note")
                }
                .tag(5)

        }
        .tint(Color.accentColor)
    }
}

