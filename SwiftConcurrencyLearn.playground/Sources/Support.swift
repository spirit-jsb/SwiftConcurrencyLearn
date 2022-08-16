import Foundation

public func example(_ description: String, action: () -> Void) {
  print("#### \(description) ####")
  
  action()
}

public func asyncExample(_ description: String, action: @escaping @Sendable () async throws -> Void) {
  print("#### \(description) ####")
  
  Task {
    try await action()
  }
}
