import SwiftUI
import RealityKit

struct CameraSurface: UIViewRepresentable {
    let controller: HuntController
    func makeUIView(context: Context) -> ARView { controller.view }
    func updateUIView(_ uiView: ARView, context: Context) {}
}

struct HuntScreen: View {
    @StateObject private var hunt = HuntController()
    @Environment(\.scenePhase) private var scenePhase
    private let mint = Color(red: 0.65, green: 1, blue: 0.78)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraSurface(controller: hunt).ignoresSafeArea()
            LinearGradient(colors: [.black.opacity(0.65), .clear, .black.opacity(0.8)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea().allowsHitTesting(false)
            if hunt.blocker == nil { reticle.allowsHitTesting(false) }
            VStack(spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("ДИКИЕ ЧУДЕСА").font(.caption.weight(.bold)).tracking(3)
                        Text("Охота").font(.largeTitle.bold())
                    }
                    Spacer()
                    Label("\(hunt.count)", systemImage: "pawprint.fill")
                        .font(.headline).padding(12).background(.ultraThinMaterial, in: Capsule())
                        .accessibilityLabel("Поймано монстров: \(hunt.count)")
                }
                HStack(spacing: 6) {
                    Circle().fill(hunt.trackingReady ? mint : .orange).frame(width: 7, height: 7)
                    Text(hunt.trackingReady ? "Мир найден" : "Медленно двигай телефоном — ищем поверхность")
                        .font(.caption)
                    Spacer()
                }
                Spacer()
                if let blocker = hunt.blocker {
                    VStack(spacing: 16) {
                        Image(systemName: "camera.fill").font(.largeTitle)
                        Text(blocker).multilineTextAlignment(.center)
                        if hunt.permissionDenied {
                            Button("Открыть настройки") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }.buttonStyle(.borderedProminent).tint(mint).foregroundStyle(.black)
                        } else {
                            Button("Повторить") { hunt.activate() }.buttonStyle(.bordered)
                        }
                    }.padding(24).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
                } else {
                    controls
                }
            }
            .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 24)
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .onAppear { hunt.activate() }
        .onDisappear { hunt.suspend() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { hunt.activate() } else { hunt.suspend() }
        }
    }

    private var reticle: some View {
        ZStack {
            if hunt.stage == .encounter || hunt.stage == .catching {
                Circle().stroke(.white.opacity(0.5), lineWidth: 1).frame(width: 96, height: 96)
                Circle().stroke(hunt.aimed ? mint : .white.opacity(0.65), lineWidth: 3)
                    .frame(width: 96 * hunt.ring, height: 96 * hunt.ring)
                Circle().fill(hunt.aimed ? mint : .white).frame(width: 5, height: 5)
            } else if hunt.stage == .scanning {
                Image(systemName: "viewfinder").font(.system(size: 44, weight: .ultraLight))
                    .foregroundStyle(hunt.surfaceReady ? mint : .white)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var controls: some View {
        VStack(spacing: 16) {
            if hunt.stage != .scanning {
                HStack {
                    Text("Мохлик").font(.title2.bold())
                    Spacer()
                    Text(hunt.rarity.title).font(.caption.bold())
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color(uiColor: MonsterFactory.color(for: hunt.rarity)).opacity(0.25), in: Capsule())
                }
            }
            Text(hunt.stage == .scanning
                 ? (hunt.surfaceReady ? "След найден. Выпусти монстра на эту поверхность" : "Наведи прицел на землю в 0,5–3 метрах и немного подожди")
                 : hunt.message)
                .font(.subheadline).multilineTextAlignment(.center).frame(minHeight: 40)

            switch hunt.stage {
            case .scanning:
                action("Найти монстра", icon: "sparkles", enabled: hunt.surfaceReady && hunt.trackingReady) { hunt.spawn() }
                Text("Прототип: появление по кнопке на найденной поверхности")
                    .font(.caption2).foregroundStyle(.white.opacity(0.65)).multilineTextAlignment(.center)
            case .encounter:
                action("Поймать", icon: "scope", enabled: hunt.aimed && hunt.trackingReady) { hunt.catchMonster() }
                Text(hunt.aimed ? "Маленькое кольцо повышает шанс" : "Прицелься в монстра с расстояния 0,5–3 м")
                    .font(.caption).foregroundStyle(mint)
                Button("Искать в другом месте") { hunt.resetSearch() }.font(.caption)
            case .catching:
                ProgressView().tint(mint).frame(height: 56)
            case .caught:
                action("Продолжить охоту", icon: "arrow.right", enabled: true) { hunt.resetSearch() }
            }
        }.padding(20).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
    }

    private func action(_ title: String, icon: String, enabled: Bool, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Label(title, systemImage: icon).font(.headline).frame(maxWidth: .infinity).frame(height: 56)
        }
        .background(enabled ? mint : .white.opacity(0.15), in: Capsule())
        .foregroundStyle(enabled ? .black : .white.opacity(0.5)).disabled(!enabled)
    }
}
