import SwiftUI

@MainActor
@Observable
public final class LoginViewModel {
  var customerID: String = ""
  var password: String = ""
  var isLoading: Bool = false
  var errorMessage: String?

  private let loginAction: (String, String) async throws -> Void

  public init(loginAction: @escaping (String, String) async throws -> Void) {
    self.loginAction = loginAction
  }

  func login() async {
    guard !customerID.isEmpty, !password.isEmpty else {
      errorMessage = "Please enter your customer ID and password."
      return
    }

    isLoading = true
    errorMessage = nil

    do {
      try await loginAction(customerID, password)
    } catch let error as AuthError {
      switch error {
      case .loginFailed:
        errorMessage = "Invalid customer ID or password."
      case .accountInvalid:
        errorMessage = "Account is expired, disabled, or unconfirmed."
      default:
        errorMessage = "Login failed. Please try again."
      }
    } catch {
      errorMessage = "Network error. Please check your connection."
    }

    isLoading = false
  }
}

public struct LoginView: View {
  @Bindable var viewModel: LoginViewModel

  public init(viewModel: LoginViewModel) {
    self.viewModel = viewModel
  }

  public var body: some View {
    VStack(spacing: 24) {
      Text("SugoiTV")
        .font(.largeTitle)
        .fontWeight(.bold)

      Text("YoiTV")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      VStack(spacing: 16) {
        TextField("Customer ID", text: $viewModel.customerID)
          .textContentType(.username)
          #if os(iOS)
          .textInputAutocapitalization(.never)
          .keyboardType(.asciiCapable)
          #endif
          .autocorrectionDisabled()

        SecureField("Password", text: $viewModel.password)
          .textContentType(.password)
          .onSubmit { Task { await viewModel.login() } }
      }
      .textFieldStyle(.roundedBorder)

      if let error = viewModel.errorMessage {
        Text(error)
          .font(.callout)
          .foregroundStyle(.red)
          .multilineTextAlignment(.center)
      }

      Button {
        Task { await viewModel.login() }
      } label: {
        if viewModel.isLoading {
          ProgressView()
            .frame(maxWidth: .infinity)
        } else {
          Text("Sign In")
            .frame(maxWidth: .infinity)
        }
      }
      .buttonStyle(.borderedProminent)
      .disabled(viewModel.isLoading || viewModel.customerID.isEmpty || viewModel.password.isEmpty)
    }
    .padding(32)
    .frame(maxWidth: 400)
  }
}
