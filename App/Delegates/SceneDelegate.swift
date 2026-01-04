import HotwireNative
import UIKit
import WebKit

//dev
let baseURL = URL(string: "https://barchordtestdomain.ngrok.app")!
//prod
//let baseURL = URL(string: "https://pickleball.co")!

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    
    private var navigators: [Int: Navigator] = [:]

    
    private lazy var tabBarController = HotwireTabBarController(
        navigatorDelegate: self
    )
    private lazy var notificationRouter = NotificationRouter(
        navigationHandler: tabBarController
    )
    
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        
        window = UIWindow(windowScene: windowScene)
        
        // Configure global navigation bar appearance BEFORE setting up controllers
        configureNavigationBarAppearance()
        
        // Configure tab bar appearance
        configureTabBarAppearance()
        
        // Set up the tab bar controller
        UNUserNotificationCenter.current().delegate = notificationRouter
        window?.rootViewController = tabBarController
        tabBarController.load(HotwireTab.all)
        tabBarController.selectedIndex = 0
        
        // Additional configuration after setup
        configureAfterSetup()
        
        window?.makeKeyAndVisible()
        
        if let activity = connectionOptions.userActivities.first(where: { $0.activityType == NSUserActivityTypeBrowsingWeb }),
           let url = activity.webpageURL {
            DispatchQueue.main.async { [weak self] in
                self?.handleUniversalLink(url)
            }
        }
    }
    
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else { return }
        handleUniversalLink(url)
    }
    
    private func configureAfterSetup() {
        // Ensure all child navigation controllers inherit the appearance
        tabBarController.viewControllers?.forEach { viewController in
            if let navController = viewController as? UINavigationController {
                let appearance = UINavigationBarAppearance()
                appearance.configureWithOpaqueBackground()
                appearance.backgroundColor = .systemBackground
                appearance.titleTextAttributes = [.foregroundColor: UIColor.label]
                appearance.shadowColor = .clear

                navController.navigationBar.standardAppearance = appearance
                navController.navigationBar.scrollEdgeAppearance = appearance
                navController.navigationBar.compactAppearance = appearance
                navController.navigationBar.isTranslucent = false
            }
        }

        // Configure web views for inline video playback
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.configureAllWebViews()
        }

        // Add person icon to initial view controllers
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.addPersonIconsToAllTabs()
        }
    }

    private func configureAllWebViews() {
        tabBarController.viewControllers?.forEach { viewController in
            if let navController = viewController as? UINavigationController {
                navController.viewControllers.forEach { vc in
                    if let webView = findWebView(in: vc.view) {
                        configureWebView(webView)
                    }
                }
            }
        }
    }

    private func configureWebView(_ webView: WKWebView) {
        let config = webView.configuration
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = false
        print("✅ Configured WebView for inline video playback")
    }


    
    private func findWebView(in view: UIView?) -> WKWebView? {
        guard let view = view else { return nil }
        
        if let webView = view as? WKWebView {
            return webView
        }
        
        for subview in view.subviews {
            if let found = findWebView(in: subview) {
                return found
            }
        }
        return nil
    }
    
    private func findWebViewInNavigationController(_ navController: UINavigationController) -> WKWebView? {
        if let topViewController = navController.topViewController {
            return findWebView(in: topViewController.view)
        }
        return nil
    }
    
    private func configureNavigationBarAppearance() {
        // Create a consistent appearance for all navigation bars
        let standardAppearance = UINavigationBarAppearance()
        standardAppearance.configureWithOpaqueBackground()
        standardAppearance.backgroundColor = .systemBackground
        standardAppearance.titleTextAttributes = [.foregroundColor: UIColor.label]
        standardAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor.label]
        
        // Apply to all navigation bar states
        UINavigationBar.appearance().standardAppearance = standardAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = standardAppearance
        UINavigationBar.appearance().compactAppearance = standardAppearance
        
        // Additional properties to ensure consistency
        UINavigationBar.appearance().isTranslucent = false
        UINavigationBar.appearance().tintColor = .systemBlue
        UINavigationBar.appearance().barTintColor = .systemBackground
    }
    
    private func configureTabBarAppearance() {
        // Create a consistent appearance for the tab bar
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = .systemBackground
        
        // Configure item appearances
        tabBarAppearance.stackedLayoutAppearance.normal.iconColor = .systemGray
        tabBarAppearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.systemGray]
        tabBarAppearance.stackedLayoutAppearance.selected.iconColor = .systemBlue
        tabBarAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.systemBlue]
        
        // Apply to all tab bar states
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
        
        // Additional properties
        tabBarController.tabBar.isTranslucent = false
        tabBarController.tabBar.backgroundColor = .systemBackground
        tabBarController.tabBar.tintColor = .systemBlue
        tabBarController.tabBar.unselectedItemTintColor = .systemGray
    }
    
    // MARK: - Alert Helper
    private func showSignInAlert(completion: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            // Find the topmost view controller
            var topController = self?.window?.rootViewController
            while let presented = topController?.presentedViewController {
                topController = presented
            }
            
            let alert = UIAlertController(
                title: "Sign In Required",
                message: "You need to sign in to follow Artists & Venues.",
                preferredStyle: .alert
            )
            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            
            alert.addAction(UIAlertAction(title: "Sign In", style: .default) { _ in
                completion()
            })
            
            topController?.present(alert, animated: true)
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    private func handleUniversalLink(_ url: URL) {
        // Accept only our domains (include dev host while testing)
        let allowedHosts = ["pickleball.co", "www.pickleball.co", "barchordtestdomain.ngrok.app"]
        guard let host = url.host?.lowercased(), allowedHosts.contains(host) else { return }

        // Normalize incoming link to current baseURL’s scheme/host (so dev/prod both work)
        var dest = url
        if var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            comps.scheme = baseURL.scheme
            comps.host   = baseURL.host
            // preserve path/query/fragment
            if let rebuilt = comps.url { dest = rebuilt }
        }

        // Drive the current tab’s web view to the deep-linked URL.
        // Your NavigatorDelegate will turn /events/map into MapController automatically.
        guard let selectedNav = tabBarController.selectedViewController as? UINavigationController,
              let topVC = selectedNav.topViewController,
              let webView = findWebView(in: topVC.view) else {
            return
        }

        let escaped = dest.absoluteString.replacingOccurrences(of: "'", with: "\\'")
        webView.evaluateJavaScript("window.location.href = '\(escaped)'", completionHandler: nil)
    }
}

// MARK: - Person Icon Management
extension SceneDelegate {
    private func addPersonIconsToAllTabs() {
        tabBarController.viewControllers?.enumerated().forEach { index, viewController in
            if let navController = viewController as? UINavigationController,
               let topViewController = navController.topViewController,
               !(topViewController is MapController) {
                addPersonIconToViewController(topViewController)
            }
        }
    }
    
    private func addPersonIconToViewController(_ viewController: UIViewController) {
        let personButton = UIBarButtonItem(
            image: UIImage(systemName: "person.circle"),
            style: .plain,
            target: self,
            action: #selector(personIconTapped)
        )
        
        viewController.navigationItem.rightBarButtonItem = personButton
    }
    
    private func addPersonIconToCurrentViewController() {
        guard let selectedViewController = tabBarController.selectedViewController as? UINavigationController,
              let topViewController = selectedViewController.topViewController,
              !(topViewController is MapController) else {
            return
        }
        
        addPersonIconToViewController(topViewController)
    }
    
    @objc private func personIconTapped() {
        // Simple approach: navigate using JavaScript injection
        guard let selectedViewController = tabBarController.selectedViewController as? UINavigationController,
              let topViewController = selectedViewController.topViewController else {
            return
        }
        
        // Find the web view in the current view controller
        if let webView = findWebView(in: topViewController.view) {
            let script = "window.location.href = '\(baseURL.appending(path: "menu").absoluteString)'"
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }
}

// MARK: - NavigatorDelegate
extension SceneDelegate: NavigatorDelegate {
    func handle(
        proposal: VisitProposal,
        from navigator: Navigator
    ) -> ProposalResult {
       
        // Store navigator by tab index
        if let tabIndex = tabBarController.selectedIndex as Int? {
            navigators[tabIndex] = navigator
        }
        
        let result: ProposalResult
        
        switch proposal.viewController {
        case "map":
            if proposal.url.path == "/events/map" || proposal.url.path == "/map/map" {
                // If the URL includes map data, render Swift native map
                result = .acceptCustom(MapController(url: proposal.url, navigator: navigator))
            } else {
                // Otherwise, render the HTML location entry form
                result = .accept
            }
        default:
            result = .accept
        }
        
        // Add person icon to all web-based views (not MapController)
        if case .accept = result {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.addPersonIconToCurrentViewController()
            }
        }
        
        return result
    }
    
    func webViewConfiguration(for navigator: Navigator) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()

        // Use shared data store for all web views
        configuration.websiteDataStore = WKWebsiteDataStore.default()

        // Use shared process pool
       // configuration.processPool = SharedWebViewProcessPool.shared.processPool

        // Set user agent for session identification
        configuration.applicationNameForUserAgent = "Pickleball-iOS/1.0"

        // Enable inline media playback (prevents fullscreen video)
        configuration.allowsInlineMediaPlayback = true

        // Allow autoplay for all media types without user interaction
        configuration.mediaTypesRequiringUserActionForPlayback = []

        // Configure preferences for video playback
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.preferences.javaScriptEnabled = true

        // Allow picture-in-picture and inline playback
        configuration.allowsPictureInPictureMediaPlayback = false

        // Suppress incremental rendering until page loads
        configuration.suppressesIncrementalRendering = false

        // Allow arbitrary loads for media content
        configuration.limitsNavigationsToAppBoundDomains = false

        return configuration
    }
}
