import Foundation
import CoreLocation

@Observable class EventViewModel {
    var events: [Event] = []
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var hasError: Bool { errorMessage != nil }
    
    // Add new properties for centering (won't break existing functionality)
    var centerCoordinate: CLLocationCoordinate2D?
    var selectedVenueId: Int?
    
    // ADDED: Expose the URL so MapView can check for parameters
    let url: URL
    
    private let maxRetries = 3
    private var currentRetryCount = 0
    
    init(url: URL) {
        // Only append .json if the URL doesn't already have it
        if url.pathExtension.isEmpty {
            self.url = url.appendingPathExtension("json")
        } else {
            self.url = url
        }
        
        print("🔗 EventViewModel initialized with URL: \(self.url.absoluteString)")
    }
    
    @MainActor
    func fetchCoordinates() async {
        await fetchCoordinatesWithRetry()
    }
    
    @MainActor
    private func fetchCoordinatesWithRetry() async {
        isLoading = true
        errorMessage = nil
        currentRetryCount = 0
        
        while currentRetryCount <= maxRetries {
            do {
                let response = try await performFetch()
                
                // Extract events (existing logic)
                let fetchedEvents = response.events
                
                // Validate and filter events with proper coordinates (existing logic)
                let validEvents = validateEvents(fetchedEvents)
                
                if validEvents.isEmpty && !fetchedEvents.isEmpty {
                    // All events had invalid coordinates
                    throw EventError.invalidCoordinates
                }
                
                events = validEvents
                
                // Handle new centering data (won't break if not present)
                if let center = response.center {
                    centerCoordinate = CLLocationCoordinate2D(
                        latitude: center.latitude,
                        longitude: center.longitude
                    )
                    print("🎯 Centering map on: \(center.latitude), \(center.longitude)")
                } else {
                    centerCoordinate = nil
                }
                
                selectedVenueId = response.selectedVenueId
                
                isLoading = false
                errorMessage = nil
                
                print("✅ Successfully loaded \(events.count) events")
                return
                
            } catch {
                currentRetryCount += 1
                
                print("❌ Attempt \(currentRetryCount) failed: \(error.localizedDescription)")
                
                if currentRetryCount > maxRetries {
                    isLoading = false
                    errorMessage = getErrorMessage(for: error)
                    print("🔥 All retry attempts failed. Error: \(errorMessage ?? "Unknown")")
                    return
                } else {
                    // Wait before retrying (exponential backoff)
                    let delay = Double(currentRetryCount) * 1.0
                    print("⏳ Retrying in \(delay) seconds...")
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
    }
    
    private func performFetch() async throws -> MapResponse {
        print("🌐 Fetching events from: \(url.absoluteString)")
        
        let request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 15.0
        )
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Check HTTP response status
        if let httpResponse = response as? HTTPURLResponse {
            print("📡 HTTP Status: \(httpResponse.statusCode)")
            
            guard 200...299 ~= httpResponse.statusCode else {
                throw EventError.httpError(httpResponse.statusCode)
            }
        }
        
        // Validate response data
        guard !data.isEmpty else {
            throw EventError.emptyResponse
        }
        
        print("📦 Received \(data.count) bytes of data")
        
        // Parse JSON - first try new format, fall back to old format
        let decoder = JSONDecoder()
        
        do {
            // Try new format with centering data
            let mapResponse = try decoder.decode(MapResponse.self, from: data)
            print("🎯 Parsed \(mapResponse.events.count) events from enhanced JSON")
            return mapResponse
        } catch {
            // Fall back to old format (just events array)
            do {
                let events = try decoder.decode([Event].self, from: data)
                print("🎯 Parsed \(events.count) events from simple JSON")
                return MapResponse(events: events, center: nil, selectedVenueId: nil)
            } catch {
                // Log the raw data for debugging
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("🔍 Raw JSON response: \(jsonString.prefix(500))...")
                }
                throw EventError.decodingError(error)
            }
        }
    }
    
    private func validateEvents(_ events: [Event]) -> [Event] {
        let validEvents = events.filter { event in
            let lat = event.venue.coordinate.latitude
            let lon = event.venue.coordinate.longitude
            
            // Check for valid coordinates
            let isValidLat = lat.isFinite && lat >= -90 && lat <= 90 && lat != 0.0
            let isValidLon = lon.isFinite && lon >= -180 && lon <= 180 && lon != 0.0
            
            if !isValidLat || !isValidLon {
                print("⚠️ Filtering out event '\(event.label)' with invalid coordinates: (\(lat), \(lon))")
                return false
            }
            
            return true
        }
        
        print("✅ Validated \(validEvents.count) out of \(events.count) events")
        return validEvents
    }
    
    private func getErrorMessage(for error: Error) -> String {
        switch error {
        case EventError.httpError(let statusCode):
            return "Server error (\(statusCode)). Please try again later."
        case EventError.emptyResponse:
            return "No data received from server."
        case EventError.invalidCoordinates:
            return "All events have invalid location data."
        case EventError.decodingError:
            return "Unable to process server response."
        case let urlError as URLError:
            switch urlError.code {
            case .notConnectedToInternet:
                return "No internet connection available."
            case .timedOut:
                return "Request timed out. Please try again."
            case .cannotFindHost, .cannotConnectToHost:
                return "Cannot connect to server."
            default:
                return "Network error: \(urlError.localizedDescription)"
            }
        default:
            return "An unexpected error occurred: \(error.localizedDescription)"
        }
    }
    
    @MainActor
    func retry() async {
        await fetchCoordinatesWithRetry()
    }
    
    @MainActor
    func clearError() {
        errorMessage = nil
    }
}

// MARK: - Response Models
struct MapResponse: Decodable {
    let events: [Event]
    let center: MapCenter?
    let selectedVenueId: Int?
    
    enum CodingKeys: String, CodingKey {
        case events, center
        case selectedVenueId = "selected_venue_id"
    }
}

struct MapCenter: Decodable {
    let latitude: Double
    let longitude: Double
}

// MARK: - Custom Errors
enum EventError: LocalizedError {
    case httpError(Int)
    case emptyResponse
    case invalidCoordinates
    case decodingError(Error)
    
    var errorDescription: String? {
        switch self {
        case .httpError(let code):
            return "HTTP Error \(code)"
        case .emptyResponse:
            return "Empty response from server"
        case .invalidCoordinates:
            return "Invalid coordinate data"
        case .decodingError(let error):
            return "JSON decoding failed: \(error.localizedDescription)"
        }
    }
}
