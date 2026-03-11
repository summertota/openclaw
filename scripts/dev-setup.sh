#!/usr/bin/env bash
# ============================================================================
# OpenClaw — One-Click Development Environment Setup & Verification Script
# ============================================================================
#
# This script automates the full development environment setup for OpenClaw,
# a self-hosted personal AI assistant (CLI + Gateway + Web UI + Extensions).
#
# What it does:
#   1. Checks and installs system prerequisites (Node.js >= 22, pnpm 10.23.0)
#   2. Installs project dependencies via pnpm
#   3. Runs lint/format checks
#   4. Runs the automated test suite
#   5. Builds the project
#   6. Starts the dev gateway and verifies it responds
#   7. Runs the CLI doctor as a hello-world sanity check
#
# Usage:
#   chmod +x scripts/dev-setup.sh
#   ./scripts/dev-setup.sh
#
# Options:
#   --skip-tests     Skip the test suite (saves ~6 min on constrained machines)
#   --skip-build     Skip the build step
#   --skip-gateway   Skip starting and verifying the dev gateway
#
# Platform: Linux / macOS (bash 4+; macOS bash 3.x also supported)
# ============================================================================

set -euo pipefail

# ─── Color helpers (safe for non-TTY) ────────────────────────────────────────

if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  CYAN='\033[0;36m'
  BOLD='\033[1m'
  RESET='\033[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' RESET=''
fi

info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
fail()    { echo -e "${RED}[FAIL]${RESET}  $*"; }
step()    { echo -e "\n${BOLD}${CYAN}══════ $* ══════${RESET}\n"; }

# ─── Parse CLI flags ─────────────────────────────────────────────────────────

SKIP_TESTS=false
SKIP_BUILD=false
SKIP_GATEWAY=false

for arg in "$@"; do
  case "$arg" in
    --skip-tests)   SKIP_TESTS=true ;;
    --skip-build)   SKIP_BUILD=true ;;
    --skip-gateway) SKIP_GATEWAY=true ;;
    --help|-h)
      echo "Usage: $0 [--skip-tests] [--skip-build] [--skip-gateway]"
      exit 0
      ;;
    *)
      warn "Unknown option: $arg (ignored)"
      ;;
  esac
done

# ─── Resolve project root (script lives in scripts/) ────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

info "Project root: $PROJECT_ROOT"

# Track overall result for final summary
RESULTS=()
record_result() {
  # Usage: record_result "step name" pass|fail|warn|skip
  RESULTS+=("$1|$2")
}

# ─── Gateway cleanup helper (kills only our gateway PID, never pkill -f) ────

GATEWAY_PID=""
cleanup_gateway() {
  if [[ -n "$GATEWAY_PID" ]] && kill -0 "$GATEWAY_PID" 2>/dev/null; then
    info "Stopping dev gateway (PID $GATEWAY_PID)..."
    kill "$GATEWAY_PID" 2>/dev/null || true
    wait "$GATEWAY_PID" 2>/dev/null || true
    success "Gateway stopped."
  fi
}
trap cleanup_gateway EXIT

# ============================================================================
# STEP 1: Check and install Node.js >= 22
# ──────────────────────────────────────────────────────────────────────────────
# AI Agent To-Do: "Ensure Node.js >= 22.12.0 is installed as required by
# package.json engines field. Use nvm if available; otherwise instruct user."
# ============================================================================

step "Step 1/7: Verify Node.js >= 22"

REQUIRED_NODE_MAJOR=22

check_node_version() {
  if ! command -v node &>/dev/null; then
    return 1
  fi
  local ver
  ver="$(node --version 2>/dev/null | sed 's/^v//')"
  local major
  major="$(echo "$ver" | cut -d. -f1)"
  if [[ "$major" -ge "$REQUIRED_NODE_MAJOR" ]]; then
    return 0
  fi
  return 1
}

if check_node_version; then
  success "Node.js $(node --version) found — meets >= v${REQUIRED_NODE_MAJOR} requirement."
  record_result "Node.js >= 22" "pass"
else
  warn "Node.js >= v${REQUIRED_NODE_MAJOR} not found (current: $(node --version 2>/dev/null || echo 'none'))."

  # Attempt to install via nvm if available
  if command -v nvm &>/dev/null || [[ -s "$HOME/.nvm/nvm.sh" ]]; then
    info "nvm detected — installing Node.js 22..."
    # shellcheck disable=SC1091
    [[ -s "$HOME/.nvm/nvm.sh" ]] && source "$HOME/.nvm/nvm.sh"
    nvm install 22
    nvm use 22
  elif command -v fnm &>/dev/null; then
    info "fnm detected — installing Node.js 22..."
    fnm install 22
    fnm use 22
  elif command -v mise &>/dev/null; then
    info "mise detected — installing Node.js 22..."
    mise install node@22
    mise use node@22
  else
    fail "No version manager (nvm/fnm/mise) found. Please install Node.js >= 22 manually."
    fail "Visit https://nodejs.org/ or run: curl -fsSL https://fnm.vercel.app/install | bash"
    record_result "Node.js >= 22" "fail"
    exit 1
  fi

  # Re-check after install
  if check_node_version; then
    success "Node.js $(node --version) installed successfully."
    record_result "Node.js >= 22" "pass"
  else
    fail "Node.js installation failed. Current version: $(node --version 2>/dev/null || echo 'none')"
    record_result "Node.js >= 22" "fail"
    exit 1
  fi
fi

# ============================================================================
# STEP 2: Check and install pnpm 10.23.0
# ──────────────────────────────────────────────────────────────────────────────
# AI Agent To-Do: "Ensure pnpm version matches packageManager field in
# package.json (pnpm@10.23.0). Use corepack if available."
# ============================================================================

step "Step 2/7: Verify pnpm 10.23.0"

REQUIRED_PNPM="10.23.0"

check_pnpm_version() {
  if ! command -v pnpm &>/dev/null; then
    return 1
  fi
  local ver
  ver="$(pnpm --version 2>/dev/null)"
  if [[ "$ver" == "$REQUIRED_PNPM" ]]; then
    return 0
  fi
  return 1
}

if check_pnpm_version; then
  success "pnpm $(pnpm --version) found — matches required version."
  record_result "pnpm 10.23.0" "pass"
else
  warn "pnpm $REQUIRED_PNPM not found (current: $(pnpm --version 2>/dev/null || echo 'none'))."

  # Attempt via corepack (ships with Node.js 16+)
  if command -v corepack &>/dev/null; then
    info "Installing pnpm $REQUIRED_PNPM via corepack..."
    corepack enable 2>/dev/null || true
    corepack prepare "pnpm@${REQUIRED_PNPM}" --activate
  else
    info "corepack not available — installing pnpm via npm..."
    npm install -g "pnpm@${REQUIRED_PNPM}"
  fi

  if check_pnpm_version; then
    success "pnpm $(pnpm --version) installed successfully."
    record_result "pnpm 10.23.0" "pass"
  else
    # Accept close-enough versions (same major.minor)
    if command -v pnpm &>/dev/null; then
      warn "pnpm $(pnpm --version) installed (wanted exact $REQUIRED_PNPM). Proceeding anyway."
      record_result "pnpm 10.23.0" "warn"
    else
      fail "Failed to install pnpm. Please install manually: npm install -g pnpm@${REQUIRED_PNPM}"
      record_result "pnpm 10.23.0" "fail"
      exit 1
    fi
  fi
fi

# ============================================================================
# STEP 3: Install project dependencies
# ──────────────────────────────────────────────────────────────────────────────
# AI Agent To-Do: "Install all workspace dependencies with pnpm install.
# This handles root + extensions/* + ui/ + packages/* workspace packages.
# Note: @discordjs/opus and @tloncorp/tlon-skill build scripts are skipped
# (not in pnpm.onlyBuiltDependencies). This is non-blocking."
# ============================================================================

step "Step 3/7: Install dependencies"

info "Running pnpm install (this may take 30-60 seconds)..."
if pnpm install 2>&1 | tee /tmp/openclaw-pnpm-install.log; then
  success "Dependencies installed successfully."
  record_result "pnpm install" "pass"
else
  fail "pnpm install failed. Check /tmp/openclaw-pnpm-install.log for details."
  record_result "pnpm install" "fail"
  exit 1
fi

# Check for the known non-blocking build script warning
if grep -q "Ignored build scripts" /tmp/openclaw-pnpm-install.log 2>/dev/null; then
  warn "Some optional build scripts were skipped (@discordjs/opus, @tloncorp/tlon-skill)."
  warn "This is expected and non-blocking — these packages are not in pnpm.onlyBuiltDependencies."
fi

# ============================================================================
# STEP 4: Run lint and format checks
# ──────────────────────────────────────────────────────────────────────────────
# AI Agent To-Do: "Run the full check suite (pnpm check) which includes:
#   - Host env policy check (Swift)
#   - Format check (oxfmt --check)
#   - TypeScript type check (tsgo / @typescript/native-preview)
#   - Lint (oxlint --type-aware)
#   - Multiple custom lint scripts for channel boundaries, plugin SDK, etc."
# ============================================================================

step "Step 4/7: Lint & format checks"

info "Running full check suite (pnpm check)..."
if pnpm check 2>&1 | tee /tmp/openclaw-check.log; then
  success "All lint and format checks passed."
  record_result "pnpm check" "pass"
else
  fail "Lint/format checks failed. Review output above or /tmp/openclaw-check.log."
  record_result "pnpm check" "fail"
  # Non-fatal: continue to see full picture
fi

# ============================================================================
# STEP 5: Run automated test suite
# ──────────────────────────────────────────────────────────────────────────────
# AI Agent To-Do: "Run tests with memory-constrained profile to avoid OOM on
# non-Mac-Studio hosts. Uses OPENCLAW_TEST_PROFILE=low and
# OPENCLAW_TEST_SERIAL_GATEWAY=1. Expects ~892 test files, ~7400 tests,
# taking approximately 6 minutes."
# ============================================================================

step "Step 5/7: Automated tests"

if [[ "$SKIP_TESTS" == "true" ]]; then
  warn "Tests skipped (--skip-tests flag)."
  record_result "pnpm test" "skip"
else
  info "Running test suite with low-memory profile (this takes ~6 minutes)..."
  info "Using: OPENCLAW_TEST_PROFILE=low OPENCLAW_TEST_SERIAL_GATEWAY=1 pnpm test"

  if OPENCLAW_TEST_PROFILE=low OPENCLAW_TEST_SERIAL_GATEWAY=1 pnpm test 2>&1 | tee /tmp/openclaw-test.log; then
    # Extract pass counts from the log
    PASS_COUNT=$(grep -oP '\d+ passed' /tmp/openclaw-test.log | tail -1 || echo "unknown")
    success "All tests passed ($PASS_COUNT)."
    record_result "pnpm test" "pass"
  else
    fail "Some tests failed. Review output above or /tmp/openclaw-test.log."
    record_result "pnpm test" "fail"
    # Non-fatal: continue to see full picture
  fi
fi

# ============================================================================
# STEP 6: Build the project
# ──────────────────────────────────────────────────────────────────────────────
# AI Agent To-Do: "Build the project with pnpm build. This runs:
#   - canvas:a2ui:bundle (rolldown bundle for Canvas A2UI)
#   - tsdown-build (TypeScript bundling via tsdown/rolldown)
#   - Plugin SDK root alias copy
#   - Plugin SDK .d.ts generation (tsc)
#   - Various post-build copy scripts (hook metadata, HTML templates, etc.)
#   - Build info + CLI startup metadata generation
# Output goes to dist/."
# ============================================================================

step "Step 6/7: Build"

if [[ "$SKIP_BUILD" == "true" ]]; then
  warn "Build skipped (--skip-build flag)."
  record_result "pnpm build" "skip"
else
  info "Building the project (pnpm build, ~30 seconds)..."
  if pnpm build 2>&1 | tee /tmp/openclaw-build.log; then
    success "Build completed successfully. Output in dist/."
    record_result "pnpm build" "pass"
  else
    fail "Build failed. Review output above or /tmp/openclaw-build.log."
    record_result "pnpm build" "fail"
    # Non-fatal for gateway test (gateway:dev auto-rebuilds)
  fi
fi

# ============================================================================
# STEP 7: Start dev gateway and verify it responds
# ──────────────────────────────────────────────────────────────────────────────
# AI Agent To-Do: "Start the gateway in dev mode with channels disabled
# (OPENCLAW_SKIP_CHANNELS=1). The gateway listens on ws://127.0.0.1:18789.
# Verify by hitting /healthz (expects {"ok":true,"status":"live"}) and
# /readyz (expects {"ready":true,...}).
# Then run 'openclaw --dev doctor --non-interactive' as a CLI hello-world
# action that exercises config loading, plugin scanning, and security checks."
# ============================================================================

step "Step 7/7: Start dev gateway & verify"

if [[ "$SKIP_GATEWAY" == "true" ]]; then
  warn "Gateway start skipped (--skip-gateway flag)."
  record_result "Gateway /healthz" "skip"
  record_result "Gateway /readyz" "skip"
  record_result "CLI doctor" "skip"
else
  GATEWAY_PORT=18789

  # Check if port is already in use
  if command -v ss &>/dev/null && ss -ltnp 2>/dev/null | grep -q ":${GATEWAY_PORT} "; then
    warn "Port $GATEWAY_PORT is already in use. Skipping gateway start."
    warn "If this is a stale process, free the port and re-run."
    record_result "Gateway /healthz" "warn"
    record_result "Gateway /readyz" "warn"
  elif command -v lsof &>/dev/null && lsof -i ":${GATEWAY_PORT}" -sTCP:LISTEN &>/dev/null 2>&1; then
    warn "Port $GATEWAY_PORT is already in use. Skipping gateway start."
    record_result "Gateway /healthz" "warn"
    record_result "Gateway /readyz" "warn"
  else
    info "Starting dev gateway on port $GATEWAY_PORT (channels disabled)..."

    # Start gateway in background
    OPENCLAW_SKIP_CHANNELS=1 \
    CLAWDBOT_SKIP_CHANNELS=1 \
      pnpm openclaw --dev gateway --port "$GATEWAY_PORT" --force \
      > /tmp/openclaw-gateway-setup.log 2>&1 &
    GATEWAY_PID=$!

    info "Gateway PID: $GATEWAY_PID — waiting for it to be ready..."

    # Poll /healthz for up to 60 seconds
    MAX_WAIT=60
    WAITED=0
    GATEWAY_READY=false

    while [[ $WAITED -lt $MAX_WAIT ]]; do
      if ! kill -0 "$GATEWAY_PID" 2>/dev/null; then
        fail "Gateway process exited unexpectedly. Check /tmp/openclaw-gateway-setup.log"
        break
      fi

      HEALTH_RESPONSE=$(curl -s "http://127.0.0.1:${GATEWAY_PORT}/healthz" 2>/dev/null || true)
      if echo "$HEALTH_RESPONSE" | grep -q '"ok":true'; then
        GATEWAY_READY=true
        break
      fi

      sleep 2
      WAITED=$((WAITED + 2))
    done

    if [[ "$GATEWAY_READY" == "true" ]]; then
      success "Gateway is live! /healthz response: $HEALTH_RESPONSE"
      record_result "Gateway /healthz" "pass"

      # Also check /readyz
      READY_RESPONSE=$(curl -s "http://127.0.0.1:${GATEWAY_PORT}/readyz" 2>/dev/null || true)
      if echo "$READY_RESPONSE" | grep -q '"ready":true'; then
        success "Gateway is ready! /readyz response: $READY_RESPONSE"
        record_result "Gateway /readyz" "pass"
      else
        warn "Gateway /readyz returned unexpected: $READY_RESPONSE"
        record_result "Gateway /readyz" "warn"
      fi
    else
      fail "Gateway did not become ready within ${MAX_WAIT}s."
      fail "Last health response: ${HEALTH_RESPONSE:-<none>}"
      fail "Check logs: /tmp/openclaw-gateway-setup.log"
      record_result "Gateway /healthz" "fail"
      record_result "Gateway /readyz" "fail"
    fi
  fi

  # ── CLI hello-world: openclaw doctor ──────────────────────────────────────
  # AI Agent To-Do: "Run openclaw --dev doctor --non-interactive as a
  # meaningful hello-world. This exercises config loading, plugin system,
  # security audit, skills enumeration, and memory search status — far
  # more than just 'the binary runs'."

  info "Running CLI hello-world: openclaw --dev doctor --non-interactive..."
  if pnpm openclaw --dev doctor --non-interactive 2>&1 | tee /tmp/openclaw-doctor.log; then
    success "CLI doctor completed successfully."
    record_result "CLI doctor" "pass"
  else
    fail "CLI doctor failed. Check /tmp/openclaw-doctor.log."
    record_result "CLI doctor" "fail"
  fi

  # ── Version check ─────────────────────────────────────────────────────────
  info "Verifying CLI version..."
  VERSION_OUTPUT=$(pnpm openclaw --version 2>&1 | grep -oP 'OpenClaw \S+' || echo "unknown")
  success "CLI version: $VERSION_OUTPUT"
fi

# ============================================================================
# SUMMARY
# ============================================================================

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║          OpenClaw Development Environment — Summary         ║${RESET}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${RESET}"
echo ""

HAS_FAIL=false
for entry in "${RESULTS[@]}"; do
  STEP_NAME="${entry%%|*}"
  STEP_STATUS="${entry##*|}"
  case "$STEP_STATUS" in
    pass) echo -e "  ✅  ${GREEN}${STEP_NAME}${RESET}" ;;
    fail) echo -e "  ❌  ${RED}${STEP_NAME}${RESET}"; HAS_FAIL=true ;;
    warn) echo -e "  ⚠️   ${YELLOW}${STEP_NAME}${RESET}" ;;
    skip) echo -e "  ⏭️   ${BLUE}${STEP_NAME} (skipped)${RESET}" ;;
  esac
done

echo ""
echo -e "${BOLD}Key paths:${RESET}"
echo "  Project root:   $PROJECT_ROOT"
echo "  Built output:   $PROJECT_ROOT/dist/"
echo "  Dev config:     ~/.openclaw-dev/openclaw.json"
echo "  Prod config:    ~/.openclaw/openclaw.json"
echo "  Logs:           /tmp/openclaw/"
echo ""
echo -e "${BOLD}Quick reference:${RESET}"
echo "  pnpm check          — lint + format + typecheck"
echo "  pnpm test           — run all tests"
echo "  pnpm build          — build to dist/"
echo "  pnpm gateway:dev    — start dev gateway (port 18789, no channels)"
echo "  pnpm gateway:watch  — start gateway with file watching"
echo "  pnpm openclaw --dev doctor  — health checks"
echo "  pnpm ui:dev         — start web UI dev server"
echo ""

if [[ "$HAS_FAIL" == "true" ]]; then
  echo -e "${RED}${BOLD}Some steps failed. Review the output above for details.${RESET}"
  exit 1
else
  echo -e "${GREEN}${BOLD}Development environment is ready! 🦞${RESET}"
  exit 0
fi
