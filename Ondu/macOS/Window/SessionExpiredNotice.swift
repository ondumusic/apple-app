#if os(macOS)
import SwiftUI

/// Stays under the player for as long as the session is expired, so the sign-in sheet can
/// be brought back after Not Now. Styled like ServerVersionNotice, which it sits beside.
struct SessionExpiredNotice: View {
    let onSignIn: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Your session expired. Sign in again to keep listening.")
            Spacer(minLength: 0)
            Button("Sign In…", action: onSignIn)
                .buttonStyle(.link)
        }
        .font(.subheadline)
        .foregroundStyle(.primary)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.16))
        .overlay(alignment: .bottom) { Divider() }
    }
}
#endif
