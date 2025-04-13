import Foundation
import SocketIO

class SocketHelper {
    // MARK: - Shared Instance
    static let shared = SocketHelper()
    
    // MARK: - Configuration
    #if targetEnvironment(simulator)
    private let serverHost = "localhost"
    #else
    // Change this to your actual server IP or hostname when running on a device
    private let serverHost = "172.20.10.14:5555"
    #endif
    
    private let serverPort = 5555
    
    // Full server URL constructed from host and port
    var serverURL: URL {
        #if targetEnvironment(simulator)
        return URL(string: "http://\(serverHost):\(serverPort)")!
        #else
        return URL(string: "http://\(serverHost)")!
        #endif
    }
    
    // MARK: - Socket Manager
    private var _manager: SocketManager?
    
    var manager: SocketManager {
        if _manager == nil {
            _manager = createSocketManager()
        }
        return _manager!
    }
    
    // Default socket with consistent configuration
    var socket: SocketIOClient {
        return manager.defaultSocket
    }
    
    // MARK: - Socket Configuration
    private func createSocketManager() -> SocketManager {
        let manager = SocketManager(socketURL: serverURL, config: [
            .log(true),
            .compress,
            .reconnects(true),
            .reconnectAttempts(10),
            .reconnectWait(2000),
            .connectParams(["transport": "polling"]), // Start with polling, more reliable initially
            .extraHeaders(["Accept": "application/json"]),
            .selfSigned(true),            // Allow self-signed certificates for development
            //.secure(true)                 // Use secure connection
        ])
        
        return manager
    }
    
    // MARK: - Connection Testing
    func testConnection(completion: @escaping (Bool, String?) -> Void) {
        // Test via a health check endpoint rather than socket
        let url = serverURL.appendingPathComponent("/health")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Health check failed: \(error)")
                completion(false, "Connection error: \(error.localizedDescription)")
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200,
               let data = data,
               let responseString = String(data: data, encoding: .utf8) {
                print("✅ Health check successful: \(responseString)")
                
                // If health check passes, also try connecting the socket
                let socket = self.manager.defaultSocket
                
                socket.on(clientEvent: .connect) { _, _ in
                    print("✅ Socket connection successful")
                    socket.disconnect()
                    completion(true, nil)
                }
                
                socket.on(clientEvent: .error) { data, _ in
                    print("⚠️ Socket connection warning: \(data)")
                    // Continue anyway if health check succeeded
                    completion(true, "Server is reachable but socket had issues: \(data)")
                }
                
                // Set a short timeout
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    socket.disconnect()
                    // Even if socket times out, if health check passed, we're good
                    completion(true, "Server is reachable but socket connection timed out")
                }
                
                socket.connect()
            } else {
                print("❌ Health check failed with unexpected response")
                completion(false, "Server returned unexpected response")
            }
        }
        
        task.resume()
    }
    
    // Function to reconnect socket if needed
    func ensureConnection() {
        if socket.status != .connected {
            print("Socket not connected, reconnecting...")
            socket.connect()
        }
    }
}
