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
    @State private var message = "Zaimportuj swoją playlistę M3U"

    private var filtered: [Channel] {
        if search.isEmpty { return channels }
        return channels.filter {
            $0.name.localizedCaseInsensitiveContains(search) ||
            $0.group.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if let current, let player {
                VideoPlayer(player: player)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                Text(current.name)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.06))

                    VStack(spacing: 10) {
                        Image(systemName: "tv.fill")
                            .font(.system(size: 42))
                            .foregroundColor(.cyan)

                        Text("Wybierz kanał")
                            .font(.title3.bold())

                        Text("Twoja telewizja w jednym miejscu")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(height: 175)
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }

            Button {
                importing = true
            } label: {
                Label("Importuj playlistę M3U", systemImage: "folder.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(15)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 15))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 16)

            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.top, 10)

            if !channels.isEmpty {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)

                    TextField("Szukaj kanału...", text: $search)
                        .autocorrectionDisabled()
                }
                .padding(12)
                .background(Color.white.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.top, 12)

                HStack {
                    Text("KANAŁY")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)

                    Spacer()

                    Text("\(filtered.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 18)
                .padding(.top, 15)
                .padding(.bottom, 5)

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
                            .foregroundColor(.cyan)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(channel.name)
                                    .foregroundColor(.primary)

                                if !channel.group.isEmpty {
                                    Text(channel.group)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Color.white.opacity(0.035))
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            } else {
                Spacer()
            }
        }
        .background(Color(red: 0.035, green: 0.045, blue: 0.07))
        .preferredColorScheme(.dark)
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

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.cyan.opacity(0.15))
                    .frame(width: 52, height: 52)

                Image(systemName: "play.tv.fill")
                    .font(.system(size: 27))
                    .foregroundColor(.cyan)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("My IPTV")
                    .font(.system(size: 29, weight: .bold))

                Text("Twoja playlista. Twoje kanały.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 15)
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

                guard let text =
                    String(data: data, encoding: .utf8) ??
                    String(data: data, encoding: .isoLatin1)
                else {
                    message = "Nie udało się odczytać pliku."
                    return
                }

                let parsed = parseM3U(text)

                guard !parsed.isEmpty else {
                    message = "Nie znaleziono kanałów w pliku."
                    return
                }

                channels = parsed
                savePlaylist()

                player?.pause()
                player = nil
                current = nil

                message = "Wczytano \(parsed.count) pozycji."

            } catch {
                message = "Błąd odczytu pliku."
            }

        case .failure:
            message = "Nie udało się zaimportować playlisty."
        }
    }

    private func parseM3U(_ text: String) -> [Channel] {
        let lines = text
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .components(separatedBy: .newlines)

        var result: [Channel] = []
        var info = ""

        for raw in lines {
            let line = raw.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            if line.hasPrefix("#EXTINF:") {
                info = line
            } else if !line.isEmpty && !line.hasPrefix("#") {
                var name = "Kanał \(result.count + 1)"

                if let comma = info.firstIndex(of: ",") {
                    let extracted = String(
                        info[info.index(after: comma)...]
                    ).trimmingCharacters(in: .whitespaces)

                    if !extracted.isEmpty {
                        name = extracted
                    }
                }

                var group = ""

                if let range = info.range(
                    of: #"group-title="([^"]*)""#,
                    options: .regularExpression
                ) {
                    let attribute = String(info[range])
                    group = String(
                        attribute
                            .dropFirst("group-title=\"".count)
                            .dropLast()
                    )
                }

                result.append(
                    Channel(name: name, group: group, url: line)
                )

                info = ""
            }
        }

        return result
    }

    private func play(_ channel: Channel) {
        guard let url = URL(string: channel.url),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            message = "Nieprawidłowy adres kanału."
            return
        }

        player?.pause()
        current = channel

        let newPlayer = AVPlayer(url: url)
        player = newPlayer
        newPlayer.play()

        message = "Odtwarzanie: \(channel.name)"
    }

    private func savePlaylist() {
        guard let data = try? JSONEncoder().encode(channels),
              let json = String(data: data, encoding: .utf8)
        else { return }

        playlistJSON = json
    }

    private func restorePlaylist() {
        guard let data = playlistJSON.data(using: .utf8),
              let saved = try? JSONDecoder().decode(
                [Channel].self,
                from: data
              ),
              !saved.isEmpty
        else { return }

        channels = saved
        message = "Przywrócono \(saved.count) kanałów."
    }
}
