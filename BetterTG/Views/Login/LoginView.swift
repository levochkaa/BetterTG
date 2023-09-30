// LoginView.swift

struct LoginView: View {
    
    @State var viewModel = LoginViewModel()
    
    @State var showSelectCountryView = false
    @State var searchCountries = ""
    
    @FocusState var focused: LoginState?
    
    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.loginState {
                    case .phoneNumber:
                        loginStateView(next: .code) {
                            GroupBox {
                                HStack {
                                    Text("+\(viewModel.selectedCountryNum.phoneNumberPrefix)")
                                    
                                    TextField("Phone Number", text: $viewModel.phoneNumber)
                                        .focused($focused, equals: .phoneNumber)
                                        .keyboardType(.numberPad)
                                }
                            } label: {
                                Button(viewModel.selectedCountryNum.name) {
                                    showSelectCountryView.toggle()
                                }
                            }
                        }
                        .task { await viewModel.loadCountries() }
                        .sheet(isPresented: $showSelectCountryView) {
                            selectCountryView
                                .presentationDetents([.medium, .large])
                                .presentationDragIndicator(.hidden)
                        }
                    case .code:
                        loginStateView(next: .twoFactor) {
                            TextField("Code", text: $viewModel.code)
                                .focused($focused, equals: .code)
                                .keyboardType(.numberPad)
                                .padding()
                                .background(.gray6)
                                .cornerRadius(10)
                        }
                    case .twoFactor:
                        loginStateView(next: nil) {
                            SecureField(viewModel.hint.isEmpty ? "2FA" : viewModel.hint, text: $viewModel.twoFactor)
                                .focused($focused, equals: .twoFactor)
                                .textContentType(.password)
                                .keyboardType(.alphabet)
                                .padding()
                                .background(.gray6)
                                .cornerRadius(10)
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
            .navigationTitle("Login")
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                withAnimation {
                    switch focused {
                        case .phoneNumber: focused = .code
                        case .code: focused = .twoFactor
                        case .twoFactor: focused = nil
                        case nil: break
                    }
                }
                Task {
                    await viewModel.handleAuthorizationState()
                }
            } label: {
                Text("Continue")
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
        .errorAlert(
            show: $viewModel.errorShown,
            text: "There was an error with Authorization state. Please, restart the app."
        )
    }
    
    func loginStateView(next state: LoginState?, _ content: () -> some View) -> some View {
        VStack(spacing: 10) {
            SpacingAround {
                Text(viewModel.loginState.title)
                    .font(.system(.largeTitle, weight: .bold))
            }
            
            content()
            
            Spacer()
        }
        .padding()
    }
    
    @ViewBuilder var selectCountryView: some View {
        NavigationStack {
            List(viewModel.getFilteredCountries(query: searchCountries), id: \.self) { info in
                Button {
                    viewModel.selectedCountryNum = info
                    showSelectCountryView.toggle()
                } label: {
                    HStack {
                        Text(info.name)
                        
                        Spacer()
                        
                        Text("+\(info.phoneNumberPrefix)")
                    }
                    .foregroundColor(.white)
                }
            }
            .background(.black)
            .padding(.top, -20)
            .navigationTitle("Country")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchCountries, placement: .navigationBarDrawer(displayMode: .always))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showSelectCountryView.toggle()
                    }
                }
            }
        }
    }
}
