import ComposableArchitecture
import SwiftUI
import Amplify
import AWSDataStorePlugin
import AWSAPIPlugin

@main
struct TodosApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene {
    WindowGroup {
      AppView(
        store: Store(
          initialState: AppState(),
          reducer: appReducer,
          environment: AppEnvironment(
            mainQueue: .main,
            uuid: UUID.init,
            datastore: Amplify.DataStore
          )
        )
      )
    }
  }
}
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Amplify.Logging.logLevel = .verbose
        do {
            try Amplify.add(plugin: AWSAPIPlugin())
            let dataStorePlugin = AWSDataStorePlugin(modelRegistration: AmplifyModels())
            try Amplify.add(plugin: dataStorePlugin)
            try Amplify.configure()
            print("Amplify configured with DataStore plugin")
        } catch {
            print("Failed to initialize Amplify with \(error)")
            return false
        }
        Amplify.DataStore.start { result in
            print(result)
        }
        
        return true
    }
}
