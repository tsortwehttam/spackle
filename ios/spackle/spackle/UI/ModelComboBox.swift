import AppKit
import SwiftUI

struct ModelComboBox: NSViewRepresentable {
    @Binding var value: String
    var options: [String]

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSComboBox {
        let box = NSComboBox()
        box.usesDataSource = false
        box.completes = true
        box.isEditable = true
        box.numberOfVisibleItems = 12
        box.font = .systemFont(ofSize: 13)
        box.delegate = context.coordinator
        box.addItems(withObjectValues: options)
        box.stringValue = value
        return box
    }

    func updateNSView(_ box: NSComboBox, context: Context) {
        context.coordinator.parent = self
        let old = Set(box.objectValues.compactMap { $0 as? String })
        let new = Set(options)
        if old != new {
            box.removeAllItems()
            box.addItems(withObjectValues: options)
        }
        if box.currentEditor() == nil, box.stringValue != value {
            box.stringValue = value
        }
    }

    final class Coordinator: NSObject, NSComboBoxDelegate, NSTextFieldDelegate {
        var parent: ModelComboBox

        init(_ parent: ModelComboBox) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let box = obj.object as? NSComboBox else {
                return
            }
            parent.value = box.stringValue
        }

        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let box = notification.object as? NSComboBox else {
                return
            }
            let idx = box.indexOfSelectedItem
            if idx >= 0, let picked = box.itemObjectValue(at: idx) as? String {
                parent.value = picked
            }
        }
    }
}
