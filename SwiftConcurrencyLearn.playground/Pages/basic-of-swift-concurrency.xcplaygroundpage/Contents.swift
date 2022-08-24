import Foundation
import UIKit

/// ## 一些基本概念

/// ### 同步与异步
///
/// 线程执行方式：
/// * 同步 (synchronous)
/// * 异步 (asynchronous)
///
/// 同步操作意味着在操作完成之前，运行该操作的线程都将被占用，直到函数最终被抛出或返回
///
/// synchronous appending value to string
var results: [String] = []

func addAppending(_ value: String, to string: String) {
  results.append(value.appending(string))
}
/// ──────────┬────────────┬┬─────────────┬┬─────────────┬──────────
///  Thread   │addAppending││Other Actions││Other Actions│
/// ──────────┴────────────┴┴─────────────┴┴─────────────┴──────────
///
/// iOS 开发中，使用的 UI 开发框架 (UIKit / SwiftUI) 不是线程安全的，对于用户输入的处理和 UI 的绘制必须在与主线程绑定的 main runloop 中进行
/// 假设我们希望用户界面以每秒60帧的速率运行，那么主线程中每两次绘制之间所能允许的处理时间最多只有 16ms (1/60s)
/// 当主线程中要同步处理的操作耗时过长的话，主线程将被阻塞，既无法接受用户输入、也无法向 GPU 提交绘制 UI 的请求
/// 这种 “长耗时” 的操作是常见的：例如从网络请求中或许数据、从磁盘中加载一个大文件、进行某些复杂的加解密运算等等
///
/// synchronous load signature from remote (blocking actions)
func loadSignature() throws -> String? {
  // 从网络读取一个字符串
  let data = try Data(contentsOf: URL(string: "https://example.com")!)
  return String(data: data, encoding: .utf8)
}
///                │            │         │
///                │◄───16ms───►◄─UI Lags─►
///                │            │         │
/// ───────────────┼────────────┴────────┬┼──────────┬───────────
///  Main Thread   │    loadSignature    ││UI Actions│
/// ───────────────┴─────────────────────┴┴──────────┴───────────
///
/// loadSignature 最终的耗时超过 16ms，对 UI 的操作或刷新处理不得不被延后，在用户的观感上将表现为掉帧或页面卡顿
/// Swift5.5 前，解决这个问题最常见的做法是将耗时的同步操作转为异步操作：
/// 把实际长时间执行的任务放到另外的线程 (后台线程) 运行，在操作结束时提供运行在主线程的回调
///
/// asynchronous load signature from remote
func loadSignature_1(_ completion: @escaping (String?, Error?) -> Void) {
  DispatchQueue.global().async {
    do {
      let data = try Data(contentsOf: URL(string: "https://example.com")!)
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
///              │                            │
///              │◄───────────16ms───────────►│
///              │                            │
/// ─────────────┼┬────┬──────────┬┬──────────┼──┬──────────┬──
///  Main Thread ││    │UI Actions││UI Actions│  │completion│
/// ─────────────┴┼────┴──────────┴┴──────────┴──▲──────────┴──
///               │                              │
///               │                              │
/// ──────────────▼──────────────────────────────┼─────────────
///  Other Thread │    Data.init(contentOf:)     │
/// ──────────────┴──────────────────────────────┴─────────────
///
/// DispacthQueue.global 负责将任务添加到全局后台派发队列
/// 在底层，GCD (Grand Center Dispatch) 负责进行线程调度，将为耗时繁重的 Data.init(contentOf:) 分配合适的线程
/// 耗时任务完成后再由 DispatchQueue.main 派发回主线程，并按照结果调用 completion 回调方法
///
/// 异步操作的问题：
/// * 错误处理隐藏在回调函数的参数中，无法用 throw 的方式明确的告知并强制调用侧去进行错误处理
/// * 对回调函数的调用没有编译器保证，开发者可能会忘记调用 completion，或者多次调用 completion
/// * 通过 DispatchQueue 进行线程调度很快会使代码复杂化，特别是如果线程调度的操作被隐藏在被调用的方法中时，不查看源码，在调用侧的回调函数中几乎无法确定当前代码运行的线程状态
/// * 对于正在执行的任务，没有很好的取消机制
///
/// 注意：虽然将运行在后台线程加载数据的行为称为异步操作，但是接受回调函数作为参数的 loadSignature(_:) 方法本身依然是一个同步函数，这个方法在返回前仍旧会占据主线程，只不过它的执行时间非常短暂，并不会对 UI 相关的操作造成影响。
/// Swift5.5 前，Swift 并没有真正的异步函数概念

/// ### 串行和并行
///
/// #### 串行
///
/// 方法被顺次调用，在同一线程中按严格的先后顺序方法，这种执行方式称之为串行 (serial)
///
/// * 对于通过同步方法执行的同步操作，这些操作一定是以串行方式在同一线程中发生的
///
/// synchronous serial actions
if let signature = try? loadSignature() {
  addAppending(signature, to: "some data")
}

print("synchronous serial actions results: \n\(results)\n")
/// ───────────┬───────────────┬──────────────┬───────┬───────
///  Thread    │ loadSignature │ addAppending │ print │
/// ───────────┴───────────────┴──────────────┴───────┴───────
///
/// * 同步方法执行的同步操作，是串行 (serial) 的充分不必要条件，异步操作也可能会以串行的方式执行
///
/// asynchronous serial actions
func loadFromDatabase(_ completion: @escaping ([String]?, Error?) -> Void) {
  DispatchQueue.global().async {
    sleep(2)
    
    DispatchQueue.main.async {
      completion(["some data"], nil)
    }
  }
}

loadFromDatabase { (strings, error) in
  if let strings = strings {
    loadSignature_1 { (signature, error) in
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
/// ─────────────┬┬──────────────────┬┬───────────────┬──────────────┬┬───────────────┬────────
///  Main Thread ││                  ││               │ addAppending ││ Other Actions │
/// ─────────────┴┼──────────────────▲├───────────────▲──────────────┴┴───────────────┴────────
///               │                  ││               │
///               │                  ││               │
/// ──────────────▼──────────────────┤▼───────────────┼────────────────────────────────────────
///  Other Thread │ loadFromDatabase ││ loadSignature │
/// ──────────────┴──────────────────┴┴───────────────┴────────────────────────────────────────
///
/// 这些操作虽然是异步 (asynchronous) 的，但它们 (loadFromDatabase、loadSignature、addAppending) 依然是串行 (serial) 的
///
/// 虽然 addAppending 任务同时需要原始数据和签名才能进行，但 loadFromDatabase 和 loadSignature 之间并没有依赖关系，一同执行可以提高程序运行速度，这时候我们需要更多的线程来同时执行两个操作
///
/// loadFromDatabase { (strings, error) in
/// ...
/// loadSignature { (signature, error) in
/// ...
///
/// 将串行调用替换为
///
/// loadFromDatabase { (strings, error) in
///   ...
/// }
///
/// loadSignature { (signature, error) in
///   ...
/// }
///
/// 为了确保在 addAppending 执行时，loadFromDatabase 和 loadSignature 都已经准备好，我们需要某种手段来确保这些数据的可用性。在 GCD 中，通常可以使用 DispatchGroup 或 DispatchSemaphore 来实现
///
/// ─────────────┬┬───────────────────┬──────────────┬┬───────────────┬───────
///  Main Thread ││                   │ addAppending ││ Other Actions │
/// ─────────────┼┼──────────────▲────▲──────────────┴┴───────────────┴───────
///              ││              │    │
/// ─────────────┤▼──────────────┼────┼───────────────────────────────────────
///  Other Thread││ loadFromDatab│ase │
/// ─────────────┼┴──────────────┼────┴───────────────────────────────────────
///              │               │
/// ─────────────▼───────────────┼────────────────────────────────────────────
///  Other Thread│ loadSignature │
/// ─────────────┴───────────────┴────────────────────────────────────────────
///
/// 这时，loadFromDatabase 和 loadSignature 两个异步操作，在不同的线程中同时执行
///
/// #### 并行
///
/// 方法被同时调用，在不同线程中同时执行，这种执行方式称之为并行 (parallel)

/// ### Swift 并发是什么
///
/// #### 并发
///
/// 指多个计算同时执行 (若干个操作的开始和结束时间之间存在重叠) 的特性，称之为并发 (concurrency)
///
/// Apple 有关并发 (concurrency) 的解释
/// ```
/// Swift has built-in support for writing asynchronous and parallel code in a structured way, ... concurrency to refer to this common combination of asynchronous and parallel code.
///
/// Swift 提供内建的支持，让开发者能以结构化的方式编写异步和并行代码，... 并发这个术语，指的是异步和并行这一常见组合。
/// ```
///
/// Swift 并发 (concurrency) 是指异步和并行代码的组合
///
/// #### 并发编程历史及难点
///
/// ┌──────────────────┐  ┌─────────────────────┐              ┌─────────────┐
/// │Edsger W. Dijkstra├─►│      Tony Hoare     ├─────────────►│ Carl Hewitt │
/// └────────┬─────────┘  └─┬─────────────────┬─┘              └──────┬──────┘
///          │              │                 │                       │
///     ┌────▼────┐       ┌─▼─┐ ┌─────────────▼─────────────┐  ┌──────▼──────┐
///     │semaphore│       │CSP│ │Dining philosophers problem│  │ Actor Model │
///     └─────────┘       └───┘ └───────────────────────────┘  └─────────────┘
///
/// 并发编程需要解决的问题：
/// * 如何确保不同运算运行步骤之间的交互或通信可以按照正确的顺序执行 (逻辑正确)
/// * 如何确保运算资源在不同运算之间被安全地共享、访问和传递 (内存安全)
///
/// #### Swift 并发 (concurrency) 的解决方案
///
/// * 设计了异步函数的书写方法
/// * 利用结构化并发确保运算步骤的交互和通信正确
/// * 利用 actor 模型确保共享的计算资源能在隔离的情况下被正确访问和操作

/// ## 异步函数
///
/// 1. 添加了异步函数概念
///
/// 在函数声明的返回箭头前，加上 async 关键字，就可以把一个函数声明为异步函数
///
/// using async function to load signature from remote
func loadSignature_2() async throws -> String? {
  let (data, _) = try await URLSession.shared.data(from: URL(string: "https://example.com")!)
  return String(data: data, encoding: .utf8)
}
/// async 关键字会帮助编译器确保：
/// * 它允许我们在函数体内部使用 await 关键字
/// * 它要求其他人在调用这个函数时，使用 await 关键字
///
/// await 关键字表示函数在此处可能会放弃当前线程，是程序的潜在暂停点
/// 放弃线程，意味着异步方法可以被“暂停”，这个线程可以被用来执行其他代码。如果这个线程是主线程的话，那么页面将不会卡顿。被 await 的语句将被底层机制分配到其他合适的线程，在执行完后，之前的“暂停”将结束，异步方法从刚才的 await 语语句后开始，继续向下执行
///
/// using async function to asynchronous serial actions
func loadFromDatabase_1() async throws -> [String]? {
  try await Task.sleep(nanoseconds: 2 * NSEC_PER_SEC)
  return ["data1^sig", "data2^sig", "data3^sig"]
}

Task {
  if let strings = try await loadFromDatabase_1() {
    if let signature = try await loadSignature_2() {
      strings.forEach {
        addAppending(signature, to: $0)
      }
      
      print("using async function to asynchronous serial actions results: \n\(results)\n")
    }
  }
}

/// ## 结构化并发
///
/// 对于同步函数而言，线程决定了执行环境
/// 对于异步函数而言，任务 (Task) 决定了执行环境
///
/// * 一个任务 (Task) 具有它自己的优先级和取消标识，它可以拥有若干子任务并在其中执行异步函数
/// * 当一个父任务被取消时，这个父任务的取消标识将被设置并向下传递到所有的子任务中
/// * 无论是正常完成还是抛出错误，子任务都会将结果向上报告给父任务，在所有子任务完成前 (无论是正常结束还是抛出错误)，父任务是不会完成的
///
/// struct Task<Success, Failure> where Failure: Error {
///
///   init(prioity: TaskPriority? = nil, action: @escaping @Sendable () async throws -> Success)
/// }
///
/// 结构化并发创建方式：
/// * async let (异步绑定)
/// * Task group (任务组)
///
/// task function
func processFromScratch() async throws {
  if let strings = try await loadFromDatabase_1() {
    if let signature = try await loadSignature_2() {
      strings.forEach {
        addAppending(signature, to: $0)
      }
    }
  }
}

Task {
  try await processFromScratch()
}

print("task function results: \n\(results)\n")
/// 注意：在 processFromScratch 中的处理依然是串行 (serial) 的：对 loadFromDatabase 的 await 将使这个异步函数在此暂停，直到实际操作结束，接下来才会执行 loadSignature
///
/// ┌───────────┐  ┌──────────────────┐  ┌───────────────┐    │ ┌──────────────┐
/// │ Task.init ├─►│ loadFromDatabase ├─►│ loadSignature │    │ │ addAppending │
/// └───────────┘  └──────────────────┘  └───────────────┘    │ └──────────────┘
///
/// 当我们希望 loadFromDatabase 和 loadSignature 这两个操作可以同时进行时，就需要将任务 (Task) 以结构化 (structured) 的方式进行组织
///
/// structured concurrency
#warning("Playground can’t testing structured concurrency code")
//func processFromScratch_1() async throws {
//  async let loadStrings = loadFromDatabase_1()
//  async let loadSignature = loadSignature_2()
//
//  if let strings = try await loadStrings {
//    if let signature = try await loadSignature {
//      strings.forEach {
//        addAppending(signature, to: $0)
//      }
//    }
//  }
//}
func processFromScratch_1() async throws {
  Task {
    await withThrowingTaskGroup(of: Void.self) { (group) in
      group.addTask {
        let loadStrings = try await loadFromDatabase_1()
        let loadSignature = try await loadSignature_2()
        
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
  try await processFromScratch_1()
}

print("structured concurrency results: \n\(results)\n")
/// async let 被称为异步绑定，它在当前 Task 上下文中创建新的子任务，并将它用作被绑定的异步函数 (即 async let 右侧表达式) 的运行环境
/// 与 Task.init 新建一个任务根节点不同，async let 所创建的子任务是任务树上的叶子节点，被异步绑定的操作会立即开始执行，即使在 await 之前执行就已经完成，其结果依然可以等到 await 语句时再进行求值
///
///                  ┌──────────────────┐    │
///               ┌─►│ loadFromDatabase │    │
/// ┌───────────┐ │  └──────────────────┘    │ ┌──────────────┐
/// │ Task.init ├─┤                          │ │ addAppending │
/// └───────────┘ │  ┌───────────────┐       │ └──────────────┘
///               └─►│ loadSignature │       │
///                  └───────────────┘       │
///
/// 相对于 GCD 调度的并发，基于任务的结构化并发在控制并发行为上具有明显优势
///
/// 另一种创建结构化并发的方式，是使用任务组 (Task group)
///
/// structured concurrency
func loadResultRemotely() async throws {
  try await Task.sleep(nanoseconds: 2 * NSEC_PER_SEC)
  results = ["data1^sig", "data2^sig", "data3^sig"]
}

func someSyncMethod() {
  Task {
    await withThrowingTaskGroup(of: Void.self) { (group) in
      /// * group 满足 AsyncSequence 协议，可以使用 for await 的方式用类似同步循环的写法来访问异步操作的结果
      /// * 通过调用 groud 的 cancelAll，可以在适当的情况下将任务标记为取消
      group.addTask {
        try await loadResultRemotely()
      }
      
      group.addTask(priority: .low) {
        try await processFromScratch_1()
      }
    }
  }
  
  print("structured concurrency results: \n\(results)\n")
}
/// 对于 processFromScratch 我们将它特别指定为 .low 的优先级，这会导致该任务在另一个低优先级线程中被调度
///
///                    ┌────────────────────────────────────────────┐
///                    │                                            │
///                    │             processFromScratch             │
///                    │                                            │
///                    │ ┌──────────────────┐    │                  │
///                    │ │ loadFromDatabase │    │                  │
///               ┌───►│ └──────────────────┘    │ ┌──────────────┐ │
///               │    │                         │ │ addAppending │ │
///               │    │ ┌───────────────┐       │ └──────────────┘ │
///               │    │ │ loadSignature │       │                  │
///               │    │ └───────────────┘       │                  │
///               │    │                                            │
///               │    └────────────────────────────────────────────┘
///               │
///               │    ┌──────────────────────────────────┐
/// ┌───────────┐ │    │                                  │
/// │ Task.init ├─┤    │        loadResultRemotely        │
/// └───────────┘ │    │                                  │
///               └───►│ ┌───────────────┐ ┌────────────┐ │
///                    │ │ async actions │ │ set result │ │
///                    │ └───────────────┘ └────────────┘ │
///                    │                                  │
///                    └──────────────────────────────────┘
///
/// withThrowingTaskGroup / withTaskGroup 提供了另一种创建结构化并发的组织方式
///
/// 当运行时才知道任务数量或需要为不同的子任务设置不同的优先级时，我们只能选择使用 Task group
/// 其他大部分情况下，async let 和 Task group 可以相互混用或替代
///

/// ## actor 模型和数据隔离
///
/// 在上面的示例中
/// 在 progressFromScratch 里，先将 results 设置为 []，然后再处理每条数据，并将结果添加到 results 里
/// 在 loadResultRemotely 里，直接将结果赋值给了 results
/// 一般来说，我们认为不论 processFromScratch 和 loadResultRemotely 执行的先后顺序如何，我们总应该得到唯一确定的 results，但事实上，如果我们对 loadResultRemotely 的 Task.sleep 时长进行调整，使它与 processFromScratch 所耗费的时间相仿，则会出现出人意料的结果
/// 出现问题的原因在于，我们在 addTask 时为两个任务指定了不同的优先级，因此它们中的代码将运行在不同的调度线程上，两个异步操作在不同线程同时访问了 results，造成了数据竞争
