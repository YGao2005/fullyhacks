import Foundation
import SwiftUI
import AVFoundation
import SocketIO

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
    private var audioBufferSize: UInt32 = 4096 // Adjust based on your needs
    
    // Server URL - update this with your actual backend URL
    private let serverUrl = "http://localhost:8000" // Changed from 5000 to 8000 as seen in your Python code
    
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
            print("Socket connected")
            DispatchQueue.main.async {
                self?.isConnected = true
                self?.errorMessage = nil
            }
        }
        
        socket?.on(clientEvent: .disconnect) { [weak self] data, ack in
            print("Socket disconnected")
            DispatchQueue.main.async {
                self?.isConnected = false
            }
        }
        
        socket?.on("connection_response") { [weak self] data, ack in
            print("Connection response: \(data)")
        }
        
        socket?.on("session_started") { [weak self] data, ack in
            guard let dict = data[0] as? [String: Any],
                  let sessionId = dict["sessionId"] as? String else {
                return
            }
            print("Session started: \(sessionId)")
            DispatchQueue.main.async {
                self?.sessionId = sessionId
                self?.transcription = [] // Clear previous transcripts
            }
        }
        
        socket?.on("transcription") { [weak self] data, ack in
            guard let dict = data[0] as? [String: Any],
                  let text = dict["text"] as? String,
                  let timestamp = dict["timestamp"] as? TimeInterval else {
                return
            }
            
            print("Received transcription: \(text)")
            let entry = TranscriptionEntry(text: text, timestamp: timestamp)
            DispatchQueue.main.async {
                self?.transcription.append(entry)
            }
        }
        
        socket?.on("error") { [weak self] data, ack in
            guard let dict = data[0] as? [String: Any],
                  let message = dict["message"] as? String else {
                return
            }
            
            print("Received error: \(message)")
            DispatchQueue.main.async {
                self?.errorMessage = message
            }
        }
        
        // Connect to the socket
        socket?.connect()
    }
    
    // MARK: - Session Management
    
    func createNewSession(userId: String = "anonymous", sessionName: String? = nil) {
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
            return
        }
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.errorMessage = "Failed to create session: \(error.localizedDescription)"
                }
                return
            }
            
            // Check for HTTP errors
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                DispatchQueue.main.async {
                    self?.errorMessage = "Server returned error code: \(httpResponse.statusCode)"
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    self?.errorMessage = "No data received"
                }
                return
            }
            
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                
                if let sessionId = json?["sessionId"] as? String {
                    print("Created new session: \(sessionId)")
                    
                    DispatchQueue.main.async {
                        self?.sessionId = sessionId
                        self?.errorMessage = nil
                    }
                    
                    // Start the session via Socket.IO
                    self?.socket?.emit("start_session", ["sessionId": sessionId])
                } else {
                    DispatchQueue.main.async {
                        self?.errorMessage = "Invalid response format - missing sessionId"
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.errorMessage = "Failed to parse response: \(error.localizedDescription)"
                }
            }
        }.resume()
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
        
        // Emit end_session event
        socket?.emit("end_session", ["sessionId": sessionId])
        
        // Reset state
        self.sessionId = nil
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
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)
            
            audioEngine = AVAudioEngine()
            guard let audioEngine = audioEngine else {
                errorMessage = "Failed to create audio engine"
                return
            }
            
            let inputNode = audioEngine.inputNode
            
            // Configure audio format for better transcription quality
            // 16 kHz mono is ideal for speech recognition
            let recordingFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16000,
                channels: 1,
                interleaved: false
            )
            
            // Install a tap on the audio input
            inputNode.installTap(onBus: 0, bufferSize: audioBufferSize, format: recordingFormat) { [weak self] (buffer, time) in
                // Convert buffer to data and send to the server
                guard let audioData = self?.pcmBufferToData(buffer: buffer) else {
                    return
                }
                
                // Send audio data to server
                self?.socket?.emit("audio_data", [
                    "sessionId": sessionId,
                    "audio": audioData
                ])
            }
            
            // Start the audio engine
            audioEngine.prepare()
            try audioEngine.start()
            
            isRecording = true
            
        } catch {
            errorMessage = "Error setting up audio: \(error.localizedDescription)"
        }
    }
    
    func stopRecording() {
        // Stop the audio engine if it's running
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        isRecording = false
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
    
    deinit {
        stopRecording()
        socket?.disconnect()
    }
}
