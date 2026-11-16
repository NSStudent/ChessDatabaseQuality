//
//  QualityReport.swift
//  ChessDatabaseQuality
//

import Foundation

/// The figures and examples of one analysis, ready to show or store as JSON.
public struct QualityReport: Sendable, Codable {
    public struct Timings: Sendable, Codable {
        public var scan: Double
        public var duplicates: Double
        public var aliases: Double
        public var report: Double
        public var total: Double
    }

    public struct DuplicateExample: Sendable, Codable {
        public struct Game: Sendable, Codable {
            public var id: Int64
            public var relation: String
            public var white: String
            public var black: String
            public var event: String
            public var date: String
            public var result: String
            public var plyCount: String?
        }

        public var kind: String
        public var games: [Game]
        public var proposal: MergeProposal
    }

    public var source: String
    public var fileBytes: Int64
    public var games: Int
    public var timings: Timings
    public var peakMemoryBytes: UInt64
    public var concurrency: Int
    public var health: HealthReport
    public var duplicates: DuplicateStatistics
    public var duplicateExamples: [DuplicateExample]
    public var playerVariants: Int
    public var aliasCounts: [String: Int]
    public var aliasExamples: [AliasProposal]

    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// The «salud de la base» report in Markdown (Spanish).
    public func markdown() -> String {
        func number(_ value: Int) -> String {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.locale = Locale(identifier: "es_ES")
            formatter.usesGroupingSeparator = true
            return formatter.string(from: NSNumber(value: value)) ?? String(value)
        }
        func percent(_ part: Int, _ total: Int) -> String {
            total == 0 ? "0 %" : String(format: "%.2f %%", Double(part) * 100 / Double(total)).replacingOccurrences(of: ".", with: ",")
        }
        func seconds(_ value: Double) -> String { String(format: "%.1f s", value).replacingOccurrences(of: ".", with: ",") }
        func escape(_ text: String) -> String { text.replacingOccurrences(of: "|", with: "\\|") }

        var lines: [String] = []
        lines.append("# Salud de la base: \(source)")
        lines.append("")
        lines.append("| Medida | Valor |")
        lines.append("|---|---|")
        lines.append("| Partidas leídas | \(number(games)) |")
        lines.append("| Tamaño | \(String(format: "%.1f", Double(fileBytes) / 1_048_576).replacingOccurrences(of: ".", with: ",")) MB |")
        lines.append("| Tiempo total | \(seconds(timings.total)) (lectura y validación \(seconds(timings.scan)), duplicados \(seconds(timings.duplicates)), alias \(seconds(timings.aliases)), informe \(seconds(timings.report))) |")
        lines.append("| Memoria máxima (RSS) | \(peakMemoryBytes / 1_048_576) MB |")
        lines.append("| Hilos | \(concurrency) |")
        lines.append("| Partidas sin problemas | \(number(health.cleanGames)) (\(percent(health.cleanGames, games))) |")
        lines.append("| Saltadas (ilegibles) | \(number(health.skippedGames)) |")
        lines.append("| Cortadas por jugada ilegal | \(number(health.truncatedGames)) |")
        lines.append("")

        lines.append("## Validación")
        lines.append("")
        lines.append("| Problema | Gravedad | Partidas | % |")
        lines.append("|---|---|---|---|")
        for entry in health.sortedEntries {
            lines.append("| \(entry.kind.title) | \(entry.kind.severity.rawValue) | \(number(entry.games)) | \(percent(entry.games, games)) |")
        }
        lines.append("")
        for entry in health.sortedEntries {
            lines.append("### \(entry.kind.title)")
            lines.append("")
            for example in entry.examples {
                lines.append("- #\(example.gameIndex) (byte \(example.byteOffset)) \(example.label): \(example.detail)")
            }
            lines.append("")
        }

        lines.append("## Duplicados")
        lines.append("")
        lines.append("| Tipo | Partidas a eliminar |")
        lines.append("|---|---|")
        lines.append("| Exactos | \(number(duplicates.exact)) |")
        lines.append("| Subsumidos | \(number(duplicates.subsumed)) |")
        lines.append("| Casi duplicados (posición en la ply 40 o final) | \(number(duplicates.nearByPosition)) |")
        lines.append("| Casi duplicados (MinHash) | \(number(duplicates.nearByMinHash)) |")
        lines.append("| **Grupos** | **\(number(duplicates.groups))** |")
        lines.append("")
        lines.append("Partidas con firma MinHash: \(number(duplicates.gamesWithSignature)); pares candidatos LSH verificados: \(number(duplicates.lshCandidatePairs)); cubos LSH descartados por grandes: \(number(duplicates.lshSkippedBuckets)).")
        lines.append("")
        for example in duplicateExamples {
            lines.append("### Ejemplo: \(example.kind)")
            lines.append("")
            lines.append("| # | Relación | Blancas | Negras | Evento | Fecha | Resultado | PlyCount |")
            lines.append("|---|---|---|---|---|---|---|---|")
            for game in example.games {
                lines.append("| \(game.id) | \(game.relation) | \(escape(game.white)) | \(escape(game.black)) | \(escape(game.event)) | \(game.date) | \(game.result) | \(game.plyCount ?? "") |")
            }
            lines.append("")
            let improved = example.proposal.improvedTags
            lines.append("Propuesta: conservar #\(example.proposal.keeper), eliminar \(example.proposal.remove.map { "#\($0)" }.joined(separator: ", "))"
                + (improved.isEmpty ? "." : "; etiquetas tomadas de otra partida: \(improved.joined(separator: ", ")).")
            )
            for conflict in example.proposal.conflicts {
                lines.append("- Conflicto en \(conflict.name): \(conflict.values.map { "«\($0)»" }.joined(separator: " / "))")
            }
            lines.append("")
        }

        lines.append("## Jugadores")
        lines.append("")
        lines.append("Grafías distintas: \(number(playerVariants)).")
        lines.append("")
        lines.append("| Confianza | Propuestas de alias |")
        lines.append("|---|---|")
        for confidence in AliasConfidence.allCases {
            lines.append("| \(confidence.rawValue) | \(number(aliasCounts[confidence.rawValue] ?? 0)) |")
        }
        lines.append("")
        if !aliasExamples.isEmpty {
            lines.append("| Confianza | Canónica | Alias | Motivos |")
            lines.append("|---|---|---|---|")
            for proposal in aliasExamples {
                func describe(_ variant: PlayerVariant) -> String {
                    var text = escape(variant.rawSamples.first ?? variant.normalized) + " (\(variant.games)"
                    if !variant.fideIDs.isEmpty { text += ", FIDE \(variant.fideIDs.map(String.init).joined(separator: "/"))" }
                    if let low = variant.eloMin, let high = variant.eloMax { text += ", \(low)–\(high)" }
                    return text + ")"
                }
                lines.append("| \(proposal.confidence.rawValue) | \(describe(proposal.canonical)) | \(describe(proposal.alias)) | \(escape(proposal.reasons.joined(separator: "; "))) |")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
