// WebAppProbe.swift

#if DEBUG
    import UIKit

    /// Launch with `-ui-probe-web-app`. Once an account is active it opens the Web App sheet on a local page whose
    /// buttons post TelegramWebviewProxy events (main and secondary buttons, back button, expansion, header colour,
    /// popup, closing confirmation, haptics, theme, close) and which lists the events it gets back. No bot is
    /// involved and nothing is sent.
    @MainActor enum WebAppProbe {
        private static let page = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        body { font: 15px -apple-system; margin: 12px; background: var(--bg, #fff); color: var(--fg, #000); }
        button { font: 15px -apple-system; margin: 3px; padding: 8px 10px; border-radius: 8px; border: 0;
          background: #3478f6; color: #fff; }
        #log { font: 12px ui-monospace; white-space: pre-wrap; margin-top: 8px; }
        </style></head><body>
        <div>
        <button onclick="post('web_app_setup_main_button', {is_visible: true, text: 'Probe Main', color: '#2ea043', text_color: '#ffffff'})">main</button>
        <button onclick="post('web_app_setup_secondary_button', {is_visible: true, text: 'Second', position: 'left'})">second</button>
        <button onclick="post('web_app_setup_main_button', {is_visible: true, text: 'Probe Main', is_progress_visible: true})">progress</button>
        <button onclick="post('web_app_setup_back_button', {is_visible: true})">back</button>
        <button onclick="post('web_app_expand')">expand</button>
        <button onclick="post('web_app_set_header_color', {color: '#cc3333'})">header</button>
        <button onclick="post('web_app_open_popup', {title: 'Probe', message: 'Pick one', buttons: [{id: 'alpha', type: 'default', text: 'Alpha'}, {id: 'gone', type: 'destructive', text: 'Remove'}, {id: 'cancel', type: 'cancel'}]})">popup</button>
        <button onclick="post('web_app_setup_closing_behavior', {need_confirmation: true})">confirm close</button>
        <button onclick="post('web_app_trigger_haptic_feedback', {type: 'impact', impact_style: 'medium'})">haptic</button>
        <button onclick="post('web_app_request_theme')">theme</button>
        <button onclick="post('web_app_close')">close</button>
        </div>
        <div id="log"></div>
        <script>
        function line(text) { document.getElementById('log').textContent = text + '\\n' + document.getElementById('log').textContent; }
        function post(name, data) { window.TelegramWebviewProxy.postEvent(name, JSON.stringify(data || {})); line('> ' + name); }
        window.TelegramGameProxy = { receiveEvent: function(name, data) {
          if (name === 'theme_changed') {
            document.body.style.setProperty('--bg', data.theme_params.bg_color);
            document.body.style.setProperty('--fg', data.theme_params.text_color);
            line('< theme_changed bg=' + data.theme_params.bg_color + ' button=' + data.theme_params.button_color);
          } else if (name === 'viewport_changed') {
            line('< viewport_changed h=' + Math.round(data.height) + ' expanded=' + data.is_expanded);
          } else {
            line('< ' + name + ' ' + JSON.stringify(data));
          }
        } };
        post('web_app_ready'); post('web_app_request_theme'); post('web_app_request_viewport');
        </script></body></html>
        """

        static func runIfRequested(in window: UIWindow) {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-web-app") else { return }
            Task { @MainActor in
                for _ in 0..<60 where TDLib.shared.activeAccountID == nil {
                    try? await Task.sleep(for: .milliseconds(500))
                }
                guard TDLib.shared.activeAccountID != nil else { return }
                try? await Task.sleep(for: .seconds(2))
                var presenter = window.rootViewController
                while let presented = presenter?.presentedViewController {
                    presenter = presented
                }
                guard let presenter, let url = URL(string: "https://bettertg.probe/") else { return }
                let controller = WebAppViewController(
                    launch: WebAppLaunch(
                        source: .probe(html: page),
                        url: url,
                        requiresSameOrigin: false,
                        botUserID: 0,
                        botName: "Probe Bot",
                        botUsername: "probe_bot",
                        client: TDLib.shared.activeClient,
                    ),
                    actions: .init(
                        openTelegramLink: { _ in },
                        switchInline: { _, _ in },
                    ),
                )
                presenter.present(controller, animated: true)
            }
        }
    }
#endif
