import Foundation
import Synchronization

// Debug builds only (32b, L9): a Release build has no fake backend to fall back to.
#if DEBUG
    /// Serves requests for a `FakeBackend`'s host inside the process, so the app's real network
    /// client runs unchanged against it. Add it to a session with
    /// `APIClient.makeSession(protocolClasses: [FakeBackendURLProtocol.self])`.
    public final class FakeBackendURLProtocol: URLProtocol, @unchecked Sendable {
        private static let backends = Mutex<[String: WeakBackend]>([:])

        private struct WeakBackend: @unchecked Sendable {
            weak var backend: FakeBackend?
        }

        static func register(_ backend: FakeBackend) {
            backends.withLock { $0[backend.host] = WeakBackend(backend: backend) }
        }

        static func unregister(_ host: String) {
            _ = backends.withLock { $0.removeValue(forKey: host) }
        }

        private static func backend(for request: URLRequest) -> FakeBackend? {
            guard let host = request.url?.host() else { return nil }
            return backends.withLock { $0[host]?.backend }
        }

        override public class func canInit(with request: URLRequest) -> Bool {
            backend(for: request) != nil
        }

        override public class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        private let work = Mutex<Task<Void, Never>?>(nil)

        override public func startLoading() {
            let request = self.request
            guard let backend = Self.backend(for: request) else {
                client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
                return
            }
            let reply = backend.reply(to: request, body: Self.body(of: request))
            let loader = Loader(protocol: self)
            let task = Task.detached {
                switch reply {
                case .hang:
                    // Never answers: the client's timeout ends the request.
                    return
                case .fail(let code, let delay):
                    guard (try? await Task.sleep(for: delay)) != nil else { return }
                    loader.fail(URLError(code))
                case .respond(let status, let headers, let body, let delay):
                    guard (try? await Task.sleep(for: delay)) != nil else { return }
                    loader.respond(status: status, headers: headers, body: body)
                case .trickle(let status, let headers, let body):
                    loader.begin(status: status, headers: headers)
                    for byte in body {
                        guard (try? await Task.sleep(for: .milliseconds(100))) != nil else { return }
                        loader.load(Data([byte]))
                    }
                    loader.finish()
                }
            }
            work.withLock { $0 = task }
        }

        override public func stopLoading() {
            work.withLock {
                $0?.cancel()
                $0 = nil
            }
        }

        /// Delivers an answer to the loading system. URLProtocol's client is safe to call from any
        /// thread once loading has started; the box only tells the compiler so.
        private struct Loader: @unchecked Sendable {
            let `protocol`: FakeBackendURLProtocol

            func fail(_ error: URLError) {
                `protocol`.client?.urlProtocol(`protocol`, didFailWithError: error)
            }

            func begin(status: Int, headers: [String: String]) {
                guard let url = `protocol`.request.url,
                    let response = HTTPURLResponse(
                        url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)
                else { return }
                `protocol`.client?.urlProtocol(`protocol`, didReceive: response, cacheStoragePolicy: .notAllowed)
            }

            func load(_ data: Data) {
                `protocol`.client?.urlProtocol(`protocol`, didLoad: data)
            }

            func finish() {
                `protocol`.client?.urlProtocolDidFinishLoading(`protocol`)
            }

            func respond(status: Int, headers: [String: String], body: Data) {
                guard let url = `protocol`.request.url,
                    let response = HTTPURLResponse(
                        url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)
                else { return }
                let client = `protocol`.client
                client?.urlProtocol(`protocol`, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(`protocol`, didLoad: body)
                client?.urlProtocolDidFinishLoading(`protocol`)
            }
        }

        /// URLSession hands a protocol the body as a stream, not as `httpBody`.
        private static func body(of request: URLRequest) -> Data? {
            if let body = request.httpBody { return body }
            guard let stream = request.httpBodyStream else { return nil }
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                guard read > 0 else { break }
                data.append(buffer, count: read)
                if data.count > (APIV1.endpoints.map(\.maxBodyBytes).max() ?? APIV1.maxBodyBytes) * 2 { break }
            }
            return data
        }
    }
#endif
