import Foundation
import SwiftUI
import AVFoundation
import SocketIO
import Firebase
import FirebaseFirestore
import Combine
import AudioToolbox

extension Notification.Name {
    static let negativeSentimentDetected = Notification.Name("negativeSentimentDetected")
    static let wakeWordDetected = Notification.Name("wakeWordDetected")
}

class AudioService: NSObject, ObservableObject {
    // MARK: - Published Properties
    // Audio player for sounds
    private var audioPlayer: AVAudioPlayer?
    
    // Connection state
    @Published var isConnected = false
    
    // Recording state
    @Published var isRecording = false
    
    // Audio visualization data
    @Published var audioLevels: [Float] = Array(repeating: 0, count: 100)
    
    // Transcription data
    @Published var transcriptionEntries: [TranscriptionEntry] = []
    @Published var latestTranscription: String = ""
    
    // Session info
    @Published var sessionId: String?
    @Published var sessionName: String?
    
    // Error handling
    @Published var errorMessage: String?
    
    // AI Suggestion properties
    @Published var isShowingAIPopup = false
    @Published var aiSuggestion: String = ""
    @Published var negativeSentimentText: String = ""
    
    // Wake Word properties
    @Published var isWakeWordDetected = false
    @Published var wakeWordMessage: String = ""
    @Published var wakeWordActive = false
    
    // MARK: - Private Properties
    
    // Socket connection
    private var socket: SocketIOClient
    
    // Audio recording components
    private var audioEngine: AVAudioEngine?
    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var chunkIndex: Int = 0
    private var audioChunkTimer: Timer?
    
    // Configuration
    private let audioBufferSize: UInt32 = 4096
    private let chunkDuration: TimeInterval = 3.0 // Send chunks every 3 seconds
    
    // Audio settings for recording
    private let audioSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 44100,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
    ]
    
    // Firebase reference
    private let db = Firestore.firestore()
    private var firebaseListener: ListenerRegistration?
    
    // MARK: - Initialization
    
    override init() {
        // Use the shared socket from SocketHelper
        self.socket = SocketHelper.shared.socket
        
        super.init()
        
        // Set up socket events and connection
        setupSocket()
    }
    
    // MARK: - Socket Setup
    
    private func setupSocket() {
        // Set up socket event handlers
        socket.on(clientEvent: .connect) { [weak self] data, ack in
            print("Socket connected successfully")
            DispatchQueue.main.async {
                self?.isConnected = true
                self?.errorMessage = nil
            }
        }
        
        // Sentiment alert events
        socket.on("sentiment_alert") { [weak self] data, ack in
            guard let dict = data[0] as? [String: Any],
                  let severity = dict["severity"] as? String,
                  let text = dict["text"] as? String,
                  severity == "high" else { return }
            
            print("⚠️ Negative sentiment alert received")
            
            DispatchQueue.main.async {
                // Play sound alert
                self?.playNegativeSentimentSound()
                
                // Show visual feedback
                self?.showNegativeSentimentWarning(text: text)
                
                // Request AI suggestion (we'll implement this next)
                self?.requestAISuggestion(for: text)
            }
        }
        
        socket.on(clientEvent: .disconnect) { [weak self] data, ack in
            print("Socket disconnected")
            DispatchQueue.main.async {
                self?.isConnected = false
            }
        }
        
        socket.on(clientEvent: .error) { [weak self] data, ack in
            print("Socket error: \(data)")
            DispatchQueue.main.async {
                self?.errorMessage = "Socket error: \(data)"
            }
        }
        
        // Session related events
        socket.on("connection_response") { [weak self] data, ack in
            print("Connection response: \(data)")
        }
        
        socket.on("session_started") { [weak self] data, ack in
            guard let dict = data[0] as? [String: Any],
                  let sessionId = dict["sessionId"] as? String else {
                print("Invalid session data format: \(data)")
                return
            }
            print("Session started: \(sessionId)")
            DispatchQueue.main.async {
                self?.sessionId = sessionId
                self?.transcriptionEntries = [] // Clear previous transcripts
            }
        }
        
        // Transcription events
        socket.on("transcription") { [weak self] data, ack in
            guard let dict = data[0] as? [String: Any],
                  let text = dict["text"] as? String,
                  let timestamp = dict["timestamp"] as? TimeInterval,
                  let sessionId = dict["sessionId"] as? String else {
                print("Invalid transcription data format: \(data)")
                return
            }
            
            print("Received transcription: \(text)")
            let entry = TranscriptionEntry(text: text, timestamp: timestamp)
            DispatchQueue.main.async {
                self?.transcriptionEntries.append(entry)
                self?.latestTranscription = text
            }
        }
        
        socket.on("transcript_update") { [weak self] data, ack in
            guard let self = self, let dataArray = data as? [[String: Any]], let first = dataArray.first else { return }
            
            if let transcriptText = first["text"] as? String {
                DispatchQueue.main.async {
                    self.latestTranscription = transcriptText
                    print("Received transcript update: \(transcriptText)")
                }
            }
        }
        
        // Error events
        socket.on("error") { [weak self] data, ack in
            guard let dict = data[0] as? [String: Any],
                  let message = dict["message"] as? String else {
                print("Invalid error format: \(data)")
                return
            }
            
            print("Received error: \(message)")
            DispatchQueue.main.async {
                self?.errorMessage = message
            }
        }
        
        // Connect to the socket
        socket.connect()
    }
    
    // MARK: - Wake Word Setup
    
    // Setup wake word listener
    func setupWakeWordListener() {
        socket.on("wake_word_activated") { [weak self] data, ack in
            guard let self = self else { return }
            
            guard let dict = data[0] as? [String: Any],
                  let sessionId = dict["sessionId"] as? String,
                  let message = dict["message"] as? String else {
                print("Invalid wake word data format: \(data)")
                return
            }
            
            DispatchQueue.main.async {
                self.handleWakeWordDetection(sessionId: sessionId, message: message)
            }
        }
        
        print("Wake word socket listener configured")
    }
    
    // Handle wake word detection event
    func handleWakeWordDetection(sessionId: String, message: String) {
        print("🎙️ Wake word detected! Session: \(sessionId)")
        
        // Play a notification sound
        playWakeWordDetectedSound()
        
        // Update session ID
        self.sessionId = sessionId
        
        // Update state to show the popup
        self.wakeWordMessage = message
        self.isWakeWordDetected = true
        
        // Start Firebase listener for this session
        self.setupFirebaseListener(for: sessionId)
        
        // Post notification for other components that might need to respond
        NotificationCenter.default.post(
            name: .wakeWordDetected,
            object: nil,
            userInfo: ["sessionId": sessionId, "message": message]
        )
    }
    
    // Wake Word Control APIs
    
    func activateWakeWordDetection() {
        let url = URL(string: "\(SocketHelper.shared.serverURL.absoluteString)/api/wake-word/start")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Failed to activate wake word: \(error.localizedDescription)")
                    self?.errorMessage = "Failed to activate wake word: \(error.localizedDescription)"
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    print("Received error response for wake word activation")
                    self?.errorMessage = "Failed to activate wake word. Server error."
                    return
                }
                
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let status = json["status"] as? String {
                    
                    print("Wake word activation response: \(status)")
                    self?.wakeWordActive = (status == "started" || status == "already_running")
                }
            }
        }.resume()
    }
    
    func deactivateWakeWordDetection() {
        let url = URL(string: "\(SocketHelper.shared.serverURL.absoluteString)/api/wake-word/stop")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Failed to deactivate wake word: \(error.localizedDescription)")
                    self?.errorMessage = "Failed to deactivate wake word: \(error.localizedDescription)"
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse,
                   (200...299).contains(httpResponse.statusCode) {
                    self?.wakeWordActive = false
                    print("Wake word detection deactivated")
                }
            }
        }.resume()
    }
    
    func checkWakeWordStatus() {
        let url = URL(string: "\(SocketHelper.shared.serverURL.absoluteString)/api/wake-word/status")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Failed to check wake word status: \(error.localizedDescription)")
                    return
                }
                
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let active = json["active"] as? Bool {
                    
                    self?.wakeWordActive = active
                    print("Wake word status: \(active ? "active" : "inactive")")
                }
            }
        }.resume()
    }
    
    private func playWakeWordDetectedSound() {
        // Try to use a success sound or synthesized voice
        let soundName = "wake_word_detected" // You can add this sound to your bundle
        
        // First try playing a custom sound if available
        if let soundURL = Bundle.main.url(forResource: soundName, withExtension: "mp3") {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                try AVAudioSession.sharedInstance().setActive(true)
                
                audioPlayer = try AVAudioPlayer(contentsOf: soundURL)
                audioPlayer?.volume = 0.7
                audioPlayer?.play()
            } catch {
                print("Error playing wake word sound: \(error.localizedDescription)")
                
                // Fallback to speech synthesis
                speakWakeWordDetection()
            }
        } else {
            // Fallback to speech synthesis
            speakWakeWordDetection()
        }
        
        // Provide haptic feedback (subtle success feedback)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
    
    private func speakWakeWordDetection() {
        let speechSynthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: "Harmon activated")
        utterance.rate = 0.5
        utterance.volume = 0.7
        speechSynthesizer.speak(utterance)
    }
    
    // MARK: - Sentiment Feedback
    
    private func requestAISuggestion(for text: String) {
        // Store the negative sentiment text
        self.negativeSentimentText = text
        
        // Create the request to your backend
        let url = URL(string: "\(SocketHelper.shared.serverURL.absoluteString)/api/ai-suggestion")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Prepare the request body with the transcript context
        let requestBody: [String: Any] = [
            "sessionId": sessionId ?? "",
            "text": text,
            "requestType": "negative_sentiment_suggestion"
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            print("Error encoding request: \(error)")
            return
        }
        
        // Make the request
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                print("Error requesting AI suggestion: \(error)")
                return
            }
            
            guard let data = data else {
                print("No data received from AI suggestion request")
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let suggestion = json["suggestion"] as? String {
                    
                    DispatchQueue.main.async {
                        self?.aiSuggestion = suggestion
                        self?.isShowingAIPopup = true
                        print("📱 Showing AI suggestion popup")
                    }
                }
            } catch {
                print("Error parsing AI suggestion response: \(error)")
            }
        }.resume()
    }
    
    private func playNegativeSentimentSound() {
        let speechSynthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: "Negative sentiment detected")
        utterance.rate = 0.5
        utterance.volume = 1.0
        speechSynthesizer.speak(utterance)
        print("🔊 Speaking negative sentiment alert")
        
        guard let soundURL = Bundle.main.url(forResource: "negative_alert", withExtension: "mp3") else {
            print("⚠️ Sound file not found")
            return
        }
        
        do {
            // Configure audio session for loudest playback
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            
            guard let soundURL = Bundle.main.url(forResource: "negative_alert", withExtension: "mp3") else {
                print("⚠️ Sound file not found")
                return
            }
            
            audioPlayer = try AVAudioPlayer(contentsOf: soundURL)
            audioPlayer?.volume = 1.0
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            
            print("🔊 Playing negative sentiment sound at maximum volume")
        } catch {
            print("⚠️ Error playing sound: \(error.localizedDescription)")
        }
        
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        AudioServicesPlaySystemSound(1073)
        print("🔊 Playing negative sentiment sound alert")
    }
    
    private func triggerNegativeSentimentFeedback() {
        // Create and prepare the generator in advance (improves responsiveness)
        let notificationGenerator = UINotificationFeedbackGenerator()
        notificationGenerator.prepare()
        
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
        
        // Create impact generators with different intensities
        let heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)
        let rigidGenerator = UIImpactFeedbackGenerator(style: .rigid)
        let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
        
        // Prepare all generators
        heavyGenerator.prepare()
        rigidGenerator.prepare()
        
        // Initial strong error feedback
        notificationGenerator.notificationOccurred(.error)
        
        // Create a sequence of strong vibrations with minimal delays
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            heavyGenerator.impactOccurred(intensity: 1.0)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                rigidGenerator.impactOccurred(intensity: 1.0)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    notificationGenerator.notificationOccurred(.error)
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        heavyGenerator.impactOccurred(intensity: 1.0)
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            mediumGenerator.impactOccurred(intensity: 1.0)
                        }
                    }
                }
            }
        }
        
        // For iOS 13+ devices, add a final strong impact after the sequence
        if #available(iOS 13.0, *) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                let finalGenerator = UIImpactFeedbackGenerator(style: .heavy)
                finalGenerator.prepare()
                finalGenerator.impactOccurred(intensity: 1.0)
            }
        }
        
        // Log that feedback was triggered
        print("💥 Haptic feedback triggered at maximum intensity")
    }
    
    private func showNegativeSentimentWarning(text: String?) {
        // You can post a notification that your UI can observe
        NotificationCenter.default.post(
            name: .negativeSentimentDetected,
            object: nil,
            userInfo: text != nil ? ["text": text!] : nil
        )
    }
    
    // MARK: - Session Management
    
    /// Creates a new discussion session
    func createNewSession(userId: String = "anonymous", sessionName: String? = nil, completion: (() -> Void)? = nil) {
        let name = sessionName ?? "Session \(Date())"
        self.sessionName = name
        
        // Create a URLSession for the API call
        let url = SocketHelper.shared.serverURL.appendingPathComponent("/api/discussions/create")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let params: [String: Any] = [
            "userId": userId,
            "sessionName": name
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: params)
        } catch {
            self.errorMessage = "Failed to encode request: \(error.localizedDescription)"
            completion?()
            return
        }
        
        print("Creating session at URL: \(url.absoluteString)")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.errorMessage = "Failed to create session: \(error.localizedDescription)"
                    completion?()
                }
                return
            }
            
            // Check for HTTP errors
            if let httpResponse = response as? HTTPURLResponse {
                print("Server response code: \(httpResponse.statusCode)")
                
                if !(200...299).contains(httpResponse.statusCode) {
                    DispatchQueue.main.async {
                        self?.errorMessage = "Server returned error code: \(httpResponse.statusCode)"
                        completion?()
                    }
                    return
                }
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    self?.errorMessage = "No data received"
                    completion?()
                }
                return
            }
            
            do {
                // Print the response for debugging
                if let responseString = String(data: data, encoding: .utf8) {
                    print("Server response: \(responseString)")
                }
                
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                
                if let sessionId = json?["sessionId"] as? String {
                    print("Created new session: \(sessionId)")
                    
                    DispatchQueue.main.async {
                        self?.sessionId = sessionId
                        self?.errorMessage = nil
                        
                        // Set up Firebase listener for this session
                        self?.setupFirebaseListener(for: sessionId)
                        
                        // Start the session via Socket.IO
                        self?.socket.emit("start_session", ["sessionId": sessionId])
                        completion?()
                    }
                } else {
                    DispatchQueue.main.async {
                        self?.errorMessage = "Invalid response format - missing sessionId"
                        completion?()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.errorMessage = "Failed to parse response: \(error.localizedDescription)"
                    completion?()
                }
            }
        }.resume()
    }
    
    /// Ends the current session
    func endSession() {
        guard let sessionId = sessionId else {
            errorMessage = "No active session"
            return
        }
        
        // Stop recording if it's active
        if isRecording {
            stopRecording()
        }
        
        // Remove Firebase listener
        removeFirebaseListener()
        
        // Emit end_session event
        socket.emit("end_session", ["sessionId": sessionId])
        
        // Reset state
        self.sessionId = nil
        self.transcriptionEntries = []
    }
    
    // MARK: - Firebase Interactions
    
    /// Sets up a Firebase listener for real-time transcription updates
    private func setupFirebaseListener(for sessionId: String) {
        // Remove any existing listener
        removeFirebaseListener()
        
        print("Setting up Firebase listener for session: \(sessionId)")
        
        // Create a new listener
        firebaseListener = db.collection("discussions").document(sessionId)
            .addSnapshotListener { [weak self] documentSnapshot, error in
                guard let document = documentSnapshot else {
                    print("Error fetching document: \(error?.localizedDescription ?? "Unknown error")")
                    return
                }
                
                guard let data = document.data() else {
                    print("Document data was empty")
                    return
                }
                
                if let transcriptionData = data["transcription"] as? [[String: Any]] {
                    var entries: [TranscriptionEntry] = []
                    
                    for entryData in transcriptionData {
                        if let text = entryData["text"] as? String,
                           let timestamp = entryData["timestamp"] as? TimeInterval {
                            let entry = TranscriptionEntry(text: text, timestamp: timestamp)
                            entries.append(entry)
                        }
                    }
                    
                    // Sort by timestamp and update
                    DispatchQueue.main.async {
                        self?.transcriptionEntries = entries.sorted(by: { $0.timestamp < $1.timestamp })
                        
                        // Update the latest transcription if available
                        if let latestEntry = self?.transcriptionEntries.last {
                            self?.latestTranscription = latestEntry.text
                        }
                    }
                }
            }
    }
    
    /// Removes the Firebase listener
    private func removeFirebaseListener() {
        firebaseListener?.remove()
        firebaseListener = nil
    }
    
    // MARK: - Audio Recording and Processing
    
    /// Starts recording audio
    func startRecording() {
        // Create a new session if none exists
        if sessionId == nil {
            createNewSession {
                self.startRecordingWithChunks()
            }
        } else {
            startRecordingWithChunks()
        }
    }
    
    /// Starts recording with chunked approach
    private func startRecordingWithChunks() {
        guard let sessionId = sessionId else {
            errorMessage = "No active session. Please create a session first."
            return
        }
        
        guard isConnected else {
            errorMessage = "Not connected to server. Please try again."
            return
        }
        
        // Check microphone permission
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            guard let self = self else { return }
            
            guard granted else {
                DispatchQueue.main.async {
                    self.errorMessage = "Microphone permission denied"
                }
                return
            }
            
            DispatchQueue.main.async {
                self.setupChunkedRecording(sessionId: sessionId)
            }
        }
    }
    
    /// Stops recording audio
    func stopRecording() {
        if isRecording {
            // Stop audio engine for visualization
            audioEngine?.stop()
            audioEngine?.inputNode.removeTap(onBus: 0)
            audioEngine = nil
            
            // Stop recorder
            audioRecorder?.stop()
            audioRecorder = nil
            
            // Stop chunk timer
            audioChunkTimer?.invalidate()
            audioChunkTimer = nil
            
            isRecording = false
            
            // Reset audio levels over time
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 1.0)) {
                    self.audioLevels = Array(repeating: 0, count: 100)
                }
            }
        }
    }
    
    /// Sets up chunked audio recording
    private func setupChunkedRecording(sessionId: String) {
        do {
            // Set up audio session
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)
            
            // 1. Set up audio engine for visualization
            setupAudioEngine()
            
            // 2. Set up audio recorder for chunked recording
            setupChunkedAudioRecorder(sessionId: sessionId)
            
            isRecording = true
            
        } catch {
            errorMessage = "Error setting up audio: \(error.localizedDescription)"
            print("Audio setup error: \(error)")
        }
    }
    
    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            errorMessage = "Failed to create audio engine"
            return
        }
        
        // Get the input node
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // Install a tap on the audio input to get real-time audio data for visualization
        inputNode.installTap(onBus: 0, bufferSize: audioBufferSize, format: inputFormat) { [weak self] (buffer, time) in
            // Process the buffer for visualization only
            self?.processAudioBufferForVisualization(buffer)
        }
        
        // Start the audio engine
        audioEngine.prepare()
        try? audioEngine.start()
    }
    
    private func setupChunkedAudioRecorder(sessionId: String) {
        // Create a unique filename for this chunk
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        chunkIndex = 0
        
        // Start the first chunk
        createNewChunk(baseURL: documentsPath, sessionId: sessionId)
        
        // Set up timer to create new chunks periodically
        audioChunkTimer = Timer.scheduledTimer(withTimeInterval: chunkDuration, repeats: true) { [weak self] _ in
            guard let self = self, self.isRecording else { return }
            
            // Stop current chunk
            self.audioRecorder?.stop()
            
            // Process the completed chunk
            if let recordingURL = self.recordingURL {
                self.sendAudioChunk(fileURL: recordingURL, sessionId: sessionId)
            }
            
            // Start a new chunk
            self.chunkIndex += 1
            self.createNewChunk(baseURL: documentsPath, sessionId: sessionId)
        }
    }
    
    private func createNewChunk(baseURL: URL, sessionId: String) {
        // Create a unique filename for this chunk
        recordingURL = baseURL.appendingPathComponent("chunk_\(chunkIndex)_\(Int(Date().timeIntervalSince1970)).m4a")
        
        do {
            if let url = recordingURL {
                audioRecorder = try AVAudioRecorder(url: url, settings: audioSettings)
                audioRecorder?.delegate = self
                audioRecorder?.record()
                print("Started recording chunk \(chunkIndex) to \(url.lastPathComponent)")
            }
        } catch {
            print("Error creating audio recorder: \(error)")
            errorMessage = "Error creating audio recorder: \(error.localizedDescription)"
        }
    }
    
    /// Process audio buffer for visualization
    /// Process audio buffer for visualization
    private func processAudioBufferForVisualization(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        
        let channelDataValue = channelData.pointee
        let channelDataValueArray = stride(from: 0, to: Int(buffer.frameLength), by: buffer.stride).map{ channelDataValue[$0] }
        
        // Calculate the RMS (root mean square) of the samples
        let rms = sqrt(channelDataValueArray.map{ $0 * $0 }.reduce(0, +) / Float(channelDataValueArray.count))
        
        // Convert to decibels with normalization
        var decibels = 20 * log10(rms)
        decibels = max(-80, min(decibels, 0)) // Clamp to realistic dB range
        
        // Normalize to 0-1 range
        let normalizedValue = (decibels + 80) / 80
        
        // Update the levels array
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Shift values to create a scrolling effect
            var newLevels = self.audioLevels
            newLevels.removeFirst()
            newLevels.append(normalizedValue)
            self.audioLevels = newLevels
        }
    }
    
    /// Send completed audio chunk to server
    private func sendAudioChunk(fileURL: URL, sessionId: String) {
        do {
            // Read the audio file data
            let audioData = try Data(contentsOf: fileURL)
            
            print("Sending audio chunk (\(audioData.count) bytes) to server for session \(sessionId)")
            
            // Send to server
            socket.emit("audio_chunk", [
                "sessionId": sessionId,
                "audio": audioData.base64EncodedString(),
                "chunkIndex": chunkIndex
            ])
            
            // Clean up the file after sending
            try? FileManager.default.removeItem(at: fileURL)
            
        } catch {
            print("Error reading audio file: \(error)")
            errorMessage = "Error reading audio file: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Debugging Helpers
    
    /// Tests the socket connection
    func testConnection(completion: ((Bool, String?) -> Void)? = nil) {
        SocketHelper.shared.testConnection { success, errorMessage in
            DispatchQueue.main.async {
                if success {
                    self.errorMessage = nil
                    print("Connection test successful")
                } else {
                    self.errorMessage = errorMessage ?? "Unknown connection error"
                }
                
                completion?(success, errorMessage)
            }
        }
    }
    
    // MARK: - Cleanup
    
    deinit {
        stopRecording()
        removeFirebaseListener()
        socket.disconnect()
    }
}

// MARK: - AVAudioRecorder Delegate
extension AudioService: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            print("Recording finished unsuccessfully")
        }
    }
    
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error = error {
            print("Recording error: \(error.localizedDescription)")
            errorMessage = "Recording error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Helper Models
struct TranscriptionEntry: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let timestamp: TimeInterval
    
    var date: Date {
        return Date(timeIntervalSince1970: timestamp)
    }
    
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    static func == (lhs: TranscriptionEntry, rhs: TranscriptionEntry) -> Bool {
        return lhs.id == rhs.id
    }
}
