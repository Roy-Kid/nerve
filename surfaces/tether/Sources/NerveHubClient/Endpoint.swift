import Foundation

/// The one ingest address. Binding it is the hub's single-instance lock.
public enum NerveEndpoint: Sendable {
  public static let host = "127.0.0.1"
  public static let port: UInt16 = 17890

  public static let baseURL: URL = {
    var components = URLComponents()
    components.scheme = "http"
    components.host = host
    components.port = Int(port)
    return components.url!
  }()

  public static let health = baseURL.appending(path: "/v1/health")
  public static let jobs = baseURL.appending(path: "/v1/jobs")
  public static let refresh = baseURL.appending(path: "/v1/refresh")
  public static let stream = baseURL.appending(path: "/v1/stream")
  public static let notify = baseURL.appending(path: "/v1/notify")
  public static let demo = baseURL.appending(path: "/v1/demo")
  public static let clear = baseURL.appending(path: "/v1/clear")

  public static let surfaceName = "tether"

  public static var streamURL: URL {
    var components = URLComponents(url: stream, resolvingAgainstBaseURL: false)!
    components.queryItems = [URLQueryItem(name: "surface", value: surfaceName)]
    return components.url!
  }
}
