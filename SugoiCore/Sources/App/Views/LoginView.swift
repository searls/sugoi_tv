import SwiftUI

struct LoginView: View {
  @Environment(AuthManager.self) private var authManager

  @State private var cid = ""
  @State private var password = ""

  var body: some View {
    VStack(spacing: 24) {
      Text("SugoiTV")
        .font(.largeTitle.bold())

      Text("Sign in with your YoiTV account")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      VStack(spacing: 16) {
        TextField("Customer ID", text: $cid)
          .textContentType(.username)
          #if os(iOS)
            .textInputAutocapitalization(.never)
          #endif
          .autocorrectionDisabled()

        SecureField("Password", text: $password)
          .textContentType(.password)
      }
      .textFieldStyle(.roundedBorder)
      .frame(maxWidth: 320)

      if let error = authManager.errorMessage {
        Text(error)
          .font(.caption)
          .foregroundStyle(.red)
          .multilineTextAlignment(.center)
      }

      Button {
        Task {
          do {
            try await authManager.login(cid: cid, password: password)
          } catch {
            authManager.errorMessage = error.localizedDescription
          }
        }
      } label: {
        if authManager.isLoading {
          ProgressView()
            .frame(maxWidth: .infinity)
        } else {
          Text("Sign In")
            .frame(maxWidth: .infinity)
        }
      }
      .buttonStyle(.borderedProminent)
      .frame(maxWidth: 320)
      .disabled(cid.isEmpty || password.isEmpty || authManager.isLoading)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
