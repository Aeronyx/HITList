import SwiftUI
import HITListCore

/// The share sheet's card (brief 90), plain for now: the title, what Add makes, Add and Cancel.
struct ShareCardRoot: View {
    @Bindable var model: ShareSheetModel

    var body: some View {
        VStack(alignment: .leading, spacing: HITSpacing.m) {
            Text("Add to HITList").font(HITType.title).foregroundStyle(HITColor.text)
            switch model.phase {
            case .reading:
                Text("Reading what was shared…").font(HITType.callout).foregroundStyle(Theme.secondaryText)
            case .nothing:
                Text("There is nothing here HITList can add.").font(HITType.callout).foregroundStyle(Theme.secondaryText)
            case .editing:
                HITField("Task name", text: Binding(get: { model.title }, set: { model.edit($0) }), autofocus: true)
                    .onSubmit { model.add() }
                Text(model.plan.notes).font(HITType.caption).foregroundStyle(Theme.secondaryText).lineLimit(4)
            case .saved(let destination):
                Text(ShareText.savedLine(destination)).font(HITType.callout).foregroundStyle(HITColor.text)
            case .added(let destination):
                Text(ShareText.addedLine(destination)).font(HITType.callout).foregroundStyle(HITColor.text)
            }
            if let failure = model.failure {
                Text(failure).font(HITType.caption).foregroundStyle(HITColor.danger)
            }
            HStack {
                Button("Cancel") { model.cancel() }.buttonStyle(.hitGhost)
                Spacer()
                Button("Add") { model.add() }.buttonStyle(.hitPrimary).disabled(!model.canAdd)
            }
        }
        .padding(HITSpacing.l)
        .background(Theme.surface)
        .font(HITType.body)
        .environment(\.colorScheme, .dark)
    }
}
