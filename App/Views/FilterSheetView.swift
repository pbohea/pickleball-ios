

import SwiftUI
struct FilterSheetView: View {
    let eventCategories: [String]

    @Binding var selectedCategories: Set<String>
    @Binding var coverOnly: Bool
    @Binding var indoorsOnly: Bool
    @Binding var outdoorsOnly: Bool

    var onApply: () -> Void

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Event Category")) {
                    ForEach(eventCategories, id: \.self) { category in
                        HStack {
                            Text(category)
                            Spacer()
                            Image(systemName: selectedCategories.contains(category) ? "checkmark.square.fill" : "square")
                                .foregroundColor(.blue)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if category == "All" {
                                selectedCategories = ["All"]
                            } else {
                                if selectedCategories.contains("All") { selectedCategories = [] }
                                if selectedCategories.contains(category) {
                                    selectedCategories.remove(category)
                                } else {
                                    selectedCategories.insert(category)
                                }
                            }
                        }
                    }
                }

                Section(header: Text("Event Properties")) {
//                    Toggle("Only Show Events Without Cover Charge", isOn: $coverOnly)
                    Toggle("Only Show Indoor Events", isOn: $indoorsOnly)
                        .onChange(of: indoorsOnly) { _, newValue in
                            if newValue { outdoorsOnly = false }
                        }

                    Toggle("Only Show Outdoor Events", isOn: $outdoorsOnly)
                        .onChange(of: outdoorsOnly) { _, newValue in
                            if newValue { indoorsOnly = false }
                        }
                }

                Section {
                    Button(role: .destructive) {
                        selectedCategories = ["All"]
                        coverOnly = false
                        indoorsOnly = false
                        outdoorsOnly = false
                    } label: {
                        HStack {
                            Spacer(); Text("Clear Filters"); Spacer()
                        }
                    }
                }

                Section {
                    Button(action: onApply) {
                        HStack { Spacer(); Text("Go").bold(); Spacer() }
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
