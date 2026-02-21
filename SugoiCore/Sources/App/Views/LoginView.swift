import AuthenticationServices
import SwiftUI

@MainActor
@Observable
public final class LoginViewModel {
  var fieldValues: [String: String]
  var isLoading: Bool = false
  var errorMessage: String?

  let loginFields: [LoginField]
  private let loginAction: ([String: String]) async throws -> Void

  public init(
    loginFields: [LoginField],
    loginAction: @escaping ([String: String]) async throws -> Void
  ) {
    self.loginFields = loginFields
    self.loginAction = loginAction
    var defaults: [String: String] = [:]
    for field in loginFields {
      defaults[field.key] = field.defaultValue
    }
    self.fieldValues = defaults
  }

  func fillCredentials(username: String, password: String) async {
    for field in loginFields {
      switch field.contentType {
      case .username: fieldValues[field.key] = username
      case .password: fieldValues[field.key] = password
      default: break
      }
    }
    await login()
  }

  func login() async {
    let hasEmptyRequired = loginFields.contains { field in
      (fieldValues[field.key] ?? "").isEmpty
    }
    guard !hasEmptyRequired else {
      errorMessage = "Please fill in all fields."
      return
    }

    isLoading = true
    errorMessage = nil

    do {
      try await loginAction(fieldValues)
    } catch {
      errorMessage = "Login failed. Please check your credentials and try again."
    }

    isLoading = false
  }

  /// Whether this form has both username and password fields (for autofill).
  var supportsPasswordAutofill: Bool {
    let types = Set(loginFields.map(\.contentType))
    return types.contains(.username) && types.contains(.password)
  }
}

public struct LoginView: View {
  @Bindable var viewModel: LoginViewModel
  let providerName: String
  #if os(iOS) || os(tvOS)
  @Environment(\.authorizationController) private var authorizationController
  #endif

  public init(viewModel: LoginViewModel, providerName: String = "") {
    self.viewModel = viewModel
    self.providerName = providerName
  }

  public var body: some View {
    VStack(spacing: 24) {
      Text("SugoiTV")
        .font(.largeTitle)
        .fontWeight(.bold)

      if !providerName.isEmpty {
        Text(providerName)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      VStack(spacing: 16) {
        ForEach(viewModel.loginFields) { field in
          fieldView(for: field)
        }
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
      .disabled(viewModel.isLoading)
    }
    .padding(32)
    .frame(maxWidth: 400)
    #if os(iOS) || os(tvOS)
    .task {
      if viewModel.supportsPasswordAutofill {
        await requestSavedCredentials()
      }
    }
    #endif
  }

  @ViewBuilder
  private func fieldView(for field: LoginField) -> some View {
    let binding = Binding(
      get: { viewModel.fieldValues[field.key] ?? "" },
      set: { viewModel.fieldValues[field.key] = $0 }
    )

    switch field.contentType {
    case .password:
      SecureField(field.label, text: binding)
        .textContentType(.password)
        .onSubmit { Task { await viewModel.login() } }
    case .url:
      TextField(field.label, text: binding)
        #if os(iOS)
        .textInputAutocapitalization(.never)
        .keyboardType(.URL)
        #endif
        .autocorrectionDisabled()
    case .username:
      TextField(field.label, text: binding)
        .textContentType(.username)
        #if os(iOS)
        .textInputAutocapitalization(.never)
        .keyboardType(.asciiCapable)
        #endif
        .autocorrectionDisabled()
    case .text:
      TextField(field.label, text: binding)
        #if os(iOS)
        .textInputAutocapitalization(.never)
        #endif
        .autocorrectionDisabled()
    }
  }

  #if os(iOS) || os(tvOS)
  private func requestSavedCredentials() async {
    let request = ASAuthorizationPasswordProvider().createRequest()
    do {
      let result = try await authorizationController.performAutoFillAssistedRequest(request)
      if case .password(let credential) = result {
        await viewModel.fillCredentials(
          username: credential.user, password: credential.password
        )
      }
    } catch {
      // No saved credentials selected — manual form takes over
    }
  }
  #endif
}
