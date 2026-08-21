import XCTest
@testable import TokenUsageWidget

final class TranscriptParserTests: XCTestCase {
    func testParseValidAssistantLineWithCacheCreationObject() {
        let json = """
        {
          "type": "assistant",
          "timestamp": "2026-08-07T21:44:37.953Z",
          "message": {
            "id": "msg_01",
            "model": "claude-sonnet-5",
            "usage": {
              "input_tokens": 4,
              "output_tokens": 118,
              "cache_creation_input_tokens": 1573,
              "cache_read_input_tokens": 20241,
              "cache_creation": { "ephemeral_5m_input_tokens": 1573, "ephemeral_1h_input_tokens": 0 }
            }
          }
        }
        """
        
        let data = json.data(using: .utf8)!
        let record = TranscriptParser.parseLine(data: data, filePath: "test.jsonl", lineNumber: 1)
        
        XCTAssertNotNil(record)
        XCTAssertEqual(record?.messageID, "msg_01")
        XCTAssertEqual(record?.model, "claude-sonnet-5")
        XCTAssertEqual(record?.counts.input, 4)
        XCTAssertEqual(record?.counts.output, 118)
        XCTAssertEqual(record?.counts.cacheRead, 20241)
        XCTAssertEqual(record?.counts.cacheCreation5m, 1573)
        XCTAssertEqual(record?.counts.cacheCreation1h, 0)
        XCTAssertEqual(record?.counts.cacheCreationTotal, 1573)
    }
    
    func testParseLegacyCacheCreationWithoutObject() {
        let json = """
        {
          "type": "assistant",
          "timestamp": "2026-08-07T21:44:37Z",
          "message": {
            "id": "msg_02",
            "model": "claude-haiku-4-5",
            "usage": {
              "input_tokens": 10,
              "output_tokens": 20,
              "cache_creation_input_tokens": 50,
              "cache_read_input_tokens": 100
            }
          }
        }
        """
        
        let data = json.data(using: .utf8)!
        let record = TranscriptParser.parseLine(data: data, filePath: "test.jsonl", lineNumber: 2)
        
        XCTAssertNotNil(record)
        XCTAssertEqual(record?.counts.cacheCreation5m, 50)
        XCTAssertEqual(record?.counts.cacheCreation1h, 0)
    }
    
    func testSkipNonAssistantLine() {
        let json = """
        {
          "type": "user",
          "timestamp": "2026-08-07T21:44:37Z",
          "message": { "id": "msg_user" }
        }
        """
        let data = json.data(using: .utf8)!
        let record = TranscriptParser.parseLine(data: data, filePath: "test.jsonl", lineNumber: 3)
        XCTAssertNil(record)
    }
    
    func testSkipSyntheticModelLine() {
        let json = """
        {
          "type": "assistant",
          "timestamp": "2026-08-07T21:44:37Z",
          "message": {
            "id": "msg_synth",
            "model": "<synthetic>",
            "usage": { "input_tokens": 0, "output_tokens": 0 }
          }
        }
        """
        let data = json.data(using: .utf8)!
        let record = TranscriptParser.parseLine(data: data, filePath: "test.jsonl", lineNumber: 4)
        XCTAssertNil(record, "Synthetic model lines must be skipped")
    }
    
    func testHandleMalformedJSONLineSafely() {
        let badJSON = "this is not valid json at all!"
        let data = badJSON.data(using: .utf8)!
        let record = TranscriptParser.parseLine(data: data, filePath: "corrupted.jsonl", lineNumber: 5)
        XCTAssertNil(record, "Malformed JSON lines must fail gracefully without throwing fatal errors")
    }
}
