# Firefox installer for Docker builds.
# Downloads via curl (temp write + atomic rename); validates cached tarballs
# with tar before reuse. Expects curl, tar, and dpkg-architecture or uname.

def resolve-multiarch []: nothing -> string {
    let result = try {
        ^dpkg-architecture -qDEB_HOST_MULTIARCH | complete
    } catch {
        {exit_code: 127, stdout: "", stderr: ""}
    }
    if $result.exit_code == 0 {
        $result.stdout | str trim
    } else {
        let arch = (^uname -m | complete)
        if $arch.exit_code != 0 {
            error make {msg: "uname -m failed"}
        }
        match ($arch.stdout | str trim) {
            "x86_64"  => "x86_64-linux-gnu"
            "aarch64" => "aarch64-linux-gnu"
            $other    => (error make {msg: $"unsupported arch: ($other)"})
        }
    }
}

def is-nonempty-file [path: string]: nothing -> bool {
    ($path | path exists) and ((ls $path | get 0.size | into int) > 0)
}

def probe-cached-tarball [path: string, list_flags: list<string>]: nothing -> bool {
    if not (is-nonempty-file $path) {
        return false
    }
    let probe = (^tar ...$list_flags $path | complete)
    if $probe.exit_code == 0 {
        return true
    }
    print $"Invalid cached tarball; re-downloading: ($path)"
    rm -f $path
    false
}

def download-to-cache [url: string, dest: string]: nothing -> bool {
    let tmp = $"($dest).tmp"
    rm -f $tmp
    let dl = (
        ^curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 30 --max-time 600
            -o $tmp $url
        | complete
    )
    if $dl.exit_code != 0 {
        rm -f $tmp
        return false
    }
    ^mv -f $tmp $dest
    true
}

def main [
    --version: string       # Firefox release version (required)
    --locale: string = "en-US"
    --dest: string = "/opt"
    --bin-link: string = "/usr/local/bin/firefox"
    --desktop-entry-source: string  # Path to firefox.desktop in build context (required)
    --desktop-entry-dest: string = "/usr/share/applications/firefox.desktop"
    --download-dir: string = ""     # Cache dir for the tarball; omit to use /tmp and delete after
] {
    if ($version | is-empty) {
        error make {msg: "--version is required"}
    }
    if ($desktop_entry_source | is-empty) {
        error make {msg: "--desktop-entry-source is required"}
    }

    let firefox_dir = $"($dest)/firefox"
    let raw_arch = (^uname -m | str trim)
    let mozilla_arch = match $raw_arch {
        "x86_64"  => "linux-x86_64"
        "aarch64" => "linux-aarch64"
        $other    => (error make {msg: $"unsupported arch: ($other)"})
    }
    let base_url = $"https://download-installer.cdn.mozilla.net/pub/firefox/releases/($version)/($mozilla_arch)/($locale)"
    let url_xz  = $"($base_url)/firefox-($version).tar.xz"
    let url_bz2 = $"($base_url)/firefox-($version).tar.bz2"

    # When a download-dir is given, keep the tarball so BuildKit cache mounts
    # can reuse it across builds. Otherwise fall back to /tmp and clean up.
    let dl_dir = if ($download_dir | is-empty) { "/tmp" } else { $download_dir }
    let keep_tarball = not ($download_dir | is-empty)
    mkdir $dl_dir
    let cache_stem = $"($dl_dir)/firefox-($version)-($mozilla_arch)-($locale)"
    let cache_xz  = $"($cache_stem).tar.xz"
    let cache_bz2 = $"($cache_stem).tar.bz2"

    # Remove existing install
    if ($firefox_dir | path exists) {
        rm -rf $firefox_dir
    }

    # Resolve which tarball to use: prefer xz from cache, then bz2, then download.
    let tarball_info = if (probe-cached-tarball $cache_xz [-tJf]) {
        print $"Using cached tarball: ($cache_xz)"
        {path: $cache_xz, flags: "-xJf"}
    } else if (probe-cached-tarball $cache_bz2 [-tjf]) {
        print $"Using cached tarball: ($cache_bz2)"
        {path: $cache_bz2, flags: "-xjf"}
    } else {
        print $"Downloading Firefox ($version) [($locale)]..."
        if (download-to-cache $url_xz $cache_xz) {
            {path: $cache_xz, flags: "-xJf"}
        } else if (download-to-cache $url_bz2 $cache_bz2) {
            {path: $cache_bz2, flags: "-xjf"}
        } else {
            error make {msg: $"Firefox download failed for both formats.\n  xz:  ($url_xz)\n  bz2: ($url_bz2)"}
        }
    }

    # Extract
    print $"Extracting to ($dest)..."
    let ex = (^tar ($tarball_info.flags) ($tarball_info.path) -C $dest | complete)
    if $ex.exit_code != 0 {
        error make {msg: $"tar failed: ($ex.stderr)"}
    }
    if not $keep_tarball {
        rm -f $tarball_info.path
    }

    # Symlink binary
    if ($bin_link | path exists) {
        rm -f $bin_link
    }
    ^ln -s $"($dest)/firefox/firefox" $bin_link

    # Use system NSS roots module
    let multiarch = (resolve-multiarch)
    let system_nssckbi = $"/usr/lib/($multiarch)/libnssckbi.so"
    if not ($system_nssckbi | path exists) {
        error make {msg: $"system libnssckbi.so not found: ($system_nssckbi)"}
    }
    let nssckbi = $"($dest)/firefox/libnssckbi.so"
    if ($nssckbi | path exists) {
        rm -f $nssckbi
    }
    ^ln -s $system_nssckbi $nssckbi

    # Install desktop entry
    ^cp $desktop_entry_source $desktop_entry_dest
    ^chmod 0644 $desktop_entry_dest

    print "Firefox install complete."
}
