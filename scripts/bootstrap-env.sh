#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BACKEND_DIR="${PROJECT_ROOT}/backend"

REQUIRED_JAVA_VERSION="17"
REQUIRED_MAVEN_MAJOR="3"
REQUIRED_MAVEN_MINOR="9"
SDKMAN_JAVA_VERSION="17.0.12-tem"
SDKMAN_MAVEN_VERSION="3.9.9"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

ensure_sdkman() {
    if [[ -s "${HOME}/.sdkman/bin/sdkman-init.sh" ]]; then
        source "${HOME}/.sdkman/bin/sdkman-init.sh"
    fi

    if command_exists sdk; then
        log_info "SDKMAN is available: $(sdk version | head -n1)"
        return 0
    fi

    log_warn "SDKMAN is not installed. Installing SDKMAN (the only allowed toolchain manager for this project) ..."
    if ! command_exists curl && ! command_exists wget; then
        log_error "Neither curl nor wget is available. Please install one of them first to allow SDKMAN installation."
        exit 1
    fi

    export SDKMAN_DIR="${HOME}/.sdkman"
    if command_exists curl; then
        curl -s "https://get.sdkman.io" | bash
    else
        wget -qO- "https://get.sdkman.io" | bash
    fi

    source "${SDKMAN_DIR}/bin/sdkman-init.sh"
    log_info "SDKMAN installed: $(sdk version | head -n1)"
}

check_docker() {
    log_info "Checking Docker ..."
    if ! command_exists docker; then
        log_error "Docker is not installed or not in PATH. Please install Docker Desktop / Docker Engine first."
        exit 1
    fi
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon is not running. Please start Docker and re-run this script."
        exit 1
    fi
    log_info "Docker is available: $(docker --version)"
}

check_docker_compose() {
    log_info "Checking Docker Compose ..."
    if docker compose version >/dev/null 2>&1; then
        log_info "Docker Compose (v2 plugin) is available: $(docker compose version --short)"
    elif command_exists docker-compose; then
        log_info "docker-compose (standalone) is available: $(docker-compose --version | head -n1)"
    else
        log_error "Docker Compose is not available. Please install Docker Compose (v2 plugin recommended)."
        exit 1
    fi
}

check_java() {
    log_info "Checking Java ..."
    if command_exists java; then
        JAVA_VER="$(java -version 2>&1 | awk -F'"' '/version/ {print $2}')"
        JAVA_MAJOR="$(echo "${JAVA_VER}" | awk -F'.' '{print $1}')"
        log_info "Detected Java version: ${JAVA_VER}"
        if [[ "${JAVA_MAJOR}" == "${REQUIRED_JAVA_VERSION}" ]]; then
            log_info "Java ${REQUIRED_JAVA_VERSION} is present."
            return 0
        fi
        log_warn "Java ${JAVA_VER} found, but Java ${REQUIRED_JAVA_VERSION} is required."
    else
        log_warn "Java is not installed."
    fi

    log_warn "Java ${REQUIRED_JAVA_VERSION} will be installed exclusively via SDKMAN (Temurin)."
    ensure_sdkman
    sdk install java "${SDKMAN_JAVA_VERSION}"
    sdk use java "${SDKMAN_JAVA_VERSION}"
    log_info "Java ${REQUIRED_JAVA_VERSION} (Temurin) installed via SDKMAN: $(java -version 2>&1 | head -n1)"
}

check_maven() {
    log_info "Checking Maven ..."
    if command_exists mvn; then
        MVN_VER="$(mvn -version 2>&1 | awk '/Apache Maven/ {print $3}')"
        log_info "Detected Maven version: ${MVN_VER}"
        MVN_MAJOR="$(echo "${MVN_VER}" | awk -F'.' '{print $1}')"
        MVN_MINOR="$(echo "${MVN_VER}" | awk -F'.' '{print $2}')"
        if [[ "${MVN_MAJOR}" -eq "${REQUIRED_MAVEN_MAJOR}" && "${MVN_MINOR}" -ge "${REQUIRED_MAVEN_MINOR}" ]] 2>/dev/null; then
            log_info "Maven ${REQUIRED_MAVEN_MAJOR}.${REQUIRED_MAVEN_MINOR}.x+ is present."
            return 0
        fi
        log_warn "Maven ${MVN_VER} found, but Maven ${REQUIRED_MAVEN_MAJOR}.${REQUIRED_MAVEN_MINOR}.x is required."
    else
        log_warn "Maven is not installed."
    fi

    log_warn "Maven will be installed exclusively via SDKMAN (Maven ${REQUIRED_MAVEN_MAJOR}.${REQUIRED_MAVEN_MINOR}.x)."
    ensure_sdkman
    sdk install maven "${SDKMAN_MAVEN_VERSION}"
    sdk use maven "${SDKMAN_MAVEN_VERSION}"
    log_info "Maven installed via SDKMAN: $(mvn -version 2>&1 | head -n1)"
}

warmup_maven_dependencies() {
    log_info "Pre-warming Maven dependencies in backend/ ..."
    if [[ ! -f "${BACKEND_DIR}/pom.xml" ]]; then
        log_error "Cannot find backend/pom.xml at ${BACKEND_DIR}. Aborting dependency warm-up."
        exit 1
    fi
    (
        cd "${BACKEND_DIR}"
        mvn -q -DskipTests dependency:resolve
    )
    log_info "Maven dependencies resolved successfully."
}

main() {
    log_info "=== bootstrap-env: starting environment check ==="
    check_docker
    check_docker_compose
    check_java
    check_maven
    warmup_maven_dependencies
    log_info "=== bootstrap-env: all checks passed. Environment is ready. ==="
}

main "$@"
