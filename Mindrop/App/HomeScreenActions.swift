import MindropIntents
import UIKit

final class HomeScreenActionAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        if connectingSceneSession.role == .windowApplication {
            configuration.delegateClass = HomeScreenActionSceneDelegate.self
        }
        return configuration
    }
}

final class HomeScreenActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let shortcutItem = connectionOptions.shortcutItem {
            handle(shortcutItem)
        }
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(handle(shortcutItem))
    }

    @discardableResult
    private func handle(_ item: UIApplicationShortcutItem) -> Bool {
        switch item.type {
        case "mfsaglam.Mindrop.newMemory":
            NewMemoryRequest.shared.request(scanning: false)
        case "mfsaglam.Mindrop.scan":
            NewMemoryRequest.shared.request(scanning: true)
        default:
            return false
        }
        return true
    }
}
