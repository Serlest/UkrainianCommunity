import Combine
import MapKit
import SwiftUI
import UIKit

extension EventEditorView {
        var locationCard: some View {
            editorCard {
                VStack(alignment: .leading, spacing: editorCardSpacing) {
                    editorSectionTitle(AppStrings.Events.fieldLocation)

                    iconTextField(systemImage: "mappin.circle", placeholder: AppStrings.Events.locationPlaceholder, text: $viewModel.venue)

                    locationSuggestions

                    editorField(title: AppStrings.Events.addressPlaceholder) {
                        TextField(AppStrings.Events.addressPlaceholder, text: $viewModel.address)
                            .font(.subheadline)
                            .textInputAutocapitalization(.words)
                            .eventEditorCompactInputStyle(minHeight: compactInputHeight)
                    }

                    editorField(title: AppStrings.Common.city) {
                        TextField(AppStrings.Common.city, text: $viewModel.city)
                            .font(.subheadline)
                            .textInputAutocapitalization(.words)
                            .eventEditorCompactInputStyle(minHeight: compactInputHeight)
                    }

                    editorField(title: AppStrings.Events.locationNoteTitle) {
                        multilineInput(
                            placeholder: AppStrings.Events.locationNotePlaceholder,
                            text: $viewModel.locationNote,
                            minHeight: locationNoteInputHeight,
                            counterText: "\(viewModel.locationNote.count)/\(EventEditorViewModel.locationNoteCharacterLimit)"
                        )
                    }

                    if viewModel.selectedCoordinate != nil || !viewModel.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        selectedLocationRow
                    }

                    mapPickerButton
                }
            }
        }

        @ViewBuilder
        var locationSuggestions: some View {
            if !locationSearch.completions.isEmpty && !viewModel.venue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let visibleCompletions = Array(locationSearch.completions.prefix(5))
                VStack(spacing: 0) {
                    ForEach(Array(visibleCompletions.enumerated()), id: \.offset) { index, completion in
                        Button {
                            Task {
                                guard let selection = await locationSearch.resolve(completion) else { return }
                                applyLocation(selection)
                                locationSearch.clear()
                            }
                        } label: {
                            locationSuggestionRow(title: completion.title, subtitle: completion.subtitle)
                        }
                        .buttonStyle(.plain)

                        if index < visibleCompletions.count - 1 {
                            editorDivider
                        }
                    }
                }
                .padding(.vertical, 4)
                .background(AppTheme.glassControlSurface(for: colorScheme), in: RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous)
                        .strokeBorder(AppTheme.glassBorder(for: colorScheme))
                )
            }
        }

        func locationSuggestionRow(title: String, subtitle: String) -> some View {
            HStack(spacing: AppTheme.eventsMetadataSpacing) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accentPrimary)
                    .frame(width: AppTheme.metadataIconSize, height: AppTheme.metadataIconSize)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)

                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: AppTheme.eventsMetadataSpacing)
            }
            .padding(.horizontal, AppTheme.inputHorizontalPadding)
            .frame(minHeight: 48)
        }

        var selectedLocationRow: some View {
            HStack(alignment: .top, spacing: AppTheme.eventsMetadataSpacing) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accentPrimary)
                    .frame(width: AppTheme.metadataIconSize, height: AppTheme.metadataIconSize)

                VStack(alignment: .leading, spacing: 3) {
                    Text(AppStrings.Events.selectedLocation)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)

                    Text(selectedLocationText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)
                }

                Spacer(minLength: AppTheme.eventsMetadataSpacing)
            }
            .padding(AppTheme.inputHorizontalPadding)
            .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous))
        }

        var selectedLocationText: String {
            [viewModel.venue, viewModel.address, viewModel.city]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        }

        var mapPickerButton: some View {
            Button {
                isShowingMapPicker = true
            } label: {
                Label(AppStrings.Events.chooseOnMap, systemImage: "map")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accentPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: AppTheme.searchControlHeight)
                    .background(AppTheme.glassControlSurface(for: colorScheme), in: RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous)
                            .strokeBorder(AppTheme.glassBorder(for: colorScheme))
                    )
            }
            .buttonStyle(.plain)
        }

        func iconTextField(systemImage: String, placeholder: String, text: Binding<String>) -> some View {
            HStack(spacing: AppTheme.eventsMetadataSpacing) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: AppTheme.metadataIconSize, height: AppTheme.metadataIconSize)

                TextField(placeholder, text: text)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .textInputAutocapitalization(.words)
            }
            .padding(.horizontal, AppTheme.eventsControlGroupSpacing)
            .frame(minHeight: compactInputHeight, alignment: .leading)
            .background(AppTheme.surfaceControl.opacity(0.36), in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                    .strokeBorder(AppTheme.borderSubtle)
            )
        }


        func applyLocation(_ selection: EventLocationSelection) {
            isApplyingLocationSelection = true
            locationSearch.clear()
            viewModel.applyLocation(
                venueName: selection.name,
                address: selection.address,
                city: selection.city,
                federalState: selection.federalState,
                latitude: selection.coordinate?.latitude,
                longitude: selection.coordinate?.longitude
            )
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000)
                isApplyingLocationSelection = false
            }
        }
}

struct EventLocationSelection: Identifiable {
    let id = UUID()
    let name: String
    let address: String?
    let city: String?
    let federalState: AustrianFederalState?
    let coordinate: CLLocationCoordinate2D?

    var subtitle: String {
        [address, city]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    init(mapItem: MKMapItem) {
        let placemark = mapItem.placemark
        self.name = mapItem.name?.nilIfEmpty ?? placemark.name?.nilIfEmpty ?? AppStrings.Events.selectedLocation
        self.address = EventLocationSelection.formattedAddress(from: placemark)
        self.city = placemark.locality?.nilIfEmpty ?? placemark.subAdministrativeArea?.nilIfEmpty
        self.federalState = AustrianFederalState(administrativeArea: placemark.administrativeArea)
        self.coordinate = placemark.coordinate
    }

    init(name: String, coordinate: CLLocationCoordinate2D?) {
        self.name = name
        self.address = nil
        self.city = nil
        self.federalState = nil
        self.coordinate = coordinate
    }

    private static func formattedAddress(from placemark: MKPlacemark) -> String? {
        let street = [placemark.thoroughfare, placemark.subThoroughfare]
            .compactMap { $0?.nilIfEmpty }
            .joined(separator: " ")
        let locality = [placemark.postalCode, placemark.locality]
            .compactMap { $0?.nilIfEmpty }
            .joined(separator: " ")
        let address = [street.nilIfEmpty, locality.nilIfEmpty]
            .compactMap { $0 }
            .joined(separator: ", ")
        return address.nilIfEmpty
    }
}

@MainActor
final class EventLocationSearchViewModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published private(set) var completions: [MKLocalSearchCompletion] = []
    @Published private(set) var isSearching = false

    private let completer = MKLocalSearchCompleter()
    var debounceTask: Task<Void, Never>?

    override init() {
        super.init()
        completer.delegate = self
        completer.region = Self.austriaRegion
        completer.resultTypes = [.address, .pointOfInterest]
    }

    deinit {
        debounceTask?.cancel()
    }

    func updateQuery(_ query: String) {
        debounceTask?.cancel()
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.count >= 2 else {
            clear()
            return
        }

        isSearching = true
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.completer.queryFragment = trimmedQuery
            }
        }
    }

    func clear() {
        debounceTask?.cancel()
        completer.queryFragment = ""
        completions = []
        isSearching = false
    }

    func resolve(_ completion: MKLocalSearchCompletion) async -> EventLocationSelection? {
        let request = MKLocalSearch.Request(completion: completion)
        request.region = Self.austriaRegion

        do {
            let response = try await MKLocalSearch(request: request).start()
            guard let mapItem = response.mapItems.first else { return nil }
            return EventLocationSelection(mapItem: mapItem)
        } catch {
            return nil
        }
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor in
            completions = completer.results
            isSearching = false
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            completions = []
            isSearching = false
        }
    }

    static let austriaRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 47.6965, longitude: 13.3457),
        span: MKCoordinateSpan(latitudeDelta: 5.1, longitudeDelta: 9.8)
    )
}

struct EventMapPickerView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @StateObject var search = EventLocationSearchViewModel()
    @State var query: String
    @State var selection: EventLocationSelection?
    @FocusState private var isSearchFocused: Bool

    private let initialCoordinate: CLLocationCoordinate2D?
    private let onSelect: (EventLocationSelection) -> Void

    init(
        initialCoordinate: CLLocationCoordinate2D?,
        initialQuery: String,
        onSelect: @escaping (EventLocationSelection) -> Void
    ) {
        self.initialCoordinate = initialCoordinate
        self.onSelect = onSelect
        _query = State(initialValue: initialQuery)
        if let initialCoordinate {
            _selection = State(initialValue: EventLocationSelection(name: initialQuery.nilIfEmpty ?? AppStrings.Events.selectedLocation, coordinate: initialCoordinate))
        } else {
            _selection = State(initialValue: nil)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: AppTheme.dashboardSpacing) {
                mapSearchField

                if !search.completions.isEmpty {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            let visibleCompletions = Array(search.completions.prefix(6))
                            ForEach(Array(visibleCompletions.enumerated()), id: \.offset) { index, completion in
                                Button {
                                    Task {
                                        guard let resolvedSelection = await search.resolve(completion) else { return }
                                        selection = resolvedSelection
                                    }
                                } label: {
                                    mapSearchResultRow(title: completion.title, subtitle: completion.subtitle)
                                }
                                .buttonStyle(.plain)

                                if index < visibleCompletions.count - 1 {
                                    Rectangle()
                                        .fill(AppTheme.borderSubtle)
                                        .frame(height: 1)
                                        .padding(.leading, AppTheme.metadataIconSize + AppTheme.dashboardSpacing + AppTheme.inputHorizontalPadding)
                                }
                            }
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .frame(maxHeight: 250)
                    .background(AppTheme.surfaceGlass, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
                } else if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !search.isSearching {
                    Text(AppStrings.Events.noLocationResults)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                EventMapView(selection: selection, fallbackCoordinate: initialCoordinate)
                    .frame(maxWidth: .infinity)
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                            .strokeBorder(AppTheme.glassBorder(for: colorScheme))
                    )

                Button {
                    guard let selection else { return }
                    onSelect(selection)
                    dismiss()
                } label: {
                    Text(AppStrings.Events.selectLocation)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: AppTheme.searchControlHeight)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous)
                                .fill(selection == nil ? AppTheme.accentPrimary.opacity(0.28) : AppTheme.accentPrimary)
                        )
                }
                .buttonStyle(.plain)
                .disabled(selection == nil)
            }
            .padding(AppTheme.pageHorizontal)
            .background(AppBackgroundView())
            .navigationTitle(AppStrings.Events.chooseOnMap)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.Common.cancel) {
                        dismiss()
                    }
                }
            }
            .onAppear {
                search.updateQuery(query)
            }
            .onChange(of: query) { _, newValue in
                search.updateQuery(newValue)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    var mapSearchField: some View {
        HStack(spacing: AppTheme.eventsMetadataSpacing) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: AppTheme.metadataIconSize, height: AppTheme.metadataIconSize)

            TextField(AppStrings.Events.searchLocation, text: $query)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.textPrimary)
                .textInputAutocapitalization(.words)
                .focused($isSearchFocused)
                .submitLabel(.search)
                .onSubmit { isSearchFocused = false }
        }
        .padding(.horizontal, AppTheme.inputHorizontalPadding)
        .frame(height: AppTheme.searchControlHeight)
        .background(AppTheme.glassControlSurface(for: colorScheme), in: RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous)
                .strokeBorder(AppTheme.glassBorder(for: colorScheme))
        )
    }

    func mapSearchResultRow(title: String, subtitle: String) -> some View {
        HStack(spacing: AppTheme.eventsMetadataSpacing) {
            Image(systemName: "mappin.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)
                .frame(width: AppTheme.metadataIconSize, height: AppTheme.metadataIconSize)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: AppTheme.eventsMetadataSpacing)
        }
        .padding(.horizontal, AppTheme.inputHorizontalPadding)
        .frame(minHeight: 48)
    }
}

struct EventMapView: UIViewRepresentable {
    let selection: EventLocationSelection?
    let fallbackCoordinate: CLLocationCoordinate2D?

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.isRotateEnabled = false
        mapView.pointOfInterestFilter = .includingAll
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.removeAnnotations(mapView.annotations)

        let coordinate = selection?.coordinate
            ?? fallbackCoordinate
            ?? EventLocationSearchViewModel.austriaRegion.center
        let span = selection?.coordinate == nil && fallbackCoordinate == nil
            ? EventLocationSearchViewModel.austriaRegion.span
            : MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)

        mapView.setRegion(MKCoordinateRegion(center: coordinate, span: span), animated: true)

        if selection?.coordinate != nil || fallbackCoordinate != nil {
            let annotation = MKPointAnnotation()
            annotation.coordinate = coordinate
            annotation.title = selection?.name
            annotation.subtitle = selection?.subtitle
            mapView.addAnnotation(annotation)
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
