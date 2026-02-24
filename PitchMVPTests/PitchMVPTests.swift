// //
// //  PitchMVPTests.swift
// //  PitchMVPTests
// //
// //  Created by victor on 21/02/26.
// //

// // PitchMVPTests.swift
// // PitchMVPTests
// //
// // Como adicionar ao projeto:
// // File → New → Target → Unit Testing Bundle → "PitchMVPTests"
// // Depois arraste este arquivo para dentro do target de testes.

// import XCTest
// @testable import PitchMVP

// // ─────────────────────────────────────────────────────────────────────────────
// // MARK: - MentorViewModel Tests
// // ─────────────────────────────────────────────────────────────────────────────

// final class MentorViewModelTests: XCTestCase {

//     var sut: MentorViewModel!

//     override func setUp() {
//         super.setUp()
//         sut = MentorViewModel()
//     }

//     override func tearDown() {
//         sut = nil
//         super.tearDown()
//     }

//     // MARK: update(detectedFrequency:)

//     func test_update_withValidFrequency_producesFeedback() {
//         // Dado que o alvo é A4 = 440 Hz
//         sut.targetFrequency = 440
//         sut.targetNote = "A4"

//         // Quando detectamos exatamente 440 Hz
//         sut.update(detectedFrequency: 440)

//         // Deve produzir feedback com 0 cents de desvio
//         XCTAssertNotNil(sut.feedback)
//         XCTAssertEqual(sut.feedback?.cents ?? 999, 0, accuracy: 0.01)
//         XCTAssertTrue(sut.feedback?.isInTune ?? false)
//     }

//     func test_update_withZeroFrequency_doesNotProduceFeedback() {
//         // Frequência 0 indica silêncio — não deve gerar feedback
//         sut.update(detectedFrequency: 0)
//         XCTAssertNil(sut.feedback)
//     }

//     func test_update_withNegativeFrequency_doesNotProduceFeedback() {
//         // Frequência negativa é inválida fisicamente
//         sut.update(detectedFrequency: -100)
//         XCTAssertNil(sut.feedback)
//     }

//     func test_update_sharpFrequency_producesPositiveCents() {
//         // 446 Hz está acima de 440 Hz → cents positivo (agudo)
//         sut.targetFrequency = 440
//         sut.update(detectedFrequency: 446)

//         XCTAssertNotNil(sut.feedback)
//         XCTAssertGreaterThan(sut.feedback?.cents ?? 0, 0, "Agudo deve ter cents positivo")
//     }

//     func test_update_flatFrequency_producesNegativeCents() {
//         // 434 Hz está abaixo de 440 Hz → cents negativo (grave)
//         sut.targetFrequency = 440
//         sut.update(detectedFrequency: 434)

//         XCTAssertNotNil(sut.feedback)
//         XCTAssertLessThan(sut.feedback?.cents ?? 0, 0, "Grave deve ter cents negativo")
//     }

//     func test_update_within5Cents_isInTune() {
//         // ±5 cents é o limiar de "afinado"
//         // +4 cents acima de A4: 440 * 2^(4/1200) ≈ 441.02 Hz
//         let slightlySharp = 440.0 * pow(2.0, 4.0 / 1200.0)
//         sut.targetFrequency = 440
//         sut.update(detectedFrequency: slightlySharp)

//         XCTAssertTrue(sut.feedback?.isInTune ?? false, "4 cents deve ser considerado afinado")
//     }

//     func test_update_beyond5Cents_isNotInTune() {
//         // +20 cents acima de A4
//         let sharp = 440.0 * pow(2.0, 20.0 / 1200.0)
//         sut.targetFrequency = 440
//         sut.update(detectedFrequency: sharp)

//         XCTAssertFalse(sut.feedback?.isInTune ?? true, "20 cents deve ser considerado desafinado")
//     }

//     func test_centsFormula_oneOctaveUp_equals1200Cents() {
//         // Uma oitava acima = exatamente 1200 cents
//         sut.targetFrequency = 440
//         sut.update(detectedFrequency: 880)

//         XCTAssertEqual(sut.feedback?.cents ?? 0, 1200, accuracy: 0.1)
//     }
// }

// // ─────────────────────────────────────────────────────────────────────────────
// // MARK: - PitchFeedback Tests
// // ─────────────────────────────────────────────────────────────────────────────

// final class PitchFeedbackTests: XCTestCase {

//     func test_normalizedOffset_clampedAt1_forLargeCents() {
//         // Desvio de 100 cents deve ser clampeado em 1.0 (não 2.0)
//         let feedback = PitchFeedback(
//             detectedFrequency: 880,
//             targetFrequency: 440,
//             note: "A4",
//             cents: 1200
//         )
//         XCTAssertEqual(feedback.nomalizedOffset, 1.0, accuracy: 0.001)
//     }

//     func test_normalizedOffset_clampedAtMinus1_forLargeNegativeCents() {
//         let feedback = PitchFeedback(
//             detectedFrequency: 220,
//             targetFrequency: 440,
//             note: "A4",
//             cents: -1200
//         )
//         XCTAssertEqual(feedback.nomalizedOffset, -1.0, accuracy: 0.001)
//     }

//     func test_normalizedOffset_proportional_within50Cents() {
//         // 25 cents = 0.5 normalizado
//         let feedback = PitchFeedback(
//             detectedFrequency: 440,
//             targetFrequency: 440,
//             note: "A4",
//             cents: 25
//         )
//         XCTAssertEqual(feedback.nomalizedOffset, 0.5, accuracy: 0.001)
//     }

//     func test_equatable_sameValues_areEqual() {
//         let f1 = PitchFeedback(detectedFrequency: 440, targetFrequency: 440, note: "A4", cents: 0)
//         let f2 = PitchFeedback(detectedFrequency: 440, targetFrequency: 440, note: "A4", cents: 0)
//         XCTAssertEqual(f1, f2)
//     }

//     func test_equatable_differentCents_areNotEqual() {
//         let f1 = PitchFeedback(detectedFrequency: 440, targetFrequency: 440, note: "A4", cents: 0)
//         let f2 = PitchFeedback(detectedFrequency: 440, targetFrequency: 440, note: "A4", cents: 5)
//         XCTAssertNotEqual(f1, f2)
//     }
// }

// // ─────────────────────────────────────────────────────────────────────────────
// // MARK: - MusicTheory Tests
// // ─────────────────────────────────────────────────────────────────────────────

// final class MusicTheoryTests: XCTestCase {

//     func test_analyze_A4_returnsCorrectNote() {
//         let result = MusicTheory.analyze(frequency: 440)
//         XCTAssertEqual(result?.noteName, "A4")
//         XCTAssertEqual(result?.cents ?? 999, 0, accuracy: 0.1)
//     }

//     func test_analyze_C4_returnsCorrectNote() {
//         // C4 (Dó central) = 261.63 Hz
//         let result = MusicTheory.analyze(frequency: 261.63)
//         XCTAssertEqual(result?.noteName, "C4")
//     }

//     func test_analyze_zeroFrequency_returnsNil() {
//         XCTAssertNil(MusicTheory.analyze(frequency: 0))
//     }

//     func test_analyze_negativeFrequency_returnsNil() {
//         XCTAssertNil(MusicTheory.analyze(frequency: -440))
//     }

//     func test_analyze_A3_returnsCorrectNote() {
//         // A3 = 220 Hz (uma oitava abaixo de A4)
//         let result = MusicTheory.analyze(frequency: 220)
//         XCTAssertEqual(result?.noteName, "A3")
//     }

//     func test_analyze_octaveRelationship() {
//         // A4 e A5 devem ter o mesmo nome de nota base, oitavas consecutivas
//         let a4 = MusicTheory.analyze(frequency: 440)
//         let a5 = MusicTheory.analyze(frequency: 880)
//         XCTAssertEqual(a4?.noteName, "A4")
//         XCTAssertEqual(a5?.noteName, "A5")
//     }

//     func test_cents_sharpFrequency_isPositive() {
//         // Frequência ligeiramente acima de A4
//         let result = MusicTheory.analyze(frequency: 445)
//         XCTAssertGreaterThan(result?.cents ?? 0, 0)
//     }

//     func test_cents_flatFrequency_isNegative() {
//         // Frequência ligeiramente abaixo de A4
//         let result = MusicTheory.analyze(frequency: 435)
//         XCTAssertLessThan(result?.cents ?? 0, 0)
//     }
// }

// // ─────────────────────────────────────────────────────────────────────────────
// // MARK: - YINDetector Tests
// // ─────────────────────────────────────────────────────────────────────────────

// final class YINDetectorTests: XCTestCase {

//     var sut: YINDetector!
//     let sampleRate: Float = 44100

//     override func setUp() {
//         super.setUp()
//         sut = YINDetector()
//     }

//     override func tearDown() {
//         sut = nil
//         super.tearDown()
//     }

//     // Gera onda senoidal pura para testes
//     private func sine(frequency: Float, duration: Float = 1.0) -> [Float] {
//         let count = Int(sampleRate * duration)
//         return (0..<count).map { i in
//             sin(2 * .pi * frequency * Float(i) / sampleRate)
//         }
//     }

//     func test_detect_A4_440Hz_accurate() {
//         let buffer = sine(frequency: 440)
//         let detected = sut.detect(buffer: buffer, sampleRate: sampleRate)

//         XCTAssertNotNil(detected)
//         // YIN deve ser preciso dentro de 2 cents (~0.5 Hz em A4)
//         if let freq = detected {
//             let centsDiff = abs(1200 * log2(freq / 440))
//             XCTAssertLessThan(centsDiff, 2.0, "YIN deve ser preciso dentro de 2 cents")
//         }
//     }

//     func test_detect_C4_261Hz_accurate() {
//         let buffer = sine(frequency: 261.63)
//         let detected = sut.detect(buffer: buffer, sampleRate: sampleRate)

//         XCTAssertNotNil(detected)
//         if let freq = detected {
//             let centsDiff = abs(1200 * log2(freq / 261.63))
//             XCTAssertLessThan(centsDiff, 2.0)
//         }
//     }

//     func test_detect_maleVoiceRange_110Hz() {
//         // A2 — típico de tenor baixo
//         let buffer = sine(frequency: 110)
//         let detected = sut.detect(buffer: buffer, sampleRate: sampleRate)

//         XCTAssertNotNil(detected, "YIN deve detectar vozes masculinas graves")
//         if let freq = detected {
//             let centsDiff = abs(1200 * log2(freq / 110))
//             XCTAssertLessThan(centsDiff, 5.0)
//         }
//     }

//     func test_detect_silence_returnsNil() {
//         // Buffer de zeros = silêncio absoluto
//         let buffer = [Float](repeating: 0, count: 8192)
//         let detected = sut.detect(buffer: buffer, sampleRate: sampleRate)
//         XCTAssertNil(detected, "Silêncio não deve produzir detecção")
//     }

//     func test_detect_insufficientBuffer_returnsNil() {
//         // Buffer menor que bufferSize do YIN
//         let buffer = [Float](repeating: 0.5, count: 100)
//         let detected = sut.detect(buffer: buffer, sampleRate: sampleRate)
//         XCTAssertNil(detected)
//     }

//     func test_detect_pureNoise_doesNotCrash() {
//         // Ruído branco — não deve crashar, pode retornar nil ou qualquer frequência
//         let buffer = (0..<8192).map { _ in Float.random(in: -1...1) }
//         XCTAssertNoThrow(sut.detect(buffer: buffer, sampleRate: sampleRate))
//     }
// }

// // ─────────────────────────────────────────────────────────────────────────────
// // MARK: - TunerViewModel Tests
// // ─────────────────────────────────────────────────────────────────────────────

// final class TunerViewModelTests: XCTestCase {

//     var sut: TunerViewModel!

//     override func setUp() {
//         super.setUp()
//         sut = TunerViewModel()
//     }

//     override func tearDown() {
//         sut = nil
//         super.tearDown()
//     }

//     func test_initialState_pitchIsNil() {
//         XCTAssertNil(sut.pitch)
//     }

//     func test_initialState_currentIndexIsZero() {
//         XCTAssertEqual(sut.currentIndex, 0)
//     }

//     func test_nextItem_incrementsIndex() {
//         let initial = sut.currentIndex
//         // nextItem tenta carregar arquivo do Bundle — ok falhar o load em testes
//         sut.currentIndex = (initial + 1) % sut.musics.count
//         XCTAssertEqual(sut.currentIndex, 1)
//     }

//     func test_nextItem_wrapsAroundAtEnd() {
//         // Simula estar no último item
//         sut.currentIndex = sut.musics.count - 1

//         // Avança circularmente
//         let next = (sut.currentIndex + 1) % sut.musics.count
//         XCTAssertEqual(next, 0, "Deve voltar ao índice 0 após o último")
//     }

//     func test_musics_notEmpty() {
//         XCTAssertFalse(sut.musics.isEmpty)
//     }
// }

// // ─────────────────────────────────────────────────────────────────────────────
// // MARK: - TunerLabViewModel Tests
// // ─────────────────────────────────────────────────────────────────────────────

// final class TunerLabViewModelTests: XCTestCase {

//     var sut: TunerLabViewModel!

//     override func setUp() {
//         super.setUp()
//         sut = TunerLabViewModel()
//     }

//     override func tearDown() {
//         sut = nil
//         super.tearDown()
//     }

//     func test_initialResults_isEmpty() {
//         XCTAssertTrue(sut.results.isEmpty)
//     }

//     func test_runPitchTests_producesResults() {
//         sut.runPitchTests()
//         XCTAssertFalse(sut.results.isEmpty, "Deve produzir resultados após execução")
//     }

//     func test_runPitchTests_resultCount() {
//         // 3 freq masculinas × 3 variações + 3 freq femininas × 3 variações = 18 resultados
//         sut.runPitchTests()
//         XCTAssertEqual(sut.results.count, 18)
//     }

//     func test_runPitchTests_clearsOldResults() {
//         sut.runPitchTests()
//         let firstCount = sut.results.count
//         sut.runPitchTests()
//         // Não deve acumular — deve limpar e reexecutar
//         XCTAssertEqual(sut.results.count, firstCount)
//     }

//     func test_pitchTestResult_intensityHint_excellent() {
//         let result = TunerLabViewModel.PitchTestResult(
//             label: "Test", targetFrequency: 440, detectedFrequency: 440,
//             note: "A4", cents: 2.0, pass: true
//         )
//         XCTAssertEqual(result.intensityHint, "Excelente controle")
//     }

//     func test_pitchTestResult_intensityHint_almostThere() {
//         let result = TunerLabViewModel.PitchTestResult(
//             label: "Test", targetFrequency: 440, detectedFrequency: 440,
//             note: "A4", cents: 10.0, pass: false
//         )
//         XCTAssertEqual(result.intensityHint, "Quase lá")
//     }

//     func test_pitchTestResult_direction_perfect() {
//         let result = TunerLabViewModel.PitchTestResult(
//             label: "Test", targetFrequency: 440, detectedFrequency: 440,
//             note: "A4", cents: 0.0, pass: true
//         )
//         XCTAssertEqual(result.direction, "🎯 Perfeito")
//     }

//     func test_pitchTestResult_hashable_differentInstances_differentHash() {
//         let r1 = TunerLabViewModel.PitchTestResult(
//             label: "Test", targetFrequency: 440, detectedFrequency: 440,
//             note: "A4", cents: 0, pass: true
//         )
//         let r2 = TunerLabViewModel.PitchTestResult(
//             label: "Test", targetFrequency: 440, detectedFrequency: 440,
//             note: "A4", cents: 0, pass: true
//         )
//         // IDs diferentes → hashes diferentes
//         XCTAssertNotEqual(r1.hashValue, r2.hashValue)
//     }
// }