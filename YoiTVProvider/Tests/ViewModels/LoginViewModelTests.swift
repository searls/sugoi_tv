import Foundation
import Testing

@testable import YoiTVProvider
@testable import SugoiCore

private let yoiTVLoginFields: [LoginField] = [
  LoginField(key: "cid", label: "Customer ID", contentType: .username),
  LoginField(key: "password", label: "Password", isSecure: true, contentType: .password),
]

@Suite("LoginViewModel")
struct LoginViewModelTests {
  @Test("Empty fields show validation error")
  @MainActor
  func emptyFieldsValidation() async {
    let mock = MockHTTPSession()
    let keychain = MockKeychainService()
    let client = APIClient(session: mock.session)
    let auth = AuthService(keychain: keychain, apiClient: client)
    let vm = LoginViewModel(loginFields: yoiTVLoginFields, loginAction: { credentials in
      _ = try await auth.login(cid: credentials["cid"]!, password: credentials["password"]!)
    })

    vm.fieldValues["cid"] = ""
    vm.fieldValues["password"] = ""
    await vm.login()

    #expect(vm.errorMessage == "Please fill in all fields.")
    #expect(vm.isLoading == false)
  }

  @Test("Successful login clears error message")
  @MainActor
  func successfulLogin() async {
    let mock = MockHTTPSession()
    let loginJSON = """
      {"access_token":"t","token_type":"bearer","expires_in":9999999999,"refresh_token":"r","expired":false,"disabled":false,"confirmed":true,"cid":"CID","type":"tvum_cid","trial":0,"create_time":0,"expire_time":9999999999,"product_config":"{\\"vms_host\\":\\"http://live.yoitv.com:9083\\",\\"vms_vod_host\\":\\"http://vod.yoitv.com:9083\\",\\"vms_uid\\":\\"UID\\",\\"vms_live_cid\\":\\"CID\\",\\"vms_referer\\":\\"http://play.yoitv.com\\",\\"epg_days\\":30,\\"single\\":\\"https://crm.yoitv.com/single.sjs\\"}","server_time":0,"code":"OK"}
      """
    mock.requestHandler = { request in
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
      )!
      return (response, Data(loginJSON.utf8))
    }

    let auth = AuthService(keychain: MockKeychainService(), apiClient: APIClient(session: mock.session))
    let vm = LoginViewModel(loginFields: yoiTVLoginFields, loginAction: { credentials in
      _ = try await auth.login(cid: credentials["cid"]!, password: credentials["password"]!)
    })
    vm.fieldValues["cid"] = "testuser"
    vm.fieldValues["password"] = "testpass"

    await vm.login()

    #expect(vm.errorMessage == nil)
    #expect(vm.isLoading == false)
  }

  @Test("Failed login shows appropriate error")
  @MainActor
  func failedLogin() async {
    let mock = MockHTTPSession()
    let failJSON = """
      {"access_token":"","token_type":"","expires_in":0,"refresh_token":"","expired":false,"disabled":false,"confirmed":true,"cid":"","type":"","trial":0,"create_time":0,"expire_time":0,"product_config":"{}","server_time":0,"code":"INVALID"}
      """
    mock.requestHandler = { request in
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
      )!
      return (response, Data(failJSON.utf8))
    }

    let auth = AuthService(keychain: MockKeychainService(), apiClient: APIClient(session: mock.session))
    let vm = LoginViewModel(loginFields: yoiTVLoginFields, loginAction: { credentials in
      _ = try await auth.login(cid: credentials["cid"]!, password: credentials["password"]!)
    })
    vm.fieldValues["cid"] = "bad"
    vm.fieldValues["password"] = "bad"

    await vm.login()

    #expect(vm.errorMessage == "Login failed. Please check your credentials and try again.")
    #expect(vm.isLoading == false)
  }

  @Test("fillCredentials sets fields and triggers successful login")
  @MainActor
  func fillCredentialsSuccess() async {
    let mock = MockHTTPSession()
    let loginJSON = """
      {"access_token":"t","token_type":"bearer","expires_in":9999999999,"refresh_token":"r","expired":false,"disabled":false,"confirmed":true,"cid":"CID","type":"tvum_cid","trial":0,"create_time":0,"expire_time":9999999999,"product_config":"{\\"vms_host\\":\\"http://live.yoitv.com:9083\\",\\"vms_vod_host\\":\\"http://vod.yoitv.com:9083\\",\\"vms_uid\\":\\"UID\\",\\"vms_live_cid\\":\\"CID\\",\\"vms_referer\\":\\"http://play.yoitv.com\\",\\"epg_days\\":30,\\"single\\":\\"https://crm.yoitv.com/single.sjs\\"}","server_time":0,"code":"OK"}
      """
    mock.requestHandler = { request in
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
      )!
      return (response, Data(loginJSON.utf8))
    }

    let auth = AuthService(keychain: MockKeychainService(), apiClient: APIClient(session: mock.session))
    let vm = LoginViewModel(loginFields: yoiTVLoginFields, loginAction: { credentials in
      _ = try await auth.login(cid: credentials["cid"]!, password: credentials["password"]!)
    })

    await vm.fillCredentials(username: "autofill_user", password: "autofill_pass")

    #expect(vm.fieldValues["cid"] == "autofill_user")
    #expect(vm.fieldValues["password"] == "autofill_pass")
    #expect(vm.errorMessage == nil)
    #expect(vm.isLoading == false)
  }

  @Test("fillCredentials shows error on failure")
  @MainActor
  func fillCredentialsFailure() async {
    let mock = MockHTTPSession()
    let failJSON = """
      {"access_token":"","token_type":"","expires_in":0,"refresh_token":"","expired":false,"disabled":false,"confirmed":true,"cid":"","type":"","trial":0,"create_time":0,"expire_time":0,"product_config":"{}","server_time":0,"code":"INVALID"}
      """
    mock.requestHandler = { request in
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
      )!
      return (response, Data(failJSON.utf8))
    }

    let auth = AuthService(keychain: MockKeychainService(), apiClient: APIClient(session: mock.session))
    let vm = LoginViewModel(loginFields: yoiTVLoginFields, loginAction: { credentials in
      _ = try await auth.login(cid: credentials["cid"]!, password: credentials["password"]!)
    })

    await vm.fillCredentials(username: "bad", password: "bad")

    #expect(vm.fieldValues["cid"] == "bad")
    #expect(vm.fieldValues["password"] == "bad")
    #expect(vm.errorMessage == "Login failed. Please check your credentials and try again.")
    #expect(vm.isLoading == false)
  }

  @Test("Network error shows connection message")
  @MainActor
  func networkError() async {
    let mock = MockHTTPSession()
    mock.requestHandler = { _ in
      throw URLError(.notConnectedToInternet)
    }

    let auth = AuthService(keychain: MockKeychainService(), apiClient: APIClient(session: mock.session))
    let vm = LoginViewModel(loginFields: yoiTVLoginFields, loginAction: { credentials in
      _ = try await auth.login(cid: credentials["cid"]!, password: credentials["password"]!)
    })
    vm.fieldValues["cid"] = "user"
    vm.fieldValues["password"] = "pass"

    await vm.login()

    #expect(vm.errorMessage == "Login failed. Please check your credentials and try again.")
    #expect(vm.isLoading == false)
  }
}
