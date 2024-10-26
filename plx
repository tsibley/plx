#!/bin/bash
# usage: plx install <module> [args…]
#        plx link <module>
#        plx ls [<module>]
#        plx --help
#
# Install Perl programs into isolated environments.
set -euo pipefail

PREFIX="$(realpath "${PREFIX:-$HOME/.local}")"
BIN="$PREFIX/bin"
MAN="$PREFIX/share/man"
ENVS="$PREFIX/share/plx/envs"

main() {
    local cmd="${1:-help}"
    shift || true

    case "$cmd" in
        install)
            install "$@";;

        link)
            link "$@";;

        ls|list)
            list "$@";;

        help|--help|-h)
            help:;;

        *)
            error: unknown command: "$cmd";;
    esac
}

# Install a program.
install() {
    local module="${1:-}"
    [[ -n "$module" ]] || error: module name required
    shift

    local env="$ENVS/${module//::/-}"

    :::::: installing "$module" into "$env"

    [[ -d "$env" ]] && [[ -z "${PLX_FORCE:-}" ]] && error: "$env" already exists
    mkdir -p "$env"

    cpanm --quiet --notest ${PLX_FORCE:+--reinstall} --local-lib-contained "$env" "$module"

    echo
    link "$module"
}

# Link a program.
link() {
    local module="${1:-}"
    [[ -n "$module" ]] || error: module name required
    shift

    local env="$ENVS/${module//::/-}"

    [[ -d "$env" ]] || error: "$module" not installed "(checked $env)"

    :::::: linking programs and man pages

    mkdir -p "$env/shim" "$BIN" "$MAN"

    local path filename failures=0
    while read -d $'\0' -r path; do
        filename="$(basename "$path")"
        case "$path" in
            "$env"/bin/"$filename")
                # Write static shim
                cat >"$env/shim/$filename" <<'~~~'
#!/bin/bash
[[ -n "${PLX_DEBUG:-}" ]] && set -x
env="$(realpath "$(dirname "$(realpath "$0")")/..")"
export PATH="${env}/bin${PATH:+:}${PATH}"
export PERL5LIB="${env}/lib/perl5${PERL5LIB:+:}${PERL5LIB}"
exec "$env"/bin/"$(basename "$(realpath "$0")")" "$@"
~~~
                chmod +x "$env/shim/$filename"

                # Link shim to global bin
                ln -snvr${PLX_FORCE:+f} "$env/shim/$filename" "$BIN/$filename" || let ++failures

                # XXX FIXME: record receipt for upgrade/uninstall later
                ;;

            "$env"/man/man[0-9]/"$filename")
                # Link to global man
                local section="$(basename "$(dirname "$path")")"
                mkdir -p "$MAN/$section"
                ln -snvr${PLX_FORCE:+f} "$path" "$MAN/$section/$filename" || let ++failures

                # XXX FIXME: record receipt for upgrade/uninstall later
                ;;
        esac
    done < <(perl -I"$env"/lib/perl5 -MExtUtils::Installed -l0E 'print for sort ExtUtils::Installed->files(shift)' "$module")

    if [[ $failures -gt 0 ]]; then
        :::::: failed to link "$failures" programs or man pages
        :::::: re-run under PLX_FORCE=1 to forcibly replace existing files
    fi
}

# List programs.
list() {
    local -a envs

    if [[ $# -gt 0 ]]; then
        local module="${1:-}"
        [[ -n "$module" ]] || error: module name required when arguments given
        shift

        local env="$ENVS/${module//::/-}"

        [[ -d "$env" ]] || error: "$module" not installed "(checked $env)"

        envs=("$env")
    else
        envs=("$ENVS"/*)
    fi

    for env in "${envs[@]}"; do
        :::::: "$(basename "$env")" "($env)"
        ls "$env/shim" 2>/dev/null || true
    done
}

# Print a log message.
::::::() {
    echo '::::::' "$@"
}

# Print an error message.
error:() {
    echo error: "$@" >&2
    echo >&2
    help: usage >&2
    return 1
}

# Print the embedded help at the top of this file.
help:() {
    local what="${1:-}"
    local line
    while read -r line; do
        if [[ $line =~ ^#! ]]; then
            continue
        elif [[ $line =~ ^# ]]; then
            line="${line/##/}"
            line="${line/# /}"
            if [[ $what == usage && $line =~ ^\s*$ ]]; then
                break
            fi
            echo "$line"
        else
            break
        fi
    done < "$0"
}

main "$@"
