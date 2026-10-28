import SwiftUI
import DKWCore

/// Récapitulatif après extraction (Échap ou « FERMER » pour fermer).
struct SummarySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private var total: Int { model.reports.reduce(0) { $0 + $1.copied.count } }

    var body: some View {
        ZStack {
            PedalBackground()
            VStack(spacing: 18) {
                HStack(spacing: 10) {
                    PedalLED(on: total > 0, blinking: false)
                    Text("\(total) SON\(total > 1 ? "S" : "") COPIÉ\(total > 1 ? "S" : "")")
                        .font(.system(size: 24, weight: .heavy)).tracking(3)
                        .foregroundStyle(.white)
                }
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(model.reports) { report in
                            ReportBlock(report: report, showName: model.reports.count > 1)
                        }
                    }
                }
                .frame(maxHeight: 320)
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Button("FERMER") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button {
                        if let first = model.reports.first {
                            NSWorkspace.shared.open(model.reports.count > 1 ? (model.outputURL ?? first.destination) : first.destination)
                        }
                    } label: {
                        Label("OUVRIR LE DOSSIER DANS LE FINDER", systemImage: "folder")
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .buttonStyle(CreamButtonStyle(height: 34))
            }
            .padding(30)
        }
        .frame(width: 520)
        .environment(\.colorScheme, .dark)
    }
}

private struct ReportBlock: View {
    let report: ExtractionReport
    let showName: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showName {
                Text("\(report.flpName.uppercased()) · \(report.copied.count) COPIÉ\(report.copied.count > 1 ? "S" : "")")
                    .silkscreen(size: 10)
            }
            FlowLayout(spacing: 8) {
                ForEach(report.countsByType, id: \.type) { entry in
                    HStack(spacing: 4) {
                        PedalBadge(type: entry.type, minWidth: 60)
                        Text("× \(entry.count)").font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
            if !report.notFound.isEmpty {
                Label("\(report.notFound.count) introuvable\(report.notFound.count > 1 ? "s" : "") : " +
                      report.notFound.map(\.fileName).joined(separator: ", "), systemImage: "questionmark.circle")
                    .font(.caption).foregroundStyle(Studio.lavender)
            }
            ForEach(Array(report.failed.enumerated()), id: \.offset) { _, f in
                Label("Échec : \(f.item.fileName) (\(f.reason))", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .recessed(radius: 12, darkness: 0.3)
    }
}

/// Mise en page qui passe à la ligne (pour les badges).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? 400, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (i, origin) in result.origins.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        var origins: [CGPoint] = []
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}
