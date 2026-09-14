import RealityKit
import UIKit

enum MonsterFactory {
    static func color(for rarity: Rarity) -> UIColor {
        switch rarity {
        case .common: return UIColor(red: 0.40, green: 0.86, blue: 0.65, alpha: 1)
        case .rare: return UIColor(red: 0.35, green: 0.70, blue: 1, alpha: 1)
        case .epic: return UIColor(red: 0.75, green: 0.48, blue: 0.96, alpha: 1)
        case .legendary: return UIColor(red: 1, green: 0.73, blue: 0.25, alpha: 1)
        }
    }

    // Temporary original 3D creature. Ground is y=0; the face looks toward +Z.
    // Replace this factory with a normalized Blender USDZ asset after AR testing.
    static func make(rarity: Rarity) -> Entity {
        let root = Entity()
        root.name = "monster"
        let tint = color(for: rarity)
        func blob(_ name: String, _ radius: Float, _ position: SIMD3<Float>,
                  _ scale: SIMD3<Float>, _ color: UIColor) {
            let material = SimpleMaterial(color: color, roughness: 0.65, isMetallic: false)
            let part = ModelEntity(mesh: .generateSphere(radius: radius), materials: [material])
            part.name = name
            part.position = position
            part.scale = scale
            root.addChild(part)
        }
        blob("body", 0.18, [0, 0.21, 0], [1, 1.12, 0.84], tint)
        blob("belly", 0.105, [0, 0.17, 0.125], [1, 1.1, 0.28], UIColor(white: 0.96, alpha: 1))
        for side in [Float(-1), Float(1)] {
            blob("ear", 0.065, [side * 0.115, 0.41, 0], [0.7, 1.6, 0.65], tint)
            blob("foot", 0.055, [side * 0.10, 0.037, 0.04], [1, 0.67, 1.3], tint)
            blob("arm", 0.055, [side * 0.175, 0.19, 0], [0.65, 1.25, 0.75], tint)
            blob("eye", 0.029, [side * 0.064, 0.285, 0.132], [0.8, 1.15, 0.45], .black)
            blob("eyeLight", 0.009, [side * 0.064 - 0.007, 0.297, 0.145], [1, 1, 0.5], .white)
            blob("cheek", 0.025, [side * 0.108, 0.24, 0.13], [1, 0.5, 0.3], .systemPink)
        }
        blob("mouth", 0.014, [0, 0.241, 0.15], [1, 0.55, 0.4], .darkGray)
        root.generateCollisionShapes(recursive: true)
        return root
    }
}
