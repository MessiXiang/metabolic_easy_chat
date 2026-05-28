import Sparkle
import SwiftUI

final class AppUpdateController: NSObject, ObservableObject {
    let updaterController: SPUStandardUpdaterController

    override init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    @MainActor
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}

private struct AppUpdateControllerKey: EnvironmentKey {
    static let defaultValue = AppUpdateController()
}

extension EnvironmentValues {
    var appUpdateController: AppUpdateController {
        get { self[AppUpdateControllerKey.self] }
        set { self[AppUpdateControllerKey.self] = newValue }
    }
}
