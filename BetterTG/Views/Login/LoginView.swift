// LoginView.swift

import SwiftUI
import TDLibKit
import Combine

struct LoginView: View {
    @State var loginState: LoginState = .phoneNumber
    
    @State var showSelectCountryView = false
    @State var selectedCountryNum = PhoneNumberInfo(country: "RU", phoneNumberPrefix: "7", name: "Russian Federation")
    
    @State var phoneNumber = ""
    @State var code = ""
    @State var hint = ""
    @State var twoFactor = ""
    
    @State var errorShown = false
    @FocusState var focused: LoginState?
    
    @State private var cancellables = Set<AnyCancellable>()
    
    var body: some View {
        ZStack {
            Group {
                switch loginState {
                    case .phoneNumber:
                        loginStateView {
                            GroupBox {
                                HStack {
                                    Text("+\(selectedCountryNum.phoneNumberPrefix)")
                                    
                                    TextField("Phone Number", text: $phoneNumber)
                                        .focused($focused, equals: .phoneNumber)
                                        .keyboardType(.numberPad)
                                }
                            } label: {
                                Button(selectedCountryNum.name) {
                                    showSelectCountryView.toggle()
                                }
                            }
                        }
                        .sheet(isPresented: $showSelectCountryView) {
                            SelectCountryView(
                                showSelectCountryView: $showSelectCountryView,
                                selectedCountryNum: $selectedCountryNum
                            )
                            .presentationDetents([.medium, .large])
                            .presentationDragIndicator(.hidden)
                        }
                    case .code:
                        loginStateView {
                            TextField("Code", text: $code)
                                .focused($focused, equals: .code)
                                .keyboardType(.numberPad)
                                .padding()
                                .background(.gray6)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    case .twoFactor:
                        loginStateView {
                            SecureField(hint.isEmpty ? "2FA" : hint, text: $twoFactor)
                                .focused($focused, equals: .twoFactor)
                                .textContentType(.password)
                                .keyboardType(.alphabet)
                                .padding()
                                .background(.gray6)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                }
            }
            .transition(
                .asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                )
                .combined(with: .opacity)
            )
        }
        .animation(.default, value: loginState)
        .safeAreaInset(edge: .bottom) {
            Button {
                withAnimation {
                    guard let focused else { return }
                    switch focused {
                        case .phoneNumber: self.focused = .code
                        case .code: self.focused = .twoFactor
                        case .twoFactor: self.focused = nil
                    }
                }
                Task.background {
                    switch try? await td.getAuthorizationState() {
                        case .authorizationStateWaitPassword:
                            _ = try? await td.checkAuthenticationPassword(password: twoFactor)
                        case .authorizationStateWaitCode:
                            _ = try? await td.checkAuthenticationCode(code: code)
                        case .authorizationStateWaitPhoneNumber:
                            _ = try? await td.setAuthenticationPhoneNumber(
                                phoneNumber: "\(selectedCountryNum.phoneNumberPrefix)\(phoneNumber)",
                                settings: nil
                            )
                        default: 
                            break
                    }
                }
            } label: {
                Text("Continue")
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
        .alert("Error", isPresented: $errorShown) {
            Text("There was an error with Authorization State. Please, restart the app.")
        }
        .task {
            switch try? await td.getAuthorizationState() {
                case .authorizationStateWaitPassword: loginState = .twoFactor
                case .authorizationStateWaitCode: loginState = .code
                case .authorizationStateClosed, .authorizationStateClosing, .authorizationStateLoggingOut:
                    errorShown = true
                default: break
            }
        }
        .onAppear(perform: setPublishers)
    }
    
    private func setPublishers() {
        nc.publisher(&cancellables, for: .authorizationStateWaitPassword) { notification in
            guard let waitPassword = notification.object as? AuthorizationStateWaitPassword else { return }
            Task.main {
                self.loginState = .twoFactor
                withAnimation { self.hint = waitPassword.passwordHint }
            }
        }
        nc.publisher(&cancellables, for: .authorizationStateWaitCode) { _ in
            Task.main { loginState = .code }
        }
        nc.mergeMany(&cancellables, [
            .authorizationStateWaitPhoneNumber,
            .authorizationStateClosed,
            .authorizationStateClosing,
            .authorizationStateLoggingOut
        ]) { _ in
            Task.main { loginState = .phoneNumber }
        }
    }
    
    func loginStateView(_ content: () -> some View) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Text(loginState.title)
                .font(.system(.largeTitle, weight: .bold))
            Spacer()
            content()
            Spacer()
        }
        .padding()
    }
}
