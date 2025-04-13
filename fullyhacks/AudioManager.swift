import SwiftUI
import AVFoundation
import SocketIO
import Combine

class AudioManager: NSObject, ObservableObject {
    @Published var audioLevels: [Float] = Array(repeating: 0, count: 100)
    @Published var isRecording = false
    @Published var transcription: String = ""
    @Published var isConnected = false
    
    private var audioEngine: AVAudioEngine?
    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var socketManager: SocketManager?
    private var socket: SocketIOClient?
    private var discussionID: String?
    private var audioChunkTimer: Timer?
    
    // Server configuration
    private let serverURL = "http://localhost:8080" // Update with your actual server URL
    
    // Audio settings
    private let audioSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 44100,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
    ]
    
    override init() {
        super.init()
        setupSocket()
    }
    
    // MARK: - Socket Setup
    
    private func setupSocket() {
        socketManager = SocketManager(socketURL: URL(string: serverURL)!, config: [.log(true)])
        socket = socketManager?.defaultSocket
        
        // Set up socket event handlers
        socket?.on(clientEvent: .connect) { [weak self] data, ack in
            print("Socket connected")
            self?.isConnected = true
        }
        
        socket?.on(clientEvent: .disconnect) { [weak self] data, ack in
            print("Socket disconnected")
            self?.isConnected = false
        }
        
        socket?.on("transcript_update") { [weak self] data, ack in
            guard let self = self, let dataArray = data as? [[String: Any]], let first = dataArray.first else { return }
            
            if let transcriptText = first["text"] as? String {
                DispatchQueue.main.async {
                    self.transcription = transcriptText
                    print("Received transcript: \(transcriptText)")
                }
            }
        }
        
        socket?.on("error") { data, ack in
            if let dataArray = data as? [[String: Any]], let first = dataArray.first, let message = first["message"] as? String {
                print("Socket error: \(message)")
            }
        }
        
        // Connect to socket
        socket?.connect()
    }
    
    // MARK: - Discussion Management
    
    /// Create a new discussion and joins the discussion room
    func createDiscussion(title: String = "New Discussion", completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: "\(serverURL)/api/discussions") else {
            completion(.failure(NSError(domain: "AudioManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        let parameters: [String: Any] = ["title": title]
        let jsonData = try? JSONSerialization.data(withJSONObject: parameters)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "AudioManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                }
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let discussionID = json["discussion_id"] as? String {
                    DispatchQueue.main.async {
                        self.discussionID = discussionID
                        self.joinDiscussion(discussionID)
                        completion(.success(discussionID))
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "AudioManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }.resume()
    }
    
    /// Join an existing discussion room via socket
    func joinDiscussion(_ discussionID: String) {
        self.discussionID = discussionID
        socket?.emit("join_discussion", ["discussion_id": discussionID])
    }
    
    // MARK: - Audio Recording
    
    /// Start recording from the microphone
    func startRecording() {
        // Create a new discussion if none exists
        if discussionID == nil {
            createDiscussion { result in
                switch result {
                case .success(let id):
                    print("Created discussion with ID: \(id)")
                    self.checkPermissionAndRecord()
                case .failure(let error):
                    print("Failed to create discussion: \(error.localizedDescription)")
                }
            }
        } else {
            checkPermissionAndRecord()
        }
    }
    
    /// Stop recording
    func stopRecording() {
        if isRecording {
            // Stop audio engine
            audioEngine?.stop()
            audioEngine?.inputNode.removeTap(onBus: 0)
            audioEngine = nil
            
            // If using AVAudioRecorder
            audioRecorder?.stop()
            
            // Cancel timer
            audioChunkTimer?.invalidate()
            audioChunkTimer = nil
            
            // Send final audio chunk if available
            if let recordingURL = recordingURL, let discussionID = discussionID {
                sendAudioToServer(fileURL: recordingURL, discussionID: discussionID)
            }
            
            isRecording = false
            
            // Reset audio levels
            audioLevels = Array(repeating: 0, count: 100)
        }
    }
    
    // MARK: - Permission and Recording Setup
    
    private func checkPermissionAndRecord() {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            setupAudioRecording()
        case .denied:
            print("Microphone access denied")
        case .undetermined:
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                if granted {
                    DispatchQueue.main.async {
                        self?.setupAudioRecording()
                    }
                } else {
                    print("Microphone permission denied")
                }
            }
        @unknown default:
            print("Unknown microphone permission status")
        }
    }
    
    private func setupAudioRecording() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)
            
            // Two approaches: Using audio engine for monitoring levels and recorder for file
            
            // Setup AVAudioRecorder for recording to file
            setupAudioRecorder()
            
            // Setup AVAudioEngine for real-time monitoring
            setupAudioEngine()
            
            // Setup timer to send audio chunks periodically
            setupAudioChunkTimer()
            
            isRecording = true
            
        } catch {
            print("Failed to set up recording: \(error.localizedDescription)")
        }
    }
    
    private func setupAudioRecorder() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        recordingURL = documentsPath.appendingPathComponent("recording.m4a")
        
        do {
            if let url = recordingURL {
                audioRecorder = try AVAudioRecorder(url: url, settings: audioSettings)
                audioRecorder?.delegate = self
                audioRecorder?.prepareToRecord()
                audioRecorder?.record()
            }
        } catch {
            print("Could not start audio recorder: \(error.localizedDescription)")
        }
    }
    
    private func setupAudioEngine() {
        // Create a new audio engine each time
        audioEngine = AVAudioEngine()
        
        guard let audioEngine = audioEngine else { return }
        let inputNode = audioEngine.inputNode
        
        // Get the native format of the input node
        let inputFormat = inputNode.inputFormat(forBus: 0)
        print("Using input format: \(inputFormat)")
        
        // Install a tap on the audio input to get real-time audio data
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] (buffer, time) in
            guard let self = self else { return }
            
            // Process the buffer to get audio levels
            self.processAudioBuffer(buffer)
        }
        
        // Prepare and start the audio engine
        do {
            try audioEngine.start()
            print("Audio engine started successfully")
        } catch {
            print("Failed to start audio engine: \(error.localizedDescription)")
        }
    }
    
    private func setupAudioChunkTimer() {
        // Send audio chunks every 3 seconds
        audioChunkTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self = self,
                  let url = self.recordingURL,
                  let discussionID = self.discussionID else { return }
            
            // Temporarily stop recording to access the file
            self.audioRecorder?.pause()
            
            // Send current audio chunk
            self.sendAudioToServer(fileURL: url, discussionID: discussionID)
            
            // Resume recording
            self.audioRecorder?.record()
        }
    }
    
    // MARK: - Audio Processing
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        
        let channelDataValue = channelData.pointee
        let channelDataValueArray = stride(from: 0, to: Int(buffer.frameLength), by: buffer.stride).map{ channelDataValue[$0] }
        
        // Calculate the RMS (root mean square) of the samples which represents the power
        let rms = sqrt(channelDataValueArray.map{ $0 * $0 }.reduce(0, +) / Float(channelDataValueArray.count))
        
        // Convert to decibels with normalization, and clamp to 0-1 range for visualization
        var decibels = 20 * log10(rms)
        decibels = max(-80, min(decibels, 0)) // Clamp to realistic dB range
        
        // Normalize to 0-1 range
        let normalizedValue = (decibels + 80) / 80
        
        // Update the levels array with smoothing
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Shift values to create a scrolling effect
            var newLevels = self.audioLevels
            newLevels.removeFirst()
            newLevels.append(normalizedValue)
            self.audioLevels = newLevels
        }
    }
    
    // MARK: - Server Communication
    
    /// Send audio data to server using Socket.IO
    private func sendAudioChunkViaSocket(data: Data, discussionID: String) {
        let base64Audio = data.base64EncodedString()
        
        // Emit audio_chunk event with audio data
        socket?.emit("audio_chunk", [
            "discussion_id": discussionID,
            "audio": base64Audio
        ])
        
        print("Sent audio chunk via Socket.IO: \(data.count) bytes")
    }
    
    /// Send audio data to server using HTTP POST
    private func sendAudioChunkViaHTTP(data: Data, discussionID: String) {
        guard let url = URL(string: "\(serverURL)/api/audio") else {
            print("Invalid server URL")
            return
        }
        
        // Create request parameters
        let parameters: [String: Any] = [
            "discussion_id": discussionID,
            "audio": data.base64EncodedString()
        ]
        
        let jsonData = try? JSONSerialization.data(withJSONObject: parameters)
        
        // Create the request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Send the request
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error sending audio via HTTP: \(error.localizedDescription)")
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                print("HTTP Error: \(httpResponse.statusCode)")
                return
            }
            
            print("Successfully sent audio via HTTP")
        }.resume()
    }
    
    /// Read audio file and send to server
    private func sendAudioToServer(fileURL: URL, discussionID: String) {
        do {
            let audioData = try Data(contentsOf: fileURL)
            
            // Choose one method based on your preference
            if isConnected {
                // Socket.IO method (better for real-time)
                sendAudioChunkViaSocket(data: audioData, discussionID: discussionID)
            } else {
                // HTTP method (fallback)
                sendAudioChunkViaHTTP(data: audioData, discussionID: discussionID)
            }
        } catch {
            print("Error reading audio file: \(error.localizedDescription)")
        }
    }
    
    deinit {
        stopRecording()
        socket?.disconnect()
    }
}

// MARK: - AVAudioRecorder Delegate
extension AudioManager: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            print("Recording finished unsuccessfully")
        }
    }
    
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error = error {
            print("Recording error: \(error.localizedDescription)")
        }
    }
}
