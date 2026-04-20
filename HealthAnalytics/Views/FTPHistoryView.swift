//
//  FTPHistoryView.swift
//  HealthAnalytics
//
//  FTP history management: add, edit, delete, conflict resolution.
//
//  Zone re-computation is batched — changes accumulate while the user edits,
//  then a single "Apply Changes" tap triggers invalidateZones() for the
//  earliest affected date across all mutations. No redundant API calls.
//

import SwiftUI
import SwiftData

struct FTPHistoryView: View {
    @Query(sort: \StoredFTPSnapshot.date, order: .reverse) private var snapshots: [StoredFTPSnapshot]
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var syncManager = SyncManager.shared

    // Batch invalidation state
    @State private var earliestMutatedDate: Date? = nil   // tracks earliest affected date
    @State private var pendingChangeCount = 0

    // Sheet / dialog state
    @State private var editTarget: StoredFTPSnapshot? = nil
    @State private var showingEntrySheet = false
    @State private var deleteTarget: StoredFTPSnapshot? = nil
    @State private var showingDeleteConfirmation = false

    // Conflict detection: calendar days with 2+ entries
    private var conflictDates: Set<String> {
        var counts: [String: Int] = [:]
        for s in snapshots { counts[dayKey(s.date), default: 0] += 1 }
        return Set(counts.filter { $0.value > 1 }.keys)
    }

    // Snapshots grouped by calendar day, newest first
    private var grouped: [(dayKey: String, date: Date, entries: [StoredFTPSnapshot])] {
        var map: [String: (Date, [StoredFTPSnapshot])] = [:]
        for s in snapshots {
            let key = dayKey(s.date)
            if map[key] == nil { map[key] = (s.date, []) }
            map[key]!.1.append(s)
        }
        return map
            .map { (dayKey: $0.key, date: $0.value.0, entries: $0.value.1) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            // Zone backfill progress
            if let progress = syncManager.zoneBackfillProgress {
                Section {
                    HStack(spacing: 10) {
                        ProgressView().scaleEffect(0.8)
                        Text("Re-computing zones (\(progress.current)/\(progress.total))...")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }

            // Zone backfill error (rate limit or network failure)
            if let errorMsg = syncManager.zoneBackfillError {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.caption)
                            .foregroundStyle(Color.statusWarning)
                        Text(errorMsg)
                            .font(.caption)
                            .foregroundStyle(Color.statusWarning)
                    }
                }
            }

            // Pending-changes banner
            if pendingChangeCount > 0 && syncManager.zoneBackfillProgress == nil {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "bolt.fill")
                                .font(.caption)
                                .foregroundStyle(Color.accent)
                            Text("\(pendingChangeCount) unsaved zone \(pendingChangeCount == 1 ? "change" : "changes")")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        Text("Zones won't update until you apply. You can keep editing first.")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                        Button {
                            applyZoneChanges()
                        } label: {
                            Text("Apply Zone Changes")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.accent)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // Empty state
            if snapshots.isEmpty {
                Section {
                    Text("No FTP history. Tap + to add an entry, or sync from Strava in Settings.")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            } else {
                ForEach(grouped, id: \.dayKey) { group in
                    let isConflict = conflictDates.contains(group.dayKey)
                    Section {
                        if isConflict {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(Color.statusWarning)
                                Text("Conflict: \(group.date, style: .date) — keep one")
                                    .font(.caption)
                                    .foregroundStyle(Color.statusWarning)
                            }
                            .listRowBackground(Color.statusWarning.opacity(0.08))
                        }

                        ForEach(group.entries) { snapshot in
                            Button {
                                editTarget = snapshot
                                showingEntrySheet = true
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(snapshot.watts) W")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(Color.accent)
                                        Text(sourceLabel(snapshot.source))
                                            .font(.caption2)
                                            .foregroundStyle(Color.textTertiary)
                                    }
                                    Spacer()
                                    Text(snapshot.date, style: .date)
                                        .font(.caption)
                                        .foregroundStyle(Color.textSecondary)
                                    Image(systemName: "pencil")
                                        .font(.caption2)
                                        .foregroundStyle(Color.textTertiary)
                                        .padding(.leading, 4)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    deleteTarget = snapshot
                                    showingDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("FTP History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editTarget = nil
                    showingEntrySheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingEntrySheet) {
            FTPEntrySheet(existing: editTarget) { date, watts in
                let start = Calendar.current.startOfDay(for: date)
                if let existing = editTarget {
                    // Edit — mutate in place
                    let oldDate = existing.date
                    existing.date = start
                    existing.watts = watts
                    recordMutation(affectedDate: min(oldDate, start))
                } else {
                    // Add — insert new row
                    modelContext.insert(StoredFTPSnapshot(date: start, watts: watts, source: "manual"))
                    recordMutation(affectedDate: start)
                }
                try? modelContext.save()
            }
        }
        .confirmationDialog(
            "Delete FTP Entry?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            if let target = deleteTarget {
                Button(
                    "Delete \(target.watts)W (\(target.date.formatted(date: .abbreviated, time: .omitted)))",
                    role: .destructive
                ) {
                    recordMutation(affectedDate: target.date)
                    modelContext.delete(target)
                    try? modelContext.save()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Apply zone changes when you're done editing to re-compute affected workouts.")
        }
    }

    // MARK: - Helpers

    private func recordMutation(affectedDate: Date) {
        pendingChangeCount += 1
        if let current = earliestMutatedDate {
            earliestMutatedDate = min(current, affectedDate)
        } else {
            earliestMutatedDate = affectedDate
        }
    }

    private func applyZoneChanges() {
        guard let date = earliestMutatedDate else { return }
        pendingChangeCount = 0
        earliestMutatedDate = nil
        Task { await SyncManager.shared.invalidateZones(affectedAfter: date) }
    }

    private func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f.string(from: date)
    }

    private func sourceLabel(_ source: String) -> String {
        switch source {
        case "strava_profile": return "Strava"
        case "manual":         return "Manual"
        default:               return source
        }
    }
}

// MARK: - Add / Edit Sheet

private struct FTPEntrySheet: View {
    let existing: StoredFTPSnapshot?
    let onSave: (Date, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pickedDate: Date
    @State private var wattsText: String
    @State private var validationError: String? = nil

    init(existing: StoredFTPSnapshot?, onSave: @escaping (Date, Int) -> Void) {
        self.existing = existing
        self.onSave = onSave
        _pickedDate = State(initialValue: existing?.date ?? Date())
        _wattsText = State(initialValue: existing.map { "\($0.watts)" } ?? "")
    }

    private var isEditing: Bool { existing != nil }

    private var parsedWatts: Int? {
        guard let v = Int(wattsText.trimmingCharacters(in: .whitespaces)),
              (50...600).contains(v) else { return nil }
        return v
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Effective Date") {
                    DatePicker(
                        "Date",
                        selection: $pickedDate,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                }

                Section("FTP") {
                    HStack {
                        Text("Watts")
                        Spacer()
                        TextField("e.g. 265", text: $wattsText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                            .foregroundStyle(parsedWatts != nil ? Color.accent : Color.statusWarning)
                            .fontWeight(.semibold)
                        Text("W")
                            .foregroundStyle(Color.textSecondary)
                    }
                    if let error = validationError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Color.statusWarning)
                    }
                }

                Section {
                    if let w = parsedWatts {
                        Text("Zone calculations for Strava cycling workouts on and after this date will use \(w)W when you apply changes.")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    } else if !wattsText.isEmpty {
                        Text("Enter a value between 50 and 600 W.")
                            .font(.caption)
                            .foregroundStyle(Color.statusWarning)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit FTP Entry" : "Add FTP Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        guard let w = parsedWatts else {
                            validationError = "Enter a value between 50 and 600 W."
                            return
                        }
                        validationError = nil
                        onSave(pickedDate, w)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(parsedWatts == nil)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        FTPHistoryView()
    }
}
