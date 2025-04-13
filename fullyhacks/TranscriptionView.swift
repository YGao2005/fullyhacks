//
//  TranscriptionView.swift
//  fullyhacks
//
//  Created by Yang Gao on 4/13/25.
//

import SwiftUI
import Firebase
import FirebaseFirestore

struct TranscriptionView: View {
    var sessionId: String
    
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var viewModel = TranscriptionViewModel()
    
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
                    
                    Spacer()
                    
                    Text("Discussion")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button(action: {
                        // Share or export option
                    }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 18, weight: .bold))
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
                        
                        Text(viewModel.dateFormatter.string(from: viewModel.startTime ?? Date()))
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                
                // Transcription content
                ScrollView {
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
                            }
                            .padding(.horizontal, 16)
                            
                            // Add some space at the bottom for better scrolling
                            Color.clear.frame(height: 40)
                        }
                    }
                    .padding(.top, 12)
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
                        // Audio playback controls could go here
                    }) {
                        Image(systemName: "play.fill")
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
                        // Create summary based on transcription
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
            viewModel.loadTranscription(sessionId: sessionId)
        }
    }
}

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
    
    let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    func loadTranscription(sessionId: String) {
        guard !sessionId.isEmpty else {
            isLoading = false
            return
        }
        
        let db = Firestore.firestore()
        let docRef = db.collection("discussions").document(sessionId)
        
        docRef.getDocument { [weak self] (document, error) in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    print("Error getting document: \(error)")
                    return
                }
                
                guard let document = document, document.exists,
                      let data = document.data() else {
                    print("Document does not exist")
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
                if let transcriptionData = data["transcription"] as? [[String: Any]] {
                    var entries: [TranscriptionEntry] = []
                    
                    for entryData in transcriptionData {
                        if let text = entryData["text"] as? String,
                           let timestamp = entryData["timestamp"] as? Double {
                            let entry = TranscriptionEntry(
                                text: text,
                                timestamp: timestamp
                            )
                            entries.append(entry)
                        }
                    }
                    
                    // Sort by timestamp
                    self.transcriptionEntries = entries.sorted(by: { $0.timestamp < $1.timestamp })
                }
            }
        }
        
        // Also set up a listener for real-time updates
        docRef.addSnapshotListener { [weak self] (documentSnapshot, error) in
            guard let self = self,
                  let document = documentSnapshot,
                  let data = document.data(),
                  let transcriptionData = data["transcription"] as? [[String: Any]] else {
                return
            }
            
            var entries: [TranscriptionEntry] = []
            
            for entryData in transcriptionData {
                if let text = entryData["text"] as? String,
                   let timestamp = entryData["timestamp"] as? Double {
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
}

// Helper extension for rounded corners
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

// Extended TranscriptionEntry model with formatted time
struct TranscriptionEntry: Identifiable {
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
}
