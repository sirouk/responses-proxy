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

ensure_env_autoload() {
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

prompt_responses_base_url() {
    local default_value="$1"
    local input=""
    read -r -p "Responses proxy base URL [${default_value}]: " input
    if [ -z "$input" ]; then
        printf '%s\n' "$default_value"
    else
        printf '%s\n' "$input"
    fi
}

select_model() {
    local api_key="$1"
    local default_model="$DEFAULT_MODEL"

    if ! command -v curl >/dev/null 2>&1; then
        log_warn "curl not available; defaulting to ${default_model}" >&2
        printf '%s\n' "$default_model"
        return
    fi

    if ! command -v node >/dev/null 2>&1; then
        log_warn "node not available; defaulting to ${default_model}" >&2
        printf '%s\n' "$default_model"
        return
    fi

    local response=""

    log_info "Fetching available models from ${MODELS_API_BASE_URL} (unauthenticated)..." >&2
    if ! response=$(curl -fsS "${MODELS_API_BASE_URL}/v1/models" 2>/dev/null); then
        log_warn "Unable to retrieve models; defaulting to ${default_model}" >&2
        printf '%s\n' "$default_model"
        return
    fi

    if [ -z "$response" ]; then
        log_warn "Models response empty; defaulting to ${default_model}" >&2
        printf '%s\n' "$default_model"
        return
    fi

    local models_output=""
    if ! models_output=$(printf '%s' "$response" | node --eval '
        const fs = require("fs");
        try {
            const payload = JSON.parse(fs.readFileSync(0, "utf-8"));
            const models = Array.isArray(payload?.data) ? payload.data : [];
            const entries = models
                .map((model) => {
                    const id = model?.id;
                    if (typeof id !== "string" || !id.trim()) {
                        return null;
                    }

                    const inputPrice = model?.price?.input?.usd ?? model?.pricing?.prompt ?? 0;
                    const outputPrice = model?.price?.output?.usd ?? model?.pricing?.completion ?? 0;
                    const features = Array.isArray(model?.supported_features)
                        ? model.supported_features
                        : Array.isArray(model?.capabilities)
                            ? model.capabilities
                            : [];

                    const thinkTag = features.some((feature) =>
                        typeof feature === "string" && feature.toLowerCase() === "thinking"
                    ) ? "[TH]" : "    ";

                    let priceTag = "n/a";
                    if (Number(inputPrice) > 0 || Number(outputPrice) > 0) {
                        const inPrice = Number(inputPrice || 0).toFixed(2);
                        const outPrice = Number(outputPrice || 0).toFixed(2);
                        priceTag = `$${inPrice}/$${outPrice}`;
                    }

                    return { id, priceTag, thinkTag };
                })
                .filter(Boolean)
                .sort((a, b) => a.id.localeCompare(b.id, undefined, { sensitivity: "base" }));

            if (!entries.length) {
                process.exit(1);
            }

            entries.forEach((entry, idx) => {
                console.log(`${idx + 1}|${entry.id}|${entry.priceTag}|${entry.thinkTag}`);
            });
        } catch (_err) {
            process.exit(1);
        }
    ' 2>/dev/null); then
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
    if prompt_yes_no "Store API key in ${ENV_FILE} for easy sourcing?" "Y"; then
        ensure_dir_exists "$CONFIG_DIR"
        cat <<EOF >"$ENV_FILE"
# Codex responses proxy credentials
export ${ENV_VAR_NAME}="${key}"
EOF
        chmod 600 "$ENV_FILE" >/dev/null 2>&1 || true
        log_success "Saved API key to $ENV_FILE (chmod 600)"
        ensure_env_autoload
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
    echo "  - If you stored your key, run: source $ENV_FILE"
    echo "  - Otherwise, export ${ENV_VAR_NAME} manually as shown above."
    echo "  - Launch Codex: codex"
}

main "$@"

