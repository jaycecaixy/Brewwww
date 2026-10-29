import CoreHaptics
import SwiftUI
import UIKit

enum BrewHapticStrength: String, CaseIterable, Identifiable {
    case small, medium, large

    static let storageKey = "hapticStrength"
    static let defaultValue = BrewHapticStrength.medium
    var id: String { rawValue }
    var title: String {
        switch self {
        case .small: "小"
        case .medium: "中"
        case .large: "大"
        }
    }

    var pressFeedback: SensoryFeedback {
        switch self {
        case .small: .impact(weight: .light, intensity: 0.4)
        case .medium: .impact(weight: .medium, intensity: 0.75)
        case .large: .impact(weight: .heavy, intensity: 1)
        }
    }

    var landingEvents: [CHHapticEvent] {
        func impact(_ intensity: Float, at time: TimeInterval) -> CHHapticEvent {
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                .init(parameterID: .hapticIntensity, value: intensity),
                .init(parameterID: .hapticSharpness, value: 0.35)
            ], relativeTime: time)
        }
        switch self {
        case .small:
            return [impact(0.4, at: 0)]
        case .medium:
            return [impact(0.85, at: 0), impact(0.4, at: 0.08)]
        case .large:
            // A full-strength landing with a sustained thud and rebound.
            return [impact(1, at: 0),
                    CHHapticEvent(eventType: .hapticContinuous, parameters: [
                        .init(parameterID: .hapticIntensity, value: 1),
                        .init(parameterID: .hapticSharpness, value: 0.2)
                    ], relativeTime: 0, duration: 0.18),
                    impact(1, at: 0.20)]
        }
    }
}

@MainActor
protocol BrewContinuousHaptics: AnyObject {
    func prepare()
    func startContinuous(duration: TimeInterval)
    func stopContinuous()
}

@MainActor
final class BrewHaptics: BrewContinuousHaptics {
    static let shared = BrewHaptics()
    private var engine: CHHapticEngine?
    private var player: (any CHHapticPatternPlayer)?

    func prepare() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            if engine == nil {
                let engine = try CHHapticEngine()
                engine.playsHapticsOnly = true
                engine.isAutoShutdownEnabled = true
                engine.resetHandler = { [weak self] in
                    Task { @MainActor in
                        self?.player = nil
                        self?.engine = nil
                    }
                }
                self.engine = engine
            }
            try engine?.start()
        } catch {
            engine = nil
        }
    }

    func startContinuous(duration: TimeInterval) {
        stopContinuous()
        guard duration > 0 else { return }
        prepare()
        guard let engine else { return }
        do {
            let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [
                .init(parameterID: .hapticIntensity, value: 0.7),
                .init(parameterID: .hapticSharpness, value: 0.2)
            ], relativeTime: 0, duration: duration)
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let next = try engine.makePlayer(with: pattern)
            try next.start(atTime: CHHapticTimeImmediate)
            player = next
        } catch {
            stopContinuous()
            self.engine = nil
        }
    }

    func stopContinuous() {
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
    }

    func landing(strength: BrewHapticStrength) {
        prepare()
        if let engine {
            do {
                let pattern = try CHHapticPattern(events: strength.landingEvents, parameters: [])
                try player?.stop(atTime: CHHapticTimeImmediate)
                let next = try engine.makePlayer(with: pattern)
                try next.start(atTime: CHHapticTimeImmediate)
                player = next
                return
            } catch {
                self.engine = nil
                player = nil
            }
        }
        let style: UIImpactFeedbackGenerator.FeedbackStyle = switch strength {
        case .small: .light
        case .medium: .heavy
        case .large: .heavy
        }
        UIImpactFeedbackGenerator(style: style).impactOccurred(intensity: strength == .small ? 0.4 : 1)
    }
}
