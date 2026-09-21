import NerveHubClient
import SwiftUI
import TetherPluginKit

@MainActor
@Observable
final class NerveWorkspace: PluginWorkspace {
  let id = UUID()
  let session: HubSession
  let hostLabel: String
  let symbol = "waveform.path.ecg"
  var title: String { "Nerve" }
  var subtitle: String { hostLabel }

  init(session: HubSession, hostLabel: String) {
    self.session = session
    self.hostLabel = hostLabel
  }

  var commands: [PluginCommand] {
    [
      PluginCommand(id: "refresh", title: "Reconnect", symbol: "arrow.clockwise") {
        [weak self] in
        self?.session.reconnect()
      }
    ]
  }

  func content() -> AnyView { AnyView(NerveJobList(session: session, hostLabel: hostLabel)) }
  func inspector() -> AnyView { AnyView(NerveInspector(session: session)) }
  func close() {}
}

struct NerveJobList: View {
  @Bindable var session: HubSession
  var hostLabel: String

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      statusBar
      Divider()
      if !session.connected && visible.isEmpty {
        empty(session.hubError == nil ? "Connecting to the hub" : "Hub offline")
      } else if visible.isEmpty {
        empty("No jobs")
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(visible) { job in
              jobRow(job)
              Divider().padding(.leading, 44)
            }
          }
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var statusBar: some View {
    HStack(spacing: 8) {
      Circle()
        .fill(session.connected ? Color.green.opacity(0.85) : Color.secondary.opacity(0.5))
        .frame(width: 7, height: 7)
      Text(session.connected ? "Live" : "Offline")
      Spacer(minLength: 8)
      Text("\(visible.count)")
        .monospacedDigit()
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
  }

  private func empty(_ title: String) -> some View {
    VStack(spacing: 8) {
      Spacer(minLength: 24)
      Image(systemName: "waveform.path.ecg")
        .font(.system(size: 28, weight: .light))
        .foregroundStyle(.tertiary)
      Text(title).font(.callout).foregroundStyle(.secondary)
      if let error = session.hubError, !error.isEmpty {
        Text(error).font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
          .frame(maxWidth: 420)
      }
      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(24)
  }

  private func jobRow(_ job: NerveJob) -> some View {
    HStack(alignment: .center, spacing: 10) {
      Circle()
        .fill(color(for: job))
        .frame(width: 8, height: 8)
        .frame(width: 18, height: 18)
      VStack(alignment: .leading, spacing: 2) {
        Text(job.name.isEmpty ? job.id : job.name)
          .font(.body.weight(.medium))
          .lineLimit(1)
        if !job.progress.isEmpty {
          Text(job.progress)
            .font(.callout)
            .foregroundStyle(job.isAsk ? Color.orange : Color.secondary)
            .lineLimit(2)
        }
      }
      Spacer(minLength: 8)
      Text(job.alias)
        .font(.caption)
        .foregroundStyle(.tertiary)
        .lineLimit(1)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
  }

  private var visible: [NerveJob] {
    let jobs = session.jobs
    let host = hostLabel.trimmingCharacters(in: .whitespaces)
    guard !host.isEmpty else { return jobs }
    let matches = jobs.filter {
      $0.alias.caseInsensitiveCompare(host) == .orderedSame
        || $0.alias.localizedCaseInsensitiveContains(host)
        || host.localizedCaseInsensitiveContains($0.alias)
    }
    return matches.isEmpty ? jobs : matches
  }

  private func color(for job: NerveJob) -> Color {
    if job.isAsk { return .orange }
    switch job.lifecycle {
    case "ended": return .green
    case "active":
      switch job.currentType.lowercased() {
      case "waiting": return .orange
      case "idle", "starting", "booting": return .secondary
      default: return .blue
      }
    default: return .secondary
    }
  }
}

struct NerveInspector: View {
  @Bindable var session: HubSession

  var body: some View {
    Form {
      Section("Hub") {
        LabeledContent("Stream", value: session.connected ? "Connected" : "Offline")
        if let error = session.hubError {
          LabeledContent("Hub", value: error)
        }
        LabeledContent("Jobs", value: String(session.jobs.count))
        LabeledContent("Owner", value: session.notify.owner ?? "—")
      }
      if !session.jobs.isEmpty {
        Section("Now") {
          ForEach(session.jobs) { job in
            VStack(alignment: .leading, spacing: 2) {
              Text(job.name.isEmpty ? job.id : job.name)
              if !job.progress.isEmpty {
                Text(job.progress).foregroundStyle(.secondary)
              }
            }
          }
        }
      }
    }
    .formStyle(.grouped)
  }
}

struct NerveSettings: View {
  @Bindable var session: HubSession

  var body: some View {
    Picker("Banners", selection: policy) {
      Text("One").tag("single")
      Text("All").tag("all")
    }
    .pickerStyle(.segmented)
  }

  private var policy: Binding<String> {
    Binding(
      get: { session.notify.policy == .all ? "all" : "single" },
      set: { session.setPolicy($0) }
    )
  }
}
