import Foundation
import SwiftUI
import AVFoundation
import SocketIO
import Firebase
import FirebaseFirestore

class AudioTranscriptionService: ObservableObject {
    // Published properties for UI updates
    @Published var isConnected = false
    @Published var isRecording = false
    @Published var transcription: [TranscriptionEntry] = []
    @Published var sessionId: String?
    @Published var errorMessage: String?
    
    // Socket.IO manager
    private var manager: SocketManager?
    private var socket: SocketIOClient?
    
    // Audio engine components
    private var audioEngine: AVAudioEngine?
    private var audioBufferSize: UInt32 = 4096
    
    // Firebase reference
    private let db = Firestore.firestore()
    
    // Server URL - your Heroku URL
    private let serverUrl = "https://fullyhacks-dd63ad42c7dd.herokuapp.com"
    
    // Flag to track if session has been properly started
    private var isSessionStarted = false
    
    init() {
        setupSocketIO()
    }
    
    // MARK: - Socket.IO Setup
    
    private func setupSocketIO() {
        // Configure Socket.IO manager with proper options
        manager = SocketManager(socketURL: URL(string: serverUrl)!, config: [
            .log(true),
            .compress,
            .reconnects(true),
            .reconnectAttempts(5),
            .reconnectWait(3000)
        ])
        
        socket = manager?.defaultSocket
        
        // Setup event listeners
        socket?.on(clientEvent: .connect) { [weak self] data, ack in
            print("Socket connected successfully")
            DispatchQueue.main.async {
                self?.isConnected = true
                self?.errorMessage = nil
                
                // If we already have a session ID, start the session now that we're connected
                if let sessionId = self?.sessionId, !(self?.isSessionStarted ?? false) {
                    self?.startSession(sessionId: sessionId)
                }
            }
        }
        
        socket?.on(clientEvent: .disconnect) { [weak self] data, ack in
            print("Socket disconnected")
            DispatchQueue.main.async {
                self?.isConnected = false
                self?.isSessionStarted = false // Reset session started flag
            }
        }
        
        socket?.on("connection_response") { [weak self] data, ack in
            print("Connection response: \(data)")
        }
        
        socket?.on("session_started") { [weak self] data, ack in
            guard let dict = data[0] as? [String: Any],
                  let sessionId = dict["sessionId"] as? String else {
                print("Invalid session_started data format: \(data)")
                return
            }
            print("Session started successfully: \(sessionId)")
            DispatchQueue.main.async {
                self?.isSessionStarted = true
                self?.errorMessage = nil
            }
        }
        
        socket?.on("transcription") { [weak self] data, ack in
            print("Received transcription data: \(data)")
            guard let dict = data[0] as? [String: Any],
                  let text = dict["text"] as? String else {
                print("Invalid transcription data format: \(data)")
                return
            }
            
            // Get timestamp (default to current time if missing)
            let timestamp = (dict["timestamp"] as? TimeInterval) ?? Date().timeIntervalSince1970
            
            print("Received transcription: \(text)")
            let entry = TranscriptionEntry(text: text, timestamp: timestamp)
            DispatchQueue.main.async {
                self?.transcription.append(entry)
            }
        }
        
        socket?.on("error") { [weak self] data, ack in
            guard let dict = data[0] as? [String: Any],
                  let message = dict["message"] as? String else {
                print("Invalid error data format: \(data)")
                return
            }
            
            print("Received error: \(message)")
            DispatchQueue.main.async {
                self?.errorMessage = message
                
                // If the error is about an invalid session, reset the session state
                if message.contains("Invalid session ID") {
                    self?.isSessionStarted = false
                }
            }
        }
        
        // Connect to the socket
        socket?.connect()
    }
    
    // MARK: - Session Management
    
    // Create a new session via REST API
    func createNewSession(userId: String = "anonymous", sessionName: String? = nil, completion: (() -> Void)? = nil) {
        let name = sessionName ?? "Session \(Date())"
        
        // Create a URLSession for the API call
        let url = URL(string: "\(serverUrl)/api/discussions/create")!
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
                print("Session creation HTTP status: \(httpResponse.statusCode)")
                
                // Check if the status is not successful
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
            
            // Log the raw response
            if let responseString = String(data: data, encoding: .utf8) {
                print("Session creation response: \(responseString)")
            }
            
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                
                guard let sessionId = json?["sessionId"] as? String,
                      let status = json?["status"] as? String,
                      status == "success" else {
                    DispatchQueue.main.async {
                        self?.errorMessage = "Invalid response format or unsuccessful status"
                        completion?()
                    }
                    return
                }
                
                print("Created new session: \(sessionId)")
                
                DispatchQueue.main.async {
                    self?.sessionId = sessionId
                    self?.errorMessage = nil
                    
                    // Start the session if we're already connected
                    if self?.isConnected == true {
                        self?.startSession(sessionId: sessionId)
                    }
                    
                    completion?()
                }
            } catch {
                DispatchQueue.main.async {
                    self?.errorMessage = "Failed to parse response: \(error.localizedDescription)"
                    completion?()
                }
            }
        }.resume()
    }
    
    // Start a session with Socket.IO
    private func startSession(sessionId: String) {
        print("Starting session with ID: \(sessionId)")
        
        // Start the session via Socket.IO
        socket?.emit("start_session", ["sessionId": sessionId])
        DispatchQueue.main.async {
            self.isSessionStarted = true
        }
    }
    
    func endSession() {
        guard let sessionId = sessionId else {
            errorMessage = "No active session"
            return
        }
        
        // Stop recording if it's active
        if isRecording {
            stopRecording()
        }
        
        print("Ending session: \(sessionId)")
        
        // Emit end_session event
        socket?.emit("end_session", ["sessionId": sessionId])
        
        // Reset state
        self.sessionId = nil
        self.isSessionStarted = false
        self.transcription = []
    }
    
    // MARK: - Audio Recording and Streaming
    
    func startRecording() {
        guard let sessionId = sessionId else {
            errorMessage = "No active session. Please create a session first."
            return
        }
        
        guard isConnected else {
            errorMessage = "Not connected to server. Please try again."
            return
        }
        
        // Make sure the session is started before recording
        if !isSessionStarted {
            print("Session not started yet, starting it now")
            startSession(sessionId: sessionId)
            
            // Give a short delay to ensure session is started
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.setupAudioRecording(sessionId: sessionId)
            }
            return
        }
        
        print("Starting recording for session: \(sessionId)")
        
        // Check microphone permission
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            guard granted else {
                DispatchQueue.main.async {
                    self?.errorMessage = "Microphone permission denied"
                }
                return
            }
            
            DispatchQueue.main.async {
                self?.setupAudioRecording(sessionId: sessionId)
            }
        }
    }
    
    private func setupAudioRecording(sessionId: String) {
        do {
            // Set up audio session
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)
            
            // Create audio engine
            audioEngine = AVAudioEngine()
            guard let audioEngine = audioEngine else {
                errorMessage = "Failed to create audio engine"
                return
            }
            
            // Get the input node
            let inputNode = audioEngine.inputNode
            
            // Important: Get the native format of the input node first
            let nativeInputFormat = inputNode.inputFormat(forBus: 0)
            print("Native input format: \(nativeInputFormat)")
            
            // Use the native sample rate but convert to single channel if needed
            let processingFormat: AVAudioFormat
            if nativeInputFormat.channelCount > 1 {
                // Create a new format with the same sample rate but just 1 channel
                processingFormat = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: nativeInputFormat.sampleRate,
                    channels: 1,
                    interleaved: false
                )!
                print("Converting to mono format: \(processingFormat)")
            } else {
                // Use the native format directly
                processingFormat = nativeInputFormat
            }
            
            // Install a tap on the audio input
            inputNode.installTap(onBus: 0, bufferSize: audioBufferSize, format: processingFormat) { [weak self] (buffer, time) in
                // Convert buffer to data and send to the server
                guard let audioData = self?.pcmBufferToData(buffer: buffer),
                      let sessionId = self?.sessionId,
                      let isStarted = self?.isSessionStarted, isStarted else {
                    return
                }
                
                // Check that we still have a valid session and connection
                guard let self = self, self.isConnected else {
                    return
                }
                
                // Send audio data to server
                self.socket?.emit("audio_data", [
                    "sessionId": sessionId,
                    "audio": audioData
                ])
            }
            
            // Start the audio engine
            audioEngine.prepare()
            try audioEngine.start()
            print("Audio engine started successfully")
            
            isRecording = true
            
        } catch {
            errorMessage = "Error setting up audio: \(error.localizedDescription)"
            print("Audio setup error: \(error)")
        }
    }
    
    func stopRecording() {
        // Stop the audio engine if it's running
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        isRecording = false
        print("Recording stopped")
    }
    
    // Helper method to convert PCM buffer to Data
    private func pcmBufferToData(buffer: AVAudioPCMBuffer) -> Data {
        let channelData = buffer.floatChannelData?[0]
        let frameLength = Int(buffer.frameLength)
        
        var data = Data(capacity: frameLength * MemoryLayout<Float>.size)
        
        for i in 0..<frameLength {
            let sample = channelData?[i] ?? 0
            withUnsafeBytes(of: sample) { bytes in
                data.append(contentsOf: bytes)
            }
        }
        
        return data
    }
    
    // Test the server connection
    func testServerConnection() {
        guard let url = URL(string: "\(serverUrl)/health") else {
            print("Invalid URL")
            return
        }
        
        print("Testing connection to: \(url.absoluteString)")
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Connection test failed: \(error.localizedDescription)")
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("Connection test status code: \(httpResponse.statusCode)")
            }
            
            if let data = data, let message = String(data: data, encoding: .utf8) {
                print("Connection test response: \(message)")
            }
        }.resume()
    }
    
    deinit {
        stopRecording()
        socket?.disconnect()
    }
}
