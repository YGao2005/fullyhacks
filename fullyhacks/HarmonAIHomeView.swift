import SwiftUI
import Combine
import Firebase
import FirebaseFirestore

struct HarmonAIHomeView: View {
    // Create the ViewModels at the top level of the view hierarchy
    @StateObject private var galaxyViewModel: GalaxyViewModel
    
    // Use the unified AudioService
    @StateObject private var audioService = AudioService()
    
    // Track the app state
    @State private var isRecording = false
    @State private var showingDiscussionView = false
    @State private var showDebugPanel = false
    
    init() {
        // Initialize with a dummy size that will be updated in GeometryReader
        let initialSize = CGRect(x: 0, y: 0, width: 300, height: 300)
        _galaxyViewModel = StateObject(wrappedValue: GalaxyViewModel(screenSize: initialSize))
    }
    
    var body: some View {
        ZStack {
            // Galaxy background with GeometryReader to get the correct size
            GeometryReader { geometry in
                // Create this once with color.clear as a background
                Color.clear
                    .onAppear {
                        // Update the screen size when the view appears
                        galaxyViewModel.screenSize = geometry.frame(in: .global)
                        galaxyViewModel.createStars() // Recreate stars with correct size
                    }
                    .onChange(of: geometry.size) { newSize in
                        // Update if the screen size changes
                        galaxyViewModel.screenSize = geometry.frame(in: .global)
                        galaxyViewModel.createStars()
                    }
                
                // Then pass the viewModel to GalaxyEffectView
                GalaxyEffectView(viewModel: galaxyViewModel)
            }
            
            // Subtle overlay gradient for depth
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.black.opacity(0.4),
                    Color.black.opacity(0),
                    Color.black.opacity(0.5)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            
            VStack {
                // Titles at the top
                HStack {
                    HarmonAITitleView()
                    
                    Spacer()
                    
                    // Debug button
                    Button(action: {
                        showDebugPanel.toggle()
                    }) {
                        Image(systemName: "ant")
                            .font(.system(size: 20))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 40, height: 40)
                            .background(
                                Circle()
                                    .fill(Color.blue.opacity(0.2))
                                    .overlay(
                                        Circle()
                                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                                    )
                            )
                    }
                    .padding(.trailing, 15)
                }
                
                HarmonAISubtitleView()
                
                Spacer()
                
                // Dynamic button based on state
                if galaxyViewModel.isVisualizingAudio {
                    // Transcription area
                    TranscriptionBubbleView(text: audioService.latestTranscription)
                        .padding(.bottom, 20)
                        .animation(.easeInOut, value: audioService.latestTranscription)
                    
                    // Show the recording button when visualizing audio
                    RecordingButton(isRecording: $isRecording) {
                        if isRecording {
                            stopRecording()
                        } else {
                            startRecording()
                        }
                    }
                    .padding(.bottom, 35)
                    
                    // Continue button to move to discussion
                    MainNeonButton(title: "Continue") {
                        print("Continue to discussion")
                        showingDiscussionView = true
                    }
                    .padding(.bottom, 30)
                } else {
                    // Buttons at the bottom for initial state
                    VStack(spacing: 25) {
                        MainNeonButton(title: "New Discussion") {
                            print("Create button tapped")
                            // Create a new session before visualization
                            createNewSession()
                            // Trigger the galaxy transformation
                            galaxyViewModel.startTransformation()
                        }
                        
                        SecondaryNeonButton(title: "Test Connection") {
                            print("Test connection tapped")
                            showDebugPanel = true
                            
                            // Test the connection
                            audioService.testConnection()
                        }
                    }
                    .padding(.bottom, 85)
                }
            }
        }
        .edgesIgnoringSafeArea(.all)
        // Update galaxy visualization with audio levels
        .onReceive(audioService.$audioLevels) { levels in
            if isRecording {
                galaxyViewModel.updateAudioLevels(levels)
            }
        }
        // Sync recording state
        .onReceive(audioService.$isRecording) { recording in
            isRecording = recording
        }
        // Navigation to discussion view
        .fullScreenCover(isPresented: $showingDiscussionView) {
            // Present the TranscriptionView with the current session ID
            if let sessionId = audioService.sessionId {
                TranscriptionView(sessionId: sessionId)
                    .onAppear {
                        // Stop recording on this view when showing TranscriptionView
                        stopRecording()
                    }
            }
        }
    }
    
    // MARK: - Audio Control Methods
    
    private func createNewSession() {
        audioService.createNewSession {
            // Session created callback
            print("Session created with ID: \(self.audioService.sessionId ?? "unknown")")
        }
    }
    
    private func startRecording() {
        audioService.startRecording()
    }
    
    private func stopRecording() {
        audioService.stopRecording()
    }
}

// NOTE: The TranscriptionView will need to be updated to work with the new service,
// but we're focusing on the home view for now

// FirestoreManager to handle Firebase operations
class FirestoreManager {
    private let db = Firestore.firestore()
    private var transcriptionListener: ListenerRegistration?
    
    func setupListener(for sessionId: String, onUpdate: @escaping (String) -> Void) {
        // Remove existing listener first
        removeListener()
        
        // Set up new listener
        transcriptionListener = db.collection("discussions").document(sessionId)
            .addSnapshotListener { documentSnapshot, error in
                guard let document = documentSnapshot else {
                    print("Error fetching document: \(error?.localizedDescription ?? "Unknown error")")
                    return
                }
                
                guard let data = document.data() else {
                    print("Document data was empty")
                    return
                }
                
                if let transcriptionData = data["transcription"] as? [[String: Any]] {
                    // If there's at least one entry
                    if let lastEntry = transcriptionData.last,
                       let text = lastEntry["text"] as? String {
                        // Update the latest transcription text via callback
                        DispatchQueue.main.async {
                            onUpdate(text)
                        }
                    }
                    
                    // Log the total number of transcriptions
                    print("Total transcriptions: \(transcriptionData.count)")
                }
            }
    }
    
    func removeListener() {
        transcriptionListener?.remove()
        transcriptionListener = nil
    }
}

// The rest of your views remain unchanged
struct TranscriptionBubbleView: View {
    var text: String
    
    @State private var glowIntensity: CGFloat = 0.4
    
    var body: some View {
        ZStack {
            // If there's no text, display a placeholder
            if text.isEmpty {
                Text("Speak to begin recording...")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 15)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.black.opacity(0.3))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 30)
            } else {
                // Otherwise, display the transcription
                Text(text)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 15)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 0.1, green: 0.1, blue: 0.3).opacity(0.7),
                                        Color.black.opacity(0.6)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color.blue.opacity(0.7),
                                                Color.purple.opacity(0.5)
                                            ]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.5
                                    )
                            )
                            .shadow(
                                color: Color.blue.opacity(glowIntensity),
                                radius: 8,
                                x: 0,
                                y: 0
                            )
                    )
                    .padding(.horizontal, 30)
            }
        }
        .onAppear {
            withAnimation(Animation.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                glowIntensity = 0.6
            }
        }
    }
}


