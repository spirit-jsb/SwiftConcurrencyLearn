import Foundation
import UIKit

/// synchronous appending value to string
var results: [String] = []

func addAppending(_ value: String, to string: String) {
  results.append(value.appending(string))
}

/// synchronous load signature from remote (blocking actions)
func loadSignature() throws -> String? {
  // 从网络读取一个字符串
  let data = try Data(contentsOf: URL(string: "https://httpbin.org/base64/swift-concurrency-learn")!)
  return String(data: data, encoding: .utf8)
}

/// asynchronous load signature from remote
func asyncLoadSignatureUsingClosure(_ completion: @escaping (String?, Error?) -> Void) {
  DispatchQueue.global().async {
    do {
      let data = try Data(contentsOf: URL(string: "https://httpbin.org/base64/swift-concurrency-learn")!)
      DispatchQueue.main.async {
        completion(String(data: data, encoding: .utf8), nil)
      }
    }
    catch {
      DispatchQueue.main.async {
        completion(nil, error)
      }
    }
  }
}

/// synchronous serial actions
if let signature = try? loadSignature() {
  addAppending(signature, to: "some data")
}

print("synchronous serial actions results: \n\(results)\n")

/// asynchronous serial actions
func asyncLoadFromDatabaseUsingClosure(_ completion: @escaping ([String]?, Error?) -> Void) {
  DispatchQueue.global().async {
    sleep(2)
    
    DispatchQueue.main.async {
      completion(["some data"], nil)
    }
  }
}

asyncLoadFromDatabaseUsingClosure { (strings, error) in
  if let strings = strings {
    asyncLoadSignatureUsingClosure { (signature, error) in
      if let signature = signature {
        strings.forEach {
          addAppending(signature, to: $0)
        }
        
        print("asynchronous serial actions results: \n\(results)\n")
      }
      else {
        print("Error\n")
      }
    }
  }
  else {
    print("Error\n")
  }
}

/// using async function to load signature from remote
func asyncLoadSignatureUsingAsyncFunction() async throws -> String? {
  let (data, _) = try await URLSession.shared.data(from: URL(string: "https://httpbin.org/base64/swift-concurrency-learn")!)
  return String(data: data, encoding: .utf8)
}

/// using async function to asynchronous serial actions
func asyncLoadFromDatabaseUsingAsyncFunction() async throws -> [String]? {
  try await Task.sleep(nanoseconds: 2 * NSEC_PER_SEC)
  return ["data1^sig", "data2^sig", "data3^sig"]
}

Task {
  if let strings = try await asyncLoadFromDatabaseUsingAsyncFunction() {
    if let signature = try await asyncLoadSignatureUsingAsyncFunction() {
      strings.forEach {
        addAppending(signature, to: $0)
      }
      
      print("using async function to asynchronous serial actions results: \n\(results)\n")
    }
  }
}

/// task function
func asyncProcessFromScratchUsingAsyncFunction() async throws {
  if let strings = try await asyncLoadFromDatabaseUsingAsyncFunction() {
    if let signature = try await asyncLoadSignatureUsingAsyncFunction() {
      strings.forEach {
        addAppending(signature, to: $0)
      }
    }
  }
}

Task {
  try await asyncProcessFromScratchUsingAsyncFunction()
}

print("task function results: \n\(results)\n")

/// structured concurrency
#warning("Playground can’t testing structured concurrency code")
//func asyncProcessFromScratchUsingAsyncBinding() async throws {
//  async let loadStrings = asyncLoadFromDatabaseUsingAsyncFunction()
//  async let loadSignature = asyncLoadSignatureUsingAsyncFunction()
//
//  if let strings = try await loadStrings {
//    if let signature = try await loadSignature {
//      strings.forEach {
//        addAppending(signature, to: $0)
//      }
//    }
//  }
//}

func asyncProcessFromScratchUsingTaskGroup() async throws {
  Task {
    await withThrowingTaskGroup(of: Void.self) { (group) in
      group.addTask {
        let loadStrings = try await asyncLoadFromDatabaseUsingAsyncFunction()
        let loadSignature = try await asyncLoadSignatureUsingAsyncFunction()
        
        if let strings = loadStrings {
          if let signature = loadSignature {
            strings.forEach {
              addAppending(signature, to: $0)
            }
          }
        }
      }
    }
  }
}

Task {
  //  try await asyncProcessFromScratchUsingAsyncBinding()
  try await asyncProcessFromScratchUsingTaskGroup()
}

print("structured concurrency results: \n\(results)\n")

/// structured concurrency
func asyncLoadResultRemotelyUsingAsyncFunction() async throws {
  try await Task.sleep(nanoseconds: 2 * NSEC_PER_SEC)
  results = ["data1^sig", "data2^sig", "data3^sig"]
}

func someSyncMethod() {
  Task {
    await withThrowingTaskGroup(of: Void.self) { (group) in
      /// * group 满足 AsyncSequence 协议，可以使用 for await 的方式用类似同步循环的写法来访问异步操作的结果
      /// * 通过调用 groud 的 cancelAll，可以在适当的情况下将任务标记为取消
      group.addTask {
        try await asyncLoadResultRemotelyUsingAsyncFunction()
      }
      
      group.addTask(priority: .low) {
        try await asyncProcessFromScratchUsingTaskGroup()
      }
    }
  }
  
  print("someSyncMethod results: \n\(results)\n")
}

/// ```swift
/// for _ in 0 ..< 10_000 {
///   someSyncMethod()
/// }
///
/// // Thread 10: EXC_ACCESS (code=1, address=0x00000000000)
/// ```

class HolderClass {
  
  private let _queue = DispatchQueue(label: "resultholder.queue")
  
  private var _results: [String] = []
  
  func getResults() -> [String] {
    _queue.sync { return self._results }
  }
  
  func setResults(_ results: [String]) {
    _queue.sync { self._results = results }
  }
  
  func append(_ value: String) {
    _queue.sync { self._results.append(value) }
  }
}

var holderClass = HolderClass()

func addAppendingToHolderClass(_ value: String, to string: String) {
  holderClass.append(value.appending(string))
}

func asyncLoadResultRemotelyUsingAsyncFunctionToHolderClass() async throws {
  try await Task.sleep(nanoseconds: 2 * NSEC_PER_SEC)
  holderClass.setResults(["data1^sig", "data2^sig", "data3^sig"])
}

func asyncProcessFromScratchUsingAsyncFunctionForHolderClass() async throws {
  Task {
    await withThrowingTaskGroup(of: Void.self) { (group) in
      group.addTask {
        let loadStrings = try await asyncLoadFromDatabaseUsingAsyncFunction()
        let loadSignature = try await asyncLoadSignatureUsingAsyncFunction()
        
        if let strings = loadStrings {
          if let signature = loadSignature {
            strings.forEach {
              addAppendingToHolderClass(signature, to: $0)
            }
          }
        }
      }
    }
  }
}

func someSyncMethodForHolderClass() {
  Task {
    await withThrowingTaskGroup(of: Void.self) { (group) in
      /// * group 满足 AsyncSequence 协议，可以使用 for await 的方式用类似同步循环的写法来访问异步操作的结果
      /// * 通过调用 groud 的 cancelAll，可以在适当的情况下将任务标记为取消
      group.addTask {
        try await asyncLoadResultRemotelyUsingAsyncFunctionToHolderClass()
      }
      
      group.addTask(priority: .low) {
        try await asyncProcessFromScratchUsingAsyncFunctionForHolderClass()
      }
    }
  }
  
  print("someSyncMethodForHolderClass results: \n\(holderClass.getResults())\n")
}

/// ```swift
/// for _ in 0 ..< 10_000 {
///   someSyncMethodForHolderClass()
/// }
/// ```

actor HolderActor {
  
  private var _results: [String] = []
  
  func getResults() -> [String] {
    return self._results
  }
  
  func setResults(_ results: [String]) {
    self._results = results
  }
  
  func append(_ value: String) {
    self._results.append(value)
  }
}

var holderActor = HolderActor()

func addAppendingToHolderActor(_ value: String, to string: String) {
  Task {
    await holderActor.append(value.appending(string))
  }
}

func asyncLoadResultRemotelyUsingAsyncFunctionToHolderActor() async throws {
  try await Task.sleep(nanoseconds: 2 * NSEC_PER_SEC)
  await holderActor.setResults(["data1^sig", "data2^sig", "data3^sig"])
}

func asyncProcessFromScratchUsingAsyncFunctionForHolderActor() async throws {
  Task {
    await withThrowingTaskGroup(of: Void.self) { (group) in
      group.addTask {
        let loadStrings = try await asyncLoadFromDatabaseUsingAsyncFunction()
        let loadSignature = try await asyncLoadSignatureUsingAsyncFunction()
        
        if let strings = loadStrings {
          if let signature = loadSignature {
            strings.forEach {
              addAppendingToHolderActor(signature, to: $0)
            }
          }
        }
      }
    }
  }
}

func someSyncMethodForHolderActor() {
  Task {
    await withThrowingTaskGroup(of: Void.self) { (group) in
      /// * group 满足 AsyncSequence 协议，可以使用 for await 的方式用类似同步循环的写法来访问异步操作的结果
      /// * 通过调用 groud 的 cancelAll，可以在适当的情况下将任务标记为取消
      group.addTask {
        try await asyncLoadResultRemotelyUsingAsyncFunctionToHolderActor()
      }
      
      group.addTask(priority: .low) {
        try await asyncProcessFromScratchUsingAsyncFunctionForHolderActor()
      }
    }
    
    print("someSyncMethodForHolderActor results: \n\(await holderActor.getResults())\n")
  }
}

for _ in 0 ..< 10_000 {
  someSyncMethodForHolderActor()
}
