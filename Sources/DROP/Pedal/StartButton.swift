import SwiftUI

/// Gros bouton poussoir START : cadre métal fixe + pad crème qui s'enfonce.
/// Une seule image de pad ; survol, appui et désactivation sont faits en code.
struct StartButtonStyle: ButtonStyle {
    var size: CGFloat = 132

    func makeBody(configuration: Configuration) -> some View {
        StartButtonBody(size: size, pressed: configuration.isPressed)
    }
}

private struct StartButtonBody: View {
    let size: CGFloat
    let pressed: Bool
    @Environment(\.isEnabled) private var enabled
    @State private var hover = false

    // L'ouverture de start-bezel.png fait ≈ 64 % de sa largeur ; le pad est un peu plus petit.
    private var padSide: CGFloat { size * 0.615 }

    var body: some View {
        let down = pressed && enabled
        ZStack {
            // fond du logement, visible autour du pad
            RoundedRectangle(cornerRadius: size * 0.1, style: .continuous)
                .fill(Color.black.opacity(0.75))
                .frame(width: size * 0.64, height: size * 0.64)

            bezel

            ForEach(0..<4, id: \.self) { i in
                Screw(size: size * 0.085, angle: [12, 78, 141, 203][i])
                    .offset(x: (i % 2 == 0 ? -1 : 1) * size * 0.405, y: (i < 2 ? -1 : 1) * size * 0.405)
            }

            pad
                .frame(width: padSide, height: padSide)
                .shadow(color: .black.opacity(0.6), radius: down ? 1.5 : 6, y: down ? 1 : 5)
                .scaleEffect(down ? 0.975 : 1)
                .offset(y: down ? 3.5 : 0)
                .saturation(enabled ? 1 : 0.25)
                .brightness(enabled ? (hover ? 0.04 : 0) : -0.14)
                .opacity(enabled ? 1 : 0.82)
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .animation(.spring(response: 0.2, dampingFraction: 0.5), value: down)
        .animation(.easeOut(duration: 0.15), value: hover)
        .animation(.easeOut(duration: 0.25), value: enabled)
    }

    @ViewBuilder private var bezel: some View {
        if let img = PedalAssets.bezel {
            Image(nsImage: img).resizable().interpolation(.high)
                .frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Color(white: 0.55), Color(white: 0.18)], startPoint: .top, endPoint: .bottom),
                              lineWidth: size * 0.17)
                .frame(width: size, height: size)
        }
    }

    private var pad: some View {
        ZStack {
            if let img = PedalAssets.pad {
                Image(nsImage: img).resizable().interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: padSide * 0.18, style: .continuous)
                    .fill(LinearGradient(colors: [Studio.cream, Studio.creamShade], startPoint: .top, endPoint: .bottom))
            }
            Text("START")
                .font(.system(size: padSide * 0.235, weight: .black))
                .tracking(0.5)
                .foregroundStyle(Studio.color(0x141018))
                .blendMode(.multiply) // laisse passer la saleté du pad
                .offset(y: padSide * 0.04)
        }
        .compositingGroup()
    }
}
