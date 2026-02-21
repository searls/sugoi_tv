import Foundation
import Testing

@testable import YoiTVProvider
@testable import SugoiCore

@Suite("LoginViewModel")
struct LoginViewModelTests {
  @Test("Empty fields show validation error")
  @MainActor
  func emptyFieldsValidation() async {
    let mock = MockHTTPSession()
    let keychain = MockKeychainService()
    let client = APIClient(session: mock.session)
    let auth = AuthService(keychain: keychain, apiClient: client)
    let vm = LoginViewModel(loginAction: { cid, password in
      _ = try await auth.login(cid: cid, password: password)
    })

    vm.customerID = ""
    vm.password = ""
    await vm.login()

    #expect(vm.errorMessage == "Please enter your customer ID and password.")
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
    let vm = LoginViewModel(loginAction: { cid, password in
      _ = try await auth.login(cid: cid, password: password)
    })
    vm.customerID = "testuser"
    vm.password = "testpass"

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
    let vm = LoginViewModel(loginAction: { cid, password in
      _ = try await auth.login(cid: cid, password: password)
    })
    vm.customerID = "bad"
    vm.password = "bad"

    await vm.login()

    #expect(vm.errorMessage == "Login failed. Please check your credentials and try again.")
    #expect(vm.isLoading == false)
  }

  @Test("loginWithCredentials sets fields and triggers successful login")
  @MainActor
  func loginWithCredentialsSuccess() async {
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
    let vm = LoginViewModel(loginAction: { cid, password in
      _ = try await auth.login(cid: cid, password: password)
    })

    await vm.loginWithCredentials(cid: "autofill_user", password: "autofill_pass")

    #expect(vm.customerID == "autofill_user")
    #expect(vm.password == "autofill_pass")
    #expect(vm.errorMessage == nil)
    #expect(vm.isLoading == false)
  }

  @Test("loginWithCredentials shows error on failure")
  @MainActor
  func loginWithCredentialsFailure() async {
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
    let vm = LoginViewModel(loginAction: { cid, password in
      _ = try await auth.login(cid: cid, password: password)
    })

    await vm.loginWithCredentials(cid: "bad", password: "bad")

    #expect(vm.customerID == "bad")
    #expect(vm.password == "bad")
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
    let vm = LoginViewModel(loginAction: { cid, password in
      _ = try await auth.login(cid: cid, password: password)
    })
    vm.customerID = "user"
    vm.password = "pass"

    await vm.login()

    #expect(vm.errorMessage == "Login failed. Please check your credentials and try again.")
    #expect(vm.isLoading == false)
  }
}
