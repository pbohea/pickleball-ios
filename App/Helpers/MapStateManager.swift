import Foundation
import MapKit
import SwiftUI

class MapStateManager: ObservableObject {
    @Published var lastMapCenter: CLLocationCoordinate2D?
    @Published var lastMapSpan: MKCoordinateSpan?
    
    private let userDefaults = UserDefaults.standard
    
    // Keys for UserDefaults
    private enum Keys {
        static let mapCenterLat = "mapCenterLatitude"
        static let mapCenterLng = "mapCenterLongitude"
        static let mapSpanLatDelta = "mapSpanLatitudeDelta"
        static let mapSpanLngDelta = "mapSpanLongitudeDelta"
    }
    
    init() {
        loadMapState()
    }
    
    func saveMapState(center: CLLocationCoordinate2D, span: MKCoordinateSpan) {
        // Save to memory
        lastMapCenter = center
        lastMapSpan = span
        
        // Save to UserDefaults
        userDefaults.set(center.latitude, forKey: Keys.mapCenterLat)
        userDefaults.set(center.longitude, forKey: Keys.mapCenterLng)
        userDefaults.set(span.latitudeDelta, forKey: Keys.mapSpanLatDelta)
        userDefaults.set(span.longitudeDelta, forKey: Keys.mapSpanLngDelta)
    }
    
    private func loadMapState() {
        // Check if we have saved state
        guard userDefaults.object(forKey: Keys.mapCenterLat) != nil else { return }
        
        let lat = userDefaults.double(forKey: Keys.mapCenterLat)
        let lng = userDefaults.double(forKey: Keys.mapCenterLng)
        let latDelta = userDefaults.double(forKey: Keys.mapSpanLatDelta)
        let lngDelta = userDefaults.double(forKey: Keys.mapSpanLngDelta)
        
        lastMapCenter = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        lastMapSpan = MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lngDelta)
    }
    
    func getDefaultRegion() -> MKCoordinateRegion {
        // Chicago fallback with your preferred zoom level
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 41.8781, longitude: -87.6298),
            span: MKCoordinateSpan(latitudeDelta: 0.058, longitudeDelta: 0.029)
        )
    }
    
    func getUserLocationRegion(userLocation: CLLocationCoordinate2D) -> MKCoordinateRegion {
        return MKCoordinateRegion(
            center: userLocation,
            span: MKCoordinateSpan(latitudeDelta: 0.058, longitudeDelta: 0.029)
        )
    }
    
    func getSavedRegion() -> MKCoordinateRegion? {
        guard let center = lastMapCenter, let span = lastMapSpan else { return nil }
        return MKCoordinateRegion(center: center, span: span)
    }
}
