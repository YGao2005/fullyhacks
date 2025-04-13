import SwiftUI
import AVFoundation

class AudioManager: NSObject, ObservableObject {
    @Published var audioLevels: [Float] = Array(repeating: 0, count: 100)
    @Published var isRecording = false
    
    private var audioEngine: AVAudioEngine?
    private var audioLevelTimer: Timer?
    
    override init() {
        super.init()
    }
    
    // Start recording from the microphone
    func startRecording() {
        checkPermissionAndRecord()
    }
    
    // Stop recording
    func stopRecording() {
        if isRecording {
            audioEngine?.stop()
            audioEngine?.inputNode.removeTap(onBus: 0)
            audioEngine = nil
            isRecording = false
            
            // Reset audio levels
            audioLevels = Array(repeating: 0, count: 100)
        }
    }
    
    // Check for microphone permission and start recording
    private func checkPermissionAndRecord() {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            startAudioMonitoring()
        case .denied:
            print("Microphone access denied")
        case .undetermined:
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                if granted {
                    DispatchQueue.main.async {
                        self?.startAudioMonitoring()
                    }
                } else {
                    print("Microphone permission denied")
                }
            }
        @unknown default:
            print("Unknown microphone permission status")
        }
    }
    
    // Start monitoring audio levels
    private func startAudioMonitoring() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)
            
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
            try audioEngine.start()
            isRecording = true
            print("Audio monitoring started successfully")
            
        } catch {
            print("Failed to start audio monitoring: \(error.localizedDescription)")
        }
    }
    
    // Process the audio buffer to extract levels for visualization
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
    
    deinit {
        stopRecording()
    }
}
