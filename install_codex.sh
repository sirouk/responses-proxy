#!/bin/bash

### Thanks to Z.AI for creating this script! Original version, which uses z.ai, here: https://cdn.bigmodel.cn/install/claude_code_zai_env.sh

set -euo pipefail

SCRIPT_NAME=$(basename "$0")
CONFIG_DIR="${HOME}/.codex"
CONFIG_FILE="${CONFIG_DIR}/config.toml"
ENV_FILE="${CONFIG_DIR}/env"
ENV_VAR_NAME="MY_PROVIDER_API_KEY"
API_KEY_URL="https://chutes.ai/app/api"
DEFAULT_BASE_URL="https://responses.chutes.ai/v1"
MODELS_API_BASE_URL="https://llm.chutes.ai"
DEFAULT_MODEL="Qwen/Qwen3-Coder-480B-A35B-Instruct-FP8"
CODEX_REPO_SLUG="chutesai/codex"
GITHUB_API="https://api.github.com"
USER_DEFINED_LINUX_FLAVOR=0
if [ -n "${CODEX_LINUX_TARGET_FLAVOR+x}" ]; then
    USER_DEFINED_LINUX_FLAVOR=1
fi
LINUX_TARGET_FLAVOR="${CODEX_LINUX_TARGET_FLAVOR:-gnu}"
CODEX_RELEASE_TAG="${CODEX_RELEASE_TAG:-nightly}"
OS_UNAME="$(uname -s)"
ARCH_UNAME="$(uname -m)"
PLATFORM_OS=""
CODEX_BINARY_DEST_DEFAULT="/usr/local/bin/codex"
DETECTED_ASSET_NAME=""
KEY_STORED_ON_DISK=0

log_info() {
    echo "[INFO] $*" >&2
}

log_success() {
    echo "[OK] $*" >&2
}

log_warn() {
    echo "[WARN] $*" >&2
}

log_error() {
    echo "[ERROR] $*" >&2
    exit 1
}

require_command() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_error "Required command '$cmd' is not available in PATH."
    fi
}

ensure_dir_exists() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir" || log_error "Failed to create directory: $dir"
    fi
}

backup_file() {
    local file="$1"
    if [ -f "$file" ]; then
        local backup="${file}.bak.$(date +%Y%m%d%H%M%S)"
        cp "$file" "$backup" || log_error "Failed to back up $file"
        log_info "Backed up existing file to $backup"
    fi
}

determine_platform_defaults() {
    case "$OS_UNAME" in
        Darwin)
            PLATFORM_OS="macos"
            CODEX_BINARY_DEST_DEFAULT="/usr/local/bin/codex"
            ;;
        Linux)
            PLATFORM_OS="linux"
            CODEX_BINARY_DEST_DEFAULT="/usr/local/bin/codex"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            PLATFORM_OS="windows"
            CODEX_BINARY_DEST_DEFAULT="${HOME}/.codex/bin/codex.exe"
            ;;
        *)
            PLATFORM_OS="unknown"
            CODEX_BINARY_DEST_DEFAULT="/usr/local/bin/codex"
            log_warn "Unrecognized operating system '${OS_UNAME}'. Attempting install with default settings."
            ;;
    esac
}

determine_platform_defaults

detect_windows_env_fallback() {
    if [ "$PLATFORM_OS" = "windows" ]; then
        return
    fi

    local os_env="${OS:-}"
    local msystem_env="${MSYSTEM:-}"
    local ostype_env="${OSTYPE:-}"

    if [ "$os_env" = "Windows_NT" ] \
        || [[ "$msystem_env" =~ ^(MINGW|MSYS|CYGWIN) ]] \
        || [[ "$ostype_env" == *"msys"* ]] \
        || [[ "$ostype_env" == *"cygwin"* ]]; then
        PLATFORM_OS="windows"
        CODEX_BINARY_DEST_DEFAULT="${HOME}/.codex/bin/codex.exe"
    fi
}

detect_windows_env_fallback

normalize_windows_path() {
    local raw_path="$1"
    if [ -z "$raw_path" ]; then
        return
    fi

    if command -v cygpath >/dev/null 2>&1; then
        cygpath -u "$raw_path"
        return
    fi

    local path="${raw_path//\\//}"
    if [[ "$path" =~ ^([A-Za-z]):(.*)$ ]]; then
        local drive="${BASH_REMATCH[1]}"
        local rest="${BASH_REMATCH[2]}"
        drive=$(printf '%s' "$drive" | tr '[:upper:]' '[:lower:]')
        printf '/%s%s\n' "$drive" "$rest"
    else
        printf '%s\n' "$path"
    fi
}

adjust_paths_for_platform() {
    if [ "$PLATFORM_OS" != "windows" ]; then
        return
    fi

    local win_home="${USERPROFILE:-}"
    if [ -z "$win_home" ]; then
        return
    fi

    local posix_home
    posix_home=$(normalize_windows_path "$win_home")
    if [ -z "$posix_home" ]; then
        return
    fi

    CONFIG_DIR="${posix_home}/.codex"
    CONFIG_FILE="${CONFIG_DIR}/config.toml"
    ENV_FILE="${CONFIG_DIR}/env"
    CODEX_BINARY_DEST_DEFAULT="${CONFIG_DIR}/bin/codex.exe"
}

adjust_paths_for_platform

version_lt() {
    local IFS=.
    local i
    local -a ver1=($1) ver2=($2)
    local len=${#ver1[@]}
    if [ ${#ver2[@]} -gt "$len" ]; then
        len=${#ver2[@]}
    fi
    for ((i = 0; i < len; i++)); do
        local a=${ver1[i]:-0}
        local b=${ver2[i]:-0}
        if ((10#$a < 10#$b)); then
            return 0
        elif ((10#$a > 10#$b)); then
            return 1
        fi
    done
    return 1
}

detect_glibc_version() {
    if ! command -v ldd >/dev/null 2>&1; then
        return
    fi

    local output
    if ! output=$(ldd --version 2>&1 | head -n1); then
        return
    fi

    if echo "$output" | grep -qi "musl"; then
        printf '%s\n' "musl"
        return
    fi

    if [[ "$output" =~ ([0-9]+\.[0-9]+(\.[0-9]+)?) ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
    fi
}

auto_select_linux_flavor() {
    if [ "$PLATFORM_OS" != "linux" ] || [ "$USER_DEFINED_LINUX_FLAVOR" -eq 1 ]; then
        return
    fi

    local detected
    detected=$(detect_glibc_version || true)
    if [ -z "$detected" ]; then
        log_warn "Unable to detect libc version; defaulting to ${LINUX_TARGET_FLAVOR}"
        return
    fi

    if [ "$detected" = "musl" ]; then
        LINUX_TARGET_FLAVOR="musl"
        log_info "Detected musl libc via ldd; using musl Codex binary."
        return
    fi

    if version_lt "$detected" "2.39"; then
        LINUX_TARGET_FLAVOR="musl"
        log_info "Detected glibc ${detected} (<2.39); using musl Codex binary."
    else
        log_info "Detected glibc ${detected}; using GNU Codex binary."
    fi
}

auto_select_linux_flavor

if [ -z "${CODEX_BINARY_DEST:-}" ]; then
    CODEX_BINARY_DEST="$CODEX_BINARY_DEST_DEFAULT"
fi

if [ "$PLATFORM_OS" = "windows" ] && [[ "$CODEX_BINARY_DEST" != *.exe ]]; then
    CODEX_BINARY_DEST="${CODEX_BINARY_DEST}.exe"
fi

github_api_request() {
    local path="$1"
    local args=(--max-time 30 --silent --show-error --location --fail)
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    fi
    args+=(-H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28")

    local response=""
    if ! response=$(curl "${args[@]}" "${GITHUB_API}${path}"); then
        log_error "GitHub API request failed (path: ${path}). Check connectivity or set http_proxy/https_proxy if needed."
    fi

    # Check if response contains any non-whitespace content
    # Note: using grep is much faster than bash parameter expansion ${response//[[:space:]]/}
    # which can hang for several seconds on large (17KB+) JSON responses
    if ! grep -q '[^[:space:]]' <<<"$response"; then
        log_error "GitHub API returned an empty response for ${path}. The '${CODEX_RELEASE_TAG}' release may not exist yet."
    fi

    printf '%s' "$response"
}

download_file() {
    local url="$1"
    local dest="$2"
    local curl_args=(--fail --location --show-error -o "$dest")
    if [ -t 1 ]; then
        curl_args+=(--progress-bar)
        printf '\n'
    else
        curl_args+=(--silent)
    fi

    if ! curl "${curl_args[@]}" "$url"; then
        log_error "Failed to download ${url}"
    fi

    if [ -t 1 ]; then
        printf '\n'
    fi
}

detect_asset_target() {
    case "$PLATFORM_OS" in
        macos)
            case "$ARCH_UNAME" in
                arm64) DETECTED_ASSET_NAME="codex-macos-aarch64" ;;
                x86_64) DETECTED_ASSET_NAME="codex-macos-x86_64" ;;
                *) log_error "Unsupported macOS architecture: ${ARCH_UNAME}" ;;
            esac
            ;;
        linux)
            case "$ARCH_UNAME" in
                x86_64)
                    if [ "$LINUX_TARGET_FLAVOR" = "musl" ]; then
                        DETECTED_ASSET_NAME="codex-linux-x86_64-musl"
                    else
                        DETECTED_ASSET_NAME="codex-linux-x86_64-gnu"
                    fi
                    ;;
                aarch64|arm64)
                    if [ "$LINUX_TARGET_FLAVOR" = "musl" ]; then
                        DETECTED_ASSET_NAME="codex-linux-aarch64-musl"
                    else
                        DETECTED_ASSET_NAME="codex-linux-aarch64-gnu"
                    fi
                    ;;
                *) log_error "Unsupported Linux architecture: ${ARCH_UNAME}" ;;
            esac
            ;;
        windows)
            case "$ARCH_UNAME" in
                x86_64|amd64) DETECTED_ASSET_NAME="codex-windows-x86_64.exe" ;;
                arm64|aarch64) DETECTED_ASSET_NAME="codex-windows-arm64.exe" ;;
                *) log_error "Unsupported Windows architecture: ${ARCH_UNAME}" ;;
            esac
            ;;
        *)
            log_error "Unsupported operating system: ${OS_UNAME}. Supported OS: macOS, Linux, or Windows."
            ;;
    esac

    log_info "Detected platform ${OS_UNAME}/${ARCH_UNAME}; targeting asset '${DETECTED_ASSET_NAME}'"
}

fetch_release_asset_url() {
    local asset_name="$1"
    local tag="${CODEX_RELEASE_TAG:-nightly}"
    local path

    if [ "$tag" = "latest" ]; then
        path="/repos/${CODEX_REPO_SLUG}/releases/latest"
    else
        path="/repos/${CODEX_REPO_SLUG}/releases/tags/${tag}"
    fi

    local response
    if ! response=$(github_api_request "$path"); then
        log_warn "Could not fetch release info for tag: ${tag}"
        return 1
    fi

    local download_url
    download_url=$(echo "$response" | grep -oE "https://[^ \"]+/${asset_name}" | head -n 1)

    if [ -z "$download_url" ]; then
        log_error "Release asset '${asset_name}' not found in release '${tag}' metadata."
        return 1
    fi

    printf '%s' "$download_url"
    return 0
}

install_codex_binary() {
    local source_binary="$1"
    local dest="$CODEX_BINARY_DEST"
    local dest_dir
    dest_dir=$(dirname "$dest")

    if [ ! -d "$dest_dir" ]; then
        log_info "Creating ${dest_dir}"
        if mkdir -p "$dest_dir" >/dev/null 2>&1; then
            :
        elif command -v sudo >/dev/null 2>&1 && sudo mkdir -p "$dest_dir" >/dev/null 2>&1; then
            :
        else
            log_error "Unable to create destination directory ${dest_dir}"
        fi
    fi

    if install -m 0755 "$source_binary" "$dest" >/dev/null 2>&1; then
        :
    elif command -v sudo >/dev/null 2>&1 && sudo install -m 0755 "$source_binary" "$dest" >/dev/null 2>&1; then
        :
    elif cp "$source_binary" "$dest" >/dev/null 2>&1; then
        chmod +x "$dest" >/dev/null 2>&1 || true
    elif command -v sudo >/dev/null 2>&1 && sudo cp "$source_binary" "$dest" >/dev/null 2>&1; then
        sudo chmod +x "$dest" >/dev/null 2>&1 || true
    else
        log_error "Failed to install Codex binary to ${dest}"
    fi

    log_success "Codex CLI installed at ${dest}"
}

download_and_install_codex_from_release() {
    require_command curl

    detect_asset_target
    log_info "Fetching release metadata from GitHub API..."
    local asset_url
    asset_url=$(fetch_release_asset_url "$DETECTED_ASSET_NAME")
    if [ -z "$asset_url" ]; then
        log_error "Could not find release asset '${DETECTED_ASSET_NAME}' on tag ${CODEX_RELEASE_TAG}."
    fi

    log_info "Downloading '${DETECTED_ASSET_NAME}' from release '${CODEX_RELEASE_TAG}'..."
    log_info "Source: ${asset_url}"
    local tmpdir
    tmpdir=$(mktemp -d)
    local asset_path="${tmpdir}/codex-download"
    download_file "$asset_url" "$asset_path"
    log_info "Download complete."

    remove_existing_codex
    install_codex_binary "$asset_path"

    rm -rf "$tmpdir"

    if command -v codex >/dev/null 2>&1; then
        codex --version || log_warn "Installed Codex but failed to read version."
    fi
}

confirm_codex_replacement() {
    if ! command -v codex >/dev/null 2>&1; then
        return 0
    fi

    local existing_path
    existing_path=$(command -v codex)
    log_info "Detected existing Codex binary at $existing_path"

    if prompt_yes_no "Replace existing Codex binary with the latest Chutes.ai release build?" "Y"; then
        return 0
    fi

    log_warn "User opted to keep existing Codex binary; skipping installation."
    return 1
}

remove_existing_codex() {
    if command -v codex >/dev/null 2>&1; then
        local existing_path
        existing_path=$(command -v codex)
        log_info "Removing existing Codex binary at $existing_path"

        if rm -f "$existing_path" >/dev/null 2>&1; then
            log_success "Removed existing Codex at $existing_path"
        elif command -v sudo >/dev/null 2>&1 && sudo rm -f "$existing_path" >/dev/null 2>&1; then
            log_success "Removed existing Codex (sudo) at $existing_path"
        else
            log_warn "Unable to remove existing Codex binary at $existing_path"
        fi
    fi
}

ensure_env_autoload() {
    if [ "$PLATFORM_OS" = "windows" ]; then
        log_warn "Automatic shell profile updates not supported on Windows; add 'source $ENV_FILE' to your preferred shell manually."
        return
    fi

    local hook_line="source \"$ENV_FILE\""
    local shell_name
    shell_name=$(basename "${SHELL:-}")

    local candidates=()
    case "$shell_name" in
        zsh)
            candidates=("${HOME}/.zshrc" "${HOME}/.zprofile" "${HOME}/.profile")
            ;;
        bash)
            candidates=("${HOME}/.bashrc" "${HOME}/.bash_profile" "${HOME}/.profile")
            ;;
        fish)
            candidates=("${HOME}/.config/fish/config.fish")
            ;;
        *)
            candidates=("${HOME}/.profile")
            ;;
    esac

    local target=""
    for rc in "${candidates[@]}"; do
        if [ -f "$rc" ]; then
            target="$rc"
            break
        fi
    done

    if [ -z "$target" ]; then
        target="${candidates[0]}"
    fi

    if [ -z "$target" ]; then
        log_warn "Could not determine shell profile for autoload; skip profile update."
        return
    fi

    if [ -f "$target" ] && grep -F "${hook_line}" "$target" >/dev/null 2>&1; then
        log_info "Shell profile $(basename "$target") already sources Codex env."
        return
    fi

    if prompt_yes_no "Add 'source $ENV_FILE' to $(basename "$target") for automatic key loading?" "Y"; then
        ensure_dir_exists "$(dirname "$target")"
        touch "$target"
        if [ "$(basename "$target")" = "config.fish" ]; then
            local fish_line="source $ENV_FILE"
            printf '\n# Codex responses proxy\n%s\n' "$fish_line" >>"$target"
        else
            printf '\n# Codex responses proxy\n%s\n' "$hook_line" >>"$target"
        fi
        log_success "Appended Codex env hook to $target"
        log_info "Restart your shell or run: source $target"
    else
        log_warn "Skipped updating shell profile; run 'source $ENV_FILE' manually in future sessions."
    fi
}

install_codex_cli() {
    if ! confirm_codex_replacement; then
        return
    fi

    download_and_install_codex_from_release
}

prompt_yes_no() {
    local prompt="$1"
    local default_choice="${2:-N}"
    local hint
    case "$default_choice" in
        Y|y) hint="[Y/n]" ;;
        *) hint="[y/N]" ;;
    esac
    local response
    read -r -p "$prompt $hint " response
    if [ -z "$response" ]; then
        response="$default_choice"
    fi
    case "$response" in
        Y|y|yes|YES|Yes) return 0 ;;
        *) return 1 ;;
    esac
}

prompt_responses_base_url() {
    local default_value="$1"
    local input=""
    read -r -p "Responses proxy base URL [${default_value}] (press Enter to use default): " input
    if [ -z "$input" ]; then
        printf '%s\n' "$default_value"
    else
        printf '%s\n' "$input"
    fi
}

select_model() {
    local api_key="$1"
    local default_model="$DEFAULT_MODEL"

    local fetch_tool=""
    if command -v curl >/dev/null 2>&1; then
        fetch_tool="curl"
    elif command -v wget >/dev/null 2>&1; then
        fetch_tool="wget"
    else
        log_warn "Neither curl nor wget available; defaulting to ${default_model}" >&2
        printf '%s\n' "$default_model"
        return
    fi

    local python_cmd=""
    if command -v python3 >/dev/null 2>&1; then
        python_cmd="python3"
    elif command -v python >/dev/null 2>&1 && python -c 'import sys; exit(0 if sys.version_info >= (3, 0) else 1)' >/dev/null 2>&1; then
        python_cmd="python"
    else
        log_warn "Python 3 interpreter not available; defaulting to ${default_model}" >&2
        printf '%s\n' "$default_model"
        return
    fi

    local response=""

    log_info "Fetching available models from ${MODELS_API_BASE_URL} (unauthenticated)..." >&2
    if [ "$fetch_tool" = "curl" ]; then
        if ! response=$(curl -fsS "${MODELS_API_BASE_URL}/v1/models" 2>/dev/null); then
            log_warn "Unable to retrieve models; defaulting to ${default_model}" >&2
            printf '%s\n' "$default_model"
            return
        fi
    else
        if ! response=$(wget -q -O - "${MODELS_API_BASE_URL}/v1/models" 2>/dev/null); then
            log_warn "Unable to retrieve models; defaulting to ${default_model}" >&2
            printf '%s\n' "$default_model"
            return
        fi
    fi

    if [ -z "$response" ]; then
        log_warn "Unable to retrieve models; defaulting to ${default_model}" >&2
        printf '%s\n' "$default_model"
        return
    fi

    local python_script
    python_script=$(cat <<'PY'
import json
import sys

try:
    payload = json.load(sys.stdin)
except Exception:
    sys.exit(1)

models = payload.get("data")
if not isinstance(models, list):
    sys.exit(1)

entries = []
for model in models:
    model_id = model.get("id")
    if not isinstance(model_id, str) or not model_id.strip():
        continue

    price_section = model.get("price") or {}
    pricing_section = model.get("pricing") or {}

    def num(value):
        try:
            return float(value)
        except Exception:
            return 0.0

    input_price = price_section.get("input", {}).get("usd")
    output_price = price_section.get("output", {}).get("usd")

    if input_price is None and pricing_section:
        input_price = pricing_section.get("prompt")
    if output_price is None and pricing_section:
        output_price = pricing_section.get("completion")

    input_price = num(input_price)
    output_price = num(output_price)

    if input_price > 0 or output_price > 0:
        price_tag = f"${input_price:.2f}/${output_price:.2f}"
    else:
        price_tag = "n/a"

    features = model.get("supported_features")
    if not isinstance(features, list):
        features = model.get("capabilities")

    think_tag = "    "
    if isinstance(features, list):
        for feature in features:
            if isinstance(feature, str) and feature.lower() == "thinking":
                think_tag = "[TH]"
                break

    entries.append({"id": model_id.strip(), "price": price_tag, "think": think_tag})

if not entries:
    sys.exit(1)

entries.sort(key=lambda item: item["id"].lower())

for idx, entry in enumerate(entries, 1):
    print(f"{idx}|{entry['id']}|{entry['price']}|{entry['think']}")
PY
    )

    local models_output=""
    if ! models_output=$(printf '%s' "$response" | "$python_cmd" -c "$python_script" 2>/dev/null); then
        models_output=""
    fi

    if [ -z "$models_output" ]; then
        log_warn "No models returned; defaulting to ${default_model}" >&2
        printf '%s\n' "$default_model"
        return
    fi

    if [ -n "${CLAUDE_MODEL_LIST_FILE:-}" ]; then
        printf "%s\n" "$models_output" >"${CLAUDE_MODEL_LIST_FILE}"
    fi

    local model_rows=()
    while IFS= read -r line; do
        [ -n "$line" ] && model_rows+=("$line")
    done <<<"$models_output"

    local total=${#model_rows[@]}
    if [ "$total" -eq 0 ]; then
        log_warn "Parsed model list empty; defaulting to ${default_model}" >&2
        printf '%s\n' "$default_model"
        return
    fi

    local default_selection=1
    local entry
    for entry in "${model_rows[@]}"; do
        IFS='|' read -r num mid _price _think <<<"$entry"
        if [ "$mid" = "$default_model" ]; then
            default_selection="$num"
            break
        fi
    done

    printf '\n' >&2
    log_info "Available models (per 1M tokens: input/output):" >&2
    printf '\n' >&2

    local half=$(((total + 1) / 2))
    for ((i = 0; i < half; i++)); do
        local left="${model_rows[$i]}"
        local right_index=$((i + half))
        local right=""

        if [ "$right_index" -lt "$total" ]; then
            right="${model_rows[$right_index]}"
        fi

        IFS='|' read -r num1 id1 price1 think1 <<<"$left"
        printf "  %2s) %s %-45s %-16s" "$num1" "$think1" "$id1" "$price1" >&2

        if [ -n "$right" ]; then
            IFS='|' read -r num2 id2 price2 think2 <<<"$right"
            printf " %2s) %s %-45s %-16s" "$num2" "$think2" "$id2" "$price2" >&2
        fi
        printf '\n' >&2
    done

    printf '\n' >&2

    if [ "${CLAUDE_NONINTERACTIVE:-0}" = "1" ]; then
        printf '%s\n' "$(printf '%s\n' "$models_output" | sed -n '1p' | cut -d'|' -f2)"
        return
    fi

    while true; do
        local selection=""
        if ! read -r -p "Select a model (1-${total}) [default: ${default_selection}]: " selection </dev/tty; then
            log_warn "Unable to read selection; defaulting to ${default_model}" >&2
            printf '%s\n' "$default_model"
            return
        fi

        selection=${selection:-$default_selection}

        if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "$total" ]; then
            local chosen=""
            for entry in "${model_rows[@]}"; do
                IFS='|' read -r num mid price think <<<"$entry"
                if [ "$num" = "$selection" ]; then
                    chosen="$mid"
                    break
                fi
            done

            if [ -n "$chosen" ]; then
                log_success "Selected model: $chosen" >&2
                printf '%s\n' "$chosen"
                return
            fi
        fi

        log_warn "Invalid selection. Enter a number between 1 and ${total}." >&2
    done
}

write_codex_config() {
    local selected_model="${1:-$DEFAULT_MODEL}"
    ensure_dir_exists "$CONFIG_DIR"
    chmod 700 "$CONFIG_DIR" >/dev/null 2>&1 || true

    local base_url="$DEFAULT_BASE_URL"

    if [ -f "$CONFIG_FILE" ]; then
        log_info "Existing Codex config detected at $CONFIG_FILE"
        if ! prompt_yes_no "Overwrite with recommended settings?" "N"; then
            log_warn "Skipping config update per user choice"
            return
        fi
        backup_file "$CONFIG_FILE"
    else
        if ! prompt_yes_no "Write recommended Codex settings to $CONFIG_FILE?" "Y"; then
            log_warn "Skipping config creation per user choice"
            return
        fi
    fi

    base_url=$(prompt_responses_base_url "$DEFAULT_BASE_URL")

    cat <<EOF >"$CONFIG_FILE"
# Generated by ${SCRIPT_NAME} on $(date -u +%Y-%m-%dT%H:%M:%SZ)
model_provider = "chutes-ai"
model = "${selected_model}"
# model = "openai/gpt-4o-mini"
model_reasoning_effort = "high"

[model_providers."chutes-ai"]
name = "Chutes AI via responses proxy"
base_url = "${base_url}"
env_key = "MY_PROVIDER_API_KEY"
wire_api = "responses"

[notice]
hide_full_access_warning = true

[features]
#apply_patch_freeform = true
view_image_tool = true
web_search_request = true

[experimental]
#unified_exec = true
#streamable_shell = true
#experimental_sandbox_command_assessment = true
rmcp_client = true                           # Rust MCP client
EOF

    log_success "Wrote recommended Codex config to $CONFIG_FILE"
}

collect_api_key() {
    echo >&2
    log_info "You can retrieve your API key from: $API_KEY_URL" >&2
    local key
    local confirmation
    local restored_stdin=""

    if [ ! -t 0 ]; then
        local tty_path
        tty_path=$(tty 2>/dev/null || true)
        if [ -n "$tty_path" ] && [ "$tty_path" != "not a tty" ]; then
            exec 3<&0
            exec 0<"$tty_path"
            restored_stdin=1
        elif [ -r /dev/tty ]; then
            exec 3<&0
            exec 0</dev/tty
            restored_stdin=1
        else
            log_error "Interactive terminal (TTY) required to enter API key."
        fi
    fi

    while true; do
        IFS= read -r -s -p "Enter your chutes.ai API key: " key
        echo >&2
        if [ -z "$key" ]; then
            log_warn "API key cannot be empty." >&2
            continue
        fi
        IFS= read -r -s -p "Re-enter to confirm: " confirmation
        echo >&2
        if [ "$key" != "$confirmation" ]; then
            log_warn "Entries did not match. Please try again." >&2
            continue
        fi
        break
    done

    if [ -n "$restored_stdin" ]; then
        exec 0<&3
        exec 3<&-
    fi

    key=${key//$'\r'/}
    printf '%s' "$key"
}

store_api_key() {
    local key="$1"
    KEY_STORED_ON_DISK=0
    if prompt_yes_no "Store API key in ${ENV_FILE} for easy sourcing?" "Y"; then
        ensure_dir_exists "$CONFIG_DIR"
        cat <<EOF >"$ENV_FILE"
# Codex responses proxy credentials
export ${ENV_VAR_NAME}="${key}"
EOF
        chmod 600 "$ENV_FILE" >/dev/null 2>&1 || true
        log_success "Saved API key to $ENV_FILE (chmod 600)"
        ensure_env_autoload
        KEY_STORED_ON_DISK=1
    else
        log_warn "Skipped storing API key on disk."
        log_info "Export the key manually before using Codex: export ${ENV_VAR_NAME}=<your key>"
    fi
}

main() {
    echo "==> Starting ${SCRIPT_NAME}"

    install_codex_cli

    local api_key
    api_key=$(collect_api_key)

    local selected_model
    selected_model=$(select_model "$api_key")

    write_codex_config "$selected_model"

    store_api_key "$api_key"

    unset api_key
    unset selected_model

    echo
    log_success "Codex environment prepared."
    echo "Next steps:"
    if [ "$KEY_STORED_ON_DISK" -eq 1 ]; then
        echo "  - Run: source $ENV_FILE"
    else
        echo "  - Export ${ENV_VAR_NAME} before launching (e.g. export ${ENV_VAR_NAME}=cpk_xxx)"
    fi
    echo "  - Launch Codex: codex"
}

main "$@"
