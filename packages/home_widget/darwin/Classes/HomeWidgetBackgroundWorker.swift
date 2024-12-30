//
//  HomeWidgetBackgroundIntent.swift
//  home_widget
//
//  Created by Anton Borries on 25.08.23.
//

#if canImport(UIKit)
  import Flutter
#elseif canImport(AppKit)
  import FlutterMacOS
#endif
import Foundation
import Swift

@available(iOS 17, macOS 14, *)
public struct HomeWidgetBackgroundWorker {

  static let dispatcherKey: String = "home_widget.internal.background.dispatcher"
  static let callbackKey: String = "home_widget.internal.background.callback"

  static var engine: FlutterEngine?
  static var channel: FlutterMethodChannel?

  static var isSetupCompleted: Bool = false
  static var continuations: [CheckedContinuation<Void, Never>] = []

  // Plugin registration callback for iOS only
  private static var registerPlugins: ((FlutterEngine) -> Void)?

  public static func setPluginRegistrantCallback(registerPlugins: ((FlutterEngine) -> Void)?) {
    #if os(iOS)
    self.registerPlugins = registerPlugins
    #endif
  }

  /// Call this method to invoke the callback registered in your Flutter App.
  /// The url you provide will be used as arguments in the callback function in dart
  /// The AppGroup is necessary to retrieve the dart callbacks
  static public func run(url: URL?, appGroup: String) async {
    if isSetupCompleted == false {
      await withCheckedContinuation { continuation in
        continuations.append(continuation)
      }
    }

    let preferences = UserDefaults.init(suiteName: appGroup)
    let dispatcher = preferences?.object(forKey: dispatcherKey) as! Int64
    NSLog("Dispatcher: \(dispatcher)")

    await sendEvent(url: url, appGroup: appGroup)
  }

  static func setupEngine(dispatcher: Int64) {
    engine = FlutterEngine(
      name: "home_widget_background", project: nil, allowHeadlessExecution: true)

    channel = FlutterMethodChannel(
      name: "home_widget/background", binaryMessenger: engine!.binaryMessenger,
      codec: FlutterStandardMethodCodec.sharedInstance()
    )
    
    #if os(iOS)
    let flutterCallbackInfo = FlutterCallbackCache.lookupCallbackInformation(dispatcher)
    let callbackName = flutterCallbackInfo?.callbackName
    let callbackLibrary = flutterCallbackInfo?.callbackLibraryPath

    let started = engine?.run(
      withEntrypoint: callbackName,
      libraryURI: callbackLibrary)
    
    // Register plugins if callback is provided
    if let registerPlugins = self.registerPlugins {
      registerPlugins(engine!)
    }
    #endif

    channel?.setMethodCallHandler(handle)
  }

  public static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "HomeWidget.backgroundInitialized":
      isSetupCompleted = true
      while !continuations.isEmpty {
        let continuation = continuations.removeFirst()
        continuation.resume()
      }
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  static func sendEvent(url: URL?, appGroup: String) async {
    guard let _channel = channel else {
      return
    }
    let preferences = UserDefaults.init(suiteName: appGroup)
    guard let _callback = preferences?.object(forKey: callbackKey) as? Int64 else {
      return
    }
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async {
        _channel.invokeMethod("", arguments: [_callback, url?.absoluteString ?? ""]) { _ in
          continuation.resume()
        }
      }
    }
  }
}