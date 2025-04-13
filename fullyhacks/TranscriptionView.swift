import SwiftUI
import Firebase
import FirebaseFirestore

// View for a single transcription entry
struct TranscriptionEntryView: View {
    var entry: TranscriptionEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.text)
                .font(.system(size: 17, weight: .regular, design: .rounded))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
            
            Text(entry.formattedTime)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.gray.opacity(0.7))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.18).opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// View model for the transcription view
class TranscriptionViewModel: ObservableObject {
    @Published var transcriptionEntries: [TranscriptionEntry] = []
    @Published var sessionName: String = "Discussion"
    @Published var startTime: Date?
    @Published var isLoading = true
    @Published var isPlaying = false
    @Published var showingSummary = false
    @Published var summaryText = ""
    @Published var errorMessage: String?
    
    private let sessionId: String
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    
    init(sessionId: String) {
        self.sessionId = sessionId
    }
    
    var formattedStartTime: String {
        guard let startTime = startTime else {
            return "Just now"
        }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: startTime)
    }
    
    func loadData() {
        guard !sessionId.isEmpty else {
            isLoading = false
            return
        }
        
        // First do a one-time fetch to get initial data
        fetchData()
        
        // Then set up real-time listener for updates
        setupListener()
    }
    
    private func fetchData() {
        let docRef = db.collection("discussions").document(sessionId)
        
        docRef.getDocument { [weak self] (document, error) in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    print("Error getting document: \(error)")
                    self.errorMessage = "Error fetching data: \(error.localizedDescription)"
                    return
                }
                
                guard let document = document, document.exists,
                      let data = document.data() else {
                    print("Document does not exist")
                    self.errorMessage = "Discussion session not found"
                    return
                }
                
                // Parse session info
                if let sessionName = data["sessionName"] as? String {
                    self.sessionName = sessionName
                }
                
                if let startTimeTimestamp = data["startTime"] as? Timestamp {
                    self.startTime = startTimeTimestamp.dateValue()
                }
                
                // Parse transcription entries
                self.parseTranscriptionData(data)
            }
        }
    }
    
    private func setupListener() {
        // Clean up any existing listener
        listener?.remove()
        
        // Set up a real-time listener for updates
        listener = db.collection("discussions").document(sessionId)
            .addSnapshotListener { [weak self] (documentSnapshot, error) in
                guard let self = self else { return }
                
                if let error = error {
                    DispatchQueue.main.async {
                        self.errorMessage = "Listener error: \(error.localizedDescription)"
                    }
                    return
                }
                
                guard let document = documentSnapshot,
                      let data = document.data() else {
                    return
                }
                
                // Parse and update the transcription entries
                self.parseTranscriptionData(data)
            }
    }
    
    private func parseTranscriptionData(_ data: [String: Any]) {
        if let transcriptionData = data["transcription"] as? [[String: Any]] {
            var entries: [TranscriptionEntry] = []
            
            for entryData in transcriptionData {
                if let text = entryData["text"] as? String,
                   let timestamp = entryData["timestamp"] as? TimeInterval {
                    let entry = TranscriptionEntry(
                        text: text,
                        timestamp: timestamp
                    )
                    entries.append(entry)
                }
            }
            
            // Sort by timestamp and update
            DispatchQueue.main.async {
                self.transcriptionEntries = entries.sorted(by: { $0.timestamp < $1.timestamp })
            }
        }
    }
    
    func togglePlayback() {
        // This would integrate with audio playback
        // For now just toggle the state
        isPlaying.toggle()
        
        // In a real implementation, you would:
        // 1. Have access to the original audio recording
        // 2. Play it back from the current position or start
    }
    
    func generateSummary() {
        // This would ideally call an AI service to generate a summary
        // For now, just create a simple placeholder summary
        
        let allText = transcriptionEntries.map { $0.text }.joined(separator: " ")
        let words = allText.split(separator: " ")
        
        if words.count > 10 {
            // Simple summary - first sentence + length info
            var firstSentence = ""
            if let sentenceEnd = allText.firstIndex(of: ".") {
                firstSentence = String(allText[allText.startIndex...sentenceEnd])
            } else {
                // If no period found, just take first 100 characters
                let endIndex = min(allText.count, 100)
                firstSentence = String(allText.prefix(endIndex))
            }
            
            summaryText = """
            Summary of discussion:
            
            \(firstSentence)
            
            This discussion contained \(transcriptionEntries.count) segments with a total of \(words.count) words.
            """
        } else {
            summaryText = "This discussion is too short to generate a meaningful summary."
        }
        
        showingSummary = true
    }
    
    func shareTranscription() {
        // Create text to share
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        
        let headerText = """
        Discussion: \(sessionName)
        Date: \(dateFormatter.string(from: startTime ?? Date()))
        
        Transcript:
        
        """
        
        let transcriptText = transcriptionEntries
            .sorted(by: { $0.timestamp < $1.timestamp })
            .map { "[\($0.formattedTime)] \($0.text)" }
            .joined(separator: "\n\n")
        
        let fullText = headerText + transcriptText
        
        // Share the text using UIActivityViewController
        let activityViewController = UIActivityViewController(
            activityItems: [fullText],
            applicationActivities: nil
        )
        
        // Present the view controller
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(activityViewController, animated: true, completion: nil)
        }
    }
    
    deinit {
        // Clean up listener when view model is deallocated
        listener?.remove()
    }
}

// Helper extensions
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

struct TranscriptionView: View {
    var sessionId: String
    
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var viewModel: TranscriptionViewModel
    
    init(sessionId: String) {
        self.sessionId = sessionId
        // Initialize the view model with the session ID
        _viewModel = StateObject(wrappedValue: TranscriptionViewModel(sessionId: sessionId))
    }
    
    var body: some View {
        ZStack {
            // Background
            Color.black.edgesIgnoringSafeArea(.all)
            
            // Content
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(
                                Circle()
                                    .fill(Color.blue.opacity(0.2))
                                    .overlay(
                                        Circle()
                                            .stroke(Color.blue.opacity(0.5), lineWidth: 1)
                                    )
                            )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 16)
                
                // Session info
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.sessionName)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text(viewModel.formattedStartTime)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                
                // Transcription content
                ScrollView {
                    ScrollViewReader { scrollView in
                        VStack(alignment: .leading, spacing: 20) {
                            if viewModel.transcriptionEntries.isEmpty && viewModel.isLoading {
                                // Loading state
                                HStack {
                                    Spacer()
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                                        .scaleEffect(1.5)
                                    Spacer()
                                }
                                .padding(.top, 100)
                            } else if viewModel.transcriptionEntries.isEmpty {
                                // Empty state
                                VStack(spacing: 16) {
                                    Image(systemName: "text.bubble")
                                        .font(.system(size: 60))
                                        .foregroundColor(.gray.opacity(0.7))
                                    
                                    Text("No transcription available")
                                        .font(.system(size: 18, weight: .medium, design: .rounded))
                                        .foregroundColor(.gray)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 100)
                            } else {
                                // Content
                                ForEach(viewModel.transcriptionEntries) { entry in
                                    TranscriptionEntryView(entry: entry)
                                        .id(entry.id) // For ScrollViewReader
                                }
                                .padding(.horizontal, 16)
                                
                                // Add some space at the bottom for better scrolling
                                Color.clear.frame(height: 40)
                                    .id("bottomAnchor")
                            }
                        }
                        .padding(.top, 12)
                        .onChange(of: viewModel.transcriptionEntries.count) { _ in
                            // Scroll to bottom when new transcriptions come in
                            withAnimation {
                                scrollView.scrollTo("bottomAnchor", anchor: .bottom)
                            }
                        }
                    }
                }
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.05, green: 0.05, blue: 0.1),
                            Color(red: 0.07, green: 0.07, blue: 0.12)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(24, corners: [.topLeft, .topRight])
                
                // Bottom control area
                HStack(spacing: 16) {
                    Button(action: {
                        viewModel.togglePlayback()
                    }) {
                        Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .padding(14)
                            .background(
                                Circle()
                                    .fill(Color.blue.opacity(0.2))
                                    .overlay(
                                        Circle()
                                            .stroke(Color.blue.opacity(0.5), lineWidth: 1)
                                    )
                            )
                    }
                    
                    Button(action: {
                        viewModel.generateSummary()
                    }) {
                        Text("Generate Summary")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.vertical, 14)
                            .padding(.horizontal, 32)
                            .background(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color.blue.opacity(0.7),
                                                Color.purple.opacity(0.6)
                                            ]),
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            )
                    }
                }
                .padding(.vertical, 18)
                .background(Color.black.opacity(0.7))
            }
        }
        .onAppear {
            viewModel.loadData()
        }
        .alert(isPresented: $viewModel.showingSummary) {
            Alert(
                title: Text("Discussion Summary"),
                message: Text(viewModel.summaryText),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}
