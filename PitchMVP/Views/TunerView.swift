import SwiftUI

struct TunerView: View {
    
    @StateObject private var viewModel = TunerViewModel()
    @StateObject private var labViewModel = TunerLabViewModel()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
              MentorView()
              Divider()
                // MARK: Pitch Lab
                Text("PitchLabMode - Teste Profissional")
                    .font(.title2)
                
                Button("Run All Tests") {
                    labViewModel.runPitchTests()
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
                
                VStack(spacing: 8) {
                    ForEach(labViewModel.results, id: \.id) { (result: TunerLabViewModel.PitchTestResult) in
                        VStack(alignment: .leading, spacing: 4) {
                            
                            Text(result.label)
                                .font(.headline)
                            
                            Text("Target: \(String(format: "%.2f", result.targetFrequency)) Hz")
                            Text("Detected: \(String(format: "%.2f", result.detectedFrequency)) Hz")
                            
                            Text("Note: \(result.note)")
                            Text("Cents: \(String(format: "%.1f", result.cents))")
                            
                            Text(result.direction)
                                .font(.headline)
                                .foregroundStyle(result.isInTune ? .green : .orange)
                            Text(result.intensityHint)
                                .font(.headline)
                                .foregroundStyle(.red)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                
                Divider()
                
                // MARK: WAV Analyzer
                Text("Frequência Detectada")
                    .font(.title2)
                
                Text(String(format: "%.2f Hz", viewModel.pitch?.frequency ?? 0.0))
                    .font(.largeTitle)
                    .bold()
                
                Button("Trocar .wav") {
                    viewModel.nextItem()
                }
                
                Button("Analisar \(viewModel.musics[viewModel.currentIndex]).wav") {
                    if let url = Bundle.main.url(
                        forResource: viewModel.musics[viewModel.currentIndex],
                        withExtension: "wav"
                    ) {
                        viewModel.analyzeFile(url: url)
                    }
                }
            }
            .padding()
        }
    }
}
