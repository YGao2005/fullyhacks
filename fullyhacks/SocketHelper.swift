import Foundation
import SocketIO

class SocketHelper {
    // MARK: - Shared Instance
    static let shared = SocketHelper()
    
    // MARK: - Configuration
    #if targetEnvironment(simulator)
    private let serverHost = "192.168.1.166:5555"
    #else
    // Use your actual computer's IP address when running on a device
    //private let serverHost = "192.168.1.166:5555"
    private let serverHost = "fullyhacks-dd63ad42c7dd.herokuapp.com"
    #endif
    
    private let serverPort = 5555
    
    // Full server URL constructed from host and port
    var serverURL: URL {
        return URL(string: "https://\(serverHost)")!
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
            .reconnectAttempts(5),
            .reconnectWait(3000),
            .forceWebsockets(true),       // Force WebSockets instead of polling
            .connectParams(["transport": "websocket"]),
            .extraHeaders(["Accept": "application/json"]),
            .selfSigned(true),            // Allow self-signed certificates
            .secure(true)                 // Use secure connection
        ])
        
        return manager
    }
    
    // MARK: - Connection Testing
    func testConnection(completion: @escaping (Bool, String?) -> Void) {
        let testSocket = manager.defaultSocket
        
        // Set up connection handlers
        testSocket.on(clientEvent: .connect) { _, _ in
            print("✅ Socket test connection successful")
            testSocket.disconnect()
            completion(true, nil)
        }
        
        testSocket.on(clientEvent: .error) { data, _ in
            print("❌ Socket test connection error: \(data)")
            let errorMessage = "Connection error: \(data)"
            completion(false, errorMessage)
        }
        
        // Set a timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if testSocket.status != .connected {
                testSocket.disconnect()
                completion(false, "Connection timeout after 5 seconds")
            }
        }
        
        // Connect
        testSocket.connect()
    }
}
