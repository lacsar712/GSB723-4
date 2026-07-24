#!/usr/bin/env bash
#
# bootstrap-env.sh —— 本地一键环境准备脚本
#
# 目标：让未安装完整 Java/Maven 工具链的同事也能稳定完成环境准备。
#   1. 检查 Docker / Docker Compose 是否可用；
#   2. 若缺少 Java 17，则仅通过 SDKMAN 安装 Temurin 17（禁止 apt/yum/brew 直装 JDK）；
#   3. 若缺少 Maven，则仅通过 SDKMAN 安装 Maven 3.9.x；
#   4. 在 backend 目录做一次依赖预热（mvn -q -DskipTests dependency:resolve）。
#
# 使用：Linux/macOS 直接 bash 执行；Windows 同事请在 Git Bash / WSL 下执行。
#
set -euo pipefail

# ---- 全局常量（自定义变量统一使用 SCREAMING_SNAKE_CASE）-------------------
REQUIRED_JAVA_MAJOR="17"
TEMURIN_CANDIDATE="17.0.13-tem"
MAVEN_CANDIDATE="3.9.9"
SDKMAN_INIT="${SDKMAN_DIR:-$HOME/.sdkman}/bin/sdkman-init.sh"

# 定位仓库根目录与 backend 目录（脚本位于 <repo>/scripts/ 下）。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BACKEND_DIR="${REPO_ROOT}/backend"

log()  { printf '[bootstrap] %s\n' "$*"; }
fail() { printf '[bootstrap][ERROR] %s\n' "$*" >&2; exit 1; }

# ---- 1. 检查 Docker / Docker Compose --------------------------------------
check_docker() {
  command -v docker >/dev/null 2>&1 || fail "未检测到 docker，请先安装 Docker Desktop / Docker Engine。"

  if docker compose version >/dev/null 2>&1; then
    log "Docker Compose (v2 插件) 可用。"
  elif command -v docker-compose >/dev/null 2>&1; then
    log "Docker Compose (v1 独立命令) 可用。"
  else
    fail "未检测到 Docker Compose，请安装 docker compose 插件或 docker-compose。"
  fi

  if ! docker info >/dev/null 2>&1; then
    fail "Docker 守护进程未运行，请先启动 Docker 后重试。"
  fi
  log "Docker 环境检查通过。"
}

# ---- SDKMAN 准备（Java / Maven 均只允许经由 SDKMAN 安装）-------------------
ensure_sdkman() {
  if [ ! -s "${SDKMAN_INIT}" ]; then
    log "未检测到 SDKMAN，正在安装 SDKMAN……"
    command -v curl >/dev/null 2>&1 || fail "缺少 curl，无法安装 SDKMAN。"
    curl -s "https://get.sdkman.io" | bash
  fi
  # shellcheck disable=SC1090
  set +u
  source "${SDKMAN_INIT}"
  set -u
  command -v sdk >/dev/null 2>&1 || fail "SDKMAN 初始化失败，无法继续。"
}

# ---- 2. 检查 / 安装 Java 17 ------------------------------------------------
current_java_major() {
  command -v java >/dev/null 2>&1 || { echo ""; return; }
  # 形如 "17.0.13" -> 17；"1.8.0" -> 8
  local RAW
  RAW="$(java -version 2>&1 | head -n 1 | sed -E 's/.*version "([0-9]+)\.([0-9]+).*/\1 \2/')"
  local MAJOR MINOR
  MAJOR="$(echo "${RAW}" | awk '{print $1}')"
  MINOR="$(echo "${RAW}" | awk '{print $2}')"
  if [ "${MAJOR}" = "1" ]; then echo "${MINOR}"; else echo "${MAJOR}"; fi
}

check_java() {
  local JAVA_MAJOR
  JAVA_MAJOR="$(current_java_major)"
  if [ "${JAVA_MAJOR}" = "${REQUIRED_JAVA_MAJOR}" ]; then
    log "已检测到 Java ${REQUIRED_JAVA_MAJOR}，跳过安装。"
    return
  fi

  log "未检测到 Java ${REQUIRED_JAVA_MAJOR}（当前：${JAVA_MAJOR:-无}），将通过 SDKMAN 安装 Temurin ${TEMURIN_CANDIDATE}。"
  ensure_sdkman
  sdk install java "${TEMURIN_CANDIDATE}" || fail "SDKMAN 安装 Temurin ${TEMURIN_CANDIDATE} 失败。"
  sdk use java "${TEMURIN_CANDIDATE}"
  log "Temurin ${TEMURIN_CANDIDATE} 安装完成。"
}

# ---- 3. 检查 / 安装 Maven 3.9.x --------------------------------------------
check_maven() {
  if command -v mvn >/dev/null 2>&1; then
    local MVN_VERSION
    MVN_VERSION="$(mvn -v 2>/dev/null | head -n 1 | sed -E 's/Apache Maven ([0-9.]+).*/\1/')"
    case "${MVN_VERSION}" in
      3.9.*) log "已检测到 Maven ${MVN_VERSION}，跳过安装。"; return ;;
      *)     log "检测到 Maven ${MVN_VERSION}，非 3.9.x，将通过 SDKMAN 安装 ${MAVEN_CANDIDATE}。" ;;
    esac
  else
    log "未检测到 Maven，将通过 SDKMAN 安装 ${MAVEN_CANDIDATE}。"
  fi

  ensure_sdkman
  sdk install maven "${MAVEN_CANDIDATE}" || fail "SDKMAN 安装 Maven ${MAVEN_CANDIDATE} 失败。"
  sdk use maven "${MAVEN_CANDIDATE}"
  log "Maven ${MAVEN_CANDIDATE} 安装完成。"
}

# ---- 4. 依赖预热 -----------------------------------------------------------
warm_dependencies() {
  [ -f "${BACKEND_DIR}/pom.xml" ] || fail "未找到 ${BACKEND_DIR}/pom.xml，无法预热依赖。"
  log "在 backend 目录执行依赖预热（dependency:resolve）……"
  local SETTINGS_ARG=()
  [ -f "${BACKEND_DIR}/settings.xml" ] && SETTINGS_ARG=(-s "${BACKEND_DIR}/settings.xml")
  ( cd "${BACKEND_DIR}" && mvn -q -DskipTests "${SETTINGS_ARG[@]}" dependency:resolve )
  log "依赖预热完成。"
}

main() {
  log "开始本地环境准备……"
  check_docker
  check_java
  check_maven
  warm_dependencies
  log "全部完成，可继续使用 docker compose 启动服务。"
}

main "$@"
