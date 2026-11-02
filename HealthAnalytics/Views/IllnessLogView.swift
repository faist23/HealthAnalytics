//
//  IllnessLogView.swift
//  HealthAnalytics
//
//  Settings → Illness Log: past and current sick spells (Phase 2b). Logged onsets feed
//  the HRV precursor pattern alongside the step-count proxy.
//

import SwiftUI
import SwiftData

struct IllnessLogView: View {
    @Query(sort: \IllnessEvent.startDate, order: .reverse) private var events: [IllnessEvent]
    @Environment(\.modelContext) private var modelContext

    @State private var editTarget: IllnessEvent? = nil
    @State private var showingEntrySheet = false

    var body: some View {
        List {
            Section {
                Text("Log the days you were sick. The app looks at your HRV in the days before each illness to learn whether it warns you early.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            if events.isEmpty {
                Section {
                    Text("No illnesses logged. Tap + to add one.")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            } else {
                Section {
                    ForEach(events) { event in
                        Button {
                            editTarget = event
                            showingEntrySheet = true
                        } label: {
                            IllnessRow(event: event)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        for index in offsets { modelContext.delete(events[index]) }
                        try? modelContext.save()
                        IllnessLog.refreshCoach(modelContext)
                    }
                }
            }
        }
        .navigationTitle("Illness Log")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editTarget = nil
                    showingEntrySheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add illness")
            }
        }
        .sheet(isPresented: $showingEntrySheet) {
            IllnessEntrySheet(event: editTarget) { start, end in
                if let target = editTarget {
                    target.startDate = Calendar.current.startOfDay(for: start)
                    target.endDate = end.map { Calendar.current.startOfDay(for: $0) }
                } else {
                    modelContext.insert(IllnessEvent(startDate: start, endDate: end))
                }
                try? modelContext.save()
                IllnessLog.refreshCoach(modelContext)
            }
        }
    }
}

private struct IllnessRow: View {
    let event: IllnessEvent

    var body: some View {
        VStack(alignment: .leading, spacing: .spacingXs) {
            Text(IllnessFormat.span(start: event.startDate, end: event.endDate))
                .font(.subheadline)
                .foregroundStyle(Color.textPrimary)
            Text(event.isOngoing ? "Still sick" : IllnessFormat.length(start: event.startDate, end: event.endDate!))
                .font(.caption)
                .foregroundStyle(event.isOngoing ? Color.statusWarning : Color.textSecondary)
        }
        .padding(.vertical, .spacingXs)
        .contentShape(Rectangle())
    }
}

/// Add or edit one sick spell. The end date is optional: "still sick" leaves it open.
private struct IllnessEntrySheet: View {
    let event: IllnessEvent?
    let onSave: (Date, Date?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var end: Date
    @State private var stillSick: Bool

    init(event: IllnessEvent?, onSave: @escaping (Date, Date?) -> Void) {
        self.event = event
        self.onSave = onSave
        let today = Calendar.current.startOfDay(for: Date())
        _start = State(initialValue: event?.startDate ?? today)
        _end = State(initialValue: event?.endDate ?? event?.startDate ?? today)
        _stillSick = State(initialValue: event?.isOngoing ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("First sick day", selection: $start, in: ...Date(), displayedComponents: .date)
                Toggle("Still sick", isOn: $stillSick)
                if !stillSick {
                    DatePicker("Last sick day", selection: $end, in: start...max(start, Date()), displayedComponents: .date)
                }
            }
            .navigationTitle(event == nil ? "Log Illness" : "Edit Illness")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(start, stillSick ? nil : max(end, start))
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

enum IllnessFormat {
    static func span(start: Date, end: Date?) -> String {
        let s = start.formatted(.dateTime.month(.abbreviated).day())
        guard let end else { return "Since \(s)" }
        if Calendar.current.isDate(start, inSameDayAs: end) { return s }
        return "\(s) – \(end.formatted(.dateTime.month(.abbreviated).day()))"
    }

    static func length(start: Date, end: Date) -> String {
        let days = (Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0) + 1
        return days == 1 ? "1 day" : "\(days) days"
    }
}
