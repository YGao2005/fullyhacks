import SwiftUI

struct TranscriptionView: View {
    @StateObject private var audioService = AudioTranscriptionService()
    @State private var sessionName: String = ""
    
    var body: some View {
        VStack {
            // Connection status and error messages
            HStack {
                Circle()
                    .fill(audioService.isConnected ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                
                Text(audioService.isConnected ? "Connected" : "Disconnected")
                    .font(.caption)
                    .foregroundColor(audioService.isConnected ? .green : .red)
                
                Spacer()
            }
            .padding(.horizontal)
            
            if let error = audioService.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
            
            // Session controls
            if audioService.sessionId == nil {
                // Create session UI
                VStack(spacing: 20) {
                    TextField("Session Name", text: $sessionName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding(.horizontal)
                    
                    Button(action: {
                        audioService.createNewSession(sessionName: sessionName.isEmpty ? nil : sessionName)
                    }) {
                        Text("Start New Discussion")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                }
                .padding()
            } else {
                // Active session UI
                VStack {
                    Text("Session ID: \(audioService.sessionId ?? "")")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Spacer()
                    
                    // Transcription list
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(audioService.transcription) { entry in
                                TranscriptionBubble(entry: entry)
                            }
                        }
                        .padding()
                    }
                    
                    Spacer()
                    
                    // Recording control
                    HStack {
                        Spacer()
                        
                        Button(action: {
                            if audioService.isRecording {
                                audioService.stopRecording()
                            } else {
                                audioService.startRecording()
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(audioService.isRecording ? Color.red : Color.blue)
                                    .frame(width: 70, height: 70)
                                    .shadow(radius: 5)
                                
                                if audioService.isRecording {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.white)
                                        .frame(width: 20, height: 20)
                                } else {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 30, height: 30)
                                }
                            }
                        }
                        
                        Spacer()
                    }
                    .padding()
                    
                    // End session button
                    Button(action: {
                        audioService.endSession()
                    }) {
                        Text("End Discussion")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.red)
                            .cornerRadius(10)
                    }
                    .padding(.bottom)
                }
            }
        }
        .navigationTitle("HarmonAI")
    }
}

// Helper view for transcription bubbles
struct TranscriptionBubble: View {
    let entry: TranscriptionEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.text)
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(10)
            
            Text(formattedTime)
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
    
    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: entry.date)
    }
}

struct TranscriptionView_Previews: PreviewProvider {
    static var previews: some View {
        TranscriptionView()
    }
}
