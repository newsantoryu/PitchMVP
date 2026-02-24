//
//  OverlappedPitchCurveView.swift
//  PitchMVP
//
//  Created by victor on 24/02/26.
//

// OverlappedPitchCurveView.swift
// PitchMVP
//
// Gráfico com as curvas de pitch sobrepostas:
//   azul = referência (nota alvo)
//   laranja/verde = voz do usuário
// Ambas normalizadas em cents em relação à mesma nota alvo.

import SwiftUI

struct OverlappedPitchCurveView: View {

    let comparison: NoteComparison

    private let centsRange: Float = 60

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            // Header
            HStack {
                Label {
                    Text("Curvas Sobrepostas")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "waveform.path")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Legenda
                HStack(spacing: 10) {
                    legendDot(color: .blue,   label: "Ref.")
                    legendDot(color: .orange, label: "Você")
                }
            }

            GeometryReader { geo in
                Canvas { context, size in
                    drawOverlap(context: context, size: size)
                }
                .background(Color(.tertiarySystemFill).opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(yAxisLabels, alignment: .leading)
            }
            .frame(height: 120)
        }
    }

    // MARK: - Canvas

    private func drawOverlap(context: GraphicsContext, size: CGSize) {
        let w = size.width
        let h = size.height

        func yForCents(_ c: Float) -> CGFloat {
            let norm = CGFloat(c) / CGFloat(centsRange)
            return h / 2 - norm * (h / 2) * 0.85
        }

        // ── Zona afinada ±10¢ ────────────────────────────────────────────────
        let zoneRect = CGRect(
            x: 0,
            y: yForCents(10),
            width: w,
            height: yForCents(-10) - yForCents(10)
        )
        context.fill(Path(roundedRect: zoneRect, cornerRadius: 0),
                     with: .color(Color.green.opacity(0.07)))

        // ── Linha central 0¢ ─────────────────────────────────────────────────
        var center = Path()
        center.move(to: CGPoint(x: 0, y: yForCents(0)))
        center.addLine(to: CGPoint(x: w, y: yForCents(0)))
        context.stroke(center,
                       with: .color(Color.green.opacity(0.3)),
                       style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

        // ── Referência (azul) ─────────────────────────────────────────────────
        if let ref = comparison.referenceSegment {
            drawCurve(
                context: context,
                cents: ref.centsOverTime,
                size: size,
                color: Color.blue.opacity(0.55),
                lineWidth: 1.5,
                yForCents: yForCents
            )
        }

        // ── Usuário (laranja/verde) ────────────────────────────────────────────
        if let user = comparison.userSegment {
            let userColor: Color = (comparison.grade == .excellent || comparison.grade == .good)
                ? Color.green.opacity(0.85)
                : Color.orange.opacity(0.85)

            drawCurve(
                context: context,
                cents: user.centsOverTime,
                size: size,
                color: userColor,
                lineWidth: 2,
                yForCents: yForCents
            )
        }
    }

    private func drawCurve(
        context: GraphicsContext,
        cents: [Float],
        size: CGSize,
        color: Color,
        lineWidth: CGFloat,
        yForCents: (Float) -> CGFloat
    ) {
        guard cents.count > 1 else { return }

        var path = Path()
        for (i, c) in cents.enumerated() {
            let x = CGFloat(i) / CGFloat(cents.count - 1) * size.width
            let y = yForCents(c)
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else       { path.addLine(to: CGPoint(x: x, y: y)) }
        }

        context.stroke(path,
                       with: .color(color),
                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
    }

    // MARK: - Helpers

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var yAxisLabels: some View {
        VStack {
            Text("+\(Int(centsRange))¢")
                .font(.system(size: 8, design: .rounded))
                .foregroundStyle(.quaternary)
            Spacer()
            Text("0")
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
            Spacer()
            Text("-\(Int(centsRange))¢")
                .font(.system(size: 8, design: .rounded))
                .foregroundStyle(.quaternary)
        }
        .padding(.vertical, 4)
        .padding(.leading, 3)
    }
}