// WebAppProbe.swift

#if DEBUG
    import UIKit

    /// Launch with `-ui-probe-web-app`. Once an account is active it opens the Web App sheet on a local page whose
    /// buttons post TelegramWebviewProxy events (main and secondary buttons, back button, expansion, header colour,
    /// popup, closing confirmation, haptics, theme, DeviceStorage and SecureStorage, swipe behaviour, keyboard, the
    /// write access and phone alerts, close, fullscreen and orientation lock, QR scanner, biometry, location, motion
    /// sensors, home screen) and which lists the events it gets back, the sensors' latest values on one line each.
    /// No bot is involved and nothing is sent: the probe bot has ID 0, so the alerts' OK buttons fail without a
    /// request reaching Telegram. WebAppLaunchProbe opens the same page for its attachment menu and Open App launches.
    @MainActor enum WebAppProbe {
        static let page = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        body { font: 15px -apple-system; margin: 12px; background: var(--bg, #fff); color: var(--fg, #000); }
        button { font: 15px -apple-system; margin: 3px; padding: 8px 10px; border-radius: 8px; border: 0;
          background: #3478f6; color: #fff; }
        #log { font: 12px ui-monospace; white-space: pre-wrap; margin-top: 8px; }
        #sensors { font: 12px ui-monospace; white-space: pre-wrap; margin-top: 8px; color: #2ea043; }
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
        <button onclick="post('web_app_device_storage_save_key', {req_id: 'd1', key: 'probe', value: 'stored ' + Date.now()})">dev save</button>
        <button onclick="post('web_app_device_storage_get_key', {req_id: 'd2', key: 'probe'})">dev get</button>
        <button onclick="post('web_app_device_storage_save_key', {req_id: 'd3', key: 'probe', value: 5})">dev bad</button>
        <button onclick="post('web_app_device_storage_clear', {req_id: 'd4'})">dev clear</button>
        <button onclick="post('web_app_secure_storage_save_key', {req_id: 's1', key: 'probe', value: 'secret'})">sec save</button>
        <button onclick="post('web_app_secure_storage_get_key', {req_id: 's2', key: 'probe'})">sec get</button>
        <button onclick="post('web_app_secure_storage_restore_key', {req_id: 's3', key: 'probe'})">sec restore</button>
        <button onclick="post('web_app_secure_storage_clear', {req_id: 's4'})">sec clear</button>
        <button onclick="post('web_app_setup_swipe_behavior', {allow_vertical_swipe: false})">no swipe</button>
        <input id="field" placeholder="type" size="6"><button onclick="post('web_app_hide_keyboard')">hide kb</button>
        <button onclick="post('web_app_request_write_access')">write</button>
        <button onclick="post('web_app_request_phone')">phone</button>
        <button onclick="post('web_app_close')">close</button>
        </div>
        <div>
        <button onclick="post('web_app_request_fullscreen')">fullscreen</button>
        <button onclick="post('web_app_exit_fullscreen')">exit fullscreen</button>
        <button onclick="post('web_app_toggle_orientation_lock', {locked: true})">lock</button>
        <button onclick="post('web_app_toggle_orientation_lock', {locked: false})">unlock</button>
        <button onclick="post('web_app_open_scan_qr_popup', {text: 'Scan a code'})">qr</button>
        <button onclick="post('web_app_close_scan_qr_popup')">close qr</button>
        </div>
        <div>
        <button onclick="post('web_app_biometry_get_info')">bio info</button>
        <button onclick="post('web_app_biometry_request_access', {reason: 'Probe'})">bio access</button>
        <button onclick="post('web_app_biometry_request_auth', {reason: 'Probe'})">bio auth</button>
        <button onclick="post('web_app_biometry_update_token', {token: 'secret', reason: 'Probe'})">bio token</button>
        <button onclick="post('web_app_biometry_update_token', {token: ''})">bio clear</button>
        <button onclick="post('web_app_biometry_open_settings')">bio settings</button>
        </div>
        <div>
        <button onclick="post('web_app_check_location')">loc check</button>
        <button onclick="post('web_app_request_location')">loc request</button>
        <button onclick="post('web_app_open_location_settings')">loc settings</button>
        <button onclick="post('web_app_check_home_screen')">home check</button>
        <button onclick="post('web_app_add_to_home_screen')">home add</button>
        </div>
        <div>
        <button onclick="post('web_app_start_accelerometer', {refresh_rate: 500})">accel</button>
        <button onclick="post('web_app_stop_accelerometer')">stop accel</button>
        <button onclick="post('web_app_start_gyroscope', {refresh_rate: 500})">gyro</button>
        <button onclick="post('web_app_stop_gyroscope')">stop gyro</button>
        <button onclick="post('web_app_start_device_orientation', {refresh_rate: 500, need_absolute: true})">
        orient</button>
        <button onclick="post('web_app_stop_device_orientation')">stop orient</button>
        </div>
        <div id="sensors"></div>
        <div id="log"></div>
        <script>
        function line(text) { document.getElementById('log').textContent = text + '\\n' + document.getElementById('log').textContent; }
        function post(name, data) { window.TelegramWebviewProxy.postEvent(name, JSON.stringify(data || {})); line('> ' + name); }
        var sensors = {};
        function sensor(name, data) {
          sensors[name] = name.replace('_changed', '') + ' ' + Object.keys(data).map(function(key) {
            var value = data[key];
            return key + '=' + (typeof value === 'number' ? value.toFixed(2) : value);
          }).join(' ');
          document.getElementById('sensors').textContent = Object.values(sensors).join('\\n');
        }
        window.TelegramGameProxy = { receiveEvent: function(name, data) {
          if (name === 'theme_changed') {
            document.body.style.setProperty('--bg', data.theme_params.bg_color);
            document.body.style.setProperty('--fg', data.theme_params.text_color);
            line('< theme_changed bg=' + data.theme_params.bg_color + ' button=' + data.theme_params.button_color);
          } else if (name === 'viewport_changed') {
            line('< viewport_changed h=' + Math.round(data.height) + ' expanded=' + data.is_expanded);
          } else if (/^(accelerometer|gyroscope|device_orientation)_changed$/.test(name)) {
            sensor(name, data);
          } else {
            line('< ' + name + ' ' + JSON.stringify(data));
          }
        } };
        post('web_app_ready'); post('web_app_request_theme'); post('web_app_request_viewport');
        </script></body></html>
        """

        static func runIfRequested(in window: UIWindow) {
            runTransferIfRequested(in: window)
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
                        accountID: TDLib.shared.activeAccountID,
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

        /// `-ui-probe-secure-transfer`: the SecureStorage import sheet for two accounts that are gone, with the active
        /// account's avatar in place of a bot's. Import and Close only log the choice; no Keychain item moves.
        private static func runTransferIfRequested(in window: UIWindow) {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-secure-transfer") else { return }
            Task { @MainActor in
                for _ in 0..<60 where TDLib.shared.activeAccount?.userID == nil {
                    try? await Task.sleep(for: .milliseconds(500))
                }
                guard let account = TDLib.shared.activeAccount, let userID = account.userID else { return }
                try? await Task.sleep(for: .seconds(2))
                var presenter = window.rootViewController
                while let presented = presenter?.presentedViewController {
                    presenter = presented
                }
                let now = Int32(Date().timeIntervalSince1970)
                let controller = WebAppSecureStorageTransferViewController(
                    keys: [
                        .init(uuid: "probe-a", accountName: "Old Account", timestamp: now - 86400 * 40),
                        .init(uuid: "probe-b", accountName: "Work Account", timestamp: now - 86400 * 3),
                    ],
                    botUserID: userID,
                    botName: "Probe Bot",
                    accountID: account.id,
                    client: TDLib.shared.activeClient,
                ) { uuid in
                    print("[secure-transfer-probe] chose \(uuid ?? "nil")")
                }
                presenter?.present(controller, animated: true)
            }
        }
    }
#endif
