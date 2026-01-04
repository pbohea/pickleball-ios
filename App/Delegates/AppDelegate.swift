//
//  AppDelegate.swift
//  Pickleball
//
//  Created by Patrick O'Hea on 5/11/25.
//
import HotwireNative
import UIKit
import WebKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    private let viewModel = NotificationTokenViewModel()
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions:
        [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Configure WKWebView up front so videos stay inline and autoplay on iOS
        Hotwire.config.makeCustomWebView = { configuration in
            configuration.allowsInlineMediaPlayback = true
            configuration.mediaTypesRequiringUserActionForPlayback = []
            configuration.allowsPictureInPictureMediaPlayback = false
            configuration.allowsAirPlayForMediaPlayback = false
            return WKWebView(frame: .zero, configuration: configuration)
        }
        
        Hotwire.loadPathConfiguration(from: [
            .server(baseURL.appending(path: "configurations/ios_v1.json"))
        ])
        Hotwire.registerBridgeComponents([
            ButtonComponent.self,
            NotificationTokenComponent.self
        ])
        return true
    }
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await viewModel.register(token) }
    }
    
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: any Error
    ) {
        print("Failed to register token: \(error.localizedDescription)")
    }
}
