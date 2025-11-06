#!/bin/bash

set -euo pipefail

SCRIPT_NAME=$(basename "$0")
CONFIG_DIR="${HOME}/.codex"
CONFIG_FILE="${CONFIG_DIR}/config.toml"
ENV_FILE="${CONFIG_DIR}/env"
ENV_VAR_NAME="MY_PROVIDER_API_KEY"
API_KEY_URL="https://chutes.ai/app/api"
RUSTUP_INSTALL_SCRIPT="https://sh.rustup.rs"
CODEX_GIT_URL="https://github.com/chutesai/codex.git"
CODEX_FORK_DIR="${HOME}/codex-fork"
CODEX_RS_DIR="${CODEX_FORK_DIR}/codex-rs"
CODEX_BINARY_DEST="/usr/local/bin/codex"

log_info() {
    echo "[INFO] $*"
}

log_success() {
    echo "[OK] $*"
}

log_warn() {
    echo "[WARN] $*"
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

load_rust_env() {
    if [ -s "${HOME}/.cargo/env" ]; then
        # shellcheck disable=SC1091
        . "${HOME}/.cargo/env"
    fi
}

ensure_rust() {
    load_rust_env
    if command -v cargo >/dev/null 2>&1; then
        local version
        version=$(cargo --version 2>/dev/null || echo "unknown")
        log_success "Rust toolchain already available (${version})"
        return
    fi

    require_command curl
    log_info "Installing Rust toolchain via rustup..."
    if curl --proto '=https' --tlsv1.2 -sSf "$RUSTUP_INSTALL_SCRIPT" | sh -s -- -y >/dev/null; then
        log_success "Rustup installation complete"
    else
        log_error "Rust installation failed"
    fi

    load_rust_env

    if ! command -v cargo >/dev/null 2>&1; then
        log_error "Cargo not found after rustup installation"
    fi
}

clone_or_update_codex_repo() {
    require_command git

    if [ ! -d "$CODEX_FORK_DIR/.git" ]; then
        log_info "Cloning Codex fork from $CODEX_GIT_URL into $CODEX_FORK_DIR..."
        git clone "$CODEX_GIT_URL" "$CODEX_FORK_DIR" >/dev/null 2>&1 || log_error "Failed to clone Codex fork"
    else
        log_info "Updating existing Codex fork in $CODEX_FORK_DIR..."
        if ! git -C "$CODEX_FORK_DIR" remote get-url origin >/dev/null 2>&1; then
            log_warn "Codex fork appears to have no origin remote; skipping update"
        else
            git -C "$CODEX_FORK_DIR" fetch --all --tags >/dev/null 2>&1 || log_warn "Failed to fetch updates for Codex fork"
            git -C "$CODEX_FORK_DIR" pull --ff-only >/dev/null 2>&1 || log_warn "Failed to fast-forward Codex fork"
        fi
    fi

    git -C "$CODEX_FORK_DIR" submodule update --init --recursive >/dev/null 2>&1 || log_warn "Failed to update Codex submodules"
}

build_codex_binary() {
    load_rust_env

    if [ ! -d "$CODEX_RS_DIR" ]; then
        log_error "Codex Rust workspace not found at $CODEX_RS_DIR"
    fi

    log_info "Building Codex CLI (release)..."
    if cargo --quiet --version >/dev/null 2>&1; then
        :
    else
        log_error "Cargo command unavailable"
    fi

    if (cd "$CODEX_RS_DIR" && cargo build --release --bin codex >/dev/null 2>&1); then
        log_success "Codex CLI built successfully"
    else
        log_error "Failed to build Codex CLI"
    fi
}

confirm_codex_replacement() {
    if ! command -v codex >/dev/null 2>&1; then
        return 0
    fi

    local existing_path
    existing_path=$(command -v codex)
    log_info "Detected existing Codex binary at $existing_path"

    if prompt_yes_no "Replace existing Codex binary with Chutes.ai fork build?" "Y"; then
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

link_codex_binary() {
    local binary_path="${CODEX_RS_DIR}/target/release/codex"

    if [ ! -x "$binary_path" ]; then
        log_error "Expected Codex binary missing at $binary_path"
    fi

    require_command sudo
    log_info "Linking Codex binary to $CODEX_BINARY_DEST..."
    if sudo ln -sf "$binary_path" "$CODEX_BINARY_DEST" >/dev/null 2>&1; then
        log_success "Codex CLI available at $CODEX_BINARY_DEST"
    else
        log_error "Failed to create symlink for Codex CLI"
    fi

    if command -v codex >/dev/null 2>&1; then
        log_info "codex located at $(command -v codex)"
        codex --version || log_warn "Unable to determine Codex version"
    else
        log_warn "Codex CLI not found in PATH after linking"
    fi
}

install_codex_cli() {
    if ! confirm_codex_replacement; then
        return
    fi

    ensure_rust
    clone_or_update_codex_repo
    build_codex_binary
    remove_existing_codex
    link_codex_binary
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

write_codex_config() {
    ensure_dir_exists "$CONFIG_DIR"
    chmod 700 "$CONFIG_DIR" >/dev/null 2>&1 || true

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

    cat <<EOF >"$CONFIG_FILE"
# Generated by ${SCRIPT_NAME} on $(date -u +%Y-%m-%dT%H:%M:%SZ)
model_provider = "chutes-ai"
model = "Qwen/Qwen3-Coder-480B-A35B-Instruct-FP8"
# model = "openai/gpt-4o-mini"
model_reasoning_effort = "high"

[model_providers."chutes-ai"]
name = "Chutes AI via responses proxy"
base_url = "https://responses-proxy.chutes.ai/v1"
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
    echo
    log_info "You can retrieve your API key from: $API_KEY_URL"
    local key
    local confirmation
    local restored_stdin=""

    if [ ! -t 0 ]; then
        local tty_path
        tty_path=$(tty 2>/dev/null || true)
        if [ -n "$tty_path" ]; then
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
        read -s -p "Enter your chutes.ai API key: " key
        echo
        if [ -z "$key" ]; then
            log_warn "API key cannot be empty."
            continue
        fi
        read -s -p "Re-enter to confirm: " confirmation
        echo
        if [ "$key" != "$confirmation" ]; then
            log_warn "Entries did not match. Please try again."
            continue
        fi
        break
    done

    if [ -n "$restored_stdin" ]; then
        exec 0<&3
        exec 3<&-
    fi

    echo "$key"
}

store_api_key() {
    local key="$1"
    if prompt_yes_no "Store API key in ${ENV_FILE} for easy sourcing?" "Y"; then
        ensure_dir_exists "$CONFIG_DIR"
        cat <<EOF >"$ENV_FILE"
# Codex responses proxy credentials
export ${ENV_VAR_NAME}="${key}"
EOF
        chmod 600 "$ENV_FILE" >/dev/null 2>&1 || true
        log_success "Saved API key to $ENV_FILE (chmod 600)"
        log_info "Add 'source $ENV_FILE' to your shell profile to load it automatically."
    else
        log_warn "Skipped storing API key on disk."
        log_info "Export the key manually before using Codex: export ${ENV_VAR_NAME}=<your key>"
    fi
}

main() {
    echo "==> Starting ${SCRIPT_NAME}"

    install_codex_cli
    write_codex_config

    local api_key
    api_key=$(collect_api_key)
    store_api_key "$api_key"
    unset api_key

    echo
    log_success "Codex environment prepared."
    echo "Next steps:"
    echo "  - If you stored your key, run: source $ENV_FILE"
    echo "  - Otherwise, export ${ENV_VAR_NAME} manually as shown above."
    echo "  - Launch Codex: codex"
}

main "$@"

