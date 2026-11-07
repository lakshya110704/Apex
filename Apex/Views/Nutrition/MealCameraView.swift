import SwiftUI
import PhotosUI

struct MealCameraView: View {
    @Environment(\.dismiss) private var dismiss

    var claude: ClaudeService
    var onSave: (MealEntry) -> Void

    @State private var selectedItem: PhotosPickerItem?
    @State private var capturedImage: UIImage?
    @State private var mealType: MealType = .lunch
    @State private var isAnalyzing = false
    @State private var analysis: MealAnalysis?
    @State private var errorMessage: String?
    @State private var showingCamera = false

    var body: some View {
        NavigationStack {
            ZStack {
                ApexColor.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {

                        // Meal Type Selector
                        HStack(spacing: 0) {
                            ForEach(MealType.allCases, id: \.self) { type in
                                Button {
                                    mealType = type
                                } label: {
                                    VStack(spacing: 4) {
                                        Image(systemName: type.systemImage)
                                            .font(.title3)
                                        Text(type.rawValue)
                                            .font(.caption.bold())
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .foregroundStyle(mealType == type ? ApexColor.background : ApexColor.textSecondary)
                                    .background(mealType == type ? ApexColor.success : Color.clear)
                                }
                            }
                        }
                        .background(ApexColor.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal)

                        // Photo Area
                        photoSelectionArea
                            .padding(.horizontal)

                        // Analysis Results
                        if isAnalyzing {
                            analyzingView
                                .padding(.horizontal)
                        } else if let analysis {
                            analysisResultView(analysis)
                                .padding(.horizontal)
                        } else if let error = errorMessage {
                            errorView(error)
                                .padding(.horizontal)
                        }

                        Spacer(minLength: 24)
                    }
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Log Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(ApexColor.textSecondary)
                }
                if analysis != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { saveMeal() }
                            .font(.headline)
                            .foregroundStyle(ApexColor.success)
                    }
                }
            }
            .onChange(of: selectedItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        capturedImage = image
                        await analyzeImage(image)
                    }
                }
            }
        }
    }

    // MARK: - Photo Selection

    private var photoSelectionArea: some View {
        VStack(spacing: 16) {
            if let image = capturedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(alignment: .topTrailing) {
                        Button { capturedImage = nil; analysis = nil } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .shadow(radius: 4)
                                .padding(8)
                        }
                    }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(ApexColor.cardBg)
                        .frame(height: 200)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                                .foregroundStyle(ApexColor.textSecondary.opacity(0.4))
                        )
                    VStack(spacing: 12) {
                        Image(systemName: "fork.knife.circle")
                            .font(.system(size: 44))
                            .foregroundStyle(ApexColor.success)
                        Text("Add a photo of your meal")
                            .font(.subheadline)
                            .foregroundStyle(ApexColor.textSecondary)
                    }
                }
            }

            // Buttons
            HStack(spacing: 12) {
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Label("Photo Library", systemImage: "photo.on.rectangle")
                        .font(.subheadline.bold())
                        .foregroundStyle(ApexColor.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(ApexColor.cardBg2)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    showingCamera = true
                } label: {
                    Label("Camera", systemImage: "camera.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(ApexColor.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(ApexColor.success)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraView { image in
                capturedImage = image
                Task { await analyzeImage(image) }
            }
        }
    }

    // MARK: - Analyzing

    private var analyzingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(ApexColor.success)
                .scaleEffect(1.4)
            Text("Apex Coach is analyzing your meal...")
                .font(.subheadline)
                .foregroundStyle(ApexColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(ApexColor.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Results

    private func analysisResultView(_ result: MealAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Analysis", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ApexColor.success)
                Spacer()
                Text("Confidence: \(result.confidence)")
                    .font(.caption)
                    .foregroundStyle(ApexColor.textSecondary)
            }

            Text(result.description)  // MealAnalysis.description (not MealEntry)
                .font(.subheadline)
                .foregroundStyle(ApexColor.textPrimary)

            // Calories hero
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(result.estimatedCalories)")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(ApexColor.success)
                    Text("estimated calories")
                        .font(.caption)
                        .foregroundStyle(ApexColor.textSecondary)
                }
                Spacer()
                XPBadge(amount: XPValues.logMeal)
            }

            // Macros
            HStack(spacing: 12) {
                macroBar(label: "Protein", value: result.proteinGrams, color: ApexColor.accent)
                macroBar(label: "Carbs",   value: result.carbsGrams,   color: ApexColor.accentCyan)
                macroBar(label: "Fat",     value: result.fatGrams,     color: ApexColor.warning)
            }

            // Coach Feedback
            if !result.feedback.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "brain.head.profile")
                        .font(.subheadline)
                        .foregroundStyle(ApexColor.accent)
                        .padding(.top, 1)
                    Text(result.feedback)
                        .font(.subheadline)
                        .foregroundStyle(ApexColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(ApexColor.accent.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .apexCard()
    }

    private func macroBar(label: String, value: Double, color: Color) -> some View {
        VStack(spacing: 6) {
            Text("\(Int(value))g")
                .font(.headline.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(ApexColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Error

    private func errorView(_ msg: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(ApexColor.warning)
            Text(msg)
                .font(.subheadline)
                .foregroundStyle(ApexColor.textPrimary)
        }
        .apexCard()
    }

    // MARK: - Actions

    private func analyzeImage(_ image: UIImage) async {
        guard claude.isConfigured else {
            errorMessage = "Set up an AI provider in Settings to analyze meals."
            return
        }
        isAnalyzing = true
        errorMessage = nil
        do {
            analysis = try await claude.analyzeMeal(image: image)
        } catch {
            errorMessage = error.localizedDescription
        }
        isAnalyzing = false
    }

    private func saveMeal() {
        guard let result = analysis else { return }
        let entry = MealEntry(
            date: Date(),
            mealType: mealType,
            photoData: capturedImage?.jpegData(compressionQuality: 0.6),
            mealDescription: result.description,
            estimatedCalories: result.estimatedCalories,
            proteinGrams: result.proteinGrams,
            carbsGrams: result.carbsGrams,
            fatGrams: result.fatGrams,
            claudeAnalysis: result.description  // MealAnalysis.description is fine here
        )
        onSave(entry)
        dismiss()
    }
}

// MARK: - Camera UIKit Wrapper

struct CameraView: UIViewControllerRepresentable {
    var onCapture: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var onCapture: (UIImage) -> Void
        init(onCapture: @escaping (UIImage) -> Void) { self.onCapture = onCapture }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
