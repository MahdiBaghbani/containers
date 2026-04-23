#!/usr/bin/env nu

# Run an external command and fail fast on non-zero exit.
def run! [bin: string, ...args: string] {
    let result = (run-external $bin ...$args | complete)
    if $result.exit_code != 0 {
        let cmd_str = $"($bin) ($args | str join ' ')"
        error make {msg: $"'($cmd_str)' failed exit=($result.exit_code): ($result.stderr | str trim)"}
    }
}

def main [...paths: string] {
    for path in $paths {
        print $"fix permissions for: ($path)"

        # Make scripts and desktop launchers executable.
        for f in (glob $"($path)/**/*.{sh,nu,desktop}") {
            run! "chmod" "+x" $f
        }

        # Set group to root, then mirror user permissions onto the group.
        run! "chgrp" "-R" "root" $path
        run! "chmod" "-R" "g=u" $path
    }
}
