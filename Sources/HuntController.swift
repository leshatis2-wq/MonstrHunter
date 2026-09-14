import ARKit
import AVFoundation
import Combine
import RealityKit
import UIKit
import simd

final class HuntController: NSObject, ObservableObject, ARSessionDelegate {
    enum Stage: Equatable { case scanning, encounter, catching, caught }
    @Published var stage: Stage = .scanning
    @Published var surfaceReady = false
    @Published var trackingReady = false
    @Published var aimed = false
    @Published var ring = 1.0
    @Published var distance: Float = 0
    @Published var count = 0
    @Published var rarity: Rarity = .common
    @Published var message = "Медленно направь камеру на землю"
    @Published var blocker: String?
    @Published var permissionDenied = false

    let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
    private var store: CaptureStore?
    private var anchor: AnchorEntity?
    private var creature: Entity?
    private var creatureID = UUID()
    private var placement: ARRaycastResult?
    private var encounterStart: TimeInterval = 0
    private var lastUpdate: TimeInterval = 0
    private var captureWork: DispatchWorkItem?
    private var active = false
    private var started = false

    override init() {
        super.init()
        view.session.delegate = self
        view.session.delegateQueue = .main
        do {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory,
                in: .userDomainMask, appropriateFor: nil, create: true)
            store = try CaptureStore(url: directory.appendingPathComponent("captured-monsters.json"))
            count = store?.monsters.count ?? 0
        } catch {
            blocker = "Не удалось открыть сохранение. Данные не перезаписаны. Перезапусти приложение."
        }
    }

    func activate() {
        active = true
        guard store != nil else { return }
        guard ARWorldTrackingConfiguration.isSupported else {
            blocker = "Этот телефон не поддерживает нужный режим AR."
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionDenied = false
            blocker = nil
            runSession(reset: !started)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self = self, self.active else { return }
                    if granted { self.activate() } else { self.denyCamera() }
                }
            }
        default: denyCamera()
        }
    }

    private func denyCamera() {
        permissionDenied = true
        blocker = "Разреши доступ к камере в настройках, чтобы начать охоту."
    }

    private func runSession(reset: Bool) {
        if reset { lastUpdate = 0 }
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        configuration.environmentTexturing = .automatic
        // Core gameplay deliberately does not require LiDAR.
        view.session.run(configuration, options: reset ? [.resetTracking, .removeExistingAnchors] : [])
        started = true
    }

    func suspend() {
        active = false
        captureWork?.cancel()
        captureWork = nil
        if stage == .catching {
            stage = .encounter
            message = "Ловля прервана. Попробуй ещё раз"
        }
        view.session.pause()
        trackingReady = false
        surfaceReady = false
        aimed = false
        placement = nil
    }

    func resetSearch() {
        captureWork?.cancel()
        captureWork = nil
        if let anchor = anchor { view.scene.removeAnchor(anchor) }
        anchor = nil
        creature = nil
        placement = nil
        surfaceReady = false
        aimed = false
        stage = .scanning
        message = "Медленно направь камеру на землю"
        if active, blocker == nil { runSession(reset: true) }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard active, blocker == nil else { return }
        guard frame.timestamp - lastUpdate > 1.0 / 20.0 else { return }
        lastUpdate = frame.timestamp
        guard case .normal = frame.camera.trackingState else {
            trackingReady = false
            surfaceReady = false
            aimed = false
            placement = nil
            return
        }
        trackingReady = true
        let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        if stage == .scanning {
            let hit = view.raycast(from: center, allowing: .existingPlaneGeometry, alignment: .horizontal).first
            let camera = frame.camera.transform.columns.3
            if let hit = hit {
                let point = hit.worldTransform.columns.3
                let range = simd_distance(SIMD3(camera.x, camera.y, camera.z), SIMD3(point.x, point.y, point.z))
                // Plane detection is geometric, not grass or floor classification.
                // A downward hit below the camera avoids spawning on high surfaces.
                placement = point.y < camera.y - 0.35 && HuntRules.inRange(range) ? hit : nil
            } else { placement = nil }
            surfaceReady = placement != nil
        }
        if stage == .encounter, let creature = creature {
            ring = HuntRules.ringScale(elapsed: frame.timestamp - encounterStart)
            let camera = frame.camera.transform.columns.3
            distance = simd_distance(creature.position(relativeTo: nil), SIMD3(camera.x, camera.y, camera.z))
            var entity = view.entity(at: center)
            var hitCreature = false
            while let current = entity {
                if current === creature { hitCreature = true; break }
                entity = current.parent
            }
            aimed = hitCreature && HuntRules.inRange(distance)
        }
    }

    func spawn() {
        guard stage == .scanning, active, trackingReady, let result = placement else { return }
        rarity = .roll(Int.random(in: 0..<100))
        creatureID = UUID()
        let newAnchor = AnchorEntity(raycastResult: result)
        let model = MonsterFactory.make(rarity: rarity)
        newAnchor.addChild(model)
        view.scene.addAnchor(newAnchor)
        // Face the player once. The creature remains fixed as the player walks around it.
        if let frame = view.session.currentFrame {
            let camera = frame.camera.transform.columns.3
            let origin = result.worldTransform.columns.3
            let yaw = atan2(camera.x - origin.x, camera.z - origin.z)
            model.setOrientation(simd_quatf(angle: yaw, axis: [0, 1, 0]), relativeTo: nil)
            encounterStart = frame.timestamp
        }
        anchor = newAnchor
        creature = model
        stage = .encounter
        ring = 1
        aimed = false
        message = "Это Мохлик! Наведи прицел на него"
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func catchMonster() {
        guard stage == .encounter, active, trackingReady, aimed, let creature = creature else { return }
        stage = .catching
        aimed = false
        message = "Капсула удерживает Мохлика…"
        let success = Double.random(in: 0..<1) < HuntRules.probability(rarity: rarity, ring: ring)
        let id = creatureID
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let work = DispatchWorkItem { [weak self, weak creature] in
            guard let self = self, self.active, self.stage == .catching,
                  self.creatureID == id, let creature = creature else { return }
            guard self.trackingReady else {
                self.stage = .encounter
                self.message = "Слежение потеряно. Наведи камеру на монстра"
                return
            }
            if success {
                do {
                    guard let store = self.store else { return }
                    try store.append(CapturedMonster(id: id, species: "mossling",
                        rarity: self.rarity, caughtAt: Date()))
                    self.count = store.monsters.count
                    creature.removeFromParent()
                    self.stage = .caught
                    self.message = "Мохлик пойман и сохранён для будущего зоопарка"
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } catch {
                    self.stage = .encounter
                    self.message = "Не удалось сохранить монстра. Проверь свободное место и повтори ловлю"
                }
            } else {
                self.stage = .encounter
                self.message = "Вырвался! Лови, когда кольцо станет маленьким"
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }
        }
        captureWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85, execute: work)
    }

    func sessionWasInterrupted(_ session: ARSession) {
        captureWork?.cancel()
        captureWork = nil
        if stage == .catching { stage = .encounter }
        trackingReady = false
        aimed = false
        surfaceReady = false
        placement = nil
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        resetSearch()
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        suspend()
        blocker = "Камера AR остановилась: \(error.localizedDescription)"
    }
}
