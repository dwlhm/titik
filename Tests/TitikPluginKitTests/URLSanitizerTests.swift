import Foundation
import Testing
@testable import TitikPluginKit

@Suite("URL Sanitizer Tests")
struct URLSanitizerTests {

    @Test("Valid HTTPS URLs are allowed")
    func test_urlSanitizer_httpsURL_allowed() {
        let safe = "https://images.unsplash.com/photo-12345?w=800"
        let result = URLSanitizer.sanitize(safe)
        #expect(result != nil)
        #expect(result?.scheme == "https")
        #expect(result?.host == "images.unsplash.com")
    }

    @Test("Malicious schemes like file, applescript, terminal, and javascript are blocked")
    func test_urlSanitizer_maliciousSchemes_file_applescript_terminal_blocked() {
        let maliciousURLs = [
            "file:///etc/passwd",
            "applescript://do_shell_script",
            "terminal://rm%20-rf",
            "javascript:alert(document.cookie)",
            "data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==",
            "blob:https://example.com/uuid",
            "vbscript:msgbox"
        ]

        for badURL in maliciousURLs {
            let sanitized = URLSanitizer.sanitize(badURL)
            #expect(sanitized == nil, "Failed to block dangerous scheme: \(badURL)")
            if let url = URL(string: badURL) {
                #expect(!URLSanitizer.isSafeURL(url), "Failed to detect unsafe URL: \(badURL)")
            }
        }
    }
}
