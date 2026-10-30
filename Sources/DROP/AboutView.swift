import SwiftUI
import DKWCore

struct AboutView: View {
    var body: some View {
        ZStack {
            PedalBackground()
            VStack(spacing: 14) {
                LogoView(width: 300)
                Text("VERSION \(AppInfo.version)").silkscreen(size: 10, opacity: 0.7)
                Text("Extrait et range les samples de tes projets FL Studio.")
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                Label("100 % local : aucune connexion internet nécessaire.", systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(Studio.lavender)
                Text("© TONY CARLOS").silkscreen(size: 9, opacity: 0.5)
            }
            .padding(40)
        }
        .frame(width: 440)
        .environment(\.colorScheme, .dark)
    }
}
