import XCTest
@testable import TokenUsageWidget

final class PricingServiceTests: XCTestCase {
    func testParsingHTMLPricingTable() {
        let html = """
        <html>
        <body>
        <table>
          <thead>
            <tr><th>Model</th><th>Input / MTok</th><th>Output / MTok</th></tr>
          </thead>
          <tbody>
            <tr>
              <td><code>claude-opus-5</code></td>
              <td>$5.00</td>
              <td>$25.00</td>
            </tr>
            <tr>
              <td><code>claude-sonnet-5</code></td>
              <td>$2.00</td>
              <td>$10.00</td>
            </tr>
            <tr>
              <td><code>claude-haiku-4-5</code></td>
              <td>$1.00</td>
              <td>$5.00</td>
            </tr>
          </tbody>
        </table>
        </body>
        </html>
        """
        
        let pricing = PricingParser.parse(content: html)
        XCTAssertEqual(pricing.count, 3)
        XCTAssertEqual(pricing["claude-opus-5"]?.inputPerMillion, 5.0)
        XCTAssertEqual(pricing["claude-opus-5"]?.outputPerMillion, 25.0)
        XCTAssertEqual(pricing["claude-sonnet-5"]?.inputPerMillion, 2.0)
        XCTAssertEqual(pricing["claude-sonnet-5"]?.outputPerMillion, 10.0)
        XCTAssertEqual(pricing["claude-haiku-4-5"]?.inputPerMillion, 1.0)
        XCTAssertEqual(pricing["claude-haiku-4-5"]?.outputPerMillion, 5.0)
    }
    
    func testParsingMarkdownPricingTable() {
        let markdown = """
        # Pricing

        | Model | Input | Output |
        |---|---|---|
        | claude-sonnet-4-6 | $3.00 | $15.00 |
        | claude-sonnet-5 | $2.00 | $10.00 |
        | claude-haiku-4-5 | $1.00 | $5.00 |
        """
        
        let pricing = PricingParser.parse(content: markdown)
        XCTAssertEqual(pricing.count, 3)
        XCTAssertEqual(pricing["claude-sonnet-4-6"]?.inputPerMillion, 3.0)
        XCTAssertEqual(pricing["claude-sonnet-4-6"]?.outputPerMillion, 15.0)
        XCTAssertEqual(pricing["claude-sonnet-5"]?.inputPerMillion, 2.0)
        XCTAssertEqual(pricing["claude-haiku-4-5"]?.inputPerMillion, 1.0)
    }
    
    func testStandardPricingSectionNotOverriddenByBatchSection() {
        // The real page repeats "Claude Sonnet 5" under multiple headings with different prices:
        // "Model pricing" (standard, $2/$10) and "Batch processing" (discounted, $1/$5), in that
        // order. Only the standard section should win — the parser must not let a later,
        // differently-priced table for the same model silently overwrite the standard price.
        let html = """
        <h2>Model pricing</h2>
        <table><tbody>
        <tr><td>Claude Sonnet 5</td><td>$2 / MTok</td><td>$2.50 / MTok</td><td>$4 / MTok</td><td>$0.20 / MTok</td><td>$10 / MTok</td></tr>
        </tbody></table>
        <h2>Batch processing</h2>
        <table><tbody>
        <tr><td>Claude Sonnet 5</td><td>$1 / MTok</td><td>$5 / MTok</td></tr>
        </tbody></table>
        """

        let pricing = PricingParser.parse(content: html)
        XCTAssertEqual(pricing["claude-sonnet-5"]?.inputPerMillion, 2.0)
        XCTAssertEqual(pricing["claude-sonnet-5"]?.outputPerMillion, 10.0)
    }

    func testParsingRealPricingPageDisplayNames() {
        // Real row structure captured from platform.claude.com/docs/en/about-claude/pricing
        // on 2026-08-20 — the live page uses human-readable display names ("Claude Sonnet 5"),
        // not machine-readable slugs, in the table cells themselves. This regressed the parser
        // silently in production (every message showed as "unrecognized model") because the
        // fixtures above never exercised this real-world format.
        let html = """
        <table><tbody>
        <tr class="border-b-0.5 last:border-b-0"><td class="p-2 first:pl-0 last:pr-0 text-secondary">Claude Sonnet 5</td><td class="p-2 first:pl-0 last:pr-0 text-secondary">$2 / MTok</td><td class="p-2 first:pl-0 last:pr-0 text-secondary">$2.50 / MTok</td><td class="p-2 first:pl-0 last:pr-0 text-secondary">$4 / MTok</td><td class="p-2 first:pl-0 last:pr-0 text-secondary">$0.20 / MTok</td><td class="p-2 first:pl-0 last:pr-0 text-secondary">$10 / MTok</td></tr>
        <tr class="border-b-0.5 last:border-b-0"><td class="p-2 first:pl-0 last:pr-0 text-secondary">Claude Haiku 4.5</td><td class="p-2 first:pl-0 last:pr-0 text-secondary">$1 / MTok</td><td class="p-2 first:pl-0 last:pr-0 text-secondary">$5 / MTok</td></tr>
        </tbody></table>
        """

        let pricing = PricingParser.parse(content: html)
        // Sonnet 5's row has 5 numeric columns (input, 5m write, 1h write, cache read, output) —
        // input must come from the first column and output from the last, not the second.
        XCTAssertEqual(pricing["claude-sonnet-5"]?.inputPerMillion, 2.0)
        XCTAssertEqual(pricing["claude-sonnet-5"]?.outputPerMillion, 10.0)
        XCTAssertEqual(pricing["claude-haiku-4-5"]?.inputPerMillion, 1.0)
        XCTAssertEqual(pricing["claude-haiku-4-5"]?.outputPerMillion, 5.0)
    }

    func testCostMultipliers() {
        let sonnetPricing = ModelPricing(inputPerMillion: 2.0, outputPerMillion: 10.0)
        
        // 1 Million of each token type:
        let counts = TokenCounts(
            input: 1_000_000,
            output: 1_000_000,
            cacheRead: 1_000_000,
            cacheCreation5m: 1_000_000,
            cacheCreation1h: 1_000_000
        )
        
        let totalCost = CostCalculator.calculateCost(counts: counts, pricing: sonnetPricing)
        
        // input: 2.0
        // output: 10.0
        // cacheRead: 2.0 * 0.1 = 0.20
        // cacheWrite5m: 2.0 * 1.25 = 2.50
        // cacheWrite1h: 2.0 * 2.0 = 4.00
        // Total = 2.0 + 10.0 + 0.20 + 2.50 + 4.00 = 18.70
        XCTAssertEqual(totalCost, 18.70, accuracy: 0.0001)
    }
    
    func testModelPrefixMatching() {
        let snapshot = PricingSnapshot(
            lastFetchedAt: Date(),
            prices: [
                "claude-haiku-4-5": ModelPricing(inputPerMillion: 1.0, outputPerMillion: 5.0),
                "claude-sonnet-5": ModelPricing(inputPerMillion: 2.0, outputPerMillion: 10.0)
            ]
        )
        
        // Exact match
        let exact = CostCalculator.matchPricing(for: "claude-sonnet-5", in: snapshot)
        XCTAssertNotNil(exact)
        XCTAssertEqual(exact?.modelKey, "claude-sonnet-5")
        
        // Date suffix match
        let withDate = CostCalculator.matchPricing(for: "claude-haiku-4-5-20251001", in: snapshot)
        XCTAssertNotNil(withDate)
        XCTAssertEqual(withDate?.modelKey, "claude-haiku-4-5")
        
        // Unknown model
        let unknown = CostCalculator.matchPricing(for: "claude-unknown-model", in: snapshot)
        XCTAssertNil(unknown)
    }
}
