//
//  PitchCurveView.swift
//  PitchMVP
//
//  Created by victor on 24/02/26.
//

// PitchCurveView.swift
// PitchMVP
//
// Gráfico de curva de pitch (cents ao longo do tempo) para um NoteSegment.
// Desenhado com SwiftUI Canvas — zero dependências externas.

import SwiftUI

/// Visualiza o desvio em cents ao longo do tempo para um segmento de nota.
///
/// Layout:
/// - Linha central verde = nota alvo (0 cents)
/// - Zona verde suave = ±10 cents (zona de afinação)
/// - Curva colorida = pitch detectado (verde se afinado, gradiente se fora)
/// - Eixo Y: ±50 cents
/// - Eixo X: tempo em segundos
struct PitchCurveView: View {

    let segment: NoteSegment

    /// Intervalo de cents exibido no eixo Y (padrão ±50)
    var centsRange: Float = 50

    private let lineWidth: CGFloat = 2.0
    private let tuneZoneCents: Float = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            // Header do gráfico
            HStack {
                Label {
                    Text("Curva de Pitch")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "waveform.path")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Desvio médio
                Text(String(format: "±%.1f¢ médio", segment.averageCentsDeviation))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.tertiary)
            }

            // Canvas do gráfico
            GeometryReader { geo in
                Canvas { context, size in
                    drawGraph(context: context, size: size)
                }
                .background(Color(.tertiarySystemFill).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(yAxisLabels, alignment: .leading)
            }
            .frame(height: 100)
        }
    }

    // MARK: - Canvas Drawing

    private func drawGraph(context: GraphicsContext, size: CGSize) {
        let cents = segment.centsOverTime
        guard cents.count > 1 else { return }

        let w = size.width
        let h = size.height

        // Helper: converte cents → Y em pixels (0 = topo, h = base)
        func yForCents(_ c: Float) -> CGFloat {
            let normalized = CGFloat(c) / CGFloat(centsRange)  // [-1, 1]
            return h / 2 - normalized * (h / 2) * 0.85         // inverte (agudo = cima)
        }

        // ── Zona afinada (±10 cents) ──────────────────────────────────────────
        let zoneTop    = yForCents(tuneZoneCents)
        let zoneBottom = yForCents(-tuneZoneCents)
        let zoneRect   = CGRect(x: 0, y: zoneTop, width: w, height: zoneBottom - zoneTop)

        context.fill(
            Path(roundedRect: zoneRect, cornerRadius: 0),
            with: .color(Color.green.opacity(0.08))
        )

        // ── Linha central (0 cents) ───────────────────────────────────────────
        var centerLine = Path()
        let centerY = yForCents(0)
        centerLine.move(to: CGPoint(x: 0, y: centerY))
        centerLine.addLine(to: CGPoint(x: w, y: centerY))

        context.stroke(centerLine,
                       with: .color(Color.green.opacity(0.35)),
                       style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

        // ── Linhas de referência ±25¢ e ±50¢ ────────────────────────────────
        for refCents: Float in [25, -25, 50, -50] {
            let y = yForCents(refCents)
            var refLine = Path()
            refLine.move(to: CGPoint(x: 0, y: y))
            refLine.addLine(to: CGPoint(x: w, y: y))
            context.stroke(refLine,
                           with: .color(Color.secondary.opacity(0.12)),
                           style: StrokeStyle(lineWidth: 0.5))
        }

        // ── Curva de pitch (gradiente de cor por desvio) ──────────────────────
        guard cents.count > 1 else { return }

        var curve = Path()
        for (i, c) in cents.enumerated() {
            let x = CGFloat(i) / CGFloat(cents.count - 1) * w
            let y = yForCents(c)
            if i == 0 { curve.move(to: CGPoint(x: x, y: y)) }
            else       { curve.addLine(to: CGPoint(x: x, y: y)) }
        }

        // Gradiente de cor: verde (afinado) → laranja (desviado)
        context.stroke(
            curve,
            with: .linearGradient(
                Gradient(stops: colorStops(for: cents)),
                startPoint: CGPoint(x: 0, y: h / 2),
                endPoint:   CGPoint(x: w, y: h / 2)
            ),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        )

        // ── Pontos de vibrato (marcados como ondas azuis) ─────────────────────
        if segment.vibrato != nil {
            // Indica região com vibrato com linha pontilhada azul na base
            var vibratoBar = Path()
            vibratoBar.move(to: CGPoint(x: w * 0.05, y: h - 3))
            vibratoBar.addLine(to: CGPoint(x: w * 0.95, y: h - 3))
            context.stroke(vibratoBar,
                           with: .color(Color.blue.opacity(0.5)),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 2]))
        }
    }

    /// Gera stops de gradiente baseados no desvio em cents de cada ponto.
    private func colorStops(for cents: [Float]) -> [Gradient.Stop] {
        guard cents.count > 1 else { return [.init(color: .green, location: 0)] }

        return cents.enumerated().map { i, c in
            let location = Double(i) / Double(cents.count - 1)
            let absC = abs(c)
            let color: Color
            if absC < 10 {
                color = .green
            } else if absC < 25 {
                color = Color.mix(color1: .green, color2: .orange, fraction: Double((absC - 10) / 15))
            } else {
                color = .orange
            }
            return Gradient.Stop(color: color, location: location)
        }
    }

    // MARK: - Eixo Y Labels

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

// MARK: - Color Mix Helper

private extension Color {
    /// Mistura linear entre duas cores. fraction: 0 = color1, 1 = color2.
    static func mix(color1: Color, color2: Color, fraction: Double) -> Color {
        let f = max(0, min(1, fraction))
        return Color(
            red:   lerp(from: UIColor(color1).rgba.r, to: UIColor(color2).rgba.r, t: f),
            green: lerp(from: UIColor(color1).rgba.g, to: UIColor(color2).rgba.g, t: f),
            blue:  lerp(from: UIColor(color1).rgba.b, to: UIColor(color2).rgba.b, t: f)
        )
    }

    private static func lerp(from a: CGFloat, to b: CGFloat, t: Double) -> Double {
        Double(a) + (Double(b) - Double(a)) * t
    }
}

private extension UIColor {
    var rgba: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        var r: CGFloat = 0; var g: CGFloat = 0
        var b: CGFloat = 0; var a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }
}