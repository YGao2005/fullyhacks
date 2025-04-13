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
    @State private var isShowingWakeWordStatus = false
    
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
                        
                        // Setup wake word listener when view appears
                        audioService.setupWakeWordListener()
                        
                        // Check wake word status
                        audioService.checkWakeWordStatus()
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
            
            // Wake Word Status Widget (if visible)
            if isShowingWakeWordStatus || audioService.wakeWordActive {
                VStack {
                    HStack {
                        Spacer()
                        WakeWordStatusWidget(audioService: audioService)
                            .padding(.top, 20)
                            .padding(.trailing, 16)
                            .transition(.opacity)
                    }
                    
                    Spacer()
                }
            }
            
            VStack {
                // Titles at the top
                HarmonAITitleView()
                
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
                        
//                        SecondaryNeonButton(title: "Test Connection") {
//                            print("Test connection tapped")
//                            showDebugPanel = true
//                            
//                            // Test the connection
//                            audioService.testConnection()
//                        }
                        
                        // Wake Word toggle button
                        SecondaryNeonButton(title: audioService.wakeWordActive ? "Disable Wake Word" : "Enable Wake Word") {
                            if audioService.wakeWordActive {
                                audioService.deactivateWakeWordDetection()
                            } else {
                                audioService.activateWakeWordDetection()
                            }
                            
                            // Show the status widget when activated
                            withAnimation {
                                isShowingWakeWordStatus = true
                            }
                            
                            // Hide it after 5 seconds if not active
                            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                                withAnimation {
                                    if !audioService.wakeWordActive {
                                        isShowingWakeWordStatus = false
                                    }
                                }
                            }
                        }
                        .padding(.top, 10)
                    }
                    .padding(.bottom, 85)
                }
            }
            
            // Overlay the AI suggestion popup - moved outside the VStack for better layering
            if audioService.isShowingAIPopup {
                Color.black.opacity(0.6)
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture {
                        // Optional: allow dismissing by tapping outside
                        audioService.isShowingAIPopup = false
                    }
                
                AISuggestionPopup(
                    isShowing: $audioService.isShowingAIPopup,
                    negativeSentimentText: audioService.negativeSentimentText,
                    suggestion: audioService.aiSuggestion
                )
                .transition(.scale)
                .animation(.spring(), value: audioService.isShowingAIPopup)
            }
            
            // Wake Word Popup overlay
            if audioService.isWakeWordDetected {
                Color.black.opacity(0.6)
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture {
                        // Optional: allow dismissing by tapping outside
                        audioService.isWakeWordDetected = false
                    }
                
                WakeWordPopupView(
                    isShowing: $audioService.isWakeWordDetected,
                    message: audioService.wakeWordMessage,
                    sessionId: audioService.sessionId ?? "Unknown",
                    onContinue: {
                        // Navigate to discussion or session view
                        showingDiscussionView = true
                        
                        // Trigger the galaxy transformation if not already visualizing
                        if !galaxyViewModel.isVisualizingAudio {
                            galaxyViewModel.startTransformation()
                        }
                    }
                )
                .transition(.scale)
                .animation(.spring(), value: audioService.isWakeWordDetected)
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
            } else {
                // Fallback if no session ID is available
                Text("No active session")
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.black)
                    .edgesIgnoringSafeArea(.all)
            }
        }
        // Debug panel
        .sheet(isPresented: $showDebugPanel) {
            ConnectionDebugView(audioService: audioService)
        }
        // Listen for notifications
        .onReceive(NotificationCenter.default.publisher(for: .wakeWordDetected)) { notification in
            // Handle wake word notification if needed
            if let sessionId = notification.userInfo?["sessionId"] as? String {
                print("Received wake word notification for session: \(sessionId)")
            }
        }
    }
    
    // MARK: - Audio Control Methods
    
    private func createNewSession() {
        audioService.createNewSession {
            // Session created callback
            if let sessionId = self.audioService.sessionId {
                print("Session created with ID: \(sessionId)")
            } else {
                print("Session created but no ID returned")
            }
        }
    }
    
    private func startRecording() {
        audioService.startRecording()
    }
    
    private func stopRecording() {
        audioService.stopRecording()
    }
}

// Connection debug view to show connection status, errors, etc.
struct ConnectionDebugView: View {
    @ObservedObject var audioService: AudioService
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Connection Status")
                .font(.title)
                .fontWeight(.bold)
            
            // Connection status
            HStack {
                Circle()
                    .fill(audioService.isConnected ? Color.green : Color.red)
                    .frame(width: 12, height: 12)
                
                Text(audioService.isConnected ? "Connected" : "Disconnected")
            }
            .padding()
            .background(Color.black.opacity(0.5))
            .cornerRadius(8)
            
            // Wake word status
            HStack {
                Circle()
                    .fill(audioService.wakeWordActive ? Color.green : Color.gray)
                    .frame(width: 12, height: 12)
                
                Text("Wake Word: \(audioService.wakeWordActive ? "Active" : "Inactive")")
            }
            .padding()
            .background(Color.black.opacity(0.5))
            .cornerRadius(8)
            
            // Session info
            if let sessionId = audioService.sessionId {
                Text("Session ID: \(sessionId)")
                    .font(.caption)
                    .padding()
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(8)
            }
            
            // Error message
            if let error = audioService.errorMessage {
                Text("Error: \(error)")
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding()
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(8)
            }
            
            // Wake word controls
            HStack(spacing: 20) {
                Button(action: {
                    audioService.activateWakeWordDetection()
                }) {
                    Text("Start Wake Word")
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
                
                Button(action: {
                    audioService.deactivateWakeWordDetection()
                }) {
                    Text("Stop Wake Word")
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.red)
                        .cornerRadius(8)
                }
            }
            
            // Close button
            Button(action: {
                presentationMode.wrappedValue.dismiss()
            }) {
                Text("Close")
                    .foregroundColor(.white)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 12)
                    .background(Color.gray)
                    .cornerRadius(8)
            }
            .padding(.top, 20)
        }
        .padding(30)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.3),
                    Color.black
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .edgesIgnoringSafeArea(.all)
    }
}

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

// TranscriptionBubbleView
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

// Improved AI Suggestion Popup
struct AISuggestionPopup: View {
    @Binding var isShowing: Bool
    let negativeSentimentText: String
    let suggestion: String
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            Text("Negative Sentiment Detected")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.red)
                .padding(.top, 8)
            
            // Original text with quotation marks
            VStack(alignment: .leading, spacing: 6) {
                Text("Original:")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .padding(.horizontal)
                
                Text("\"\(negativeSentimentText)\"")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            
            Divider()
                .background(Color.gray.opacity(0.5))
                .padding(.vertical, 8)
            
            // Suggestion section with improved spacing and text display
            VStack(alignment: .leading, spacing: 8) {
                Text("Suggested Alternative:")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .padding(.horizontal)
                
                // This will display the full suggestion text with proper wrapping
                Text(suggestion)
                    .font(.system(size: 18))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true) // Important for text wrapping
                    .padding(.horizontal)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.bottom, 8)
            
            // Dismiss button with better styling
            Button(action: {
                withAnimation {
                    isShowing = false
                }
            }) {
                Text("Apply Suggestion")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.purple.opacity(0.8)]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .shadow(color: Color.blue.opacity(0.5), radius: 5)
            }
            .padding(.top, 8)
            .padding(.bottom, 16)
            
            // Secondary dismiss button
            Button(action: {
                withAnimation {
                    isShowing = false
                }
            }) {
                Text("Dismiss")
                    .fontWeight(.medium)
                    .foregroundColor(.gray)
            }
            .padding(.bottom, 8)
        }
        .padding(24)
        .background(
            // Dark glass effect background
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(red: 0.1, green: 0.1, blue: 0.2).opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
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
        )
        .shadow(color: Color.black.opacity(0.5), radius: 15)
        .frame(maxWidth: UIScreen.main.bounds.width - 60) // Ensure popup has reasonable width
        .padding(.horizontal, 20)
    }
}
