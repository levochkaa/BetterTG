// ScheduleMessagePickerViewController.swift

import TDLibKit
import UIKit

// MARK: - ScheduleMessagePickerViewController

/// Telegram's ChatScheduleTimeController: a date and time wheel from the next minute to a year ahead, starting five
/// minutes on (or at a scheduled message's own time), a button naming the chosen day and time, and Send When Online
/// where the person's last seen time is known. Saved Messages sets reminders with the same picker.
final class ScheduleMessagePickerViewController: UIViewController {
    private let isReminder: Bool
    private let showsSendWhenOnline: Bool
    private let initialDate: Date?
    private let onSchedule: (TDNativeMessageSchedulingState) -> Void
    private let picker = UIDatePicker()
    private let doneButton = UIButton(configuration: .filled())
    private let onlineButton = UIButton(configuration: .gray())
    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private init(
        isReminder: Bool,
        showsSendWhenOnline: Bool,
        initialDate: Date?,
        onSchedule: @escaping (TDNativeMessageSchedulingState) -> Void,
    ) {
        self.isReminder = isReminder
        self.showsSendWhenOnline = showsSendWhenOnline
        self.initialDate = initialDate
        self.onSchedule = onSchedule
        super.init(nibName: nil, bundle: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram(isReminder ? "Conversation.SetReminder.Title" : "Conversation.ScheduleMessage.Title")
        view.backgroundColor = .systemGroupedBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Cancel"),
            style: .plain,
            target: self,
            action: #selector(cancel),
        )

        picker.datePickerMode = .dateAndTime
        picker.preferredDatePickerStyle = .wheels
        picker.minuteInterval = 1
        picker.addTarget(self, action: #selector(dateChanged), for: .valueChanged)
        configureDates()

        for (button, weight) in [(doneButton, UIFont.Weight.semibold), (onlineButton, UIFont.Weight.regular)] {
            button.configuration?.cornerStyle = .large
            button.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
                var attributes = $0
                attributes.font = .systemFont(ofSize: 17, weight: weight)
                return attributes
            }
            button.heightAnchor.constraint(equalToConstant: 52).isActive = true
        }
        doneButton.accessibilityIdentifier = "schedule-message-send"
        doneButton.addTarget(self, action: #selector(scheduleAtDate), for: .touchUpInside)
        onlineButton.configuration?.title = L10n.telegram("Conversation.ScheduleMessage.SendWhenOnline")
        onlineButton.addTarget(self, action: #selector(scheduleWhenOnline), for: .touchUpInside)
        onlineButton.isHidden = !showsSendWhenOnline

        let stack = UIStackView(arrangedSubviews: [picker, doneButton, onlineButton])
        stack.axis = .vertical
        stack.spacing = 10
        stack.setCustomSpacing(16, after: picker)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])
        updateDoneTitle()
    }

    static func present(
        from presenter: UIViewController,
        isReminder: Bool,
        showsSendWhenOnline: Bool,
        initialDate: Date? = nil,
        onSchedule: @escaping (TDNativeMessageSchedulingState) -> Void,
    ) {
        let controller = ScheduleMessagePickerViewController(
            isReminder: isReminder,
            showsSendWhenOnline: showsSendWhenOnline,
            initialDate: initialDate,
            onSchedule: onSchedule,
        )
        let navigation = UINavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .pageSheet
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        presenter.chatListTopPresenter.present(navigation, animated: true)
    }

    /// updateMinimumDate: the next whole minute at the earliest, a year ahead at the latest.
    private func configureDates() {
        let now = Date()
        let calendar = Calendar.current
        let minuteStart = calendar.dateInterval(of: .minute, for: now)?.start ?? now
        let minute = calendar.component(.minute, from: minuteStart)
        picker.minimumDate = minuteStart.addingTimeInterval(60)
        picker.maximumDate = calendar.date(byAdding: .day, value: 365, to: now)
        picker.date =
            if let initialDate, initialDate > now {
                initialDate
            } else {
                minuteStart.addingTimeInterval(TimeInterval((5 - minute % 5) * 60))
            }
    }

    /// Send today / tomorrow / on a date at a time, or Remind for Saved Messages.
    private func updateDoneTitle() {
        let date = picker.date
        let time = date.formatted(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        let buttonTitle =
            if calendar.isDateInToday(date) {
                L10n.telegram(
                    isReminder ? "Conversation.SetReminder.RemindToday" : "Conversation.ScheduleMessage.SendToday",
                    time,
                )
            } else if calendar.isDateInTomorrow(date) {
                L10n.telegram(
                    isReminder
                        ? "Conversation.SetReminder.RemindTomorrow"
                        : "Conversation.ScheduleMessage.SendTomorrow",
                    time,
                )
            } else {
                L10n.telegram(
                    isReminder ? "Conversation.SetReminder.RemindOn" : "Conversation.ScheduleMessage.SendOn",
                    dayFormatter.string(from: date),
                    time,
                )
            }
        doneButton.configuration?.title = buttonTitle
    }

    @objc private func dateChanged() {
        updateDoneTitle()
    }

    @objc private func cancel() {
        dismiss(animated: true)
    }

    @objc private func scheduleAtDate() {
        let sendDate = max(picker.date, picker.minimumDate ?? picker.date)
        finish(.messageSchedulingStateSendAtDate(TDNativeMessageSchedulingStateSendAtDate(
            sendDate: Int(sendDate.timeIntervalSince1970),
            repeatPeriod: 0,
        )))
    }

    @objc private func scheduleWhenOnline() {
        finish(.messageSchedulingStateSendWhenOnline)
    }

    private func finish(_ state: TDNativeMessageSchedulingState) {
        let onSchedule = onSchedule
        dismiss(animated: true) { onSchedule(state) }
    }
}
