// AnalyticsBridge.swift
//
// File-watcher bridge: GDScript (systems/analytics.gd) writes one JSON event
// per line to
//   <Documents>/analytics_events.jsonl
// (Godot's `user://` maps to <App>/Documents on iOS.) This class reads new
// lines on a 1-second timer, forwards each to FirebaseAnalytics, and deletes
// the file once forwarded. Delete-after-forward means a crashed app might
// re-send a few events on relaunch — acceptable for an MVP signal-test vs.
// losing events. A leftover ".processing" file from a prior crash is drained
// first so nothing is lost.
//
// Record shapes (see Analytics.build_record / set_user_property):
//   { "name": "invention_discovered", "params": { "invention_id": "fan", ... } }
//   { "user_property": "<name>", "value": "<string>" }
// Param values are forwarded as String / NSNumber; anything else is stringified.

import Foundation
import FirebaseAnalytics

@objc(AnalyticsBridge)
@objcMembers
final class AnalyticsBridge: NSObject {

    private static let queue = DispatchQueue(label: "com.jfun.tinkerlab.analytics", qos: .utility)
    private static var timer: DispatchSourceTimer?
    private static let pollInterval: DispatchTimeInterval = .seconds(1)

    /// Documents/analytics_events.jsonl — matches Godot's user:// on iOS.
    private static var eventFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("analytics_events.jsonl")
    }

    /// Called from FirebaseBootstrap once the app finishes launching.
    @objc static func start() {
        queue.async {
            if timer != nil { return }
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
            t.setEventHandler { drainEventFile() }
            t.resume()
            timer = t
            NSLog("[AnalyticsBridge] file-watcher started at \(eventFileURL.path)")
        }
    }

    private static func drainEventFile() {
        let url = eventFileURL
        let processingURL = url.appendingPathExtension("processing")

        // Process a leftover .processing file from a prior crash first.
        if FileManager.default.fileExists(atPath: processingURL.path) {
            processFile(at: processingURL)
        }

        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            // Move the live file aside so GDScript can keep appending to a
            // fresh file while we drain this snapshot.
            try FileManager.default.moveItem(at: url, to: processingURL)
        } catch {
            // File likely vanished racing with a GDScript append — retry next tick.
            return
        }
        processFile(at: processingURL)
    }

    private static func processFile(at url: URL) {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        var count = 0
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            guard let lineData = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                NSLog("[AnalyticsBridge] skipping malformed line: \(trimmed)")
                continue
            }
            if let propName = json["user_property"] as? String {
                let value = json["value"] as? String
                Analytics.setUserProperty(value, forName: propName)
            } else if let name = json["name"] as? String {
                let params = (json["params"] as? [String: Any]).map(sanitize) ?? [:]
                Analytics.logEvent(name, parameters: params)
            } else {
                continue
            }
            count += 1
        }
        try? FileManager.default.removeItem(at: url)
        if count > 0 {
            NSLog("[AnalyticsBridge] forwarded \(count) event(s)")
        }
    }

    /// Firebase accepts only NSString / NSNumber values. Coerce everything else.
    private static func sanitize(_ raw: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (k, v) in raw {
            switch v {
            case let s as String: out[k] = s
            case let n as NSNumber: out[k] = n
            case let b as Bool: out[k] = NSNumber(value: b)
            case let i as Int: out[k] = NSNumber(value: i)
            case let d as Double: out[k] = NSNumber(value: d)
            default: out[k] = String(describing: v)
            }
        }
        return out
    }
}
