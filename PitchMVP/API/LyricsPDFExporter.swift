//
//  Created by victor on 12/03/26.
//
// LyricsPDFExporter.swift
// PitchMVP
//
// Exporta um LyricsAnalysis como PDF no formato de cifra musical:
//
//   ┌─────────────────────────────────────────────────┐
//   │  VOCAL ANALYSIS — Nome do arquivo               │
//   │  Data                                           │
//   │                                                 │
//   │  ══ VOCAL PROFILE ══════════════════════════   │
//   │  Range: G3 – D4   Tessitura: A3 – B3           │
//   │  High intensity: C4, D4                        │
//   │  Highest phrase: "all my childish fears"        │
//   │                                                 │
//   │  ══ DIFICULDADE ════════════════════════════   │
//   │  🟢 Confortável  🟡 Médio  🔴 Difícil          │
//   │                                                 │
//   │  ══ CIFRA ══════════════════════════════════   │
//   │       A3        A3       B3                    │
//   │  I'm so tired of being here                    │
//   │  🟢🟢🟡🟡🔴                                   │
//   └─────────────────────────────────────────────────┘
//
// Usa apenas APIs nativas do iOS (UIKit/CoreGraphics/PDFKit) — sem dependências externas.

import UIKit
import PDFKit

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - LyricsPDFExporter
// ─────────────────────────────────────────────────────────────────────────────

struct LyricsPDFExporter {

    // MARK: - Layout

    private let pageWidth:   CGFloat = 595   // A4 pts
    private let pageHeight:  CGFloat = 842
    private let marginH:     CGFloat = 48
    private let marginTop:   CGFloat = 56
    private let marginBottom: CGFloat = 56

    // MARK: - Tipografia

    private let titleFont      = UIFont.systemFont(ofSize: 16, weight: .semibold)
    private let subtitleFont   = UIFont.systemFont(ofSize: 10, weight: .regular)
    private let sectionFont    = UIFont.systemFont(ofSize: 9,  weight: .semibold)
    private let profileFont    = UIFont.systemFont(ofSize: 11, weight: .regular)
    private let profileBold    = UIFont.systemFont(ofSize: 11, weight: .semibold)
    private let noteFont       = UIFont.monospacedSystemFont(ofSize: 9, weight: .semibold)
    private let lyricFont      = UIFont.systemFont(ofSize: 12, weight: .regular)
    private let emojiFont      = UIFont.systemFont(ofSize: 9,  weight: .regular)

    // MARK: - Cores

    private let colorPrimary    = UIColor.black
    private let colorSecondary  = UIColor(white: 0.45, alpha: 1)
    private let colorDivider    = UIColor(white: 0.75, alpha: 1)
    private let colorNoteGreen  = UIColor(red: 0.18, green: 0.80, blue: 0.44, alpha: 1)
    private let colorNoteYellow = UIColor(red: 0.95, green: 0.77, blue: 0.06, alpha: 1)
    private let colorNoteRed    = UIColor(red: 0.91, green: 0.30, blue: 0.24, alpha: 1)
    private let colorNoteGray   = UIColor(white: 0.55, alpha: 1)

    // MARK: - API Pública

    /// Gera o PDF e retorna os dados prontos para compartilhamento.
    /// Pode ser chamado numa Task em background — não toca em MainActor.
    func export(analysis: LyricsAnalysis) -> Data {
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        )

        return renderer.pdfData { ctx in
            var y: CGFloat = marginTop
            var pageOpen = false

            func beginPage() {
                ctx.beginPage()
                pageOpen = true
                y = marginTop
            }

            func checkPageBreak(needed: CGFloat) {
                if y + needed > pageHeight - marginBottom {
                    beginPage()
                }
            }

            beginPage()

            // ── Cabeçalho ────────────────────────────────────────────────────
            y = drawHeader(analysis: analysis, y: y, ctx: ctx.cgContext)
            y += 20

            // ── Perfil Vocal ─────────────────────────────────────────────────
            checkPageBreak(needed: 80)
            y = drawVocalProfile(profile: analysis.vocalProfile, y: y, ctx: ctx.cgContext)
            y += 16

            // ── Legenda de Dificuldade ────────────────────────────────────────
            checkPageBreak(needed: 40)
            y = drawDifficultyLegend(analysis: analysis, y: y, ctx: ctx.cgContext)
            y += 20

            // ── Divider ──────────────────────────────────────────────────────
            drawDivider(y: y, ctx: ctx.cgContext)
            y += 14

            // ── Cifra por linha ───────────────────────────────────────────────
            for line in analysis.lines {
                let blockHeight = estimateLineBlockHeight(line: line)
                checkPageBreak(needed: blockHeight + 12)
                y = drawLyricLine(line: line, y: y, ctx: ctx.cgContext)
                y += 10
            }
        }
    }

    // MARK: - Cabeçalho

    private func drawHeader(analysis: LyricsAnalysis, y: CGFloat, ctx: CGContext) -> CGFloat {
        var cy = y
        let usableWidth = pageWidth - marginH * 2

        // Título
        let titleStr = "VOCAL ANALYSIS" as NSString
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
            .kern: NSNumber(value: 3.0),
            .foregroundColor: colorSecondary
        ]
        titleStr.draw(at: CGPoint(x: marginH, y: cy), withAttributes: titleAttrs)
        cy += 18

        // Nome do arquivo
        let nameStr = analysis.audioFileName as NSString
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: colorPrimary
        ]
        nameStr.draw(at: CGPoint(x: marginH, y: cy), withAttributes: nameAttrs)
        cy += 24

        // Data
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let dateStr = formatter.string(from: analysis.analyzedAt) as NSString
        let dateAttrs: [NSAttributedString.Key: Any] = [
            .font: subtitleFont,
            .foregroundColor: colorSecondary
        ]
        dateStr.draw(at: CGPoint(x: marginH, y: cy), withAttributes: dateAttrs)
        cy += 14

        // Linha divisória grossa
        ctx.setStrokeColor(colorPrimary.cgColor)
        ctx.setLineWidth(1.5)
        ctx.move(to: CGPoint(x: marginH, y: cy))
        ctx.addLine(to: CGPoint(x: marginH + usableWidth, y: cy))
        ctx.strokePath()

        return cy + 4
    }

    // MARK: - Perfil Vocal

    private func drawVocalProfile(profile: VocalProfile, y: CGFloat, ctx: CGContext) -> CGFloat {
        var cy = y

        // Seção header
        cy = drawSectionLabel("VOCAL PROFILE", y: cy, ctx: ctx)
        cy += 10

        // Grid 2×2
        let colW = (pageWidth - marginH * 2) / 2
        let rows: [(String, String)] = [
            ("Range",      profile.rangeLabel),
            ("Tessitura",  profile.tessituraLabel),
            ("High intensity", profile.highIntensityLabel),
            ("Semitônios", "\(profile.rangeInSemitones) st"),
        ]

        for (i, row) in rows.enumerated() {
            let col = i % 2
            let x   = marginH + CGFloat(col) * colW

            // Label
            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: sectionFont,
                .foregroundColor: colorSecondary,
                .kern: NSNumber(value: 1.5)
            ]
            (row.0.uppercased() as NSString).draw(at: CGPoint(x: x, y: cy), withAttributes: labelAttrs)

            // Valor
            let valAttrs: [NSAttributedString.Key: Any] = [
                .font: profileBold,
                .foregroundColor: colorPrimary
            ]
            (row.1 as NSString).draw(at: CGPoint(x: x, y: cy + 11), withAttributes: valAttrs)

            if col == 1 { cy += 30 }
        }

        // Highest phrase
        if let phrase = profile.highestPhrase {
            cy += 4
            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: sectionFont,
                .foregroundColor: colorSecondary,
                .kern: NSNumber(value: 1.5)
            ]
            ("FRASE MAIS AGUDA" as NSString).draw(
                at: CGPoint(x: marginH, y: cy),
                withAttributes: labelAttrs
            )
            cy += 12

            let phraseAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.italicSystemFont(ofSize: 11),
                .foregroundColor: colorPrimary
            ]
            ("\"\(phrase)\"" as NSString).draw(
                in: CGRect(x: marginH, y: cy, width: pageWidth - marginH * 2, height: 30),
                withAttributes: phraseAttrs
            )
            cy += 20
        }

        return cy
    }

    // MARK: - Legenda de Dificuldade

    private func drawDifficultyLegend(analysis: LyricsAnalysis, y: CGFloat, ctx: CGContext) -> CGFloat {
        var cy = y

        cy = drawSectionLabel("DIFICULDADE", y: cy, ctx: ctx)
        cy += 10

        let items: [(String, UIColor, Int)] = [
            ("🟢 Confortável", colorNoteGreen,  analysis.comfortableCount),
            ("🟡 Médio",       colorNoteYellow, analysis.moderateCount),
            ("🔴 Difícil",     colorNoteRed,    analysis.difficultCount),
        ]

        let colW = (pageWidth - marginH * 2) / CGFloat(items.count)
        for (i, item) in items.enumerated() {
            let x = marginH + CGFloat(i) * colW

            // Contagem
            let countAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 18, weight: .light),
                .foregroundColor: item.1
            ]
            ("\(item.2)" as NSString).draw(at: CGPoint(x: x, y: cy), withAttributes: countAttrs)

            // Label
            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10),
                .foregroundColor: colorSecondary
            ]
            (item.0 as NSString).draw(at: CGPoint(x: x, y: cy + 20), withAttributes: labelAttrs)
        }

        return cy + 38
    }

    // MARK: - Cifra (linha principal)

    private func drawLyricLine(line: LyricLine, y: CGFloat, ctx: CGContext) -> CGFloat {
        var cy = y
        let usableWidth = pageWidth - marginH * 2

        // ── Linha 1: notas acima das palavras (estilo cifra) ──────────────────
        //
        // Calcula a posição X de cada palavra primeiro, depois desenha a nota
        // acima do X correspondente.

        // Medir larguras das palavras para calcular X de cada uma
        let lyricAttrs: [NSAttributedString.Key: Any] = [.font: lyricFont]
        var wordPositions: [(word: LyricWord, x: CGFloat)] = []
        var cursorX: CGFloat = marginH

        for word in line.words {
            let spaced = word.text + " "
            let width  = (spaced as NSString).size(withAttributes: lyricAttrs).width
            wordPositions.append((word: word, x: cursorX))
            cursorX += width
            if cursorX > marginH + usableWidth { break }
        }

        // Desenha as notas na linha de cima (cy)
        var lastDrawnNote: String? = nil
        let noteAttrs: [NSAttributedString.Key: Any] = [
            .font: noteFont,
            .foregroundColor: colorNoteGray
        ]

        for wp in wordPositions {
            guard let note = wp.word.noteName, note != lastDrawnNote || wp.word.isPhraseBoundary else {
                continue
            }
            let color = noteColor(for: wp.word.difficulty)
            var attrs = noteAttrs
            attrs[.foregroundColor] = color
            (note as NSString).draw(at: CGPoint(x: wp.x, y: cy), withAttributes: attrs)
            lastDrawnNote = note
        }
        cy += 13

        // ── Linha 2: texto da letra ───────────────────────────────────────────
        for wp in wordPositions {
            let wordAttrs: [NSAttributedString.Key: Any] = [
                .font: lyricFont,
                .foregroundColor: colorPrimary
            ]
            (wp.word.text + " " as NSString).draw(
                at: CGPoint(x: wp.x, y: cy),
                withAttributes: wordAttrs
            )
        }
        cy += 16

        // ── Linha 3: emojis de dificuldade ────────────────────────────────────
        cursorX = marginH
        for wp in wordPositions {
            let emoji = wp.word.difficulty.emoji
            let spaced = wp.word.text + " "
            let wordWidth = (spaced as NSString).size(withAttributes: lyricAttrs).width
            (emoji as NSString).draw(
                at: CGPoint(x: wp.x, y: cy),
                withAttributes: [.font: emojiFont]
            )
            cursorX += wordWidth
        }
        cy += 14

        return cy
    }

    // MARK: - Helpers de Desenho

    @discardableResult
    private func drawSectionLabel(_ text: String, y: CGFloat, ctx: CGContext) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: sectionFont,
            .foregroundColor: colorSecondary,
            .kern: NSNumber(value: 2.0)
        ]
        (text as NSString).draw(at: CGPoint(x: marginH, y: y), withAttributes: attrs)
        return y + 14
    }

    private func drawDivider(y: CGFloat, ctx: CGContext) {
        ctx.setStrokeColor(colorDivider.cgColor)
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: marginH, y: y))
        ctx.addLine(to: CGPoint(x: pageWidth - marginH, y: y))
        ctx.strokePath()
    }

    // MARK: - Estimativa de Altura

    private func estimateLineBlockHeight(line: LyricLine) -> CGFloat {
        // nota (13) + lyric (16) + emoji (14) + gap (10) = 53
        return 53
    }

    // MARK: - Cor de Nota

    private func noteColor(for difficulty: NoteDifficulty) -> UIColor {
        switch difficulty {
        case .comfortable: return colorNoteGreen
        case .moderate:    return colorNoteYellow
        case .difficult:   return colorNoteRed
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - ShareSheet Helper
// ─────────────────────────────────────────────────────────────────────────────

/// Wraps UIActivityViewController para uso em SwiftUI via .sheet
import SwiftUI

struct PDFShareSheet: UIViewControllerRepresentable {

    let pdfData: Data
    let fileName: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)
        try? pdfData.write(to: url)
        return UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}