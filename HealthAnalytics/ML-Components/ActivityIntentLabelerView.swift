//
//  ActivityIntentLabelerView.swift
//  HealthAnalytics
//
//  SwiftUI interface for manually labeling workout intents
//  This creates the training data for the ML classifier
//

import SwiftUI
import SwiftData
import HealthKit

struct ActivityIntentLabelerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(sort: \StoredWorkout.startDate, order: .reverse) private var allWorkouts: [StoredWorkout]
    @Query private var existingLabels: [StoredIntentLabel]
    
    @State private var currentIndex = 0
    @State private var labeledCount = 0
    @State private var isTraining = false
    @State private var trainingResult: ActivityIntentClassifier.TrainingResult?
    @State private var showingResults = false
    @State private var autoClassifyProgress: Double = 0
    @State private var isAutoClassifying = false
    
    // Filter to unlabeled workouts
    private var unlabeledWorkouts: [StoredWorkout] {
        let labeledIds = Set(existingLabels.map { $0.workoutId })
        return allWorkouts.filter { !labeledIds.contains($0.id) }
    }
    
    private var currentWorkout: StoredWorkout? {
        guard currentIndex < unlabeledWorkouts.count else { return nil }
        return unlabeledWorkouts[currentIndex]
    }
    
    private var progress: Double {
        guard !unlabeledWorkouts.isEmpty else { return 1.0 }
        return Double(currentIndex) / Double(unlabeledWorkouts.count)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                
                // Progress Header
                VStack(spacing: 12) {
                    HStack {
                        Text("Label Activities")
                            .font(.title2)
                            .fontWeight(.bold)
                        Spacer()
                        Text("\(labeledCount) labeled")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    ProgressView(value: progress)
                        .tint(.blue)
                    
                    Text("\(currentIndex + 1) of \(unlabeledWorkouts.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(.ultraThinMaterial)
                
                if let workout = currentWorkout {
                    ScrollView {
                        VStack(spacing: 20) {
                            
                            // Workout Details Card
                            WorkoutDetailsCard(workout: workout)
                            
                            // Intent Selection Grid
                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 12) {
                                ForEach(ActivityIntent.allCases, id: \.self) { intent in
                                    IntentButton(intent: intent) {
                                        labelWorkout(workout, as: intent)
                                    }
                                }
                            }
                            .padding()
                            
                            // Quick Actions
                            HStack(spacing: 12) {
                                Button {
                                    skipWorkout()
                                } label: {
                                    Label("Skip", systemImage: "arrow.right")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                
                                Button {
                                    previousWorkout()
                                } label: {
                                    Label("Back", systemImage: "arrow.left")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .disabled(currentIndex == 0)
                            }
                            .padding(.horizontal)
                        }
                        .padding(.vertical)
                    }
                } else {
                    // All done or no workouts
                    ContentUnavailableView(
                        "All Caught Up!",
                        systemImage: "checkmark.circle.fill",
                        description: Text("You've labeled \(labeledCount) activities")
                    )
                }
                
                // Bottom Action Bar
                if labeledCount >= 10 {
                    VStack(spacing: 12) {
                        Divider()
                        
                        HStack(spacing: 12) {
                            Button {
                                Task {
                                    await trainModel()
                                }
                            } label: {
                                if isTraining {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Label("Train Model", systemImage: "brain")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isTraining || labeledCount < 10)
                            
                            if trainingResult != nil {
                                Button {
                                    Task {
                                        await autoClassifyAll()
                                    }
                                } label: {
                                    Label("Auto-Classify All", systemImage: "wand.and.stars")
                                }
                                .buttonStyle(.bordered)
                                .disabled(isAutoClassifying)
                            }
                        }
                        .padding()
                    }
                    .background(.ultraThinMaterial)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingResults) {
                if let result = trainingResult {
                    TrainingResultsView(result: result)
                }
            }
            .overlay {
                if isAutoClassifying {
                    AutoClassifyProgressView(progress: autoClassifyProgress)
                }
            }
        }
        .onAppear {
            labeledCount = existingLabels.count
        }
    }
    
    // MARK: - Actions
    
    private func labelWorkout(_ workout: StoredWorkout, as intent: ActivityIntent) {
        // Create or update label
        let label = StoredIntentLabel(
            workoutId: workout.id,
            intent: intent,
            confidence: 1.0,  // Manual labels are 100% confident
            source: .manual
        )
        
        modelContext.insert(label)
        
        do {
            try modelContext.save()
            labeledCount += 1
            
            // Move to next
            withAnimation {
                currentIndex += 1
            }
            
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            
        } catch {
            print("❌ Failed to save label: \(error)")
        }
    }
    
    private func skipWorkout() {
        withAnimation {
            currentIndex += 1
        }
    }
    
    private func previousWorkout() {
        withAnimation {
            currentIndex = max(0, currentIndex - 1)
        }
    }
    
    private func trainModel() async {
        isTraining = true
        
        do {
            // Get all manually labeled workouts
            let labeledWorkouts = existingLabels.compactMap { label -> (ActivityIntentClassifier.WorkoutFeatures, ActivityIntent)? in
                guard let workout = allWorkouts.first(where: { $0.id == label.workoutId }),
                      label.source == .manual else { return nil }
                
                let features = ActivityIntentClassifier.extractFeatures(from: workout)
                return (features, label.intent)
            }
            
            let result = try await ActivityIntentClassifier.train(labeledWorkouts: labeledWorkouts)
            
            await MainActor.run {
                trainingResult = result
                showingResults = true
                isTraining = false
            }
            
        } catch {
            print("❌ Training failed: \(error)")
            await MainActor.run {
                isTraining = false
            }
        }
    }
    
    private func autoClassifyAll() async {
        guard let trainingResult = trainingResult else { return }
        let model = trainingResult.model
        
        isAutoClassifying = true
        autoClassifyProgress = 0
        
        let existingLabelIds = Set(existingLabels.map { $0.workoutId })
        let unlabeled = allWorkouts.filter { !existingLabelIds.contains($0.id) }
        
        print("🤖 Auto-classifying \(unlabeled.count) workouts...")
        
        // Process in batches to update progress
        let batchSize = 100
        var processed = 0
        
        for batch in stride(from: 0, to: unlabeled.count, by: batchSize) {
            let end = min(batch + batchSize, unlabeled.count)
            let batchWorkouts = Array(unlabeled[batch..<end])
            
            let results = ActivityIntentClassifier.classifyAll(
                workouts: batchWorkouts,
                using: model,
                allowedActivityTypes: trainingResult.allowedActivityTypes,
                existingLabels: existingLabelIds
            )
            
            // Save labels
            for (workoutId, intent, confidence) in results {
                let label = StoredIntentLabel(
                    workoutId: workoutId,
                    intent: intent,
                    confidence: confidence,
                    source: .mlModel
                )
                modelContext.insert(label)
            }
            
            try? modelContext.save()
            
            processed += batchWorkouts.count
            
            await MainActor.run {
                autoClassifyProgress = Double(processed) / Double(unlabeled.count)
            }
        }
        
        await MainActor.run {
            isAutoClassifying = false
            labeledCount = existingLabels.count + unlabeled.count
            print("✅ Auto-classification complete!")
        }
    }
}

// MARK: - Workout Details Card

struct WorkoutDetailsCard: View {
    let workout: StoredWorkout
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundStyle(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(workoutName)
                        .font(.headline)
                    Text(workout.startDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            
            Divider()
            
            // Metrics Grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                MetricTile(
                    label: "Duration",
                    value: formattedDuration,
                    icon: "timer"
                )
                
                if let distance = workout.distance, distance > 0 {
                    MetricTile(
                        label: "Distance",
                        value: String(format: "%.2f mi", distance / 1609.34),
                        icon: "figure.run"
                    )
                }
                
                if let hr = workout.averageHeartRate {
                    MetricTile(
                        label: "Avg HR",
                        value: "\(Int(hr)) bpm",
                        icon: "heart.fill"
                    )
                }
                
                if let power = workout.averagePower, power > 0 {
                    MetricTile(
                        label: "Avg Power",
                        value: "\(Int(power)) W",
                        icon: "bolt.fill"
                    )
                }
                
                if let pace = avgPace {
                    MetricTile(
                        label: "Avg Pace",
                        value: pace,
                        icon: "speedometer"
                    )
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
    
    private var workoutName: String {
        switch workout.workoutType {
        case .running: return "Run"
        case .cycling: return "Ride"
        case .walking: return "Walk"
        case .swimming: return "Swim"
        case .functionalStrengthTraining, .traditionalStrengthTraining: return "Strength"
        default: return "Workout"
        }
    }
    
    private var iconName: String {
        switch workout.workoutType {
        case .running: return "figure.run"
        case .cycling: return "figure.outdoor.cycle"
        case .walking: return "figure.walk"
        case .swimming: return "figure.pool.swim"
        case .functionalStrengthTraining, .traditionalStrengthTraining: return "dumbbell.fill"
        default: return "figure.mixed.cardio"
        }
    }
    
    private var formattedDuration: String {
        let hours = Int(workout.duration) / 3600
        let minutes = Int(workout.duration) / 60 % 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    private var avgPace: String? {
        guard let distance = workout.distance, distance > 0, workout.duration > 0 else { return nil }
        let miles = distance / 1609.34
        let paceSeconds = workout.duration / miles
        let minutes = Int(paceSeconds) / 60
        let seconds = Int(paceSeconds) % 60
        return "\(minutes):\(String(format: "%02d", seconds))/mi"
    }
}

// MARK: - Metric Tile

struct MetricTile: View {
    let label: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
            
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Intent Button

struct IntentButton: View {
    let intent: ActivityIntent
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(intent.emoji)
                    .font(.largeTitle)
                
                Text(intent.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 100)
            .background(intent.color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(intent.color.opacity(0.3), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Training Results View

struct TrainingResultsView: View {
    let result: ActivityIntentClassifier.TrainingResult
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    
                    // Accuracy Hero
                    VStack(spacing: 8) {
                        Text(String(format: "%.1f%%", result.accuracy))
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                            .foregroundStyle(.green)
                        
                        Text("Validation Accuracy")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical)
                    
                    Divider()
                    
                    // Feature Importance
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Feature Importance")
                            .font(.headline)
                        
                        ForEach(result.featureImportance.sorted(by: { $0.value > $1.value }), id: \.key) { feature, importance in
                            HStack {
                                Text(feature.replacingOccurrences(of: "_", with: " ").capitalized)
                                    .font(.subheadline)
                                
                                Spacer()
                                
                                Text(String(format: "%.1f%%", importance * 100))
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.blue)
                            }
                            
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.blue.opacity(0.1))
                                        .frame(height: 6)
                                    
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.blue)
                                        .frame(width: geo.size.width * importance, height: 6)
                                }
                            }
                            .frame(height: 6)
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    // Model Info
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Model Information")
                            .font(.headline)
                        
                        InfoRow(label: "Training Samples", value: "\(result.sampleCount)")
                        InfoRow(label: "Trained At", value: result.trainedAt.formatted(date: .abbreviated, time: .shortened))
                        InfoRow(label: "Model Type", value: "Random Forest Classifier")
                        InfoRow(label: "Activity Types", value: result.allowedActivityTypes.sorted().joined(separator: ", "))
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding()
            }
            .navigationTitle("Training Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }
}

// MARK: - Auto-Classify Progress Overlay

struct AutoClassifyProgressView: View {
    let progress: Double
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.blue)
                    .frame(width: 200)
                
                Text("Classifying workouts...")
                    .font(.headline)
                    .foregroundStyle(.white)
                
                Text("\(Int(progress * 100))%")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(32)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }
}

#Preview {
    ActivityIntentLabelerView()
        .modelContainer(for: [StoredWorkout.self, StoredIntentLabel.self], inMemory: true)
}
