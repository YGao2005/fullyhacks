//
//  AudioService.swift
//  fullyhacks
//
//  Created by Yang Gao on 4/13/25.
//

import Foundation
import SwiftUI
import AVFoundation
import SocketIO
import Firebase
import FirebaseFirestore
import Combine

class AudioService: NSObject, ObservableObject {
    // MARK: - Published Properties
    
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
    
    // MARK: - Private Properties
    
    // Socket connection
    private var socket: SocketIOClient
    
    // Audio recording components
    private var audioEngine: AVAudioEngine?
    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    
    // Configuration
    private let audioBufferSize: UInt32 = 4096
    
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
        
//        socket.on(clientEvent: .connectError) { [weak self] data, ack in
//            print("Socket connect error: \(data)")
//            DispatchQueue.main.async {
//                self?.errorMessage = "Connection error: \(data)"
//            }
//        }
        
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
    
    /// Fetches the latest transcription data from Firebase
    func fetchLatestTranscription(completion: @escaping (Result<[TranscriptionEntry], Error>) -> Void) {
        guard let sessionId = sessionId else {
            completion(.failure(NSError(domain: "AudioService",
                                      code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: "No active session"])))
            return
        }
        
        let docRef = db.collection("discussions").document(sessionId)
        
        docRef.getDocument { (document, error) in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let document = document, document.exists,
                  let data = document.data(),
                  let transcriptionData = data["transcription"] as? [[String: Any]] else {
                completion(.failure(NSError(domain: "AudioService",
                                          code: 2,
                                          userInfo: [NSLocalizedDescriptionKey: "No transcription data found"])))
                return
            }
            
            var entries: [TranscriptionEntry] = []
            
            for entryData in transcriptionData {
                if let text = entryData["text"] as? String,
                   let timestamp = entryData["timestamp"] as? TimeInterval {
                    let entry = TranscriptionEntry(text: text, timestamp: timestamp)
                    entries.append(entry)
                }
            }
            
            completion(.success(entries))
        }
    }
    
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
                self.startRecordingAudio()
            }
        } else {
            startRecordingAudio()
        }
    }
    
    /// Internal method to start the actual audio recording
    private func startRecordingAudio() {
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
                self.setupAudioRecording(sessionId: sessionId)
            }
        }
    }
    
    /// Stops recording audio
    func stopRecording() {
        if isRecording {
            // Stop audio engine
            audioEngine?.stop()
            audioEngine?.inputNode.removeTap(onBus: 0)
            audioEngine = nil
            
            // Stop recorder if used
            audioRecorder?.stop()
            audioRecorder = nil
            
            isRecording = false
            
            // Reset audio levels over time
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 1.0)) {
                    self.audioLevels = Array(repeating: 0, count: 100)
                }
            }
        }
    }
    
    /// Sets up audio recording components
    private func setupAudioRecording(sessionId: String) {
        do {
            // Set up audio session
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)
            
            // Create audio engine for processing
            audioEngine = AVAudioEngine()
            guard let audioEngine = audioEngine else {
                errorMessage = "Failed to create audio engine"
                return
            }
            
            // Get the input node
            let inputNode = audioEngine.inputNode
            
            // Get the native format of the input node
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
            
            // Install a tap on the audio input to get real-time audio data
            inputNode.installTap(onBus: 0, bufferSize: audioBufferSize, format: processingFormat) { [weak self] (buffer, time) in
                guard let self = self else { return }
                
                // Process the buffer for visualization
                self.processAudioBuffer(buffer)
                
                // Convert buffer to data and send to the server
                guard let audioData = self.pcmBufferToData(buffer: buffer) else {
                    return
                }
                
                // Send audio data to server
                self.socket.emit("audio_data", [
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
    
    /// Processes audio buffer to extract level data for visualization
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
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
    
    /// Converts PCM buffer to Data for sending over the network
    private func pcmBufferToData(buffer: AVAudioPCMBuffer) -> Data? {
        guard let channelData = buffer.floatChannelData?[0] else { return nil }
        let frameLength = Int(buffer.frameLength)
        
        var data = Data(capacity: frameLength * MemoryLayout<Float>.size)
        
        for i in 0..<frameLength {
            let sample = channelData[i]
            withUnsafeBytes(of: sample) { bytes in
                data.append(contentsOf: bytes)
            }
        }
        
        return data
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
