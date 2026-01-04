import Foundation
import MapKit

// MARK: - Event

struct Event: Decodable, Identifiable, Equatable {
    let id: Int
    let date: String                // ISO8601 date-only string from server
    let startTime: String           // ISO8601 datetime string in venue TZ (as UTC/Z or with offset)
    let endTime: String?            // ISO8601 datetime string (optional)
    let description: String?
    let cover: Bool
    let coverAmount: Int?
    let category: String?
    let indoors: Bool
    let venue: Venue
    let artist: Artist

    enum CodingKeys: String, CodingKey {
        case id, date
        case startTime = "start_time"
        case endTime   = "end_time"
        case description, cover
        case coverAmount = "cover_amount"
        case category, indoors, venue, artist
    }

    // MARK: Equatable
    static func == (lhs: Event, rhs: Event) -> Bool { lhs.id == rhs.id }
}

// MARK: - Event Helpers (parsing)

extension Event {
    /// Robust ISO8601 parser (handles Z, offsets, and fractional seconds)
    private static let isoParserPrimary: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoParserFallback: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private func parseISO8601(_ s: String) -> Date? {
        Self.isoParserPrimary.date(from: s) ?? Self.isoParserFallback.date(from: s)
    }

    /// Date-only (uses 00:00 in venue TZ on that calendar day)
    var dateObject: Date {
        // If `date` is an ISO8601 *date-only* (e.g. "2025-08-26"), construct in venue TZ.
        // Fallback to parsing with ISO8601 parser if it's full datetime.
        if date.count == 10, let d = Self.dateOnly(date, in: venueTimeZone) {
            return d
        }
        return parseISO8601(date) ?? Date()
    }

    static func dateOnly(_ yyyymmdd: String, in tz: TimeZone) -> Date? {
        let comps = yyyymmdd.split(separator: "-").map { Int($0) }
        guard comps.count == 3, let y = comps[0], let m = comps[1], let d = comps[2] else { return nil }
        var dateComponents = DateComponents()
        dateComponents.year = y
        dateComponents.month = m
        dateComponents.day = d
        dateComponents.timeZone = tz
        return Calendar(identifier: .gregorian).date(from: dateComponents)
    }

    var startTimeDate: Date {
        parseISO8601(startTime) ?? Date()
    }

    var endTimeDate: Date? {
        guard let endTime else { return nil }
        return parseISO8601(endTime)
    }
}

// MARK: - Event Helpers (formatting with venue TZ)

extension Event {
    /// Venue’s time zone from server (falls back to device if missing/invalid)
    var venueTimeZone: TimeZone {
        if let tz = TimeZone(identifier: venue.timeZoneIdentifier) {
            return tz
        }
        return .current
    }

    /// Reusable DateFormatter configured for the venue TZ
    private func formatter(_ format: String) -> DateFormatter {
        let df = DateFormatter()
        df.dateFormat = format
        df.timeZone = venueTimeZone
        df.locale = Locale(identifier: "en_US_POSIX")
        return df
    }

    // Display strings (always in venue TZ)
    var dateFormatted: String {
        formatter("EEEE, MMMM d").string(from: dateObject)
    }

    var startTimeFormatted: String {
        formatter("h:mm a").string(from: startTimeDate)
    }

    var endTimeFormatted: String {
        guard let end = endTimeDate else { return "TBD" }
        return formatter("h:mm a").string(from: end)
    }

    // Status helpers evaluated in venue TZ
    var isToday: Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = venueTimeZone
        return cal.isDateInToday(dateObject)
    }

    var isNow: Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = venueTimeZone
        let now = Date()
        if let end = endTimeDate {
            return startTimeDate <= now && now <= end
        }
        // If no end time, consider "now" true within the same calendar day as start
        return cal.isDate(now, inSameDayAs: startTimeDate)
    }

    // Cover amount formatting
    var coverAmountFormatted: String {
        if let amount = coverAmount {
            let nf = NumberFormatter()
            nf.numberStyle = .currency
            return nf.string(from: NSNumber(value: amount)) ?? "$5"
        }
        return "$5"
    }

    /// Used for map pins
    var label: String { venue.name }
}

// MARK: - Venue

struct Venue: Decodable, Identifiable, Equatable {
    let id: Int
    let slug: String
    let name: String
    let category: String
    let website: String?
    let city: String
    let timeZoneIdentifier: String       // <- ensure server includes this (e.g. "America/New_York")

    private let coordinateData: CoordinateData

    enum CodingKeys: String, CodingKey {
        case id, slug, name, category, website, city
        case timeZoneIdentifier = "time_zone"
        case coordinateData = "coordinate"
    }

    // Map-friendly coordinate
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: coordinateData.latitude, longitude: coordinateData.longitude)
    }

    // Convenience
    var latitude: Double { coordinateData.latitude }
    var longitude: Double { coordinateData.longitude }

    static func == (lhs: Venue, rhs: Venue) -> Bool { lhs.id == rhs.id }

    var websiteURL: URL? {
        guard let website, !website.isEmpty else { return nil }
        return URL(string: website)
    }
}

struct CoordinateData: Decodable {
    let latitude: Double
    let longitude: Double
}

// MARK: - Artist

struct Artist: Decodable, Equatable, Identifiable {
    let artistId: Int?
    let slug: String?
    let username: String
    let imageURL: URL?
    let profileURL: URL?
    let isDatabaseArtist: Bool

    enum CodingKeys: String, CodingKey {
        case artistId = "id"
        case slug, username
        case imageURL = "image_url"
        case profileURL = "profile_url"
        case isDatabaseArtist = "is_database_artist"
    }

    // Stable ID for SwiftUI lists/sheets
    var id: String {
        if let artistId { return "artist_\(artistId)" }
        return "manual_\(username.lowercased().replacingOccurrences(of: " ", with: "_"))"
    }

    // Custom decode to tolerate bad/missing URLs
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        artistId = try c.decodeIfPresent(Int.self, forKey: .artistId)
        slug = try c.decodeIfPresent(String.self, forKey: .slug)
        username = try c.decode(String.self, forKey: .username)
        isDatabaseArtist = try c.decode(Bool.self, forKey: .isDatabaseArtist)

        if let s = try c.decodeIfPresent(String.self, forKey: .imageURL), !s.isEmpty {
            imageURL = URL(string: s)
        } else { imageURL = nil }

        if let s = try c.decodeIfPresent(String.self, forKey: .profileURL), !s.isEmpty {
            profileURL = URL(string: s)
        } else { profileURL = nil }
    }

    static func == (lhs: Artist, rhs: Artist) -> Bool {
        if let l = lhs.artistId, let r = rhs.artistId { return l == r }
        return lhs.username == rhs.username && lhs.isDatabaseArtist == rhs.isDatabaseArtist
    }
}
