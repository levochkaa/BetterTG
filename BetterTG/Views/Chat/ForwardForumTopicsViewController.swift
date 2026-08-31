// ForwardForumTopicsViewController.swift

import TDLibKitDynamic
import UIKit

@MainActor final class ForwardForumTopicsViewController: UIViewController, UITableViewDelegate,
    UISearchBarDelegate
{
    private enum Section {
        case topics
    }

    var onToggle: ((ForumTopic, Bool) -> Void)?

    private let chat: Chat
    private let preparedForward: PreparedMessageForward
    private let client: TDLibClient
    private let accountID: UUID
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let searchBar = UISearchBar()
    private let navigationBarView = UIVisualEffectView(
        effect: UIBlurEffect(style: .systemChromeMaterial),
    )
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private var navigationBarHeightConstraint: NSLayoutConstraint!
    private var dataSource: UITableViewDiffableDataSource<Section, Int>!
    private var topics = [ForumTopic]()
    private var selectedTopicIDs: Set<Int>
    private var allowedTopicIDs = Set<Int>()
    private var loadTask: Task<Void, Never>?
    private var generation = UInt64.zero
    private var cursor = ForumTopicPageCursor.zero
    private var requestedCursors = Set<ForumTopicPageCursor>()
    private var hasMore = true
    private var loading = false
    private var query = ""
    private var canManageTopics = false
    private var rightsResolved = false

    private var contextIsCurrent: Bool {
        TDLib.shared.activeAccountID == accountID
            && TDLib.shared.activeClient.id == client.id
    }

    init(
        chat: Chat,
        preparedForward: PreparedMessageForward,
        client: TDLibClient,
        accountID: UUID,
        selectedTopicIDs: Set<Int>,
    ) {
        self.chat = chat
        self.preparedForward = preparedForward
        self.client = client
        self.accountID = accountID
        self.selectedTopicIDs = selectedTopicIDs
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureNavigation()
        configureTable()
        configureDataSource()
        resolveRightsAndLoad()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        navigationBarHeightConstraint?.constant = view.safeAreaInsets.top + 50
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard abs(searchBar.frame.width - tableView.bounds.width) > 0.5 else { return }
        searchBar.frame.size.width = tableView.bounds.width
        tableView.tableHeaderView = searchBar
    }

    func searchBar(_: UISearchBar, textDidChange searchText: String) {
        let updated = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard updated != query else { return }
        query = updated
        load(reset: true)
    }

    func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let topicID = dataSource.itemIdentifier(for: indexPath),
              allowedTopicIDs.contains(topicID),
              let topic = topics.first(where: { $0.info.forumTopicId == topicID })
        else { return }
        let selected = !selectedTopicIDs.contains(topicID)
        if selected {
            selectedTopicIDs.insert(topicID)
        } else {
            selectedTopicIDs.remove(topicID)
        }
        onToggle?(topic, selected)
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems([topicID])
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    func tableView(_: UITableView, willDisplay _: UITableViewCell, forRowAt indexPath: IndexPath) {
        if indexPath.row >= max(0, topics.count - 5) {
            load(reset: false)
        }
    }

    private func configureTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 70
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 80, bottom: 0, right: 0)
        tableView.register(ForumTopicCell.self, forCellReuseIdentifier: ForumTopicCell.reuseID)
        searchBar.delegate = self
        searchBar.placeholder = "Search Topics"
        searchBar.autocapitalizationType = .none
        searchBar.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 56)
        tableView.tableHeaderView = searchBar
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: navigationBarView.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func configureNavigation() {
        navigationBarView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(navigationBarView)
        navigationBarHeightConstraint = navigationBarView.heightAnchor.constraint(
            equalToConstant: view.safeAreaInsets.top + 50,
        )

        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.configuration = .plain()
        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold),
            forImageIn: .normal,
        )
        backButton.accessibilityLabel = "Back"
        backButton.addTarget(self, action: #selector(backPressed), for: .touchUpInside)
        navigationBarView.contentView.addSubview(backButton)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = chat.title
        titleLabel.textColor = .label
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.8
        navigationBarView.contentView.addSubview(titleLabel)

        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator
        navigationBarView.contentView.addSubview(separator)

        NSLayoutConstraint.activate([
            navigationBarView.topAnchor.constraint(equalTo: view.topAnchor),
            navigationBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navigationBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            navigationBarHeightConstraint,
            backButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 4),
            backButton.bottomAnchor.constraint(equalTo: navigationBarView.bottomAnchor, constant: -3),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),
            titleLabel.centerXAnchor.constraint(equalTo: navigationBarView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: backButton.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -56,
            ),
            separator.leadingAnchor.constraint(equalTo: navigationBarView.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: navigationBarView.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: navigationBarView.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / traitCollection.displayScale),
        ])
    }

    private func configureDataSource() {
        dataSource = UITableViewDiffableDataSource<Section, Int>(
            tableView: tableView,
        ) { [weak self] tableView, indexPath, topicID in
            guard let self,
                  let cell = tableView.dequeueReusableCell(
                      withIdentifier: ForumTopicCell.reuseID,
                      for: indexPath,
                  ) as? ForumTopicCell,
                  let topic = topics.first(where: { $0.info.forumTopicId == topicID })
            else { return UITableViewCell() }
            let allowed = allowedTopicIDs.contains(topicID)
            let selected = selectedTopicIDs.contains(topicID)
            cell.configure(topic: topic, client: client)
            cell.accessoryType = selected ? .checkmark : .none
            cell.tintColor = .systemBlue
            cell.contentView.alpha = allowed ? 1 : 0.48
            cell.isUserInteractionEnabled = allowed
            cell.accessibilityValue = selected
                ? "Selected"
                : (allowed ? nil : "Closed")
            return cell
        }
    }

    private func resolveRightsAndLoad() {
        loadTask = Task { [weak self] in
            guard let self else { return }
            guard case .chatTypeSupergroup(let type) = chat.type,
                  let supergroup = try? await client.getSupergroup(supergroupId: type.supergroupId),
                  contextIsCurrent
            else {
                showError("This forum couldn't be checked.")
                return
            }
            canManageTopics =
                switch supergroup.status {
                case .chatMemberStatusCreator:
                    true
                case .chatMemberStatusAdministrator(let administrator):
                    administrator.rights.canManageTopics
                default:
                    false
                }
            rightsResolved = true
            loadTask = nil
            load(reset: true)
        }
    }

    private func load(reset: Bool) {
        guard rightsResolved, contextIsCurrent, !loading || reset else { return }
        if reset {
            generation &+= 1
            loadTask?.cancel()
            cursor = .zero
            requestedCursors.removeAll()
            hasMore = true
        } else {
            guard hasMore else { return }
        }
        let requestedCursor = cursor
        guard requestedCursors.insert(requestedCursor).inserted else {
            hasMore = false
            return
        }
        let currentGeneration = generation
        let currentQuery = query
        loading = true
        updateBackground()
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await client.getForumTopics(
                    chatId: chat.id,
                    limit: 50,
                    offsetDate: requestedCursor.date,
                    offsetForumTopicId: requestedCursor.forumTopicID,
                    offsetMessageId: requestedCursor.messageID,
                    query: currentQuery,
                )
                guard !Task.isCancelled,
                      currentGeneration == generation,
                      currentQuery == query,
                      contextIsCurrent
                else { return }
                topics = ForumTopicPageState.merging(
                    existing: reset ? [] : topics,
                    incoming: page.topics,
                )
                let chatEligibility = MessageForwardingService.localEligibility(
                    of: chat,
                    for: preparedForward,
                )
                allowedTopicIDs = Set(topics.compactMap { topic in
                    let restricted = topic.info.isClosed || topic.info.isHidden
                    let canPost = !restricted || topic.info.isOutgoing || self.canManageTopics
                    return chatEligibility.isAllowed && canPost ? topic.info.forumTopicId : nil
                })
                cursor = ForumTopicPageCursor(response: page)
                hasMore = ForumTopicPageState.hasMore(
                    response: page,
                    requestedCursor: requestedCursor,
                )
                loading = false
                loadTask = nil
                applySnapshot()
            } catch is CancellationError {
                return
            } catch {
                guard currentGeneration == generation else { return }
                requestedCursors.remove(requestedCursor)
                loading = false
                loadTask = nil
                showError("Topics couldn't be loaded.")
            }
        }
    }

    private func applySnapshot() {
        let previous = Set(dataSource.snapshot().itemIdentifiers)
        let ids = topics.map(\.info.forumTopicId)
        var snapshot = NSDiffableDataSourceSnapshot<Section, Int>()
        snapshot.appendSections([.topics])
        snapshot.appendItems(ids)
        let retained = ids.filter(previous.contains)
        if !retained.isEmpty {
            snapshot.reconfigureItems(retained)
        }
        dataSource.apply(snapshot, animatingDifferences: true)
        updateBackground()
    }

    private func updateBackground() {
        guard topics.isEmpty else {
            tableView.backgroundView = nil
            return
        }
        if loading {
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.startAnimating()
            tableView.backgroundView = spinner
        } else {
            let label = UILabel()
            label.text = query.isEmpty ? "No topics" : "No topics found"
            label.textAlignment = .center
            label.textColor = .secondaryLabel
            tableView.backgroundView = label
        }
    }

    private func showError(_ message: String) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: "Forward", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    @objc private func backPressed() {
        navigationController?.popViewController(animated: true)
    }
}
