import Foundation
import os
import Sparkle

@MainActor
final class UpdaterController {
    static let shared = UpdaterController()

    let controller: SPUStandardUpdaterController
    private let delegate: UpdaterDelegate

    private init() {
        let delegate = UpdaterDelegate()
        self.delegate = delegate
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: delegate,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    private static let logger = Logger(subsystem: "dev.ilkome.MaCopy", category: "updater")

    func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? {
        []
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        Self.logger.info("installing update version=\(item.displayVersionString, privacy: .public) build=\(item.versionString, privacy: .public)")
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        Self.logger.error("update aborted: \(error.localizedDescription, privacy: .public)")
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        if let error {
            Self.logger.error("update cycle finished with error: \(error.localizedDescription, privacy: .public)")
        }
    }
}
