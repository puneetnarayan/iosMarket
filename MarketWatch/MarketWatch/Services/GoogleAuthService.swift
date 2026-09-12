import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

/// Signs in to a Google account using the standard OAuth 2.0 "installed app" flow with
/// PKCE (Authorization Code + Proof Key for Code Exchange), driven entirely by Apple's
/// own AuthenticationServices framework rather than Google's GoogleSignIn-iOS SDK — this
/// avoids depending on a third-party SDK whose exact API surface may have moved on from
/// what's described here. The flow itself (accounts.google.com/o/oauth2/v2/auth ->
/// oauth2.googleapis.com/token, custom URL scheme redirect using the reversed OAuth
/// client ID) is Google's long-standing documented pattern for iOS/desktop apps — verify
/// it against Google's current "OAuth 2.0 for Mobile & Desktop Apps" docs if sign-in
/// starts failing, since the requirements around `access_type`/`prompt` or scopes can
/// change independently of this code.
///
/// Requires an iOS OAuth client ID from Google Cloud Console (see README) supplied via
/// the "GoogleOAuthClientID" Info.plist key, and a matching URL scheme (the client ID's
/// "reversed" form) registered in CFBundleURLTypes — both wired through project.yml.
@MainActor
final class GoogleAuthService: NSObject, ObservableObject {
    static let shared = GoogleAuthService()

    @Published private(set) var isSignedIn: Bool

    private let clientID: String
    private let redirectScheme: String
    private let scope = "https://www.googleapis.com/auth/spreadsheets"
    private static let refreshTokenKey = "GoogleOAuthRefreshToken"

    private var accessToken: String?
    private var accessTokenExpiry: Date?
    private var webAuthSession: ASWebAuthenticationSession?

    private override init() {
        let clientID = Bundle.main.object(forInfoDictionaryKey: "GoogleOAuthClientID") as? String ?? ""
        self.clientID = clientID

        let suffix = ".apps.googleusercontent.com"
        if clientID.hasSuffix(suffix) {
            let prefix = String(clientID.dropLast(suffix.count))
            self.redirectScheme = "com.googleusercontent.apps.\(prefix)"
        } else {
            self.redirectScheme = ""
        }

        self.isSignedIn = KeychainHelper.load(forKey: Self.refreshTokenKey) != nil
    }

    var isConfigured: Bool { !clientID.isEmpty && !redirectScheme.isEmpty }

    func signIn() async throws {
        guard isConfigured else { throw GoogleAuthError.notConfigured }

        let verifier = Self.randomURLSafeString(length: 64)
        let challenge = Self.codeChallenge(for: verifier)

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: "\(redirectScheme):/oauth2redirect"),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]

        let callbackURL = try await presentAuthSession(url: components.url!)

        guard
            let returnedComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
            let code = returnedComponents.queryItems?.first(where: { $0.name == "code" })?.value
        else {
            throw GoogleAuthError.missingCode
        }

        try await exchangeCodeForTokens(code: code, verifier: verifier)
        isSignedIn = true
    }

    func signOut() {
        accessToken = nil
        accessTokenExpiry = nil
        KeychainHelper.delete(forKey: Self.refreshTokenKey)
        isSignedIn = false
    }

    /// Returns a currently-valid access token, refreshing it first if it has expired.
    func validAccessToken() async throws -> String {
        if let token = accessToken, let expiry = accessTokenExpiry, expiry > Date().addingTimeInterval(60) {
            return token
        }
        try await refreshAccessToken()
        guard let token = accessToken else { throw GoogleAuthError.notSignedIn }
        return token
    }

    private func presentAuthSession(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: redirectScheme) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: error ?? GoogleAuthError.cancelled)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            webAuthSession = session
            session.start()
        }
    }

    private func exchangeCodeForTokens(code: String, verifier: String) async throws {
        let params = [
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier,
            "redirect_uri": "\(redirectScheme):/oauth2redirect",
            "grant_type": "authorization_code"
        ]
        let decoded: TokenResponse = try await Self.postForm(params)

        accessToken = decoded.access_token
        accessTokenExpiry = Date().addingTimeInterval(TimeInterval(decoded.expires_in))
        if let refreshToken = decoded.refresh_token {
            KeychainHelper.save(refreshToken, forKey: Self.refreshTokenKey)
        }
    }

    private func refreshAccessToken() async throws {
        guard let refreshToken = KeychainHelper.load(forKey: Self.refreshTokenKey) else {
            throw GoogleAuthError.notSignedIn
        }
        let params = [
            "client_id": clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        let decoded: TokenResponse = try await Self.postForm(params)
        accessToken = decoded.access_token
        accessTokenExpiry = Date().addingTimeInterval(TimeInterval(decoded.expires_in))
    }

    private static func postForm<T: Decodable>(_ params: [String: String]) async throws -> T {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncode(params)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw GoogleAuthError.requestFailed
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func formEncode(_ params: [String: String]) -> Data {
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&="))
        let pairs = params.map { key, value -> String in
            let escapedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let escapedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(escapedKey)=\(escapedValue)"
        }
        return Data(pairs.joined(separator: "&").utf8)
    }

    private static func randomURLSafeString(length: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func codeChallenge(for verifier: String) -> String {
        let hashed = SHA256.hash(data: Data(verifier.utf8))
        return Data(hashed).base64URLEncodedString()
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let expires_in: Int
        let refresh_token: String?
    }
}

extension GoogleAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum GoogleAuthError: LocalizedError {
    case notConfigured
    case cancelled
    case missingCode
    case notSignedIn
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Add a Google OAuth client ID in project.yml first (see README)."
        case .cancelled: return "Sign-in was cancelled."
        case .missingCode: return "Google didn't return an authorization code."
        case .notSignedIn: return "Not signed in to Google."
        case .requestFailed: return "The request to Google failed."
        }
    }
}
