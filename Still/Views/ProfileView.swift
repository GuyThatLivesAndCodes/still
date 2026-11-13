import SwiftUI

/// You → About you. Name, birthday and gender, only used to tailor Quiet AI.
struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Profile.nameKey) private var name = ""
    @AppStorage(Profile.birthdayKey) private var birthday: Double = 0
    @AppStorage(Profile.genderKey) private var genderRaw = Gender.unset.rawValue
    @AppStorage(Profile.genderOtherKey) private var genderOther = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("First name or what you go by", text: $name)
                        .textContentType(.givenName)
                        .submitLabel(.done)
                } header: {
                    Text("Name")
                }

                Section {
                    if birthday == 0 {
                        Button("Add Birthday") { birthday = ProfileDefaults.suggestedBirthday.timeIntervalSince1970 }
                    } else {
                        DatePicker("Birthday", selection: birthdayBinding, in: ProfileDefaults.birthdayRange,
                                   displayedComponents: .date)
                        Button("Remove Birthday", role: .destructive) { birthday = 0 }
                    }
                } header: {
                    Text("Date of birth")
                } footer: {
                    Text("Only your age is shared with Quiet AI, never the date.")
                }

                Section {
                    Picker("Gender", selection: $genderRaw) {
                        Text("Not set").tag(Gender.unset.rawValue)
                        ForEach(Gender.choices) { Text($0.title).tag($0.rawValue) }
                    }
                    if genderRaw == Gender.other.rawValue {
                        TextField("How you describe it", text: $genderOther)
                            .onChange(of: genderOther) { _, v in
                                if v.count > 30 { genderOther = String(v.prefix(30)) }
                            }
                    }
                } header: {
                    Text("Gender")
                }

                Section {
                    Label("Stays on this iPhone. Quiet AI uses it to word notes, replies and reminders so they fit you. It's never stored on a server.",
                          systemImage: "lock")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("About You")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onChange(of: name) { _, v in if v.count > 40 { name = String(v.prefix(40)) } }
        }
        .presentationBackground(.black)
    }

    private var birthdayBinding: Binding<Date> {
        Binding(get: { Date(timeIntervalSince1970: birthday) },
                set: { birthday = $0.timeIntervalSince1970 })
    }
}

enum ProfileDefaults {
    static var birthdayRange: ClosedRange<Date> {
        let cal = Calendar.current
        let oldest = cal.date(byAdding: .year, value: -110, to: .now) ?? .distantPast
        let youngest = cal.date(byAdding: .year, value: -13, to: .now) ?? .now
        return oldest...youngest
    }

    static var suggestedBirthday: Date {
        Calendar.current.date(byAdding: .year, value: -20, to: .now) ?? .now
    }
}
