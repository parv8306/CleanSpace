import Foundation
import LocalAuthentication
import Observation

/// Passcode / Face ID gate for the private vault. The vault relocks whenever the app leaves the
/// foreground or the vault screen closes.
@Observable
@MainActor
final class VaultLock {
    enum State: Equatable {
        case needsSetup
        case locked
        case unlocked
    }

    private(set) var state: State
    private(set) var failedAttempts: Int
    private(set) var lockedUntil: Date?
    private(set) var isWorking = false
    var biometricsEnabled: Bool {
        didSet { defaults.set(biometricsEnabled, forKey: Keys.biometrics) }
    }

    @ObservationIgnored private let defaults = UserDefaults.standard

    private enum Keys {
        static let biometrics = "cleanspace.vault.biometrics"
        static let failures = "cleanspace.vault.failures"
        static let lockedUntil = "cleanspace.vault.lockedUntil"
    }

    init() {
        state = PasscodeStore.hasPasscode ? .locked : .needsSetup
        biometricsEnabled = UserDefaults.standard.bool(forKey: Keys.biometrics)
        failedAttempts = UserDefaults.standard.integer(forKey: Keys.failures)
        lockedUntil = UserDefaults.standard.object(forKey: Keys.lockedUntil) as? Date
    }

    // MARK: Biometrics

    enum Biometry { case none, faceID, touchID, opticID }

    var biometry: Biometry {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else { return .none }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        default: return .none
        }
    }

    var biometryName: String {
        switch biometry {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        case .none: "Face ID"
        }
    }

    var biometrySymbol: String {
        switch biometry {
        case .touchID: "touchid"
        case .opticID: "opticid"
        default: "faceid"
        }
    }

    var canUseBiometrics: Bool { biometricsEnabled && biometry != .none }

    // MARK: Lockout

    /// Seconds left before another passcode attempt is allowed.
    func lockoutRemaining(now: Date = Date()) -> TimeInterval {
        guard let lockedUntil else { return 0 }
        return max(lockedUntil.timeIntervalSince(now), 0)
    }

    private func registerFailure() {
        failedAttempts += 1
        defaults.set(failedAttempts, forKey: Keys.failures)
        if failedAttempts >= 5 {
            // 30 s after five misses, doubling with each further miss, capped at 15 minutes.
            let delay = min(30 * pow(2, Double(failedAttempts - 5)), 900)
            let until = Date().addingTimeInterval(delay)
            lockedUntil = until
            defaults.set(until, forKey: Keys.lockedUntil)
        }
    }

    private func clearFailures() {
        failedAttempts = 0
        lockedUntil = nil
        defaults.removeObject(forKey: Keys.failures)
        defaults.removeObject(forKey: Keys.lockedUntil)
    }

    // MARK: Actions

    /// Saves the first passcode. The vault opens when setup calls `finishSetup()`.
    func createPasscode(_ passcode: String) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        let saved = await Task.detached(priority: .userInitiated) { PasscodeStore.save(passcode) }.value
        if saved { clearFailures() }
        return saved
    }

    func finishSetup() {
        guard PasscodeStore.hasPasscode else { return }
        state = .unlocked
    }

    func unlock(with passcode: String) async -> Bool {
        guard lockoutRemaining() == 0, !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        let ok = await Task.detached(priority: .userInitiated) { PasscodeStore.verify(passcode) }.value
        if ok {
            clearFailures()
            state = .unlocked
        } else {
            registerFailure()
        }
        return ok
    }

    func unlockWithBiometrics() async -> Bool {
        guard canUseBiometrics, state == .locked else { return false }
        let context = LAContext()
        context.localizedFallbackTitle = "Enter PIN"
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                                      localizedReason: "Unlock your private vault")
            if ok {
                clearFailures()
                state = .unlocked
            }
            return ok
        } catch {
            return false
        }
    }

    /// Turning biometrics on asks for a successful scan first, so the setting always works.
    func enableBiometrics() async -> Bool {
        let context = LAContext()
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                                      localizedReason: "Use \(biometryName) to unlock your vault")
            biometricsEnabled = ok
            return ok
        } catch {
            biometricsEnabled = false
            return false
        }
    }

    func changePasscode(current: String, new: String) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        let ok = await Task.detached(priority: .userInitiated) { () -> Bool in
            guard PasscodeStore.verify(current) else { return false }
            return PasscodeStore.save(new)
        }.value
        if !ok { registerFailure() } else { clearFailures() }
        return ok
    }

    func lock() {
        if state == .unlocked || (state == .needsSetup && PasscodeStore.hasPasscode) {
            state = .locked
        }
    }

    /// Removes the passcode, the vault key and every vault file.
    func eraseVault() async {
        await VaultStore.shared.eraseAll()
        PasscodeStore.remove()
        biometricsEnabled = false
        clearFailures()
        state = .needsSetup
    }
}
