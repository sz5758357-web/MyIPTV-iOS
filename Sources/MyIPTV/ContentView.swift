import SwiftUI
import AVKit
import UniformTypeIdentifiers

struct Channel: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var url: String
    var group: String = "Kanały"

    enum CodingKeys: String, CodingKey {
        case id, name, url, group
    }
}

struct ContentView: View {
    @AppStorage("playlistJSON") private var playlistJSON = "[]"

    @State private var channels: [Channel] = []
    @State private var searchText = ""
    @State private var message = "Zaimportuj swoją playlistę M3U"
    @State private var showImporter = false
    @State private var showPlayer = false
    @State private var selectedChannel: Channel?
    @State private var player: AVPlayer?

    private var filteredChannels: [Channel] {
        guard !searchText.isEmpty else { return channels }
        return channels.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.group.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                Button {
                    showImporter = true
                } label: {
                    Label("IMPORTUJ PLAYLISTĘ M3U", systemImage: "plus.rectangle.on.folder")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.green.gradient)
                        .clipShape(RoundedRectangle(cornerRadius: 15))
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 10)

                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 10)

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.gray)

                    TextField("Szukaj kanału...", text: $searchText)
                        .foregroundStyle(.white)
                        .autocorrectionDisabled()
                }
                .padding(13)
                .background(Color.white.opacity(0.09))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

                HStack {
                    Text("WSZYSTKIE KANAŁY")
                        .font(.caption.bold())
                        .foregroundStyle(.gray)

                    Spacer()

                    Text("\(filteredChannels.count)")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 8)

                if filteredChannels.isEmpty {
                    Spacer(minLength: 20)

                    Image(systemName: "tv")
                        .font(.system(size: 55))
                        .foregroundStyle(.green)

                    Text(channels.isEmpty ? "Brak kanałów" : "Brak wyników")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .padding(.top, 12)

                    Text(channels.isEmpty
                         ? "Zaimportuj własną playlistę M3U."
                         : "Spróbuj wpisać inną nazwę.")
                        .font(.subheadline)
                        .foregroundStyle(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)

                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 9) {
                            ForEach(filteredChannels) { channel in
                                Button {
                                    play(channel)
                                } label: {
                                    HStack(spacing: 13) {
                                        Image(systemName: "play.circle.fill")
                                            .font(.system(size: 35))
                                            .foregroundStyle(.green)

                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(channel.name)
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundStyle(.white)
                                                .lineLimit(2)

                                            Text(channel.group)
                                                .font(.caption)
                                                .foregroundStyle(.gray)
                                                .lineLimit(1)
                                        }

                                        Spacer(minLength: 4)

                                        Image(systemName: "chevron.right")
                                            .font(.caption.bold())
                                            .foregroundStyle(.gray)
                                    }
                                    .padding(14)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.white.opacity(0.07))
                                    .clipShape(RoundedRectangle(cornerRadius: 15))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 24)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .preferredColorScheme(.dark)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            importPlaylist(result)
        }
        .fullScreenCover(isPresented: $showPlayer) {
            if let player, let selectedChannel {
                FullScreenPlayer(
                    player: player,
                    channelName: selectedChannel.name,
                    onClose: {
                        player.pause()
                        showPlayer = false
                    }
                )
            }
        }
        .onAppear {
            loadSavedPlaylist()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "tv.fill")
                .font(.system(size: 29))
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 3) {
                Text("MY IPTV")
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(.white)

                Text("TWÓJ TELEWIZOR W KIESZENI")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.green)
            }

            Spacer()

            Button {
                loadSavedPlaylist()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .padding(11)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private func loadSavedPlaylist() {
        guard let data = playlistJSON.data(using: .utf8),
              let saved = try? JSONDecoder().decode([Channel].self, from: data)
        else {
            channels = []
            return
        }

        channels = saved
        message = saved.isEmpty
            ? "Zaimportuj swoją playlistę M3U"
            : "Wczytano \(saved.count) kanałów"
    }

    private func importPlaylist(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }

            let access = url.startAccessingSecurityScopedResource()
            defer {
                if access {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let content = try String(contentsOf: url, encoding: .utf8)
            let parsed = parseM3U(content)

            guard !parsed.isEmpty else {
                message = "Nie znaleziono kanałów. Sprawdź plik M3U."
                return
            }

            channels = parsed

            if let data = try? JSONEncoder().encode(parsed),
               let json = String(data: data, encoding: .utf8) {
                playlistJSON = json
            }

            message = "Zaimportowano \(parsed.count) kanałów"
        } catch {
            message = "Błąd importu: \(error.localizedDescription)"
        }
    }

    private func parseM3U(_ content: String) -> [Channel] {
        let lines = content.components(separatedBy: .newlines)
        var result: [Channel] = []
        var nextName = ""
        var nextGroup = "Kanały"

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("#EXTINF") {
                nextName = line.components(separatedBy: ",").last?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Kanał"

                if let range = line.range(of: "group-title=\"") {
                    let rest = line[range.upperBound...]
                    nextGroup = String(rest.prefix { $0 != "\"" })
                } else {
                    nextGroup = "Kanały"
                }
            } else if !line.hasPrefix("#"),
                      line.lowercased().hasPrefix("http") {
                result.append(
                    Channel(
                        name: nextName.isEmpty ? "Kanał \(result.count + 1)" : nextName,
                        url: line,
                        group: nextGroup
                    )
                )

                nextName = ""
                nextGroup = "Kanały"
            }
        }

        return result
    }

    private func play(_ channel: Channel) {
        guard let url = URL(string: channel.url),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "")
        else {
            message = "Nieprawidłowy adres kanału"
            return
        }

        selectedChannel = channel

        let newPlayer = AVPlayer(url: url)
        player = newPlayer
        message = "Uruchamianie: \(channel.name)"
        showPlayer = true

        newPlayer.play()
    }
}

struct FullScreenPlayer: View {
    let player: AVPlayer
    let channelName: String
    let onClose: () -> Void

    @State private var isPlaying = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VideoPlayer(player: player)
                .ignoresSafeArea()

            VStack {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.headline.bold())
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.7))
                            .clipShape(Circle())
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("MY IPTV")
                            .font(.caption.bold())
                            .foregroundStyle(.green)

                        Text(channelName)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Spacer()

                HStack {
                    Button {
                        if isPlaying {
                            player.pause()
                        } else {
                            player.play()
                        }
                        isPlaying.toggle()
                    } label: {
                        Label(
                            isPlaying ? "Pauza" : "Odtwórz",
                            systemImage: isPlaying ? "pause.fill" : "play.fill"
                        )
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Color.black.opacity(0.7))
                        .clipShape(Capsule())
                    }

                    Spacer()
                }
                .padding(18)
            }
        }
        .statusBarHidden()
        .preferredColorScheme(.dark)
        .onDisappear {
            player.pause()
        }
    }
}
