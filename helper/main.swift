// tidy-helper: groups browser tabs with the on-device Apple Intelligence model.
// stdin:  {"tabs":[{"id":1,"title":"...","host":"..."}], "existing":["Folder name", ...]}
// stdout: {"groups":[{"name":"...","ids":[1,2]}]}
// `tidy-helper --check` prints model availability and exits.
import Foundation
import FoundationModels

struct Tab: Codable { let id: Int; let title: String; let host: String }
struct Input: Codable { let tabs: [Tab]; var existing: [String]? }
struct OutGroup: Codable { let name: String; var ids: [Int] }
struct Output: Codable { let groups: [OutGroup] }

@Generable
struct Labeled {
    var id: Int
    @Guide(description: "What this tab is about: 1-3 words, Title Case, e.g. Tokyo Trip, Headphones, Cooking")
    var topic: String
}

@Generable
struct Labels {
    @Guide(description: "Exactly one entry per tab, in the order given")
    var tabs: [Labeled]
}

@Generable
struct Merge {
    var topic: String
    @Guide(description: "Folder name for this topic; topics about the same thing get the same folder name")
    var folder: String
}

@Generable
struct Merges {
    @Guide(description: "Exactly one entry per topic, in the order given")
    var topics: [Merge]
}

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data((msg + "\n").utf8))
    exit(1)
}

let model = SystemLanguageModel.default
guard case .available = model.availability else { fail("model unavailable: \(model.availability)") }
if CommandLine.arguments.contains("--check") { print("available"); exit(0) }

guard let input = try? JSONDecoder().decode(Input.self, from: FileHandle.standardInput.readDataToEndOfFile())
else { fail("bad input JSON") }

let instructions = """
You organise browser tabs into folders, like a tidy person would. \
A folder is one distinct topic or task, e.g. a trip, a coding project, a product being researched, \
music, cooking.
"""

func log(_ s: String) { if debug { FileHandle.standardError.write(Data((s + "\n").utf8)) } }

// shortcut: ~4k-token context, so at most 40 tabs per labelling call; raise if Apple grows the window.
let maxBatch = 40
let debug = ProcessInfo.processInfo.environment["TIDY_DEBUG"] != nil
let greedy = GenerationOptions(samplingMode: .greedy)
let existingFolders = input.existing ?? []
var topicOf: [Int: String] = [:]

// Pass 1: label every tab with a broad topic. Even-sized batches so no batch is tiny.
let batchCount = max(1, (input.tabs.count + maxBatch - 1) / maxBatch)
let per = (input.tabs.count + batchCount - 1) / max(batchCount, 1)
for start in stride(from: 0, to: input.tabs.count, by: max(per, 1)) {
    let batch = input.tabs[start..<min(start + per, input.tabs.count)]
    let lines = batch.map { "\($0.id) | \($0.host) | \($0.title.prefix(60))" }.joined(separator: "\n")
    let batchIds = Set(batch.map(\.id))
    let labels: [Labeled]
    do {
        labels = try await LanguageModelSession(instructions: instructions).respond(to: """
            Tabs (id | site | title):
            \(lines)

            Give each tab the broad subject a person would file it under, not the page's specific content. \
            Examples: "Butter Chicken recipe" -> Cooking; "tokio::sync - Rust" -> Rust; \
            "Flights to Tokyo" -> Japan Trip; "Sony headphones review" -> Headphones. \
            Use the exact same topic for every tab about the same subject.\(existingFolders.isEmpty ? "" : """
             Existing folders: \(existingFolders.joined(separator: ", ")). \
            Use an existing folder as the topic only if the tab is clearly part of it.
            """)
            """, generating: Labels.self, options: greedy).content.tabs
    } catch { fail("labelling failed: \(error)") }
    for l in labels where batchIds.contains(l.id) { topicOf[l.id] = l.topic.trimmingCharacters(in: .whitespacesAndNewlines) }
    labels.forEach { log("label \($0.id) \($0.topic)") }
}

// Pass 2: one merge over all topics, so batches end up in the same folders.
let topics = Array(Set(topicOf.values.filter { !$0.isEmpty })).sorted()
var folderOf: [String: String] = [:]
if !topics.isEmpty {
    do {
        let merges = try await LanguageModelSession(instructions: instructions).respond(to: """
            Topics: \(topics.joined(separator: ", "))

            Map each topic to a folder. Topics about the same subject must share one folder \
            (e.g. Mortgages and House Hunting -> Home Buying; Neural Networks and LLMs -> Machine Learning). \
            Keep a topic's own name when nothing else is about the same subject.
            """, generating: Merges.self, options: greedy).content.topics
        for m in merges { folderOf[m.topic] = m.folder.trimmingCharacters(in: .whitespacesAndNewlines) }
        merges.forEach { log("merge \($0.topic) -> \($0.folder)") }
    } catch { fail("merging failed: \(error)") }
}

var groups: [String: [Int]] = [:]
var order: [String] = []
var known = existingFolders
for tab in input.tabs {
    guard let topic = topicOf[tab.id], !topic.isEmpty else { continue }
    let name = folderOf[topic].flatMap { $0.isEmpty ? nil : $0 } ?? topic
    // Match names case-insensitively so near-duplicates land in one folder.
    let key = known.first { $0.caseInsensitiveCompare(name) == .orderedSame } ?? name
    if !known.contains(key) { known.append(key) }
    if groups[key] == nil { order.append(key) }
    groups[key, default: []].append(tab.id)
}

// Drop new groups with a single tab, as Arc does.
let existing = Set(existingFolders)
let out = order.compactMap { name -> OutGroup? in
    let ids = groups[name, default: []]
    return ids.count >= 2 || (existing.contains(name) && !ids.isEmpty) ? OutGroup(name: name, ids: ids) : nil
}
FileHandle.standardOutput.write(try JSONEncoder().encode(Output(groups: out)))
