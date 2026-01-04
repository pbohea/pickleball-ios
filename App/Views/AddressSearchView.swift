//
//  AddressSearchView.swift
//  Pickleball
//
//  Created by Patrick O'Hea on 6/4/25.
//


import SwiftUI
import MapKit

struct AddressSearchView: View {
    @Binding var isPresented: Bool
    let onLocationFound: (CLLocationCoordinate2D) -> Void
    
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var errorMessage: String?
    
    private let locationManager = LocationManager()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Enter an address or zip code to search")
                        .font(.headline)
                        .multilineTextAlignment(.leading)
                    
                    Text("We'll center the map on your location to show nearby events.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                VStack(spacing: 12) {
                    TextField("Address or ZIP code", text: $searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.words)
                        .disableAutocorrection(true)
                        .disabled(isSearching)
                    
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                    }
                    
                    HStack(spacing: 12) {
                        Button("Cancel") {
                            isPresented = false
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Search") {
                            Task {
                                await searchForAddress()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
                    }
                    
                    if isSearching {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Searching...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Find Location")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
        }
    }
    
    private func searchForAddress() async {
        let address = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return }
        
        isSearching = true
        errorMessage = nil
        
        do {
            let coordinate = try await locationManager.geocodeAddress(address)
            
            await MainActor.run {
                onLocationFound(coordinate)
                isPresented = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Could not find location. Please try a different address or ZIP code."
                isSearching = false
            }
        }
    }
}
