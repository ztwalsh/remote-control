import CryptoKit
import Foundation
import Security

/// The TV serves a self-signed certificate. Trust it on first pairing, remember its fingerprint,
/// and refuse anything else afterwards.
final class CertificateTrust: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var pinned: String?

    init(pinnedFingerprint: String?) {
        pinned = pinnedFingerprint
    }

    /// SHA-256 of the TV's certificate, once seen. Store it alongside the client key.
    var fingerprint: String? {
        lock.lock()
        defer { lock.unlock() }
        return pinned
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let seen = Self.leafFingerprint(trust)
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        lock.lock()
        let expected = pinned
        if expected == nil { pinned = seen }
        lock.unlock()

        if expected == nil || expected == seen {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    static func leafFingerprint(_ trust: SecTrust) -> String? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first else {
            return nil
        }
        let data = SecCertificateCopyData(leaf) as Data
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
