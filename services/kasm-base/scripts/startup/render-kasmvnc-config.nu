#!/usr/bin/env nu

# Read an env string or return a default.
def env-str [name: string, fallback: string]: nothing -> string {
    $env | get --optional $name | default $fallback
}

# Read a validated env string from an explicit allowed set.
def env-one-of [
    name: string
    allowed: list<string>
    fallback: string
]: nothing -> string {
    let raw = ($env | get --optional $name | default $fallback)
    if not ($raw in $allowed) {
        error make {
            msg: $"($name): unsupported value '($raw)'; allowed: ($allowed | str join ', ')"
        }
    }
    $raw
}

# Build the network.ssl sub-record.
# require_ssl is always set; pem paths always resolve to $HOME.
def build-network-ssl [base: record, home: string]: nothing -> record {
    let mode = (env-one-of "OCM_KASM_HTTP_MODE" ["http" "https" "both"] "http")
    let pem = $"($home)/.vnc/self.pem"
    $base
        | upsert require_ssl ($mode == "https")
        | upsert pem_certificate $pem
        | upsert pem_key $pem
}

# Encoding sub-record overrides for a quality profile.
# Returns a record whose keys are sub-sections within encoding.
def quality-encoding [profile: string]: nothing -> record {
    match $profile {
        "bandwidth" => {
            rect_encoding_mode: {min_quality: 3, max_quality: 7, consider_lossless_quality: 7}
            video_encoding_mode: {webp_encoding_time: 50}
            video_streaming_mode: {quality: 28, gop: 48}
        }
        "balanced" => {
            rect_encoding_mode: {min_quality: 4, max_quality: 8, consider_lossless_quality: 8}
            video_encoding_mode: {webp_encoding_time: 40}
        }
        "quality" => {
            rect_encoding_mode: {min_quality: 7, max_quality: 9, consider_lossless_quality: 8}
            video_encoding_mode: {webp_encoding_time: 30}
        }
        "lossless" => {
            rect_encoding_mode: {min_quality: 9, max_quality: 9, consider_lossless_quality: 10}
            video_encoding_mode: {
                enter_video_encoding_mode: {time_threshold: 60, area_threshold: "100%"}
                exit_video_encoding_mode: {time_threshold: 3}
                scaling_algorithm: "nearest"
            }
        }
        _ => {
            error make {
                msg: $"OCM_KASM_QUALITY_PROFILE: unsupported value '($profile)'; allowed: bandwidth, balanced, quality, lossless"
            }
        }
    }
}

# Build the data_loss_prevention section from env.
# All profiles set clipboard.delay_between_operations=0; returns {} when no profile is set.
def build-dlp [base: record]: nothing -> record {
    let profile = ($env | get --optional "OCM_KASM_QUALITY_PROFILE")
    if $profile == null { return $base }
    let clip = (($base.clipboard? | default {}) | upsert delay_between_operations 0)
    $base | upsert clipboard $clip
}

# Build the top-level logging section from env.
# Always returns a populated record; defaults apply when env vars are absent.
def build-logging [base: record]: nothing -> record {
    let raw_level = ($env | get --optional "OCM_KASM_VNC_LOG_LEVEL" | default "30")
    let level = (try { $raw_level | into int } catch {
        error make {msg: $"OCM_KASM_VNC_LOG_LEVEL: '($raw_level)' is not an integer in 0..100"}
    })
    if $level < 0 or $level > 100 {
        error make {msg: $"OCM_KASM_VNC_LOG_LEVEL: ($level) is out of range 0..100"}
    }
    let dest = (env-one-of "OCM_KASM_VNC_LOG_DEST" ["logfile" "syslog"] "logfile")
    let writer = (env-str "OCM_KASM_VNC_LOG_WRITER_NAME" "all")
    $base
        | upsert level $level
        | upsert log_dest $dest
        | upsert log_writer_name $writer
}

# Build the desktop section from env, returns {} when no env vars are set.
def build-desktop [base: record]: nothing -> record {
    mut d = $base
    let res = ($env | get --optional "VNC_RESOLUTION")
    if $res != null {
        let parts = ($res | split row "x")
        if ($parts | length) != 2 {
            error make {msg: $"VNC_RESOLUTION: expected WxH format, got '($res)'"}
        }
        let w = (try { $parts.0 | into int } catch {
            error make {msg: $"VNC_RESOLUTION: width '($parts.0)' is not an integer"}
        })
        let h = (try { $parts.1 | into int } catch {
            error make {msg: $"VNC_RESOLUTION: height '($parts.1)' is not an integer"}
        })
        $d = ($d | upsert resolution {width: $w, height: $h})
    }
    let depth = ($env | get --optional "VNC_COL_DEPTH")
    if $depth != null {
        let di = (try { $depth | into int } catch {
            error make {msg: $"VNC_COL_DEPTH: '($depth)' is not an integer"}
        })
        $d = ($d | upsert pixel_depth $di)
    }
    $d
}

# Build the encoding section from env, returns {} when no env vars are set.
def build-encoding [base: record]: nothing -> record {
    mut enc = $base
    let fps = ($env | get --optional "MAX_FRAME_RATE")
    if $fps != null {
        let fi = (try { $fps | into int } catch {
            error make {msg: $"MAX_FRAME_RATE: '($fps)' is not an integer"}
        })
        $enc = ($enc | upsert max_frame_rate $fi)
    }
    let profile = ($env | get --optional "OCM_KASM_QUALITY_PROFILE")
    if $profile != null {
        let qe = (quality-encoding $profile)
        for key in ($qe | columns) {
            let sub = (($enc | get --optional $key | default {}) | merge ($qe | get $key))
            $enc = ($enc | upsert $key $sub)
        }
    }
    let codec = ($env | get --optional "OCM_KASM_VIDEO_CODEC")
    if $codec != null and $codec != "" {
        let allowed = [
            "auto" "h264" "h264_vaapi" "h265" "h265_vaapi" "av1" "av1_vaapi" "none"
        ]
        if not ($codec in $allowed) {
            error make {
                msg: $"OCM_KASM_VIDEO_CODEC: unsupported value '($codec)'; allowed: ($allowed | str join ', ')"
            }
        }
        if $codec != "none" {
            let vsm = (($enc.video_streaming_mode? | default {}) | upsert codec $codec)
            $enc = ($enc | upsert video_streaming_mode $vsm)
        }
    }
    let vid_log_level = (env-one-of "OCM_KASM_VIDEO_ENCODING_LOG_LEVEL" ["off" "info"] "off")
    if $vid_log_level != "off" {
        let vem = (($enc.video_encoding_mode? | default {}) | upsert logging {level: $vid_log_level})
        $enc = ($enc | upsert video_encoding_mode $vem)
    }
    $enc
}

def main [] {
    let template_path = (
        env-str "OCM_KASM_CONFIG_TEMPLATE" "/dockerstartup/templates/kasmvnc.yaml.nuon"
    )
    let home = $env.HOME
    let output_path = (env-str "OCM_KASM_CONFIG_PATH" $"($home)/.vnc/kasmvnc.yaml")

    let base = open $template_path

    let net_ssl = (build-network-ssl ($base.network.ssl? | default {}) $home)
    let net = (($base.network? | default {}) | upsert ssl $net_ssl)

    let access = (env-one-of "OCM_KASM_PRIMARY_ACCESS" ["write" "view" "none"] "write")
    let command_line = (
        ($base.command_line? | default {}) | upsert prompt ($access == "write")
    )

    let desktop = (build-desktop ($base.desktop? | default {}))
    let encoding = (build-encoding ($base.encoding? | default {}))
    let dlp = (build-dlp ($base.data_loss_prevention? | default {}))
    let logging = (build-logging ($base.logging? | default {}))

    mut config = $base
        | upsert network $net
        | upsert command_line $command_line
        | upsert logging $logging

    if not ($desktop | is-empty) {
        $config = ($config | upsert desktop $desktop)
    }
    if not ($encoding | is-empty) {
        $config = ($config | upsert encoding $encoding)
    }
    if not ($dlp | is-empty) {
        $config = ($config | upsert data_loss_prevention $dlp)
    }

    mkdir ($output_path | path dirname)
    $config | to yaml | save -f $output_path
    print $"KasmVNC config written to ($output_path)"
}
