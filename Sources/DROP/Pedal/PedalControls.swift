import SwiftUI
import AppKit
import DKWCore

// Pièces de la pédale dessinées en code. Pas de flou ni d'ombre recalculés au redimensionnement :
// les ombres des éléments qui s'étirent sont de simples formes décalées.

/// Boîtier : texture martelée en mosaïque, vignettage, écaillures du pourtour.
struct PedalBackground: View {
    var body: some View {
        ZStack {
            Studio.paint
            if let tex = PedalAssets.texture {
                Image(nsImage: tex).resizable(resizingMode: .tile)
            }
            Studio.color(0x3E148F).opacity(0.28) // teinte plus profonde, comme la maquette
            LinearGradient(colors: [.white.opacity(0.05), .clear, .black.opacity(0.3)],
                           startPoint: .top, endPoint: .bottom)
            GeometryReader { geo in
                RadialGradient(colors: [.clear, .black.opacity(0.38)], center: .center,
                               startRadius: min(geo.size.width, geo.size.height) * 0.45,
                               endRadius: max(geo.size.width, geo.size.height) * 0.75)
            }
            if let chips = PedalAssets.edgeChips {
                Image(nsImage: chips)
                    .resizable(capInsets: EdgeInsets(top: 80, leading: 80, bottom: 80, trailing: 80), resizingMode: .tile)
                    .opacity(0.85)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct Screw: View {
    var size: CGFloat = 18
    var angle: Double = 0

    var body: some View {
        Group {
            if let img = PedalAssets.screw {
                Image(nsImage: img).resizable().interpolation(.high)
            } else {
                Circle().fill(LinearGradient(colors: [.white.opacity(0.85), .gray], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(Rectangle().fill(.black.opacity(0.5)).frame(width: size * 0.6, height: size * 0.12))
            }
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(angle))
        .background(Circle().fill(.black.opacity(0.45)).offset(y: size * 0.07).blur(radius: 0.5))
        .accessibilityHidden(true)
    }
}

/// Panneau creusé dans le boîtier.
struct Recessed: ViewModifier {
    var radius: CGFloat = 14
    var darkness: Double = 0.25

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(shape.fill(.black.opacity(darkness)))
            .overlay(alignment: .top) {
                // ombre intérieure (bord haut), sans flou
                LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: min(12, radius))
                    .clipShape(shape)
                    .allowsHitTesting(false)
            }
            .overlay(shape.strokeBorder(LinearGradient(colors: [.black.opacity(0.45), .white.opacity(0.12)],
                                                      startPoint: .top, endPoint: .bottom), lineWidth: 1)
                .allowsHitTesting(false))
    }
}

extension View {
    func recessed(radius: CGFloat = 14, darkness: Double = 0.25) -> some View {
        modifier(Recessed(radius: radius, darkness: darkness))
    }

    /// Sérigraphie : petites majuscules blanches espacées.
    func silkscreen(size: CGFloat = 11, opacity: Double = 0.92) -> some View {
        font(.system(size: size, weight: .semibold)).tracking(size * 0.28)
            .foregroundStyle(.white.opacity(opacity))
    }
}

/// Surface crème biseautée (champs, boutons, onglets).
struct CreamSurface: View {
    var radius: CGFloat = 8
    var pressed = false
    var dimmed = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            shape.fill(.black.opacity(0.45)).offset(y: pressed ? 0.5 : 2)
            shape.fill(LinearGradient(colors: pressed ? [Studio.creamShade, Studio.cream] : [Studio.cream, Studio.creamShade],
                                      startPoint: .top, endPoint: .bottom))
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.9), .black.opacity(0.22)],
                                              startPoint: .top, endPoint: .bottom), lineWidth: 1)
        }
        .opacity(dimmed ? 0.55 : 1)
    }
}

struct CreamButtonStyle: ButtonStyle {
    var radius: CGFloat = 8
    var height: CGFloat = 30
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold, design: .monospaced)).tracking(1.2)
            .foregroundStyle(Studio.ink)
            .padding(.horizontal, 12)
            .frame(height: height)
            .background(CreamSurface(radius: radius, pressed: configuration.isPressed, dimmed: !enabled))
            .offset(y: configuration.isPressed ? 1.5 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// Champ texte crème (schéma clair forcé : curseur et sélection lisibles sur le crème).
struct CreamTextField: View {
    let placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void = {}

    var body: some View {
        TextField(text: $text, prompt: Text(placeholder).foregroundStyle(Studio.ink.opacity(0.4))) { Text(placeholder) }
            .textFieldStyle(.plain)
            .font(.system(size: 14, weight: .medium, design: .monospaced))
            .tracking(1.2)
            .foregroundStyle(Studio.ink)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(CreamSurface())
            .environment(\.colorScheme, .light)
            .onSubmit(onSubmit)
    }
}

/// Étiquette sérigraphiée au-dessus d'un contrôle.
struct LabeledControl<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).silkscreen()
            content
        }
    }
}

/// Séparateur gravé (trait sombre + reflet clair).
struct EngravedSeparator: View {
    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(.black.opacity(0.4)).frame(width: 1)
            Rectangle().fill(.white.opacity(0.12)).frame(width: 1)
        }
        .frame(height: 58)
        .accessibilityHidden(true)
    }
}

struct CreamCheckbox: View {
    let isOn: Bool
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                CreamSurface(radius: 5, dimmed: !enabled)
                if isOn {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(Studio.ink)
                }
            }
            .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(isOn ? "Inclus" : "Exclu")
    }
}

/// Badge de type : capsule colorée, texte blanc en majuscules.
struct PedalBadge: View {
    let label: String
    let color: Color
    var minWidth: CGFloat = 76

    init(type: SoundType, minWidth: CGFloat = 76) { label = type.badgeLabel; color = type.color; self.minWidth = minWidth }
    init(label: String, color: Color, minWidth: CGFloat = 76) { self.label = label; self.color = color; self.minWidth = minWidth }

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .bold, design: .monospaced)).tracking(1.4)
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(minWidth: minWidth, minHeight: 26)
            .background(Capsule().fill(LinearGradient(colors: [color.opacity(0.85), color], startPoint: .top, endPoint: .bottom)))
            .overlay(Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .black.opacity(0.2)],
                                                           startPoint: .top, endPoint: .bottom), lineWidth: 1))
    }
}

/// LED : éteinte, allumée, ou clignotante (le clignotement n'existe que pendant la copie).
struct PedalLED: View {
    let on: Bool
    let blinking: Bool

    var body: some View {
        if blinking {
            TimelineView(.periodic(from: .now, by: 0.35)) { ctx in
                bulb(lit: Int(ctx.date.timeIntervalSinceReferenceDate / 0.35) % 2 == 0)
            }
        } else {
            bulb(lit: on)
        }
    }

    private func bulb(lit: Bool) -> some View {
        ZStack {
            if lit {
                Circle().fill(RadialGradient(colors: [Studio.ledOn.opacity(0.9), Studio.accent.opacity(0.45), .clear], center: .center, startRadius: 3, endRadius: 17))
                    .frame(width: 34, height: 34)
            }
            Circle()
                .fill(lit ? RadialGradient(colors: [.white, Studio.ledOn], center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: 7)
                          : RadialGradient(colors: [Studio.color(0x3B2A57), Studio.color(0x1A1030)], center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: 7))
                .frame(width: 12, height: 12)
                .overlay(Circle().strokeBorder(.black.opacity(0.5), lineWidth: 1))
        }
        .frame(width: 34, height: 34)
        .accessibilityLabel(lit ? "Prêt" : "Éteint")
    }
}

/// Bouton rond crème (réglages, retirer…).
struct CreamIconButtonStyle: ButtonStyle {
    var size: CGFloat = 26

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.48, weight: .bold))
            .foregroundStyle(Studio.ink)
            .frame(width: size, height: size)
            .background(CreamSurface(radius: size / 2, pressed: configuration.isPressed))
            .offset(y: configuration.isPressed ? 1 : 0)
            .contentShape(Circle())
    }
}
