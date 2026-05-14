//
//  CoachMemoryView.swift
//  HealthAnalytics
//

import SwiftUI
import SwiftData

struct CoachMemoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CoachMemoryNote.dateAdded, order: .reverse) private var memories: [CoachMemoryNote]
    
    @State private var showingAddMemory = false
    @State private var newContext = ""
    @State private var newCategory = "Preference"
    
    let categories = ["Preference", "Injury", "Goal", "Equipment", "Other"]
    
    var body: some View {
        List {
            Section {
                if memories.isEmpty {
                    Text("No memories yet. Add a preference, goal, or injury to personalize your coach.")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ForEach(memories) { memory in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(memory.category)
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.2))
                                    .foregroundColor(.blue)
                                    .clipShape(Capsule())
                                
                                Spacer()
                                
                                Toggle("", isOn: Bindable(memory).isActive)
                                    .labelsHidden()
                            }
                            
                            Text(memory.context)
                                .font(.body)
                                .padding(.top, 2)
                            
                            HStack {
                                Text(memory.dateAdded, style: .date)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                if let expires = memory.expiresAt {
                                    Text("•")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    if memory.isCurrentlyActive {
                                        Text("Expires in \(expires, style: .relative)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("Expired")
                                            .font(.caption2)
                                            .foregroundStyle(.red)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .opacity(memory.isCurrentlyActive ? 1.0 : 0.5)
                    }
                    .onDelete(perform: deleteMemories)
                }
            } header: {
                Text("Active Context")
            } footer: {
                Text("These memories are used by the Master Coach to personalize your daily readiness recommendations.")
            }
        }
        .navigationTitle("Coach Memory")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingAddMemory = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddMemory) {
            NavigationView {
                Form {
                    Section(header: Text("New Memory")) {
                        Picker("Category", selection: $newCategory) {
                            ForEach(categories, id: \.self) {
                                Text($0)
                            }
                        }
                        
                        TextField("e.g. 'Injured right knee'", text: $newContext)
                    }
                }
                .navigationTitle("Add Context")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingAddMemory = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            addMemory()
                            showingAddMemory = false
                        }
                        .disabled(newContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }
    
    private func addMemory() {
        let note = CoachMemoryNote(context: newContext, category: newCategory)
        modelContext.insert(note)
        newContext = ""
        newCategory = "Preference"
    }
    
    private func deleteMemories(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(memories[index])
        }
    }
}

#Preview {
    NavigationView {
        CoachMemoryView()
    }
}
