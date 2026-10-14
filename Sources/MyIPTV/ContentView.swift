
import SwiftUI
import AVKit
import UniformTypeIdentifiers

struct Channel: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var group: String
    var url: String
}

struct ContentView: View {
    @AppStorage("playlistJSON") private var playlistJSON = "[]"

    @State private var channels: [Channel] = []
    @State private var search = ""
    @State private var current: Channel?
    @State private var player: AVPlayer?
    @State private var importing = false
    @State private var message = "Wczytaj swoją playlistę M3U"

    private var filtered: [Channel] {
        guard !search.isEmpty else { return channels }
        return channels.filter {
            $0.name.localizedCaseInsensitiveContains(search) ||
            $0.group.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "play.tv.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading) {
                        Text("My IPTV")
                            .font(.system(size: 30, weight: .bold))
                        Text("Twoja playlista. Twoje kanały.")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    Spacer()
                }
                .padding(.horizontal)

                if let current, let player {
                    VideoPlayer(player: player)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)

                    Text(current.name)
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                } else {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(.white.opacity(0.06))
                        .overlay {
                            VStack(spacing: 10) {
                                Image(systemName: "tv")
                                    .font(.system(size: 38))
                                    .foregroundStyle(.blue)
                                Text("Wybierz kanał")
                                    .font(.headline)
                                Text("Odtwarzanie strumieni zgodnych z iOS")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(height: 170)
                        .padding(.horizontal)
                }

                Button {
                    importing = true
                } label: {
                    Label("Wczytaj playlistę M3U", systemImage: "folder")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue.gradient)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .padding(.horizontal)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)

                if !channels.isEmpty {
                    TextField("Szukaj kanału...", text: $search)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)

                    List(filtered) { channel in
                        Button {
                            play(channel)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName:
                                    current == channel
                                    ? "waveform"
                                    : "play.circle.fill"
                                )
                                .font(.title2)
                                .foregroundStyle(.blue)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(channel.name)
                                        .foregroundStyle(.primary)

                                    if !channel.group.isEmpty {
                                        Text(channel.group)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(Color.white.opacity(0.04))
                    }
                    .listStyle(.plain)
                } else {
                    Spacer()
                }
            }
            .padding(.top, 12)
            .background(Color(red: 0.035, green: 0.045, blue: 0.07))
            .toolbar(.hidden, for: .navigationBar)
            .fileImporter(
                isPresented: $importing,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                importPlaylist(result)
            }
            .onAppear {
                restorePlaylist()
            }
        }
    }

    private func importPlaylist(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            let access = url.startAccessingSecurityScopedResource()
            defer {
                if access {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let data = try Data(contentsOf: url)
                guard let text = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1) else {
                    message = "Nie można odczytać pliku."
                    return
                }

                let parsed = parseM3U(text)
                guard !parsed.isEmpty else {
                    message = "Nie znaleziono kanałów w playliście."
                    return
                }

                channels = parsed
                savePlaylist()
                current = nil
                player?.pause()
                player = nil
                message = "Wczytano \(channels.count) pozycji."
            } catch {
                message = "Błąd pliku: \(error.localizedDescription)"
            }

        case .failure(let error):
            message = "Import nieudany: \(error.localizedDescription)"
        }
    }

    private func parseM3U(_ text: String) -> [Channel] {
        let lines = text
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .components(separatedBy: .newlines)

        var result: [Channel] = []
        var info = ""

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)

            if line.hasPrefix("#EXTINF:") {
                info = line
            } else if !line.isEmpty && !line.hasPrefix("#") {
                let name: String

                if let comma = info.firstIndex(of: ",") {
                    name = String(info[info.index(after: comma)...])
                        .trimmingCharacters(in: .whitespaces)
                } else {
                    name = "Kanał \(result.count + 1)"
                }

                let group: String
                if let range = info.range(
                    of: #"group-title="([^"]*)""#,
                    options: .regularExpression
                ) {
                    let attribute = String(info[range])
                    group = String(attribute.dropFirst("group-title=\"".count)
                        .dropLast())
                } else {
                    group = ""
                }

                result.append(
                    Channel(
                        name: name.isEmpty
                            ? "Kanał \(result.count + 1)" : name,
                        group: group,
                        url: line
                    )
                )
                info = ""
            }
        }

        return result
    }

    private func play(_ channel: Channel) {
        guard let url = URL(string: channel.url),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "")
        else {
            message = "Nieprawidłowy adres kanału."
            return
        }

        player?.pause()
        current = channel
        player = AVPlayer(url: url)
        player?.play()
        message = "Wybrano: \(channel.name)"
    }

    private func savePlaylist() {
        guard let data = try? JSONEncoder().encode(channels),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        playlistJSON = json
    }

    private func restorePlaylist() {
        guard let data = playlistJSON.data(using: .utf8),
              let saved = try? JSONDecoder().decode(
                [Channel].self, from: data
              ), !saved.isEmpty else {
            return
        }

        channels = saved
        message = "Przywrócono \(saved.count) kanałów."
    }
}
