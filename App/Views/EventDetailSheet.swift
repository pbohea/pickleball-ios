
import SwiftUI
import HotwireNative

// MARK: - Hex Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

struct EventDetailSheet: View {
    let event: Event
    let navigator: Navigator?

    // MARK: - Venue time zone helpers
    private var venueTimeZone: TimeZone {
        TimeZone(identifier: event.venue.timeZoneIdentifier) ?? .current
    }

    private func dateStringVenueTZ(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = venueTimeZone
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: date)
    }

    private func timeString(_ date: Date?) -> String {
        guard let date = date else { return "TBD" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = venueTimeZone
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    private var tzAbbrev: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = venueTimeZone
        f.dateFormat = "zzz"
        return f.string(from: event.startTimeDate)
    }
    @ViewBuilder
    private var coverBadge: some View {
        if event.cover == true { // handles optional Bool too
            Text("Cover: \(event.coverAmountFormatted)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    (event.indoors ? Color(.systemGray6) : Color.green.opacity(0.1))
                )
                .cornerRadius(8)
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView {
                VStack(spacing: 24) {

                    // Header Section
                    VStack(spacing: 16) {
                        artistImageView
                        artistNameView
                    }

                    // Event Info Cards
                    VStack(spacing: 16) {
                        // Date & Time Card
                        VStack(spacing: 8) {
                            HStack {
                                Image(systemName: "calendar")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(Color(hex: "#0d6efd"))
                                Text("Event Time")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }

                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    // ✅ Date shown in venue TZ
                                    Text(dateStringVenueTZ(event.dateObject))
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.primary)

                                    // ✅ Times shown in venue TZ + abbreviation
                                    Text("\(timeString(event.startTimeDate)) – \(timeString(event.endTimeDate)) \(tzAbbrev)")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                        }
                        .padding(20)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color(.separator), lineWidth: 0.5)
                        )
                        .shadow(color: Color.primary.opacity(0.08), radius: 6, x: 0, y: 2)

                        // Venue Card
                        Button {
                            let venueURL = baseURL.appending(path: "venues/\(event.venue.slug)")
                            navigator?.route(venueURL)
                        } label: {
                            VStack(spacing: 8) {
                                HStack {
                                    Image(systemName: "location")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(Color(hex: "#0d6efd"))
                                    Text("Venue")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.secondary)
                                }

                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(event.venue.name)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.primary)
                                        Text(event.venue.city)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                            .padding(20)
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color(.separator), lineWidth: 0.5)
                            )
                            .shadow(color: Color.primary.opacity(0.08), radius: 6, x: 0, y: 2)
                        }

                        // Event Details Card
                        VStack(spacing: 12) {
                            HStack {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(Color(hex: "#0d6efd"))
                                Text("Event Details")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }

                            if let description = event.description ?? event.category {
                                HStack {
                                    Text(description)
                                        .font(.system(size: 15, weight: .regular))
                                        .foregroundColor(.primary)
                                        .lineLimit(nil)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer()
                                }
                                .padding(.bottom, 8)
                            }

                            // Indoor/Outdoor & Cover Info
                            HStack(spacing: 16) {
                                Label(
                                    event.indoors ? "Indoor Event" : "Outdoor Event",
                                    systemImage: event.indoors ? "house.fill" : "sun.max.fill"
                                )
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(event.indoors ? .green : .orange)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    (event.indoors ? Color.green : Color.orange).opacity(0.1)
                                )
                                .cornerRadius(8)

                                Spacer()

                                coverBadge
                            }
                        }
                        .padding(20)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color(.separator), lineWidth: 0.5)
                        )
                        .shadow(color: Color.primary.opacity(0.08), radius: 6, x: 0, y: 2)
                    }

                    // Website Button
                    if let url = event.venue.websiteURL {
                        Link(destination: url) {
                            HStack(spacing: 12) {
                                Image(systemName: "globe")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("Visit Venue Website")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [Color(hex: "#0d6efd"), Color(hex: "#4dabf7")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(12)
                            .shadow(color: Color(hex: "#0d6efd").opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                    }

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))

            // These use Event.isToday/isNow — which, per your updated model, already evaluate in the venue TZ.
            if event.isToday {
                Text(event.isNow ? "LIVE NOW" : "TODAY")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        event.isNow
                        ? LinearGradient(colors: [.red, .orange], startPoint: .leading, endPoint: .trailing)
                        : LinearGradient(colors: [.green, .mint], startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(Capsule())
                    .shadow(color: (event.isNow ? Color.red : Color.green).opacity(0.4), radius: 4, x: 0, y: 2)
                    .padding(.top, 16)
                    .padding(.trailing, 20)
                    .modifier(PulseEffect())
            }
        }
    }

    // MARK: - Artist Image View
    @ViewBuilder
    private var artistImageView: some View {
        let imageContent = AsyncImage(url: event.artist.imageURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [Color(hex: "#0d6efd"), Color(hex: "#4dabf7")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 3
                            )
                    )
                    .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 8)
            case .failure, .empty:
                Circle()
                    .fill(Color(.systemGray4))
                    .frame(width: 120, height: 120)
                    .overlay(
                        Image(systemName: "music.microphone")
                            .font(.system(size: 40, weight: .light))
                            .foregroundColor(.white)
                    )
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [Color(.systemGray3), Color(.systemGray5)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 3
                            )
                    )
                    .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 8)
            }
        }

        if event.artist.isDatabaseArtist, let artistSlug = event.artist.slug {
            Button {
                let artistURL = baseURL.appending(path: "artists/\(artistSlug)")
                navigator?.route(artistURL)
            } label: {
                imageContent
            }
        } else {
            imageContent
        }
    }

    // MARK: - Artist Name View
    @ViewBuilder
    private var artistNameView: some View {
        VStack(spacing: 8) {
            let nameContent = Text(event.artist.username)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(
                    event.artist.isDatabaseArtist
                    ? LinearGradient(
                        colors: [Color(hex: "#0d6efd"), Color(hex: "#4dabf7")],
                        startPoint: .leading,
                        endPoint: .trailing
                      )
                    : LinearGradient(
                        colors: [Color(.label), Color(.label)],
                        startPoint: .leading,
                        endPoint: .trailing
                      )
                )
                .multilineTextAlignment(.center)

            if event.artist.isDatabaseArtist, let artistSlug = event.artist.slug {
                Button {
                    let artistURL = baseURL.appending(path: "artists/\(artistSlug)")
                    navigator?.route(artistURL)
                } label: {
                    nameContent
                }
            } else {
                nameContent
            }
            
            // Category text - shown for all events
            if let category = event.category {
                Text(category)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Non-database artist message
            if !event.artist.isDatabaseArtist {
                Text("This artist isn't using Pickleball yet, tell them to sign up!")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
        }
    }
}

// MARK: - Pulse Animation
struct PulseEffect: ViewModifier {
    @State private var pulse = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(pulse ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}
