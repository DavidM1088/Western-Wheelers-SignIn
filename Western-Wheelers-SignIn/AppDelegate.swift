import UIKit
import GoogleSignIn
import GoogleSignIn
import GoogleAPIClientForREST

class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Initialize sign-in
        GIDSignIn.sharedInstance().clientID = "505823345399-a79vs9g0o24984ionca518phdqdavbuc.apps.googleusercontent.com"
        GIDSignIn.sharedInstance().delegate = GoogleDrive.shared
        GIDSignIn.sharedInstance()?.scopes = [kGTLRAuthScopeDrive]
        return true
    }

}