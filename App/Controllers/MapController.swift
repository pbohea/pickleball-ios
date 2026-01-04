import SwiftUI
import UIKit
import HotwireNative

class MapController: UIHostingController<MapView> {
    
    init(url: URL, navigator: Navigator) {
        let viewModel = EventViewModel(url: url)
        let view = MapView(viewModel: viewModel, navigator: navigator)
        super.init(rootView: view)
        
        // Configure navigation bar appearance for this specific controller
        setupNavigationBarAppearance()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Ensure the view background is consistent
        view.backgroundColor = .systemBackground
        
        // Prevent any automatic navigation bar style changes
        navigationController?.navigationBar.prefersLargeTitles = false
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Force navigation bar appearance on each appearance
        setupNavigationBarAppearance()
        
        // Ensure tab bar remains visible and styled correctly
        tabBarController?.tabBar.isHidden = false
        tabBarController?.tabBar.alpha = 1.0
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Additional safety check for navigation bar
        navigationController?.setNavigationBarHidden(false, animated: false)
    }
    
    private func setupNavigationBarAppearance() {
        guard let navigationBar = navigationController?.navigationBar else { return }
        
        // Create a fresh appearance object
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .systemBackground
        appearance.titleTextAttributes = [.foregroundColor: UIColor.label]
        appearance.shadowColor = .clear
        
        // Apply to all states
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
        
        // Set additional properties
        navigationBar.isTranslucent = false
        navigationBar.tintColor = .systemBlue
        navigationBar.backgroundColor = .systemBackground
        
        // Force immediate update
        navigationBar.setNeedsLayout()
    }
}
