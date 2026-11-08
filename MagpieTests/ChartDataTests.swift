import Foundation
import SwiftUI
import Testing

@testable import Magpie

/// 三个模型、两天：A 最多，B 次之，C 只在第一天出现过一次。
private let ledgerJSON = """
    {"period":"7d","bucket":"day","total":0,"rows":[],
     "calls":10,"errors":1,"input":600,"cost":1.0,
     "series":[
       {"label":"Nov 7","time":"2026-11-07T00:00:00Z","calls":4,"input":300,"cost":0.4,
        "by":{"model":{"a":{"calls":2,"tokens":200,"cost":0.3},
                       "b":{"calls":1,"tokens":50,"cost":0.05},
                       "c":{"calls":1,"tokens":50,"cost":0.05}}}},
       {"label":"Nov 8","time":"2026-11-08T00:00:00Z","calls":6,"input":300,"cost":0.6,
        "by":{"model":{"a":{"calls":3,"tokens":100,"cost":0.2},
                       "b":{"calls":3,"tokens":200,"cost":0.4}}}}],
     "by":{"model":[{"id":"a","name":"A","calls":5,"input":300,"cost":0.5},
                    {"id":"b","name":"B","calls":4,"input":250,"cost":0.45},
                    {"id":"c","name":"C","calls":1,"input":50,"cost":0.05}]}}
    """

@Suite struct ChartDataTests {
    private func ledger() throws -> RequestLedger {
        try MagpieJSON.decoder().decode(RequestLedger.self, from: Data(ledgerJSON.utf8))
    }

    @Test func leadersFollowTheMetric() throws {
        let ledger = try ledger()
        #expect(
            ChartData.leaders(in: ledger, by: .model, metric: .tokens).map(\.id) == ["a", "b", "c"])
        #expect(
            ChartData.leaders(in: ledger, by: .model, metric: .calls, keep: 1).map(\.id) == ["a"])
        #expect(ChartData.leaders(in: ledger, by: .agent, metric: .tokens).isEmpty)
    }

    @Test func restBecomesOtherOnlyWhenThereIsSome() throws {
        let ledger = try ledger()
        #expect(
            ChartData.names(in: ledger, by: .model, metric: .tokens, keep: 2) == ["A", "B", "其他"])
        // 三个都放得下，没有剩余，就没有「其他」。
        #expect(ChartData.names(in: ledger, by: .model, metric: .tokens) == ["A", "B", "C"])
    }

    @Test func stacksSplitEachBucketIntoLeadersAndRest() throws {
        let stacks = ChartData.stacks(in: try ledger(), by: .model, metric: .tokens, keep: 2)
        let nov7 = stacks.filter { $0.label == "Nov 7" }.map { ($0.name, $0.value) }
        #expect(nov7.map(\.0) == ["A", "B", "其他"])
        #expect(nov7.map(\.1) == [200, 50, 50])
        // 第二天 A 和 B 就是全部，没有「其他」这一段。
        let nov8 = stacks.filter { $0.label == "Nov 8" }.map { ($0.name, $0.value) }
        #expect(nov8.map(\.0) == ["A", "B"])
        #expect(nov8.map(\.1) == [100, 200])
    }

    @Test func slicesAreFractionsOfTheWholePeriod() throws {
        let slices = ChartData.slices(in: try ledger(), by: .model, metric: .calls, keep: 2)
        #expect(slices.map(\.name) == ["A", "B", "其他"])
        #expect(slices.map(\.value) == [5, 4, 1])
        #expect(abs(slices[0].fraction - 0.5) < 0.0001)
        #expect(abs(slices[2].fraction - 0.1) < 0.0001)
    }

    @Test func noUsageMeansNoSlices() throws {
        let json = """
            {"period":"today","bucket":"hour","calls":0,"series":[],"by":{"model":[]}}
            """
        let ledger = try MagpieJSON.decoder().decode(RequestLedger.self, from: Data(json.utf8))
        #expect(ChartData.slices(in: ledger, by: .model, metric: .tokens).isEmpty)
        #expect(ChartData.stacks(in: ledger, by: .model, metric: .tokens).isEmpty)
        #expect(ledger.bucket == .hour)
    }

    @Test(arguments: [
        (6, [0, 1, 2, 3, 4, 5]),
        (7, [0, 1, 2, 3, 4, 5, 6]),
        (8, [1, 3, 5, 7]),
        (24, [3, 7, 11, 15, 19, 23]),
        (30, [4, 9, 14, 19, 24, 29]),
        (13, [0, 2, 4, 6, 8, 10, 12]),
    ])
    func axisShowsAtMostSevenLabelsEndingWithTheLatest(count: Int, shown: [Int]) {
        let labels = (0..<count).map(String.init)
        #expect(ChartData.axisLabels(labels) == shown.map(String.init))
    }

    @Test func otherIsAlwaysGrayAndTheRestDiffer() {
        let names = ["A", "B", ChartData.otherName, "C"]
        let colors = ChartData.colors(for: names)
        #expect(colors.count == 4)
        #expect(colors[2] == Color.gray.opacity(0.6))
        #expect(colors[3] == ChartData.palette[2])
        #expect(ChartData.color(of: "B", in: names) == ChartData.palette[1])
    }
}
