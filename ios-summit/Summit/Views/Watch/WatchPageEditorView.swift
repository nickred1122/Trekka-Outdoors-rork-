import SwiftUI

/// Edits a single watch page: the shape of the screen and which metric sits in
/// each block, with the wrist preview updating as you go — and tappable, so a
/// block can be changed by touching it.
struct WatchPageEditorView: View {
    let sport: WatchSportProfile
    let pageID: UUID

    @Environment(WatchLayoutStore.self) private var layout
    @State private var editingSlot: Int?
    @State private var isAddingMetric = false

    private var page: WatchPage? {
        layout.page(id: pageID, for: sport)
    }

    var body: some View {
        List {
            if let page {
                Section {
                    WatchPagePreview(
                        page: page,
                        sport: sport,
                        selectedSlot: editingSlot,
                        onSelectSlot: page.kind == .data ? { slot in editingSlot = slot } : nil
                    )
                    .frame(maxWidth: .infinity)
                    .shadow(color: .black.opacity(0.6), radius: 16, y: 8)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                } footer: {
                    if page.kind == .data && !page.fields.isEmpty {
                        Text("Tap any block on the watch to change what it shows.")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }

                if page.kind == .data {
                    Section {
                        WatchLayoutBuilder(
                            layout: page.layout,
                            fieldCount: page.fields.count,
                            tint: sport.tint,
                            capacity: WatchLink.shared.watchCapacity
                        ) { next in
                            layout.setLayout(next, pageID: pageID, sport: sport)
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("Layout · \(page.layout?.title ?? "Automatic")")
                    } footer: {
                        Text(page.layout == nil
                             ? "Turn this off to set the rows yourself — one big number up top, a pair beneath, whatever you read best."
                             : "\(page.layout?.summary ?? "") · fields share their row evenly. Blocks keep the metrics they already hold.")
                    }

                    Section {
                        ForEach(Array(page.fields.enumerated()), id: \.offset) { slot, metric in
                            Button {
                                editingSlot = slot
                            } label: {
                                slotRow(slot: slot, metric: metric, page: page)
                            }
                        }
                        .onMove { offsets, destination in
                            layout.moveFields(fromOffsets: offsets, toOffset: destination, pageID: pageID, sport: sport)
                        }
                        .onDelete { offsets in
                            layout.removeFields(at: offsets, pageID: pageID, sport: sport)
                        }

                        // With a chosen layout the block count is fixed, so the
                        // way to make room is to pick a bigger arrangement. An
                        // automatic page stops growing at what the watch can hold.
                        if page.layout == nil, page.fields.count < WatchLink.shared.watchCapacity.maxSlots {
                            Button {
                                isAddingMetric = true
                            } label: {
                                Label("Add metric", systemImage: "plus.circle.fill")
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    } header: {
                        Text("Blocks · \(page.fields.count)")
                    } footer: {
                        Text(page.layout == nil
                             ? "Drag to reorder, swipe to remove, tap to swap the metric."
                             : "Drag to reorder, tap to swap the metric. Add or remove blocks by changing the rows above.")
                    }
                } else {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(page.kind.title)
                                    .font(.system(.subheadline, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text(page.kind.detail)
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                            }
                        } icon: {
                            Image(systemName: page.kind.symbol)
                                .foregroundStyle(sport.tint)
                        }
                    } footer: {
                        Text("This page draws itself from live sensor data — there is nothing to configure.")
                    }
                }

                Section {
                    Toggle(
                        "Show during workouts",
                        isOn: Binding(
                            get: { page.isEnabled },
                            set: { _ in layout.togglePage(id: pageID, for: sport) }
                        )
                    )
                }
            } else {
                Text("This page was removed.")
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle(page?.kind.title ?? "Page")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
        }
        .sheet(item: Binding(get: { editingSlot.map(SlotSelection.init) }, set: { editingSlot = $0?.slot })) { selection in
            NavigationStack {
                WatchMetricPickerView(sport: sport, title: "Slot \(selection.slot + 1)") { metric in
                    layout.replaceField(at: selection.slot, with: metric, pageID: pageID, sport: sport)
                    editingSlot = nil
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isAddingMetric) {
            NavigationStack {
                WatchMetricPickerView(sport: sport, title: "Add Metric") { metric in
                    layout.addField(metric, pageID: pageID, sport: sport)
                    isAddingMetric = false
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private struct SlotSelection: Identifiable {
        let slot: Int
        var id: Int { slot }
    }

    private func slotRow(slot: Int, metric: WatchMetric, page: WatchPage) -> some View {
        HStack(spacing: 12) {
            Text("\(slot + 1)")
                .font(.metric(14))
                .foregroundStyle(slot == 0 ? sport.tint : Theme.textPrimary.opacity(0.45))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(metric.title)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(page.resolvedLayout.position(ofSlot: slot))
                    .font(.caption2)
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
            }

            Spacer(minLength: 0)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(metric.preview)
                    .font(.metric(15))
                    .foregroundStyle(metric.tint)
                if !metric.unit.isEmpty {
                    Text(metric.unit)
                        .font(.caption2)
                        .foregroundStyle(Theme.textPrimary.opacity(0.45))
                }
            }
        }
    }

}

/// Grouped catalogue of every watch metric with sample values.
struct WatchMetricPickerView: View {
    let sport: WatchSportProfile
    var title: String = "Metric"
    var onSelect: (WatchMetric) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        List {
            ForEach(WatchMetricGroup.allCases) { group in
                let metrics = available(in: group)
                if !metrics.isEmpty {
                    Section {
                        ForEach(metrics) { metric in
                            Button {
                                onSelect(metric)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(metric.title)
                                            .font(.system(.subheadline, weight: .semibold))
                                            .foregroundStyle(Theme.textPrimary)
                                        Text(metric.label)
                                            .font(.caption2)
                                            .foregroundStyle(Theme.textPrimary.opacity(0.45))
                                    }
                                    Spacer(minLength: 8)
                                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                                        Text(metric.preview)
                                            .font(.metric(16))
                                            .foregroundStyle(sport.tint)
                                        if !metric.unit.isEmpty {
                                            Text(metric.unit)
                                                .font(.caption2)
                                                .foregroundStyle(Theme.textPrimary.opacity(0.45))
                                        }
                                    }
                                }
                            }
                        }
                    } header: {
                        Label(group.title, systemImage: group.symbol)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .searchable(text: $query, prompt: "Search metrics")
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    /// Hides metrics this sport can never produce, so the list stays honest.
    private func available(in group: WatchMetricGroup) -> [WatchMetric] {
        WatchMetric.metrics(in: group).filter { metric in
            if !query.isEmpty && !metric.title.localizedStandardContains(query) { return false }
            if metric.requiresRoute && !sport.supportsRoutes { return false }
            if group == .elevation && !sport.usesElevation { return false }
            switch metric {
            case .power: return sport.family == .ride || sport.family == .water
            case .strideLength, .cadence, .averageCadence: return sport.family != .gym
            default: return true
            }
        }
    }
}
