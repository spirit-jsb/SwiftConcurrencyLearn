import Foundation

/// ## 异步函数的动机

/// ### 基于回调的异步操作的问题
///
/// problems with callback-based async operation
var hasSignature: Bool = true

func loadSignature(
  // 5
  _ completion: @escaping (String?, Error?) -> Void)
{
  // 3
  guard hasSignature else {
    // 4
    return
  }
  
  DispatchQueue.global().async {
    do {
      let data = try Data(contentsOf: URL(string: "https://httpbin.org/base64/swift-concurrency-learn")!)
      // 1
      DispatchQueue.main.async {
        // 6
        completion(String(data: data, encoding: .utf8), nil)
      }
    }
    catch {
      DispatchQueue.main.async {
        // 2
        completion(nil, error)
      }
    }
  }
}
/// 存在的问题
/// * 1. 回调地狱：多个基于回调的异步操作进行嵌套，将不可避免的导致回调逐渐内嵌，使得代码难以阅读和追踪
/// * 2. 错误处理：Swift 中引入 throw 来处理同步函数中的错误，但回调函数并没有保有调用栈，因此其中发生的错误并不能 throw 到调用方，我们必须基于可选值的参数来表示错误
/// * 3. 破坏结构：在多个异步操作中，可能需要使用 if 或者 guard 等条件语句来决定是否执行某个操作，代码的执行可能不再按照从上向下的顺序，而要根据条件进行跳转或者提前返回
/// * 4. 错误的 completion 调用：由于回调嵌套、以及失败的代码路径往往被隐藏于正确的流程中，对 completion 的调用可能会被遗忘或被多次调用
/// * 5. 异步操作的复杂性：需要提供额外的闭包，导致框架难以维护
/// * 6. 隐藏的线程调度：对于调用者而言，回调函数的调用方式是不透明的，难以确定回调函数所在的线程
///
/// 异步函数的解决方案
/// * 1. 嵌套的回调被展开为多个 async/await
/// * 2. 保有调用栈，可以使用 throws 和正常的返回值来分别表达错误路径和正常路径
/// * 3. 使用 if 等条件语句时的行为模式与同步代码一致
/// * 4. 有明确的退出路径：返回可用值/抛出错误，编译器会保证异步函数的调用者在函数结束时会且仅会收到一个结果
/// * 5. 函数签名与同步函数类似，便于框架维护
/// * 6. 无需手动进行派发和关心线程调度，虽然在 await 后依然无法确定线程，但可以使用 actor 类型来提供合理的隔离环境，同时异步函数和并发底层使用了全新的协作式线程池 (cooperative thread pool) 进行调度，提供了更多的优化空间

/// ### 线程放弃和暂停点
///
/// 异步函数与同步函数的不同：
/// * 可以放弃当前占有的线程进行暂停
/// * 可以从暂停点继续执行
///
/// 异步函数的运行可以理解为：编译器把异步函数切割成多个部分，每个部分拥有自己分离的存储空间，并可以由运行环境进行调度。我们可以把每个这种被切割后剩余的执行单元称为续体 (continuation)，而一个异步函数在执行时就是多个续体依次运行的结果
///
/// 异步函数本身无法放弃线程，只能通过对另外的异步函数进行方法调用或主动创建续体实现暂停，这些被调用的方法和续体，有时会要求当前异步函数放弃线程并等待完成(如续体完结)，当完成后，当前函数会继续执行
///
/// await 用于标记出一个潜在的暂停点 (suspend point)，因此在异步函数中可能发生暂停的地方编译器会要求我们明确使用 await 标记
/// ⚠️ await 仅仅是一个潜在的暂停点，而非必然的暂停点，是否会触发“暂停”，需要看被调用的函数的具体实现和运行时提供的执行器是否需要触发暂停

/// ## 转换函数的签名
///
/// 将闭包回调改写为异步函数的方法与技巧
///
/// ### 修改函数签名
///
/// 对于基于回调的异步操作，一般性的转换原则就是将回调去掉，为函数加上 async 修饰，如果回调接受 Error? 表示错误的话，新的异步函数应当可以 throws，最后把回调参数当作异步函数的返回值即可
/// ```swift
/// func calculate(input: Int, completion: @escaping (Int) -> Void)
/// // 转换为
/// func calculate(input: Int) async -> Int
///
/// func load(completion: @escaping ([String]?, Error?) -> Void)
/// // 转换为
/// func load() async throws -> [String]
/// ```
///
/// ### 带有返回的情况
///
/// URLSession 中的处理方法
/// ```swift
/// class URLSession {
///   func dataTask(with url: URL, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask
/// }
/// // 转化为
/// class URLSession {
///   func data(from url: URL, delegate: URLSessionTaskDelegate? = nil) async throws -> (Data, URLResponse)
/// }
/// ```
/// dataTask 方法在接受 completionHandler 回调的同时，同步的返回一个 URLSessionDataTask，调用者可以通过调用 URLSessionDataTask 的 cancel 来取消运行中的任务
/// 这种情况下，返回的 URLSessionDataTask 不能简单的写在新的异步函数的返回里：异步函数的返回值是经过暂停点后的异步执行结果，它在语义上和同步函数的返回值不同
/// 因此新的异步函数忽略了 URLSessionDataTask 返回值，可以通过取消任务来间接取消运行中的网络请求
///
/// 如果原闭包回调函数的返回值是一个简单的基本类型，也许可以通过 inout 参数在暂停点之前获取这个值
/// ```swift
/// func syncFunc(completion: @escaping (Int) -> Void) -> Bool {
///   someAsyncMethod {
///     completion(1)
///   }
///
///   return true
/// }
/// // 转化为
/// func asyncFunc(started: inout Bool) async -> Int {
///   started = true
///   await someAsyncMethod()
///   return 1
/// }
/// ```
/// 但是，如果是从 Task 域外传递一个 inout Bool 的话，编译器将会提示错误，所以这并不是一个完备的解决方案
/// ```swift
/// var started = false
/// Task {
///   let value = await asyncFunc(started: &started)
///   print(value)
/// }
/// print("Started: \(started)")
/// // 编译错误
/// // Mutation of captured var `started` in concurrently-executing code
/// ```
