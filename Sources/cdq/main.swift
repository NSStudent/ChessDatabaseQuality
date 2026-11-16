//
//  main.swift
//  cdq
//
//  cdq analyze <file.pgn> [--out <dir>] [--threads N]
//  cdq fabricate <source.pgn> <out.pgn> [--games N] [--seed S]
//

import ChessDatabaseQuality
import Foundation

func usage() -> Never {
    FileHandle.standardError.write(Data("""
    usage:
      cdq analyze <file.pgn> [--out <dir>] [--threads N]
      cdq fabricate <source.pgn> <out.pgn> [--games N] [--seed S]
      cdq players <file.pgn> [--out aliases.json]   (tags only: player aliases)

    """.utf8))
    exit(2)
}

var arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { usage() }
arguments.removeFirst()

@MainActor func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    let value = arguments[index + 1]
    arguments.removeSubrange(index...(index + 1))
    return value
}

switch command {
case "analyze":
    let out = option("--out")
    let threads = option("--threads").flatMap(Int.init)
    guard let path = arguments.first else { usage() }
    var options = QualityOptions()
    if let threads { options.concurrency = threads }
    let url = URL(fileURLWithPath: path)
    let analysis = try await DatabaseQualityAnalyzer(options: options).analyze(fileAt: url) { progress in
        let percent = progress.totalBytes > 0 ? Double(progress.bytesRead) * 100 / Double(progress.totalBytes) : 0
        FileHandle.standardError.write(Data(String(format: "\r%@ %5.1f %% %d partidas   ", progress.phase.rawValue, percent, progress.gamesRead).utf8))
    }
    FileHandle.standardError.write(Data("\n".utf8))
    let markdown = analysis.report.markdown()
    if let out {
        let directory = URL(fileURLWithPath: out)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(markdown.utf8).write(to: directory.appendingPathComponent("report.md"))
        try analysis.report.json().write(to: directory.appendingPathComponent("report.json"))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(analysis.duplicateGroups).write(to: directory.appendingPathComponent("duplicates.json"))
        try encoder.encode(analysis.aliasProposals).write(to: directory.appendingPathComponent("aliases.json"))
        print("Informe en \(directory.path)")
    }
    print(markdown)
    let truthURL = url.appendingPathExtension("truth.json")
    if let data = try? Data(contentsOf: truthURL), let truth = try? JSONDecoder().decode(FabricationTruth.self, from: data) {
        let evaluation = truth.evaluate(groups: analysis.duplicateGroups)
        print("\n## Evaluación contra lo plantado\n\n\(evaluation)")
        for item in evaluation.missed.prefix(20) { print("- no encontrada: \(item.kind) #\(item.original) / #\(item.copy)") }
    }
case "fabricate":
    let games = option("--games").flatMap(Int.init) ?? 300
    let seed = option("--seed").flatMap(UInt64.init) ?? 42
    guard arguments.count >= 2 else { usage() }
    var fabricator = Fabricator(seed: seed)
    let truth = try fabricator.fabricate(
        source: URL(fileURLWithPath: arguments[0]), output: URL(fileURLWithPath: arguments[1]), games: games
    )
    print(truth)
case "players":
    let out = option("--out")
    guard let path = arguments.first else { usage() }
    let clock = ContinuousClock()
    let start = clock.now
    var directory = PlayerDirectory()
    var tags: [String: String] = [:]
    var games = 0
    func flush() {
        guard !tags.isEmpty else { return }
        games += 1
        let year = PGNDate(tags["Date"]).year
        for side in ["White", "Black"] {
            directory.observe(
                PlayerName(tags[side] ?? ""),
                fideID: tags[side + "FideId"].flatMap { Int($0) }.flatMap { $0 > 0 ? $0 : nil },
                elo: tags[side + "Elo"].flatMap { Int($0) }.flatMap { (1000...2900).contains($0) ? $0 : nil },
                year: year
            )
        }
        tags = [:]
    }
    let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
    var pending = Data()
    while let block = try handle.read(upToCount: 4 << 20), !block.isEmpty {
        pending.append(block)
        guard let last = pending.lastIndex(of: 0x0A) else { continue }
        let text = String(decoding: pending[pending.startIndex...last], as: UTF8.self)
        pending = Data(pending[(last + 1)...])
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) where line.first == "[" {
            guard let space = line.firstIndex(of: " "), let open = line.firstIndex(of: "\""), let close = line.lastIndex(of: "\""), open < close else { continue }
            let name = String(line[line.index(after: line.startIndex)..<space])
            if name == "Event" { flush() }
            tags[name] = String(line[line.index(after: open)..<close])
        }
    }
    flush()
    let read = clock.now
    let proposals = directory.aliasProposals()
    let done = clock.now
    var counts: [AliasConfidence: Int] = [:]
    for proposal in proposals { counts[proposal.confidence, default: 0] += 1 }
    print("partidas \(games), grafías \(directory.variantCount), lectura \(read - start), alias \(done - read)")
    print(AliasConfidence.allCases.map { "\($0.rawValue) \(counts[$0] ?? 0)" }.joined(separator: ", "))
    if let out {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(proposals).write(to: URL(fileURLWithPath: out))
    }
default:
    usage()
}
