import Testing
@testable import ChaoxingSignFakerIOS

struct SignQRCodeParsingTests {
    @Test func parsesURLQRCode() throws {
        let result = try ParsedSignQRCode("https://mobilelearn.chaoxing.com/newsign?aid=123&c=456&enc=a%2Bb")
        #expect(result.activeID == 123)
        #expect(result.code == "456")
        #expect(result.enc == "a+b")
    }

    @Test func parsesSignInQRCode() throws {
        let result = try ParsedSignQRCode("SIGNIN:id=123&c=456&enc=token-123")
        #expect(result.activeID == 123)
        #expect(result.code == "456")
        #expect(result.enc == "token")
    }

    @Test func rejectsMissingToken() {
        #expect(throws: Error.self) { try ParsedSignQRCode("https://example.com/?aid=123") }
    }
}
