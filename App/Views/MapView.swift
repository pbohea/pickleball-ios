import MapKit
import SwiftUI
import HotwireNative
import UIKit

struct MapView: View {
    var viewModel: EventViewModel
    let navigator: Navigator?
    
    // Filter states
    @State private var filtersActive = false
    @State private var selectedCategories: Set<String> = ["All"]
//    @State private var selectedVenueTypes: Set<String> = ["All"]
    @State private var filterCoverOnly: Bool = false
    @State private var filterIndoorsOnly: Bool = false
    @State private var filterOutdoorsOnly: Bool = false
    @State private var showFilterSheet = false
    
    // UI states
    @State private var selectedEvent: Event?
    @State private var venueURLToShow: IdentifiableURL?
    @State private var showAddressSearch = false
    @State private var showPinActionSheet = false // NEW: For pin action sheet
    @State private var selectedPinEvent: Event? // NEW: Track which pin was tapped
    
    // Location and map state
    @StateObject private var locationManager = LocationManager()
    @StateObject private var mapStateManager = MapStateManager()
    @State private var hasInitialized = false
    @State private var hasSetInitialPosition = false
    @State private var shouldCenterOnUser = false
    @State private var hasProcessedURLCoordinate = false
    @State private var isWaitingForURLResponse = false
    @State private var lastProcessedURL: String? // NEW: Track which URL we last processed
    
    // Add highlighted venue state
    @State private var highlightedVenueId: Int?
    
    // Map position - will be updated based on location/saved state
    @State private var mapPosition = MapCameraPosition.region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 41.8781, longitude: -87.6298),
        span: MKCoordinateSpan(latitudeDelta: 0.058, longitudeDelta: 0.029)
    ))
    
    struct IdentifiableURL: Identifiable {
        let id = UUID()
        let url: URL
    }
    
    var displayedEvents: [Event] {
        let events = filtersActive ? filteredEvents : viewModel.events
        
        // Group by venue ID and return only the soonest event per venue
        let grouped = Dictionary(grouping: events) { $0.venue.id }
        return grouped.compactMap { (venueId, venueEvents) in
            venueEvents.min { $0.startTimeDate < $1.startTimeDate }
        }
    }
    
    var filteredEvents: [Event] {
        viewModel.events.filter { event in
            let matchCategory = selectedCategories.contains("All") || selectedCategories.contains(event.category ?? "")
//            let matchVenueType = selectedVenueTypes.contains("All") || selectedVenueTypes.contains(event.venue.category)
            let matchCover = !filterCoverOnly || (filterCoverOnly && !event.cover)
            let matchIndoors = !filterIndoorsOnly || (filterIndoorsOnly && event.indoors)
            let matchOutdoors = !filterOutdoorsOnly || (filterOutdoorsOnly && !event.indoors)
            return matchCategory &&  matchCover && matchIndoors && matchOutdoors
//            matchVenueType
        }
    }
    
    var body: some View {
        ZStack {
            if viewModel.isLoading {
                LoadingView()
            } else if viewModel.hasError {
                ErrorView(
                    message: viewModel.errorMessage ?? "Unknown error occurred",
                    onRetry: {
                        Task {
                            await viewModel.retry()
                        }
                    }
                )
            } else if displayedEvents.isEmpty {
                EmptyStateView()
            } else {
                MapContentView()
            }
            
            // Show address search prompt if location permission is denied
            if locationManager.isLocationPermissionDenied {
                VStack {
                    Spacer()
                    LocationDeniedPrompt()
                        .padding()
                }
            }
        }
        .navigationTitle("Map")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    let menuURL = baseURL.appending(path: "menu")
                    navigator?.route(menuURL)
                } label: {
                    Image(systemName: "person.circle")
                }
                
                Button {
                    showFilterSheet = true
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .disabled(viewModel.isLoading)
            }
        }
//        .sheet(isPresented: $showFilterSheet) {
//            FilterSheetView(
//                eventCategories: ["All", "Guitar", "Band", "Piano", "DJ", "Other"],
////                venueTypes: ["All", "Restaurant", "Pub", "Bar & Restaurant", "Other"],
//                selectedCategories: $selectedCategories,
////                selectedVenueTypes: $selectedVenueTypes,
//                coverOnly: $filterCoverOnly,
//                indoorsOnly: $filterIndoorsOnly,
//                outdoorsOnly: $filterOutdoorsOnly,
//                onApply: {
//                    filtersActive = true
//                    showFilterSheet = false
//                }
//            )
//        }
        .sheet(isPresented: $showFilterSheet) {
            FilterSheetView(
                eventCategories: ["All", "Guitar", "Band", "Piano", "DJ", "Other"],
                selectedCategories: $selectedCategories,
                coverOnly: $filterCoverOnly,
                indoorsOnly: $filterIndoorsOnly,
                outdoorsOnly: $filterOutdoorsOnly,
                onApply: {
                    filtersActive = true
                    showFilterSheet = false
                }
            )
        }
        .sheet(item: $selectedEvent) { event in
            EventDetailSheet(event: event, navigator: navigator)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $venueURLToShow) { wrapper in
            SafariView(url: wrapper.url)
        }
        .sheet(isPresented: $showAddressSearch) {
            AddressSearchView(isPresented: $showAddressSearch) { coordinate in
                centerMapOn(coordinate: coordinate)
            }
        }
        .confirmationDialog("Event Actions", isPresented: $showPinActionSheet, presenting: selectedPinEvent) { event in
            Button("Show Event Details") {
                selectedEvent = event
            }
            Button("Open in Apple Maps") {
                openInAppleMaps(venue: event.venue)
            }
            Button("Cancel", role: .cancel) { }
        } message: { event in
            Text("\(event.venue.name)")
        }
        .task(id: viewModel.url.absoluteString) {
            await initializeMap()
        }
        .refreshable {
            await viewModel.retry()
        }
        // UPDATED: Priority handling for center coordinate vs. auto-adjusting
        .onChange(of: viewModel.events) { oldEvents, newEvents in
            if !newEvents.isEmpty && !viewModel.isLoading {
                // Set highlighted venue from the view model
                highlightedVenueId = viewModel.selectedVenueId
                
                // Priority 1: Center on specified coordinate if provided (from URL params)
                if let centerCoord = viewModel.centerCoordinate, !hasProcessedURLCoordinate {
                    print("🎯 Processing URL coordinate for the first time: \(centerCoord)")
                    hasProcessedURLCoordinate = true
                    hasSetInitialPosition = true
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        centerMapOn(coordinate: centerCoord)
                        
                        // Force a map refresh after centering to ensure pins appear
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            print("🔄 Forcing map refresh after centering")
                            // Simple refresh by creating a slightly different region
                            let nudgedRegion = MKCoordinateRegion(
                                center: CLLocationCoordinate2D(
                                    latitude: centerCoord.latitude + 0.0001,
                                    longitude: centerCoord.longitude + 0.0001
                                ),
                                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                            )
                            mapPosition = MapCameraPosition.region(nudgedRegion)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                centerMapOn(coordinate: centerCoord)
                            }
                        }
                        
                        // Auto-select the event at this venue if there's only one
                        if let venueId = viewModel.selectedVenueId {
                            let eventsAtVenue = newEvents.filter { $0.venue.id == venueId }
                            if eventsAtVenue.count == 1 {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    selectedEvent = eventsAtVenue.first
                                    print("🎭 Auto-opened event detail for venue \(venueId)")
                                }
                            }
                        }
                    }
                } else if viewModel.centerCoordinate == nil {
                    // Priority 2: Auto-adjust to show all events (only if no URL coordinate)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        adjustMapToShowEvents()
                    }
                }
            }
        }
        .onChange(of: viewModel.centerCoordinate) { oldCenter, newCenter in
            // Only process if we haven't already handled the URL coordinate
            if let center = newCenter, !hasProcessedURLCoordinate {
                print("🎯 Center coordinate received, processing: \(center)")
                hasProcessedURLCoordinate = true
                hasSetInitialPosition = true
                centerMapOn(coordinate: center)
            }
        }
        .onChange(of: locationManager.userLocation) { oldLocation, newLocation in
            if let newLocation = newLocation {
                handleLocationUpdate(newLocation)
            }
        }
        .onChange(of: locationManager.authorizationStatus) { oldStatus, newStatus in
            handleAuthorizationChange(oldStatus: oldStatus, newStatus: newStatus)
        }
    }
    
    @ViewBuilder
    private func MapContentView() -> some View {
        Map(position: $mapPosition) {
            // Show user location
            if let userLocation = locationManager.userLocation {
                Annotation("Your Location", coordinate: userLocation) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 3)
                        )
                        .shadow(radius: 3)
                }
            }
            
            // UPDATED: Show events with highlighting and action sheet on tap
            ForEach(displayedEvents, id: \.id) { event in
                Annotation(
                    event.label,
                    coordinate: event.venue.coordinate,
                    anchor: .bottom
                ) {
                    Button {
                        selectedPinEvent = event
                        showPinActionSheet = true
                    } label: {
                        Image("mapPinLogo") // <-- name in Assets.xcassets
                            .resizable()
                            .scaledToFit()
                            .frame(
                                width: highlightedVenueId == event.venue.id ? 45 : 40,
                                height: highlightedVenueId == event.venue.id ? 45 : 40
                            )
                            .background(Color.white, in: Circle()) // optional border/background
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 2)
                            )
                            .shadow(radius: highlightedVenueId == event.venue.id ? 5 : 3)
                            .animation(.easeInOut(duration: 0.3), value: highlightedVenueId)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .mapStyle(.hybrid(elevation: .realistic))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .onMapCameraChange { context in
            // Save map state when user pans/zooms
            saveCurrentMapState(context: context)
        }
        .onAppear {
            // Force a refresh when the map appears to ensure pins are visible
            if !displayedEvents.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    adjustMapToShowEvents()
                }
            }
        }
    }
    
    @ViewBuilder
    private func LocationDeniedPrompt() -> some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "location.slash")
                    .foregroundColor(.orange)
                Text("Location access was denied")
                    .font(.headline)
                Spacer()
            }
            
            HStack {
                Text("Search for a location to center the map")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                
                Button("Search") {
                    showAddressSearch = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    @ViewBuilder
    private func LoadingView() -> some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading events...")
                .foregroundColor(.secondary)
            Text("Fetching event data from server...")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
    
    @ViewBuilder
    private func ErrorView(message: String, onRetry: @escaping () -> Void) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            Text("Unable to Load Map")
                .font(.headline)
            
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            VStack(spacing: 12) {
                Button("Retry") {
                    onRetry()
                }
                .buttonStyle(.borderedProminent)
                
                Button("Clear Error") {
                    viewModel.clearError()
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
    
    @ViewBuilder
    private func EmptyStateView() -> some View {
        VStack(spacing: 20) {
            Image(systemName: "map")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            
            Text("No events found")
                .font(.headline)
            
            if filtersActive {
                Text("No events match your current filters.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                Button("Clear Filters") {
                    selectedCategories = ["All"]
//                    selectedVenueTypes = ["All"]
                    filterCoverOnly = false
                    filterIndoorsOnly = false
                    filterOutdoorsOnly = false
                    filtersActive = false
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("No events are available in this area.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                Button("Refresh") {
                    Task {
                        await viewModel.retry()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
    
    // MARK: - Location Methods
    
    private func initializeMap() async {
        let currentURL = viewModel.url.absoluteString
        
        print("🔍 InitializeMap called with URL: \(currentURL)")
        print("🔍 Last processed URL was: \(lastProcessedURL ?? "none")")
        
        // Check if we need to reinitialize for a new URL
        if hasInitialized && lastProcessedURL == currentURL {
            print("🔄 Map already initialized for this URL, skipping: \(currentURL)")
            return
        }
        
        print("🗺️ Initializing map for URL: \(currentURL)")
        
        // Reset all state flags for fresh initialization
        hasProcessedURLCoordinate = false
        isWaitingForURLResponse = false
        hasSetInitialPosition = false
        shouldCenterOnUser = false
        highlightedVenueId = nil
        hasInitialized = true
        lastProcessedURL = currentURL
        
        // Check if URL has parameters that suggest we'll get center coordinates
        if currentURL.contains("lat=") && currentURL.contains("lng=") {
            print("🔍 URL contains coordinates, waiting for server response...")
            isWaitingForURLResponse = true
        } else {
            print("❌ URL does not contain lat/lng parameters")
        }
        
        // Load events first
        await viewModel.fetchCoordinates()
        
        // Mark that we're no longer waiting
        isWaitingForURLResponse = false
        
        // Request location permission
        locationManager.requestLocationPermission()
        
        // Set initial map position
        setInitialMapPosition()
    }
    
    private func setInitialMapPosition() {
        print("📍 Setting initial map position...")
        
        // UPDATED: Check for center coordinate from URL first
        if let centerCoord = viewModel.centerCoordinate, !hasProcessedURLCoordinate {
            print("🎯 Using center coordinate from URL in initial setup: \(centerCoord)")
            hasProcessedURLCoordinate = true
            highlightedVenueId = viewModel.selectedVenueId
            centerMapOn(coordinate: centerCoord)
            hasSetInitialPosition = true
            
            // Force refresh after centering to ensure pins appear
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                print("🔄 Forcing map refresh after URL centering")
                // Use tiny zoom change instead of position nudge - much more subtle
                let currentSpan = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                let nudgedSpan = MKCoordinateSpan(
                    latitudeDelta: 0.01001,  // Even smaller change: 0.5% instead of 1%
                    longitudeDelta: 0.01001
                )
                
                // Instant tiny zoom out
                mapPosition = MapCameraPosition.region(MKCoordinateRegion(center: centerCoord, span: nudgedSpan))
                
                // Quicker restore with even smoother animation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { // Faster: 0.02 instead of 0.03
                    withAnimation(.easeInOut(duration: 0.05)) { // Shorter: 0.05 instead of 0.1
                        mapPosition = MapCameraPosition.region(MKCoordinateRegion(center: centerCoord, span: currentSpan))
                    }
                    print("🎯 Map refresh complete - pins should now be visible")
                }
            }
            
            // Auto-select event if there's only one at this venue
            if let venueId = viewModel.selectedVenueId {
                let eventsAtVenue = viewModel.events.filter { $0.venue.id == venueId }
                if eventsAtVenue.count == 1 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        selectedEvent = eventsAtVenue.first
                        print("🎭 Auto-opened event detail for venue \(venueId)")
                    }
                }
            }
            return
        }
        
        if locationManager.hasLocationPermission, let userLocation = locationManager.userLocation {
            print("✅ User has location permission and location available")
            // Only center on user if we don't have URL coordinates
            if viewModel.centerCoordinate == nil {
                centerMapOn(coordinate: userLocation)
                hasSetInitialPosition = true
            }
        } else if let savedRegion = mapStateManager.getSavedRegion() {
            print("💾 Restoring saved map position")
            mapPosition = MapCameraPosition.region(savedRegion)
            hasSetInitialPosition = true
        } else {
            print("🏙️ Using default Chicago position")
            mapPosition = MapCameraPosition.region(mapStateManager.getDefaultRegion())
            hasSetInitialPosition = true
            
            if locationManager.hasLocationPermission && viewModel.centerCoordinate == nil {
                shouldCenterOnUser = true
            }
        }
    }
    
    private func handleLocationUpdate(_ newLocation: CLLocationCoordinate2D) {
        print("📍 Location updated: \(newLocation.latitude), \(newLocation.longitude)")
        
        // UPDATED: Don't center if we have URL coordinates, already processed them, or still waiting for URL response
        if viewModel.centerCoordinate != nil || hasProcessedURLCoordinate || isWaitingForURLResponse {
            print("🎯 Ignoring location update - using URL center coordinate, already processed, or waiting for URL response")
            return
        }
        
        if shouldCenterOnUser {
            print("🎯 Centering on user location after permission grant")
            centerMapOn(coordinate: newLocation)
            shouldCenterOnUser = false
        } else if !hasSetInitialPosition || (locationManager.hasLocationPermission && mapStateManager.getSavedRegion() == nil) {
            print("🎯 Centering on first location update")
            centerMapOn(coordinate: newLocation)
        }
    }
    
    private func handleAuthorizationChange(oldStatus: CLAuthorizationStatus, newStatus: CLAuthorizationStatus) {
        print("🔐 Authorization changed from \(oldStatus.rawValue) to \(newStatus.rawValue)")
        
        switch newStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startLocationUpdates()
            
            if oldStatus == .notDetermined || oldStatus == .denied {
                // UPDATED: Only set shouldCenterOnUser if we don't have URL coordinates, haven't processed them, and aren't waiting for URL response
                if viewModel.centerCoordinate == nil && !hasProcessedURLCoordinate && !isWaitingForURLResponse {
                    shouldCenterOnUser = true
                    print("🎯 Will center on user when location becomes available")
                } else {
                    print("🎯 Not setting shouldCenterOnUser - URL coordinates present or expected")
                }
            }
            
        case .denied, .restricted:
            locationManager.stopLocationUpdates()
            shouldCenterOnUser = false
            
        case .notDetermined:
            break
            
        @unknown default:
            break
        }
    }
    
    // UPDATED: Better zoom level for venue-specific centering
    private func centerMapOn(coordinate: CLLocationCoordinate2D) {
        print("🎯 Centering map on: \(coordinate.latitude), \(coordinate.longitude)")
        
        // Use tighter zoom when centering on a specific venue (from URL)
        let span: MKCoordinateSpan
        if viewModel.centerCoordinate != nil {
            span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        } else {
            span = mapStateManager.getUserLocationRegion(userLocation: coordinate).span
        }
        
        let region = MKCoordinateRegion(center: coordinate, span: span)
        
        withAnimation(.easeInOut(duration: 1.2)) {
            mapPosition = MapCameraPosition.region(region)
        }
    }
    
    private func saveCurrentMapState(context: MapCameraUpdateContext) {
        let center = context.region.center
        let span = context.region.span
        mapStateManager.saveMapState(center: center, span: span)
    }
    
    // UPDATED: Don't auto-adjust if we have URL coordinates
    private func adjustMapToShowEvents() {
        let validEvents = displayedEvents
        guard !validEvents.isEmpty else { return }
        
        print("📌 Adjusting map to show \(validEvents.count) events")
        
        // Don't auto-adjust if we have center coordinates from URL
        if viewModel.centerCoordinate != nil {
            print("🎯 Skipping auto-adjust - using URL center coordinate")
            return
        }
        
        // Don't auto-adjust if user has location permission and we've already positioned
        guard !locationManager.hasLocationPermission || !hasSetInitialPosition else {
            print("👤 User has location control, skipping auto-adjust")
            return
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if validEvents.count == 1 {
                let event = validEvents[0]
                print("🎯 Centering on single event: \(event.label)")
                withAnimation(.easeInOut(duration: 1.0)) {
                    mapPosition = MapCameraPosition.region(MKCoordinateRegion(
                        center: event.venue.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    ))
                }
            } else {
                print("🗺️ Fitting \(validEvents.count) events in view")
                let coordinates = validEvents.map { $0.venue.coordinate }
                let region = regionThatFits(coordinates: coordinates)
                withAnimation(.easeInOut(duration: 1.0)) {
                    mapPosition = MapCameraPosition.region(region)
                }
            }
        }
    }
    
    private func regionThatFits(coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard !coordinates.isEmpty else {
            return mapStateManager.getDefaultRegion()
        }
        
        let minLat = coordinates.map { $0.latitude }.min()!
        let maxLat = coordinates.map { $0.latitude }.max()!
        let minLon = coordinates.map { $0.longitude }.min()!
        let maxLon = coordinates.map { $0.longitude }.max()!
        
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.3, 0.01),
            longitudeDelta: max((maxLon - minLon) * 1.3, 0.01)
        )
        
        return MKCoordinateRegion(center: center, span: span)
    }
    
    // MARK: - Apple Maps Integration
    
    private func openInAppleMaps(venue: Venue) {
        let coordinate = venue.coordinate
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = venue.name
        
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving,
            MKLaunchOptionsShowsTrafficKey: true
        ])
        
        print("🗺️ Opening \(venue.name) in Apple Maps")
    }
}
