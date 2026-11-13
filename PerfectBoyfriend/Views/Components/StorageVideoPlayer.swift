import AVKit
import FirebaseStorage
import SwiftUI

/// Streams a protected Firebase Storage clip only when a member explicitly opens it. Feed cards
/// use the separately stored poster image, so browsing Moments never starts video downloads.
struct StorageVideoPlayer: View {
    let path: String
    let posterPath: String?

    @State private var isPresented = false

    var body: some View {
        Button { isPresented = true } label: {
            ZStack {
                if let posterPath {
                    StorageImageView(path: posterPath)
                } else {
                    LinearGradient(colors: [PBTheme.midnightSoft, PBTheme.routeSurfaceRaised], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                Image(systemName: "play.fill")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(PBTheme.midnight)
                    .frame(width: 66, height: 66)
                    .background(PBTheme.textOnDark.opacity(0.94), in: Circle())
                    .shadow(color: .black.opacity(0.24), radius: 10, y: 5)
            }
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $isPresented) {
            StorageVideoPlaybackScreen(path: path)
        }
        .accessibilityLabel("Video abspielen")
    }
}

private struct StorageVideoPlaybackScreen: View {
    let path: String
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var errorMessage: String?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Group {
                if let player {
                    VideoPlayer(player: player)
                        .onAppear { player.play() }
                } else if let errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 29))
                        Text(errorMessage).multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.white)
                    .padding(28)
                } else {
                    ProgressView("Video wird geladen …").tint(.white).foregroundStyle(.white)
                }
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.56), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.top, 16)
            .padding(.trailing, 18)
        }
        .task {
            do {
                let url = try await Storage.storage().reference(withPath: path).downloadURL()
                player = AVPlayer(url: url)
            } catch {
                errorMessage = "Das Video konnte gerade nicht geladen werden."
            }
        }
        .onDisappear { player?.pause() }
    }
}
