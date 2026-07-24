#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# bootstrap-env.sh
#
# 一次性本地环境引导脚本：
#   1. 检查 Docker / Docker Compose 是否可用；
#   2. 若缺少 Java 17，仅通过 SDKMAN 安装 Temurin 17（禁止 apt/yum/brew）；
#   3. 若缺少 Maven 3.9.x，仅通过 SDKMAN 安装；
#   4. 在 backend/ 目录执行一次 Maven 依赖预热。
#
# Windows 同事请通过 Git Bash / WSL 执行：
#     bash scripts/bootstrap-env.sh
# ---------------------------------------------------------------------------

set -euo pipefail

readonly REQUIRED_JAVA_MAJOR=17
readonly REQUIRED_JAVA_VENDOR="tem"
readonly REQUIRED_MAVEN_MAJOR=3
readonly REQUIRED_MAVEN_MINOR=9
readonly PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly BACKEND_DIR="${PROJECT_ROOT}/backend"
readonly SDKMAN_INIT_URL="https://get.sdkman.io"

COMPOSE_CMD=()

log()  { printf '\033[1;34m[bootstrap]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[bootstrap]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[bootstrap]\033[0m %s\n' "$*" >&2; exit 1; }

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "缺少必需命令: $1"
}

# ---------------------------------------------------------------------------
# 1. Docker / Docker Compose
# ---------------------------------------------------------------------------
check_docker() {
  require_command docker
  docker info >/dev/null 2>&1 || die "Docker 守护进程不可用，请先启动 Docker Desktop / Docker Engine 并重试。"

  if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD=(docker compose)
  elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD=(docker-compose)
  else
    die "未检测到 Docker Compose（既无 'docker compose' 插件，也无 'docker-compose' 独立命令）。"
  fi
  log "Docker 就绪：$(docker --version 2>&1)"
  log "Compose 就绪：$("${COMPOSE_CMD[@]}" version 2>&1 | head -n1)"
}

# ---------------------------------------------------------------------------
# 2. SDKMAN 引导（仅当需要安装/切换 JDK 或 Maven 时才会触发）
# ---------------------------------------------------------------------------
ensure_sdkman() {
  if [[ -s "${HOME}/.sdkman/bin/sdkman-init.sh" ]]; then
    # shellcheck disable=SC1090
    source "${HOME}/.sdkman/bin/sdkman-init.sh"
    return 0
  fi

  log "未检测到 SDKMAN，开始非交互安装 ..."
  require_command curl
  require_command bash
  curl -fsSL "${SDKMAN_INIT_URL}" | bash
  # shellcheck disable=SC1090
  source "${HOME}/.sdkman/bin/sdkman-init.sh"
  sdk version >/dev/null 2>&1 || die "SDKMAN 安装失败，请检查网络后重试。"
  log "SDKMAN 安装完成：$(sdk version | head -n1)"
}

# 通过 SDKMAN 安装匹配正则的最新候选版本，并设为默认。
# 仅允许通过 SDKMAN 安装，禁止使用 apt/yum/brew 等系统包管理器。
sdk_install_latest() {
  local candidate="$1"
  local filter="$2"
  local identifier
  identifier="$(sdk list "$candidate" \
                | tr -d '\r' \
                | grep -Eo "${filter}" \
                | sort -V -u \
                | tail -n1)"
  [[ -n "${identifier}" ]] || die "无法从 SDKMAN 解析 '${candidate}' 的候选版本（filter=${filter}）。"

  log "通过 SDKMAN 安装 ${candidate}: ${identifier}"
  # 非交互：关闭自动提示、stdin 重定向到 /dev/null
  export SDKMAN_NON_INTERACTIVE=true
  yes 2>/dev/null | sdk install "${candidate}" "${identifier}" >/dev/null || true
  sdk default "${candidate}" "${identifier}" >/dev/null
  sdk use "${candidate}" "${identifier}" >/dev/null || true
  hash -r
  log "${candidate} 当前版本：$(sdk current "${candidate}" | tail -n1)"
}

# ---------------------------------------------------------------------------
# 3. Java 17 (Temurin) —— 只允许通过 SDKMAN 安装
# ---------------------------------------------------------------------------
ensure_java() {
  local java_major=""
  if command -v java >/dev/null 2>&1; then
    java_major="$(java -version 2>&1 \
                  | awk -F '"' '/version/ {split($2, a, "."); print (a[1]==1?a[2]:a[1])}')"
    if [[ "${java_major}" == "${REQUIRED_JAVA_MAJOR}" ]]; then
      log "Java 已就绪：$(java -version 2>&1 | head -n1)"
      return 0
    fi
    warn "检测到 Java major=${java_major}，需要 ${REQUIRED_JAVA_MAJOR}。"
    warn "本项目 JDK 统一通过 SDKMAN 的 Temurin 发行版锁定，请勿使用 apt/yum/brew 直接安装 JDK。"
  else
    log "未检测到 java 命令，将通过 SDKMAN 安装 Temurin ${REQUIRED_JAVA_MAJOR}。"
  fi

  ensure_sdkman
  # 仅匹配 Temurin 17.x.x 版本，例如 17.0.12-tem
  sdk_install_latest java "${REQUIRED_JAVA_MAJOR}\.[0-9]+\.[0-9]+-${REQUIRED_JAVA_VENDOR}"
  command -v java >/dev/null 2>&1 || die "SDKMAN 安装 Java 后仍未在 PATH 中找到 java。"
  log "Java 就绪：$(java -version 2>&1 | head -n1)"
}

# ---------------------------------------------------------------------------
# 4. Maven 3.9.x —— 只允许通过 SDKMAN 安装
# ---------------------------------------------------------------------------
ensure_maven() {
  if command -v mvn >/dev/null 2>&1; then
    local mvn_ver major minor
    mvn_ver="$(mvn -v 2>&1 | awk '/Apache Maven/ {print $3}')"
    major="$(echo "${mvn_ver}" | cut -d. -f1)"
    minor="$(echo "${mvn_ver}" | cut -d. -f2)"
    if [[ "${major}" == "${REQUIRED_MAVEN_MAJOR}" && "${minor}" == "${REQUIRED_MAVEN_MINOR}" ]]; then
      log "Maven 已就绪：Apache Maven ${mvn_ver}"
      return 0
    fi
    warn "检测到 Maven ${mvn_ver}，需要 ${REQUIRED_MAVEN_MAJOR}.${REQUIRED_MAVEN_MINOR}.x。"
    warn "本项目 Maven 统一通过 SDKMAN 安装，请勿使用 apt/yum/brew 直接安装。"
  else
    log "未检测到 mvn 命令，将通过 SDKMAN 安装 Maven ${REQUIRED_MAVEN_MAJOR}.${REQUIRED_MAVEN_MINOR}.x。"
  fi

  ensure_sdkman
  sdk_install_latest maven "${REQUIRED_MAVEN_MAJOR}\.${REQUIRED_MAVEN_MINOR}\.[0-9]+"
  command -v mvn >/dev/null 2>&1 || die "SDKMAN 安装 Maven 后仍未在 PATH 中找到 mvn。"
  log "Maven 就绪：$(mvn -v 2>&1 | head -n1)"
}

# ---------------------------------------------------------------------------
# 5. Maven 依赖预热
# ---------------------------------------------------------------------------
warmup_backend_dependencies() {
  log "在 backend/ 目录执行 Maven 依赖预热：mvn -q -DskipTests dependency:resolve"
  cd "${BACKEND_DIR}"
  mvn -q -DskipTests dependency:resolve
  log "Maven 依赖预热完成。"
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
  log "项目根目录：${PROJECT_ROOT}"
  check_docker
  ensure_java
  ensure_maven
  warmup_backend_dependencies
  log "全部就绪。可执行以下命令启动服务："
  log "  docker compose -f docker-compose.yml -f docker/compose.override.dev.yml up -d --build"
}

main "$@"
