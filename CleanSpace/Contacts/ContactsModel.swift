import Foundation
import Observation

@Observable
@MainActor
final class ContactsModel {
    private(set) var phase: ScanPhase = .idle
    private(set) var groups: [ContactGroup] = []
    private(set) var totalContacts = 0
    private(set) var hasResults = false

    @ObservationIgnored var onFinished: (@MainActor () -> Void)?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var token = 0

    /// Number of contact cards that would disappear if every group were merged.
    var duplicateCount: Int { groups.reduce(0) { $0 + max($1.contacts.count - 1, 0) } }
    var likelyGroups: [ContactGroup] { groups.filter { $0.confidence == .likely } }
    var reviewGroups: [ContactGroup] { groups.filter { $0.confidence == .review } }

    func group(id: String) -> ContactGroup? { groups.first { $0.id == id } }

    func scan() {
        task?.cancel()
        token += 1
        let current = token
        phase = .scanning(done: 0, total: 0)
        task = Task { [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) { () -> Result<ContactScanResult, Error> in
                do { return .success(try ContactService.scan()) } catch { return .failure(error) }
            }.value
            guard let self, self.token == current else { return }
            switch outcome {
            case let .success(result):
                self.groups = result.groups
                self.totalContacts = result.totalContacts
                self.hasResults = true
                self.phase = .finished
            case .failure:
                self.phase = .failed("CleanSpace couldn't read your contacts. Please try again.")
            }
            self.task = nil
            self.onFinished?()
        }
    }

    func cancel() {
        guard phase.isScanning else { return }
        token += 1
        task?.cancel()
        task = nil
        phase = hasResults ? .finished : .idle
    }

    func reset() {
        token += 1
        task?.cancel()
        task = nil
        phase = .idle
        groups = []
        totalContacts = 0
        hasResults = false
    }
}
