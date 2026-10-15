// ChatSearchDatePickerViewController.swift

import UIKit

// MARK: - ChatSearchDatePickerViewController

/// Telegram's calendar for a chat search (ChatControllerOpenCalendarSearch, ChatScheduleTimeScreen in `.search`
/// mode): a day picker whose Done jumps to the first message sent on that day or later.
final class ChatSearchDatePickerViewController: UIViewController {
    private let onSelect: (Date) -> Void
    private let datePicker = UIDatePicker()
    private let doneButton = UIButton(configuration: .filled())

    init(onSelect: @escaping (Date) -> Void) {
        self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = L10n.telegram("Conversation.CalendarSearch.Title")
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Cancel"), style: .plain, target: self, action: #selector(cancelPressed),
        )

        datePicker.translatesAutoresizingMaskIntoConstraints = false
        datePicker.datePickerMode = .date
        datePicker.preferredDatePickerStyle = .inline
        datePicker.maximumDate = Date()
        datePicker.date = Date()
        view.addSubview(datePicker)

        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.configuration?.title = L10n.telegram("Conversation.CalendarSearch.Done")
        doneButton.configuration?.cornerStyle = .large
        doneButton.configuration?.buttonSize = .large
        doneButton.addTarget(self, action: #selector(donePressed), for: .touchUpInside)
        view.addSubview(doneButton)

        NSLayoutConstraint.activate([
            datePicker.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            datePicker.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            datePicker.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            doneButton.topAnchor.constraint(greaterThanOrEqualTo: datePicker.bottomAnchor, constant: 12),
            doneButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            doneButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            doneButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])
    }

    @objc private func cancelPressed() {
        dismiss(animated: true)
    }

    @objc private func donePressed() {
        let date = datePicker.date
        let onSelect = onSelect
        dismiss(animated: true) { onSelect(date) }
    }
}
