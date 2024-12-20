import SwiftUI

struct TimezonePicker: View {
    @Binding var selection: String?
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private let timezones = TimeZone.knownTimeZoneIdentifiers.sorted()

    private var filteredTimezones: [String] {
        let filtered =
            searchText.isEmpty
            ? timezones
            : timezones.filter {
                $0.localizedCaseInsensitiveContains(searchText)
            }
        return searchText.isEmpty ? ["None"] + filtered : filtered
    }

    var body: some View {
        List {
            ForEach(filteredTimezones, id: \.self) { identifier in
                Button {
                    selection = identifier == "None" ? nil : identifier
                    dismiss()
                } label: {
                    HStack {
                        Text(identifier)
                            .foregroundStyle(.primary)
                        Spacer()
                        if selection == identifier || (identifier == "None" && selection == nil) {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                .foregroundColor(.primary)
            }
        }
        .navigationTitle("Select Timezone")
        .searchable(text: $searchText, prompt: "Search timezones")
    }
}
