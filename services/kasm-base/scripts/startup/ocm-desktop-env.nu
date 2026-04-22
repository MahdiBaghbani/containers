# Desktop environment defaults for OCM container sessions.
# Invoked by autostart scripts after wait-for-desktop:
#   /usr/local/bin/nu /dockerstartup/ocm-desktop-env.nu
#
# Env knobs:
#   OCM_DEFAULT_WEB_BROWSER - empty (no-op) or short name: firefox,
#       chrome, google-chrome, chromium; or explicit <id>.desktop
#   OCM_XFCE_GTK_THEME      - optional GTK theme name (xsettings)
#   OCM_XFCE_ICON_THEME     - optional icon theme name (xsettings)
#
# Idempotency: ~/.local/share/ocm/default-browser sentinel tracks the
# last-applied browser id; re-runs with the same id are no-ops.

# Map a short browser name to its .desktop application id.
def browser-desktop-id [name: string]: nothing -> string {
    match ($name | str downcase | str trim) {
        "firefox"       => "firefox.desktop"
        "chrome"        => "google-chrome.desktop"
        "google-chrome" => "google-chrome.desktop"
        "chromium"      => "chromium-browser.desktop"
        _               => $name
    }
}

def apply-default-browser [raw: string]: nothing -> nothing {
    let id = (browser-desktop-id $raw)
    if ($id | is-empty) { return }

    let sentinel_dir = ($env.HOME | path join ".local" "share" "ocm")
    let sentinel = ($sentinel_dir | path join "default-browser")

    if ($sentinel | path exists) {
        let last = (open --raw $sentinel | str trim)
        if $last == $id {
            print $"[ocm-desktop-env] Default browser already ($id) - skipping."
            return
        }
    }

    print $"[ocm-desktop-env] Setting default browser to ($id)."

    try {
        ^xdg-settings set default-web-browser $id
    } catch {|err|
        print $"[ocm-desktop-env] xdg-settings failed: ($err.msg)"
    }

    let mime_types = [
        "x-scheme-handler/http"
        "x-scheme-handler/https"
        "text/html"
        "application/xhtml+xml"
        "application/x-extension-htm"
        "application/x-extension-html"
        "application/x-extension-shtml"
        "application/x-extension-xhtml"
        "application/x-extension-xht"
    ]
    for mt in $mime_types {
        try {
            ^xdg-mime default $id $mt
        } catch {|err|
            print $"[ocm-desktop-env] xdg-mime default ($id) ($mt) failed: ($err.msg)"
        }
    }

    mkdir $sentinel_dir
    $id | save --force $sentinel
}

def apply-gtk-theme [theme: string]: nothing -> nothing {
    if ($theme | str trim | is-empty) { return }
    print $"[ocm-desktop-env] Setting GTK theme: ($theme)"
    try {
        ^xfconf-query -c xsettings -p /Net/ThemeName -s $theme
    } catch {|err|
        print $"[ocm-desktop-env] xfconf-query (GTK theme) failed: ($err.msg)"
    }
}

def apply-icon-theme [theme: string]: nothing -> nothing {
    if ($theme | str trim | is-empty) { return }
    print $"[ocm-desktop-env] Setting icon theme: ($theme)"
    try {
        ^xfconf-query -c xsettings -p /Net/IconThemeName -s $theme
    } catch {|err|
        print $"[ocm-desktop-env] xfconf-query (icon theme) failed: ($err.msg)"
    }
}

def main [] {
    let browser_raw = ($env.OCM_DEFAULT_WEB_BROWSER? | default "" | str trim)
    if not ($browser_raw | is-empty) {
        apply-default-browser $browser_raw
    }

    let gtk_theme = ($env.OCM_XFCE_GTK_THEME? | default "" | str trim)
    if not ($gtk_theme | is-empty) {
        apply-gtk-theme $gtk_theme
    }

    let icon_theme = ($env.OCM_XFCE_ICON_THEME? | default "" | str trim)
    if not ($icon_theme | is-empty) {
        apply-icon-theme $icon_theme
    }
}
