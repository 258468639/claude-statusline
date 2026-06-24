#!/usr/bin/env bash
# claude-statusline — multi-info status line for Claude Code
# https://github.com/<owner>/claude-statusline
# License: Apache-2.0

set -u
input=$(cat)

# --- Paths (XDG-compliant, no hardcoded user paths) ---
CACHE_DIR="${CLAUDE_STATUSLINE_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline}"
CONFIG_DIR="${CLAUDE_STATUSLINE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/claude-statusline}"
cache_file="$CACHE_DIR/usage_cache.json"
models_conf="$CONFIG_DIR/models.conf"
mkdir -p "$CACHE_DIR" 2>/dev/null || true

# --- Dependency check (non-fatal, prints once to stderr) ---
missing=""
for bin in jq bc git; do
    command -v "$bin" >/dev/null 2>&1 || missing="$missing $bin"
done
if [ -n "$missing" ]; then
    # Only complain once per cache dir, not on every render
    if [ ! -f "$CACHE_DIR/.deps-warned" ]; then
        printf "[claude-statusline] missing dependency:%s — install via your package manager\n" "$missing" >&2
        : >"$CACHE_DIR/.deps-warned" 2>/dev/null || true
    fi
    # bc/jq are required; degrade gracefully
fi

# --- i18n ---
lang="${CLAUDE_STATUSLINE_LANG:-zh}"
case "$lang" in
    en)
        L_PROJ="Proj"; L_SIZE="Size"; L_MODEL="Model"; L_MSGS="Msgs"
        L_CTX="Ctx"; L_IN="in"; L_OUT="out"; L_TIME="Time"; L_NOGIT="no-git"
        ;;
    *)
        L_PROJ="项目"; L_SIZE="大小"; L_MODEL="模型"; L_MSGS="消息"
        L_CTX="上下文"; L_IN="输入"; L_OUT="输出"; L_TIME="时长"; L_NOGIT="无 git"
        ;;
esac

# --- Colors ---
dim="\033[2m"; reset="\033[0m"
green="\033[92m"; cyan="\033[96m"; blue="\033[94m"
purple="\033[95m"; red="\033[91m"; yellow="\033[93m"; orange="\033[38;5;208m"

model_id=$(echo "$input" | jq -r '.model.id // .model.name // "?"' 2>/dev/null)

# --- Resolve custom model name from ANTHROPIC_DEFAULT_*_MODEL_NAME env vars ---
custom_model=""
case "$model_id" in
    *sonnet*)
        custom_model="${ANTHROPIC_DEFAULT_SONNET_MODEL_NAME:-}"
        ;;
    *opus*)
        custom_model="${ANTHROPIC_DEFAULT_OPUS_MODEL_NAME:-}"
        ;;
    *haiku*)
        custom_model="${ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME:-}"
        ;;
    *image*)
        custom_model="${ANTHROPIC_DEFAULT_IMAGE_MODEL_NAME:-}"
        ;;
    *flash*)
        custom_model="${ANTHROPIC_DEFAULT_FLASH_MODEL_NAME:-}"
        ;;
    *thinking*)
        custom_model="${ANTHROPIC_DEFAULT_THINKING_MODEL_NAME:-}"
        ;;
    *dev*)
        custom_model="${ANTHROPIC_DEFAULT_DEV_MODEL_NAME:-}"
        ;;
    *st*)
        custom_model="${ANTHROPIC_DEFAULT_ST_MODEL_NAME:-}"
        ;;
esac
# Fall back to model_id if no custom name found
model="${custom_model:-$model_id}"

pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0 | tonumber' 2>/dev/null)
in_tok=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0' 2>/dev/null)
out_tok=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0' 2>/dev/null)
dur_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // 0' 2>/dev/null)
dur_h=$(echo "scale=2; ${dur_ms:-0}/3600000" | bc -l 2>/dev/null | xargs printf "%.1f" 2>/dev/null)

# --- Context window total tokens with unit conversion ---
total_tok=$(( ${in_tok:-0} + ${out_tok:-0} ))
if [ "$total_tok" -ge 1048576 ]; then
    ctx_unit="M"
    ctx_val=$(echo "scale=1; $total_tok/1048576" | bc -l 2>/dev/null | xargs printf "%.1f" 2>/dev/null)
    [ -z "$ctx_val" ] && ctx_val="0.0"
elif [ "$total_tok" -ge 1024 ]; then
    ctx_unit="K"
    ctx_val=$(echo "scale=1; $total_tok/1024" | bc -l 2>/dev/null | xargs printf "%.1f" 2>/dev/null)
    [ -z "$ctx_val" ] && ctx_val="0.0"
else
    ctx_unit=""
    ctx_val="$total_tok"
fi
[ -z "$dur_h" ] && dur_h="0.0"

# --- Project name ---
proj_dir=$(echo "$input" | jq -r '.workspace.project_dir // .workspace.current_dir // empty' 2>/dev/null)
proj_name="?"
[ -n "$proj_dir" ] && proj_name=$(basename "$proj_dir" 2>/dev/null || echo "?")

# --- Load cache & estimate message count by input-token delta ---
msg_count=1
if [ -f "$cache_file" ]; then
    cached_model=$(jq -r '.model // empty' "$cache_file" 2>/dev/null)
    last_in=$(jq -r '.last_input // 0' "$cache_file" 2>/dev/null)
    msg_count=$(jq -r '.msg_count // 1' "$cache_file" 2>/dev/null)
    if [ "$cached_model" = "$model" ]; then
        delta=$(( in_tok - last_in ))
        if [ "$delta" -gt 50 ]; then
            msg_count=$(( msg_count + 1 ))
        fi
    else
        msg_count=1
    fi
fi

# --- Project size (cached for 120s, du is slow on big trees) ---
dir_size=""
current_time=$(date +%s)
last_du_time=0
if [ -f "$cache_file" ]; then
    last_du_time=$(jq -r '.last_du_time // 0' "$cache_file" 2>/dev/null)
    dir_size=$(jq -r '.dir_size // empty' "$cache_file" 2>/dev/null)
fi

time_diff=$(( current_time - last_du_time ))
should_update=0
if [ -z "$dir_size" ] || [ "$time_diff" -gt 120 ]; then
    should_update=1
fi

size_str=""
[ -n "$dir_size" ] && size_str="${dim}|${reset} ${orange}${L_SIZE}: ${dir_size}M"

if [ "$should_update" -eq 1 ]; then
    if [ -n "$proj_dir" ] && [ -d "$proj_dir" ]; then
        # -sk for KB, works on BSD/macOS and GNU du
        size_kb=$(du -sk "$proj_dir" 2>/dev/null | cut -f1)
        if [ -n "$size_kb" ] && [ "$size_kb" -gt 0 ] 2>/dev/null; then
            dir_size=$(echo "scale=2; $size_kb/1024" | bc -l 2>/dev/null | xargs printf "%.1f" 2>/dev/null)
        fi
    fi
    jq -n \
        --arg m "$model" \
        --argjson in "${in_tok:-0}" \
        --argjson out "${out_tok:-0}" \
        --argjson cnt "${msg_count:-1}" \
        --arg ds "${dir_size:-}" \
        --argjson ldt "$current_time" \
        '{model: $m, last_input: $in, last_output: $out, msg_count: $cnt, dir_size: $ds, last_du_time: $ldt}' \
        > "$cache_file" 2>/dev/null || true
fi

# --- Progress bar (context window usage) ---
int_pct=$(printf "%.0f" "${pct:-0}" 2>/dev/null || echo 0)
filled=$(( int_pct * 20 / 100 ))
empty=$(( 20 - filled ))
bar=""
for (( i=0; i<filled; i++ )); do bar+="█"; done
for (( i=0; i<empty; i++ )); do bar+="░"; done
if [ "$int_pct" -gt 85 ]; then bar_color="\033[91m"
elif [ "$int_pct" -gt 70 ]; then bar_color="\033[93m"
else bar_color="\033[92m"
fi

# --- Git branch + dirty flag ---
cwd=$(echo "$input" | jq -r '.workspace.current_dir // empty' 2>/dev/null)
git_root="${proj_dir:-$cwd}"
branch=""
is_dirty=""
if [ -n "$git_root" ] && [ -d "$git_root/.git" ]; then
    branch=$(GIT_OPTIONAL_LOCKS=0 git -C "$git_root" branch --show-current 2>/dev/null || true)
    [ -z "$branch" ] && branch=$(GIT_OPTIONAL_LOCKS=0 git -C "$git_root" rev-parse --short HEAD 2>/dev/null || true)
    dirty_check=$(GIT_OPTIONAL_LOCKS=0 git -C "$git_root" status --porcelain 2>/dev/null || true)
    [ -n "$dirty_check" ] && is_dirty="true"
fi
[ -z "$branch" ] && branch="$L_NOGIT"
dirty_mark=""; [ "$is_dirty" = "true" ] && dirty_mark="*"

# --- Render ---
echo -e "${purple}${L_PROJ}: ${proj_name}${size_str}${reset} ${dim}|${reset} ${blue}${L_MODEL}: ${model}${reset} ${dim}|${reset} ${bar_color}${L_CTX}: ${bar} ${ctx_val}${ctx_unit} (${int_pct}%)${reset} ${dim}|${reset} ${cyan}🌿 ${branch}${yellow}${dirty_mark}${reset} ${dim}|${reset} ${green}${L_IN}: ${in_tok} ${L_OUT}: ${out_tok}${reset} ${dim}|${reset} ${red}${L_TIME}: ${dur_h}h${reset}"
