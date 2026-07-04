import SwiftUI

/// Connexion au compte Stremio (e-mail / mot de passe), ou accès invité.
struct LoginScreen: View {
    @Environment(SessionStore.self) private var session
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    private var canSubmit: Bool {
        !email.isEmpty && !password.isEmpty && session.status != .working
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 40)

                Image(systemName: "play.tv.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.brand)
                Text("StremioTV").font(.largeTitle.bold())
                Text("Connecte-toi à ton compte Stremio pour retrouver tous tes add-ons, dont RealDebrid.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(spacing: 14) {
                    TextField("E-mail", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))

                    SecureField("Mot de passe", text: $password)
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { if canSubmit { submit() } }
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .frame(maxWidth: 460)

                if let error = session.errorMessage {
                    Text(error).foregroundStyle(.red).font(.callout)
                        .multilineTextAlignment(.center)
                }

                Button(action: submit) {
                    Group {
                        if session.status == .working {
                            ProgressView().tint(.white)
                        } else {
                            Text("Se connecter").fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: 460)
                    .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)

                Button("Continuer sans compte (Cinemeta)") {
                    session.continueAsGuest()
                }
                .foregroundStyle(.secondary)
                .padding(.top, 4)
                .accessibilityIdentifier("guestButton")

                Spacer(minLength: 40)
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .background(Color.black.ignoresSafeArea())
    }

    private func submit() {
        focus = nil
        Task { await session.login(email: email, password: password) }
    }
}
