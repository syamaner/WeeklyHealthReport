import Darwin
import Foundation
import Network
import Security
import FoodLedgerApplication
import FoodLedgerDomain

/// Public website policy is independent of nutrition semantics. Resolve once and
/// connect to that public address with TLS verification for the original host.
/// This v1 transport uses IPv4 HTTPS, never cookies, credentials or subresources.
public struct PublicFoodSourceCapture: FoodDocumentCapturing {
    /// Opt-in evaluation evidence, never installed by the app composition. The
    /// observer receives only an unauthenticated website response, not API traffic.
    public struct ResponseObservation: Sendable {
        public let url: URL
        public let status: Int
        public let mediaType: String?
        public let body: Data
    }
    typealias Resolver = @Sendable (String) async throws -> [String]
    typealias Fetch = @Sendable (URL, String) async throws -> Data
    private let resolve: Resolver
    private let fetch: Fetch
    private let now: @Sendable () -> Date
    private let observe: @Sendable (ResponseObservation) throws -> Void

    public init(observe: @escaping @Sendable (ResponseObservation) throws -> Void = { _ in }) {
        resolve = { try await PublicFoodDNS.resolve($0) }
        fetch = { try await PinnedFoodHTTPS(url: $0, address: $1).run() }
        now = Date.init
        self.observe = observe
    }
    init(resolve: @escaping Resolver, fetch: @escaping Fetch, now: @escaping @Sendable () -> Date,
         observe: @escaping @Sendable (ResponseObservation) throws -> Void = { _ in }) {
        self.resolve = resolve; self.fetch = fetch; self.now = now
        self.observe = observe
    }

    public func capture(_ url: URL) async throws -> CapturedFoodDocument {
        var current = try Self.canonicalURL(url)
        var seen = Set<URL>()
        for _ in 0..<3 {
            try Task.checkCancellation()
            guard seen.insert(current).inserted, let host = current.host else { throw FoodSourceAcquisitionError.requestLimit }
            let addresses = try await resolve(host)
            try Task.checkCancellation()
            guard !addresses.isEmpty, addresses.allSatisfy(Self.isPublicIPv4), let address = addresses.first else {
                throw FoodSourceAcquisitionError.hostNotAdmitted
            }
            let raw = try await fetch(current, address)
            try Task.checkCancellation()
            let reply = try FoodSourceHTTPReply.decode(raw)
            try observe(.init(url: current, status: reply.status, mediaType: reply.headers["content-type"], body: reply.body))
            if [301, 302, 303, 307, 308].contains(reply.status) {
                guard let location = reply.headers["location"], let next = URL(string: location, relativeTo: current)?.absoluteURL else {
                    throw FoodSourceAcquisitionError.invalidResponse
                }
                current = try Self.canonicalURL(next)
                continue
            }
            guard reply.status == 200 else { throw FoodSourceAcquisitionError.unavailable }
            let contentType = (reply.headers["content-type"] ?? "").lowercased()
            let segments = contentType.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let mediaType = segments.first, ["text/html", "text/plain", "application/pdf"].contains(mediaType),
                  segments.dropFirst().allSatisfy({ !$0.hasPrefix("charset=") || ["charset=utf-8", "charset=utf8", "charset=\"utf-8\""].contains($0) }),
                  reply.headers["content-encoding"].map({ $0.lowercased() == "identity" }) ?? true else {
                throw FoodSourceAcquisitionError.unsupportedContent
            }
            return try GenericFoodDocumentProjector.project(reply.body, url: current, mediaType: mediaType,
                                                           retrievedAt: now())
        }
        throw FoodSourceAcquisitionError.requestLimit
    }

    static func canonicalURL(_ url: URL) throws -> URL {
        guard url.absoluteString.utf8.count <= 4096,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              components.scheme?.lowercased() == "https", components.user == nil, components.password == nil,
              components.port == nil || components.port == 443, let host = components.host?.lowercased(),
              host.utf8.count <= 253, host.split(separator: ".", omittingEmptySubsequences: false).count >= 2,
              ![".localhost", ".local", ".internal", ".home.arpa"].contains(where: { host.hasSuffix($0) }),
              host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ label in
                  !label.isEmpty && label.count <= 63 && label.first != "-" && label.last != "-"
                      && label.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
              }), let last = host.split(separator: ".").last, last.contains(where: { $0.isLetter }) else {
            throw FoodSourceAcquisitionError.invalidURL
        }
        components.scheme = "https"; components.host = host; components.fragment = nil
        guard let canonical = components.url else { throw FoodSourceAcquisitionError.invalidURL }
        return canonical
    }

    static func isPublicIPv4(_ address: String) -> Bool {
        let parts = address.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts.allSatisfy({ !$0.isEmpty && ($0.count == 1 || $0.first != "0") && $0.allSatisfy(\.isNumber) }),
              let a = UInt8(parts[0]), let b = UInt8(parts[1]), let c = UInt8(parts[2]), UInt8(parts[3]) != nil else { return false }
        if a == 0 || a == 10 || a == 127 || a >= 224 { return false }
        if a == 100 && (64...127).contains(b) { return false }
        if a == 169 && b == 254 || a == 172 && (16...31).contains(b) || a == 192 && b == 168 { return false }
        if a == 192 && b == 0 && (c == 0 || c == 2) || a == 192 && b == 88 && c == 99 { return false }
        if a == 198 && (b == 18 || b == 19) || a == 198 && b == 51 && c == 100 || a == 203 && b == 0 && c == 113 { return false }
        return true
    }
}

/// Small HTTP/1.x decoder for one connection-close GET response. Ambiguous framing
/// is rejected. No decompression, pipelining, authentication or script execution.
struct FoodSourceHTTPReply {
    let status: Int
    let headers: [String: String]
    let body: Data
    static let maximumWireBytes = GenericFoodDocumentProjector.maximumBytes + 65_536

    static func decode(_ raw: Data) throws -> Self {
        guard raw.count <= maximumWireBytes,
              let split = raw.range(of: Data("\r\n\r\n".utf8)), split.lowerBound <= 65_536,
              let headerText = String(data: raw[..<split.lowerBound], encoding: .isoLatin1) else {
            throw FoodSourceAcquisitionError.invalidResponse
        }
        let lines = headerText.components(separatedBy: "\r\n")
        let statusParts = (lines.first ?? "").split(separator: " ")
        guard statusParts.count >= 2, ["HTTP/1.0", "HTTP/1.1"].contains(statusParts[0]),
              statusParts[1].count == 3, let status = Int(statusParts[1]), (200...599).contains(status), lines.count <= 200 else {
            throw FoodSourceAcquisitionError.invalidResponse
        }
        var headers: [String: String] = [:]
        let unique: Set<String> = ["content-length", "transfer-encoding", "content-type", "content-encoding", "location"]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":"), colon != line.startIndex,
                  line[..<colon].utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }) else {
                throw FoodSourceAcquisitionError.invalidResponse
            }
            let name = line[..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !value.unicodeScalars.contains(where: { $0.value < 32 && $0.value != 9 || $0.value == 127 }),
                  !unique.contains(name) || headers[name] == nil else { throw FoodSourceAcquisitionError.invalidResponse }
            headers[name] = value
        }
        let encodedBody = Data(raw[split.upperBound...])
        let body: Data
        if let encoding = headers["transfer-encoding"] {
            guard encoding.lowercased() == "chunked", headers["content-length"] == nil else { throw FoodSourceAcquisitionError.invalidResponse }
            body = try unchunk(encodedBody)
        } else {
            if let length = headers["content-length"] {
                guard !length.isEmpty, length.utf8.allSatisfy({ (48...57).contains($0) }), Int(length) == encodedBody.count else {
                    throw FoodSourceAcquisitionError.invalidResponse
                }
            }
            body = encodedBody
        }
        guard body.count <= GenericFoodDocumentProjector.maximumBytes else { throw FoodSourceAcquisitionError.responseTooLarge }
        return Self(status: status, headers: headers, body: body)
    }

    private static func unchunk(_ raw: Data) throws -> Data {
        var index = raw.startIndex
        var body = Data()
        while index < raw.endIndex {
            guard let end = raw.range(of: Data("\r\n".utf8), in: index..<raw.endIndex), end.lowerBound - index <= 128,
                  let line = String(data: raw[index..<end.lowerBound], encoding: .ascii),
                  let digits = line.split(separator: ";", omittingEmptySubsequences: false).first, !digits.isEmpty,
                  digits.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
                  let count = Int(digits, radix: 16), count <= GenericFoodDocumentProjector.maximumBytes - body.count else {
                throw FoodSourceAcquisitionError.invalidResponse
            }
            index = end.upperBound
            if count == 0 {
                // Trailers are uncommon for these pages. Reject them rather than
                // let trailing headers revise the provenance/content interpretation.
                guard Data(raw[index...]) == Data("\r\n".utf8) else { throw FoodSourceAcquisitionError.invalidResponse }
                return body
            }
            guard count <= raw.endIndex - index - 2,
                  raw[index + count] == 13, raw[index + count + 1] == 10 else { throw FoodSourceAcquisitionError.invalidResponse }
            body.append(raw[index..<(index + count)]); index += count + 2
        }
        throw FoodSourceAcquisitionError.invalidResponse
    }
}

/// OS DNS may finish after cancellation; the continuation has a ten-second bound
/// and completion is serialised. Late results are discarded and never connected.
private final class PublicFoodDNS: @unchecked Sendable {
    private let queue = DispatchQueue(label: "FoodSourceDNS")
    private var continuation: CheckedContinuation<[String], Error>?
    private var cancelled = false
    static func resolve(_ host: String) async throws -> [String] {
        let operation = PublicFoodDNS()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in operation.start(host, continuation) }
        } onCancel: { operation.cancel() }
    }
    private func start(_ host: String, _ continuation: CheckedContinuation<[String], Error>) {
        queue.async {
            self.continuation = continuation
            if self.cancelled { self.finish(.failure(CancellationError())); return }
            self.queue.asyncAfter(deadline: .now() + 10) { self.finish(.failure(FoodSourceAcquisitionError.timedOut)) }
            DispatchQueue.global(qos: .utility).async {
                var hints = addrinfo(); hints.ai_family = AF_INET; hints.ai_socktype = SOCK_STREAM; hints.ai_protocol = IPPROTO_TCP
                var pointer: UnsafeMutablePointer<addrinfo>?
                guard getaddrinfo(host, "443", &hints, &pointer) == 0, let first = pointer else {
                    self.queue.async { self.finish(.failure(FoodSourceAcquisitionError.unavailable)) }; return
                }
                defer { freeaddrinfo(first) }
                var addresses: [String] = []; var current: UnsafeMutablePointer<addrinfo>? = first
                while let item = current {
                    var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(item.pointee.ai_addr, item.pointee.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                        let address = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                        if !addresses.contains(address) { addresses.append(address) }
                    }
                    current = item.pointee.ai_next
                }
                let resolved = addresses
                self.queue.async { self.finish(.success(resolved)) }
            }
        }
    }
    private func cancel() { queue.async { self.cancelled = true; self.finish(.failure(CancellationError())) } }
    private func finish(_ result: Result<[String], Error>) {
        let pending = continuation; continuation = nil; pending?.resume(with: result)
    }
}

/// The numeric NW endpoint pins DNS. TLS server-name verification and SNI retain
/// the original hostname; default system trust evaluation is never overridden.
private final class PinnedFoodHTTPS: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "FoodSourceHTTPS")
    private let request: Data
    private var continuation: CheckedContinuation<Data, Error>?
    private var received = Data()
    private var cancelled = false
    private var sent = false

    init(url: URL, address: String) throws {
        guard let host = url.host, let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              PublicFoodSourceCapture.isPublicIPv4(address) else { throw FoodSourceAcquisitionError.invalidURL }
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions, host)
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        connection = NWConnection(host: NWEndpoint.Host(address), port: 443, using: NWParameters(tls: tls, tcp: .init()))
        let path = (components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath)
            + (components.percentEncodedQuery.map { "?" + $0 } ?? "")
        request = Data(("GET " + path + " HTTP/1.1\r\nHost: " + host
            + "\r\nUser-Agent: WeeklyHealthReport/0.1.1\r\nAccept: text/html, text/plain, application/pdf\r\nAccept-Encoding: identity\r\nConnection: close\r\n\r\n").utf8)
    }
    func run() async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    self.continuation = continuation
                    if self.cancelled { self.finish(.failure(CancellationError())); return }
                    self.queue.asyncAfter(deadline: .now() + 20) { self.finish(.failure(FoodSourceAcquisitionError.timedOut)) }
                    self.connection.stateUpdateHandler = { [self] state in
                        switch state {
                        case .ready:
                            guard !self.sent, self.continuation != nil else { return }
                            self.sent = true
                            self.connection.send(content: self.request, completion: .contentProcessed { error in
                                if error != nil { self.finish(.failure(FoodSourceAcquisitionError.unavailable)) }
                                else { self.receive() }
                            })
                        case .failed: self.finish(.failure(FoodSourceAcquisitionError.unavailable))
                        default: break
                        }
                    }
                    self.connection.start(queue: self.queue)
                }
            }
        } onCancel: {
            self.queue.async { self.cancelled = true; self.finish(.failure(CancellationError())) }
        }
    }
    private func receive() {
        guard continuation != nil else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, complete, error in
            guard self.continuation != nil else { return }
            if let data {
                guard self.received.count + data.count <= FoodSourceHTTPReply.maximumWireBytes else {
                    self.finish(.failure(FoodSourceAcquisitionError.responseTooLarge)); return
                }
                self.received.append(data)
            }
            if error != nil { self.finish(.failure(FoodSourceAcquisitionError.unavailable)) }
            else if complete { self.finish(.success(self.received)) }
            else { self.receive() }
        }
    }
    private func finish(_ result: Result<Data, Error>) {
        guard let pending = continuation else { return }
        continuation = nil; connection.stateUpdateHandler = nil; connection.cancel(); pending.resume(with: result)
    }
}
