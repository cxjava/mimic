#!/usr/bin/env bash
#
# install_dkms.sh - mimic dkms module install script
# Try `install_dkms.sh --help` for usage.
#
# Copyright (c) 2025 Mimic Contributors
#

set -e


###
# SCRIPT CONFIGURATION
###

# Command line arguments of this script
SCRIPT_ARGS=("$@")

# Initial URL & command of one-click script (for usage & logging)
SCRIPT_INITIATOR_URL="https://raw.githubusercontent.com/hack3ric/mimic/master/install_dkms.sh"
SCRIPT_INITIATOR_COMMAND="bash <(curl -fsSL $SCRIPT_INITIATOR_URL)"

# URL of GitHub
REPO_URL="https://github.com/hack3ric/mimic"

# curl command line flags.
# To using a proxy, please specify ALL_PROXY in the environ variable, such like:
# export ALL_PROXY=socks5h://192.0.2.1:1080
CURL_FLAGS=(-L -f -q --retry 5 --retry-delay 10 --retry-max-time 60)

DKMS_MODULE_NAME="mimic"
KERNEL_MODULE_NAME="mimic"


###
# AUTO DETECTED GLOBAL VARIABLE
###

# Package manager
PACKAGE_MANAGEMENT_INSTALL="${PACKAGE_MANAGEMENT_INSTALL:-}"


###
# COMMAND REPLACEMENT & UTILITIES
###

has_command() {
  local _command=$1

  type -P "$_command" > /dev/null 2>&1
}

curl() {
  command curl "${CURL_FLAGS[@]}" "$@"
}

mktemp() {
  command mktemp "$@" "/tmp/mimicinst.XXXXXXXXXX"
}

tput() {
  if has_command tput; then
    command tput "$@" 2>/dev/null || true
  fi
}

tred="$(tput setaf 1 2>/dev/null || true)"
tgreen="$(tput setaf 2 2>/dev/null || true)"
tyellow="$(tput setaf 3 2>/dev/null || true)"
tblue="$(tput setaf 4 2>/dev/null || true)"
taoi="$(tput setaf 6 2>/dev/null || true)"
tbold="$(tput bold 2>/dev/null || true)"
treset="$(tput sgr0 2>/dev/null || true)"

is_run_from_fd() {
  has_prefix "$0" "/dev/" || has_prefix "$0" "/proc/"
}

script_name() {
  local _keep_dirname="$1"

  if is_run_from_fd; then
    echo "$SCRIPT_INITIATOR_COMMAND"
    return
  fi

  if ! has_prefix "$0" "." && [[ -z "$_keep_dirname" ]]; then
    basename "$0"
    return
  fi
  echo "$0"
}

note() {
  local _msg="$1"

  echo -e "$(script_name): ${tbold}note: $_msg${treset}"
}

warning() {
  local _msg="$1"

  echo -e "$(script_name): ${tyellow}warning: $_msg${treset}"
}

error() {
  local _msg="$1"

  echo -e "$(script_name): ${tred}error: $_msg${treset}"
}

has_prefix() {
    local _s="$1"
    local _prefix="$2"

    if [[ -z "$_prefix" ]]; then
        return 0
    fi

    if [[ -z "$_s" ]]; then
        return 1
    fi

    [[ "x$_s" != "x${_s#"$_prefix"}" ]]
}

show_argument_error_and_exit() {
  local _error_msg="$1"

  error "$_error_msg"
  echo "Try \"$(script_name) --help\" for usage." >&2
  exit 22
}

exec_sudo() {
  # exec sudo with configurable environ preserved.
  local _saved_ifs="$IFS"
  IFS=$'\n'
  local _preserved_env=(
    $(env | grep "^PACKAGE_MANAGEMENT_INSTALL=" || true)
    $(env | grep "^FORCE_\w*=" || true)
  )
  IFS="$_saved_ifs"

  exec sudo env \
    "${_preserved_env[@]}" \
    "$@"
}

detect_package_manager() {
  if [[ -n "$PACKAGE_MANAGEMENT_INSTALL" ]]; then
    return 0
  fi

  if has_command apt; then
    apt update
    PACKAGE_MANAGEMENT_INSTALL='apt -y --no-install-recommends install'
    return 0
  fi

  if has_command dnf; then
    PACKAGE_MANAGEMENT_INSTALL='dnf -y install'
    return 0
  fi

  if has_command yum; then
    PACKAGE_MANAGEMENT_INSTALL='yum -y install'
    return 0
  fi

  if has_command zypper; then
    PACKAGE_MANAGEMENT_INSTALL='zypper install -y'
    return 0
  fi

  if has_command pacman; then
    PACKAGE_MANAGEMENT_INSTALL='pacman -Syu --noconfirm'
    return 0
  fi

  return 1
}

install_software() {
  local _package_name="$1"

  if ! detect_package_manager; then
    error "Supported package manager is not detected, please install the following package manually:"
    echo
    echo -e "\t* $_package_name"
    echo
    exit 65
  fi

  echo "Installing missing dependence '$_package_name' with '$PACKAGE_MANAGEMENT_INSTALL' ... "
  if $PACKAGE_MANAGEMENT_INSTALL "$_package_name"; then
    echo "ok"
  else
    error "Cannot install '$_package_name' with detected package manager, please install it manually."
    exit 65
  fi
}

install_linux_headers() {
  local _kernel_ver="$(uname -r)"

  echo "Try to install linux-headers for $_kernel_ver ... "

  if has_command pacman; then
    local _kernel_img="/lib/modules/$_kernel_ver/vmlinuz"
    if [[ ! -f "$_kernel_img" ]]; then
      error "Kernel image does not exist."
      note "If you are using a kernel installed by pacman, this usually caused by system upgrading without reboot."
      note "Please reboot your server and try again."
      return 2
    fi
    local _kernel_pkg=$(pacman -Qoq "$_kernel_img")
    if [[ -z "$_kernel_pkg" ]]; then
      error "Failed to detect kernel package."
      warning "It seems like you are NOT using a kernel that installed by pacman."
      return 2
    fi
    install_software "$_kernel_pkg-headers"
  elif has_command apt; then
    install_software "linux-headers-$_kernel_ver"
  elif has_command dnf || has_command yum; then
    install_software "kernel-devel-$_kernel_ver"
  else
    # unsupported
    error "Automatically linux headers installing is currently not supported on this distribution."
    return 1
  fi
}

rerun_with_sudo() {
  if ! has_command sudo; then
    return 13
  fi

  local _target_script

  if is_run_from_fd; then
    local _tmp_script="$(mktemp)"
    chmod +x "$_tmp_script"

    if has_command curl; then
      curl -o "$_tmp_script" "$SCRIPT_INITIATOR_URL"
    elif has_command wget; then
      wget -O "$_tmp_script" "$SCRIPT_INITIATOR_URL"
    else
      return 127
    fi

    _target_script="$_tmp_script"
  else
    _target_script="$0"
  fi

  note "Re-running this script with sudo."
  exec_sudo "$_target_script" "${SCRIPT_ARGS[@]}"
}

check_permission() {
  if [[ "$UID" -eq '0' ]]; then
    return
  fi

  note "The user running this script is not root."

  if ! rerun_with_sudo; then
    error "Please manually switch to root and run this script again."
    echo
    echo -e "\t${tred}sudo -H bash${treset}"
    echo -e "\t${tred}$(script_name "1")${treset}"
    echo
    exit 13
  fi
}

check_environment_operating_system() {
  if [[ "x$(uname)" == "xLinux" ]]; then
    return
  fi

  error "This script only supports Linux."
  exit 95
}

check_environment_curl() {
  if has_command curl; then
    return
  fi

  install_software curl
}

check_environment_git() {
  if has_command git; then
    return
  fi

  install_software git
}

check_environment_grep() {
  if has_command grep; then
    return
  fi

  install_software grep
}

check_environment_dkms() {
  if has_command dkms; then
    return
  fi

  install_software dkms
}

check_environment_make() {
  if has_command make; then
    return
  fi

  if has_command apt; then
    install_software build-essential
  elif has_command dnf || has_command yum; then
    install_software "Development Tools"
  elif has_command pacman; then
    install_software base-devel
  else
    install_software make
  fi
}

check_environment_clang() {
  if has_command clang; then
    return
  fi

  install_software clang
}

is_linux_headers_installed() {
  test -d "/lib/modules/$(uname -r)/build"
}

is_archlinux() {
  test -f "/etc/arch-release"
}


check_linux_headers() {
  echo -n "Checking linux-headers ... "
  if is_linux_headers_installed; then
    echo "ok"
  else
    echo "not installed"
    if ! install_linux_headers; then
      warning "Kernel headers is missing for current running kernel."
      warning "The DKMS kernel module will not be compiled."
    fi
  fi
}

check_environment() {
  check_environment_operating_system
  check_environment_curl
  check_environment_git
  check_environment_grep
  check_environment_dkms
  check_environment_make
  check_environment_clang
  check_linux_headers
}

vercmp_segment() {
  local _lhs="$1"
  local _rhs="$2"

  if [[ "x$_lhs" == "x$_rhs" ]]; then
    echo 0
    return
  fi
  if [[ -z "$_lhs" ]]; then
    echo -1
    return
  fi
  if [[ -z "$_rhs" ]]; then
    echo 1
    return
  fi

  local _lhs_num="${_lhs//[A-Za-z]*/}"
  local _rhs_num="${_rhs//[A-Za-z]*/}"

  if [[ "x$_lhs_num" == "x$_rhs_num" ]]; then
    echo 0
    return
  fi
  if [[ -z "$_lhs_num" ]]; then
    echo -1
    return
  fi
  if [[ -z "$_rhs_num" ]]; then
    echo 1
    return
  fi
  local _numcmp=$(($_lhs_num - $_rhs_num))
  if [[ "$_numcmp" -ne 0 ]]; then
    echo "$_numcmp"
    return
  fi

  local _lhs_suffix="${_lhs#"$_lhs_num"}"
  local _rhs_suffix="${_rhs#"$_rhs_num"}"

  if [[ "x$_lhs_suffix" == "x$_rhs_suffix" ]]; then
    echo 0
    return
  fi
  if [[ -z "$_lhs_suffix" ]]; then
    echo 1
    return
  fi
  if [[ -z "$_rhs_suffix" ]]; then
    echo -1
    return
  fi
  if [[ "$_lhs_suffix" < "$_rhs_suffix" ]]; then
    echo -1
    return
  fi
  echo 1
}

vercmp() {
  local _lhs=${1#v}
  local _rhs=${2#v}

  while [[ -n "$_lhs" && -n "$_rhs" ]]; do
    local _clhs="${_lhs/.*/}"
    local _crhs="${_rhs/.*/}"

    local _segcmp="$(vercmp_segment "$_clhs" "$_crhs")"
    if [[ "$_segcmp" -ne 0 ]]; then
      echo "$_segcmp"
      return
    fi

    _lhs="${_lhs#"$_clhs"}"
    _lhs="${_lhs#.}"
    _rhs="${_rhs#"$_crhs"}"
    _rhs="${_rhs#.}"
  done

  if [[ "x$_lhs" == "x$_rhs" ]]; then
    echo 0
    return
  fi

  if [[ -z "$_lhs" ]]; then
    echo -1
    return
  fi

  if [[ -z "$_rhs" ]]; then
    echo 1
    return
  fi

  return
}


###
# ARGUMENTS PARSER
###

show_usage_and_exit() {
  echo
  echo -e "\t${tbold}$(script_name)${treset} - mimic dkms install script"
  echo
  echo -e "Usage:"
  echo
  echo -e "${tbold}Install mimic${treset}"
  echo -e "\t$(script_name) [install] [ -f | -l <directory> | --version <version> | --branch <branch> ]"
  echo -e "Options:"
  echo -e "\t-f, --force\tForce re-install latest or specified version even if it has been installed."
  echo -e "\t-l, --local <directory>\tInstall from specified local source directory instead of cloning."
  echo -e "\t--version <version>\tInstall specified version instead of the latest."
  echo -e "\t--branch <branch>\tInstall from specified git branch instead of latest release."
  echo
  echo -e "${tbold}Uninstall mimic${treset}"
  echo -e "\t$(script_name) uninstall"
  echo
  echo -e "${tbold}Check for the status & update${treset}"
  echo -e "\t$(script_name) check"
  echo
  echo -e "${tbold}Reload / Unload mimic kernel module${treset}"
  echo -e "\t$(script_name) [re]load"
  echo -e "\t$(script_name) unload"
  echo
  echo -e "${tbold}Show this help${treset}"
  echo -e "\t$(script_name) help"
  exit 0
}

check_show_usage_and_exit() {
  case "$1" in
    "help")
      show_usage_and_exit
      ;;
  esac

  # if '-h' or '--help' appear in arguments in any position,
  # display help and exit
  while [[ "$#" -gt '0' ]]; do
    case "$1" in
      '--help' | '-h')
        show_usage_and_exit
        ;;
    esac
    shift
  done
}


###
# DKMS
###

dkms_get_installed_versions() {
  local _module="$1"

  local _dkms_moddir="/var/lib/dkms/$_module"

  if [[ ! -d "$_dkms_moddir" ]]; then
    return
  fi

  for file in $(command ls "$_dkms_moddir/"); do
    if [[ -L "$_dkms_moddir/$file" ]]; then
      # ignore kernel-* symlinks
      continue
    fi
    echo "v$file"
  done
}

dkms_remove_modules() {
  local _module="$1"
  local _keep_latest="$2"

  local _versions_to_remove=($(dkms_get_installed_versions "$_module"))
  if [[ -n "$_keep_latest" ]]; then
    local _latest=""
    local _new_versions_to_remove
    _new_versions_to_remove=()
    for version in "${_versions_to_remove[@]}"; do
      local _vercmp="$(vercmp "$version" "$_latest")"
      if [[ "$_vercmp" -gt 0 ]]; then
        if [[ -n "$_latest" ]]; then
          _new_versions_to_remove+=("$_latest")
        fi
        _latest="$version"
      else
        _new_versions_to_remove+=("$version")
      fi
    done
    _versions_to_remove=("${_new_versions_to_remove[@]}")
  fi

  for version in "${_versions_to_remove[@]}"; do
    local _dkms_version="${version#v}"

    echo -n "Removing DKMS module $_module/$_dkms_version ... "
    if dkms remove "$_module/$_dkms_version" --all > /dev/null; then
      echo "ok"
    else
      # suppress dkms remove failed, shall not to be a problem
      continue
    fi
    echo -n "Cleaning DKMS module source /usr/src/$_module-$_dkms_version ... "
    if rm -rf "/usr/src/$_module-$_dkms_version"; then
      echo "ok"
    else
      # also suppress this
      continue
    fi
  done
}

dkms_install_from_source() {
  local _source_dir="$1"
  local _version="$2"

  echo "Installing DKMS module from source directory $_source_dir ... "

  # Generate dkms.conf if needed
  if [[ ! -f "$_source_dir/kmod/dkms.conf" ]]; then
    echo "Generating dkms.conf ... "
    cd "$_source_dir/kmod"
    make dkms.conf
    cd - > /dev/null
  fi

  # Read package info from dkms.conf
  local PACKAGE_NAME PACKAGE_VERSION
  source "$_source_dir/kmod/dkms.conf"

  if [[ -z "$PACKAGE_NAME" ]]; then
    error "Malformed dkms.conf, PACKAGE_NAME is missing."
    exit 22
  fi

  # Use provided version if available
  if [[ -n "$_version" ]]; then
    PACKAGE_VERSION="${_version#v}"
  fi

  if [[ -z "$PACKAGE_VERSION" ]]; then
    error "Malformed dkms.conf, PACKAGE_VERSION is missing."
    exit 22
  fi

  echo "Installing DKMS module $PACKAGE_NAME/$PACKAGE_VERSION ... "

  rm -rf "/usr/src/$PACKAGE_NAME-$PACKAGE_VERSION"
  mkdir -p "/usr/src/$PACKAGE_NAME-$PACKAGE_VERSION"
  cp -a "$_source_dir/kmod/." "/usr/src/$PACKAGE_NAME-$PACKAGE_VERSION/"
  cp -a "$_source_dir/common" "/usr/src/$PACKAGE_NAME-$PACKAGE_VERSION/"

  dkms add "$PACKAGE_NAME/$PACKAGE_VERSION"
}


###
# Kernel modules
###

kmod_is_loaded() {
  local _module="$1"

  lsmod | grep -qP '\b'"$_module"'\b'
}

kmod_load_if_unloaded() {
  local _module="$1"

  if ! kmod_is_loaded "$_module"; then
    echo -n "Loading kernel module $_module ... "
    if modprobe "$_module"; then
      echo "ok"
    else
      error "Failed to load kernel module, kernel module might not be installed successfully."
      return 1
    fi
  fi
}

kmod_unload_if_loaded() {
  local _module="$1"

  if kmod_is_loaded "$_module"; then
    echo -n "Unloading kernel module $_module ... "
    if rmmod "$_module"; then
      echo "ok"
    else
      error "Failed to unload kernel module, kernel module might be occupied by other process."
      error "Try to stop all related proxy service, or simply reboot your server and try again."
      return 1
    fi
  fi
}

kmod_setup_autoload() {
  local _module="$1"

  echo -n "Enabling auto load kernel module $_module on system boot ... "
  if echo "$_module" > "/etc/modules-load.d/$_module.conf"; then
    echo "ok"
  else
    warning "Failed to enable auto load $_module on system boot."
  fi
}

kmod_unsetup_autoload() {
  local _module="$1"

  echo -n "Disabling auto load kernel module $_module on system boot ... "
  if rm -f "/etc/modules-load.d/$_module.conf"; then
    echo "ok"
  else
    warning "Failed to disable auto load $_module on system boot."
  fi
}

###
# GitHub API
###

get_latest_version() {
  if [[ -n "$VERSION" ]]; then
    echo "$VERSION"
    return
  fi

  local _tmpfile=$(mktemp)
  if ! curl -sS "https://api.github.com/repos/hack3ric/mimic/releases/latest" -o "$_tmpfile"; then
    error "Failed to get the latest version from GitHub API, please check your network and try again."
    rm -f "$_tmpfile"
    exit 11
  fi

  local _latest_version=$(grep -oP '"tag_name":\s*\K"v[^"]*"' "$_tmpfile" | head -1)
  _latest_version=${_latest_version#'"'}
  _latest_version=${_latest_version%'"'}

  if [[ -n "$_latest_version" ]]; then
    echo "$_latest_version"
  fi

  rm -f "$_tmpfile"
}

clone_source() {
  local _version="$1"
  local _branch="$2"
  local _destination="$3"

  echo "Cloning mimic source from GitHub ..."

  if [[ -n "$_branch" ]]; then
    echo "Using branch: $_branch"
    if ! git clone --depth 1 --branch "$_branch" "$REPO_URL" "$_destination"; then
      error "Failed to clone repository, please check your network and branch name."
      return 11
    fi
  elif [[ -n "$_version" ]]; then
    echo "Using version: $_version"
    if ! git clone --depth 1 --branch "$_version" "$REPO_URL" "$_destination"; then
      error "Failed to clone repository, please check your network and version tag."
      return 11
    fi
  else
    if ! git clone --depth 1 "$REPO_URL" "$_destination"; then
      error "Failed to clone repository, please check your network."
      return 11
    fi
  fi

  return 0
}


###
# ENTRY
###

perform_install() {
  local _local_dir=""
  local _user_provided_local_dir=""
  local _version=""
  local _branch=""
  local _install_needed=""

  while [[ "$#" -gt '0' ]]; do
    case "$1" in
      '--force' | '-f')
        _install_needed="1"
        ;;
      '--local' | '-l')
        shift
        if [[ "x$1" == "x--" ]]; then
          shift
          _local_dir="$1"
        elif has_prefix "$1" "-"; then
          _local_dir=""
        else
          _local_dir="$1"
        fi
        if [[ -z "$_local_dir" ]]; then
          show_argument_error_and_exit "Please specify the local source directory for option '-l' or '--local'."
        fi
        _install_needed="1"
        _user_provided_local_dir="1"
        ;;
      '--version')
        shift
        if [[ "x$1" == "x--" ]]; then
          shift
          _version="$1"
        elif has_prefix "$1" "-"; then
          _version=""
        else
          _version="$1"
        fi
        if [[ -z "$_version" ]]; then
          show_argument_error_and_exit "Please specify the version for option '--version'."
        fi
        ;;
      '--branch')
        shift
        if [[ "x$1" == "x--" ]]; then
          shift
          _branch="$1"
        elif has_prefix "$1" "-"; then
          _branch=""
        else
          _branch="$1"
        fi
        if [[ -z "$_branch" ]]; then
          show_argument_error_and_exit "Please specify the branch for option '--branch'."
        fi
        ;;
      *)
        show_argument_error_and_exit "Unrecognized option '$1' for subcommand 'install'."
        ;;
    esac
    shift
  done

  if [[ -n "$_local_dir" && -n "$_version" ]]; then
    show_argument_error_and_exit "'--version' and '--local' cannot be used together."
  fi

  if [[ -n "$_local_dir" && -n "$_branch" ]]; then
    show_argument_error_and_exit "'--branch' and '--local' cannot be used together."
  fi

  if [[ -n "$_version" && -n "$_branch" ]]; then
    show_argument_error_and_exit "'--version' and '--branch' cannot be used together."
  fi

  # check installed version
  echo "Cleaning old installations ... "
  dkms_remove_modules "$DKMS_MODULE_NAME" "1"

  echo -n "Checking installed version ... "
  local _installed_version="$(dkms_get_installed_versions "$DKMS_MODULE_NAME" | head -1)"
  if [[ -n "$_installed_version" ]]; then
    echo "$_installed_version"
  else
    echo "not installed"
  fi

  if [[ -z "$_local_dir" && -z "$_version" && -z "$_branch" ]]; then
    echo -n "Checking latest version ... "
    local _latest_version=$(get_latest_version)
    if [[ -n "$_latest_version" ]]; then
      echo "$_latest_version"
      _version="$_latest_version"
    fi
  fi

  if [[ -z "$_local_dir" && -n "$_version" ]]; then
    local _vercmp="$(vercmp "$_installed_version" "$_version")"
    if [[ "$_vercmp" -lt "0" ]]; then
      _install_needed="1"
    fi
  fi

  if [[ -z "$_local_dir" && -n "$_install_needed" ]]; then
    local _clone_destination="$(mktemp -d)"
    clone_source "$_version" "$_branch" "$_clone_destination"
    _local_dir="$_clone_destination"
  fi

  if [[ -n "$_install_needed" ]]; then
    # remove all installed version as DKMS not allowed to overwrite a installed module
    dkms_remove_modules "$DKMS_MODULE_NAME" ""
    dkms_install_from_source "$_local_dir" "$_version"
  fi

  if [[ -z "$_user_provided_local_dir" && -n "$_local_dir" ]]; then
    # clean auto cloned directory
    rm -rf "$_local_dir"
  fi

  echo "Rebuilding DKMS modules as needed ... "
  if ! dkms autoinstall; then
    warning "Error occurred in 'dkms autoinstall', please check above output."
  fi

  kmod_setup_autoload "$KERNEL_MODULE_NAME"

  if [[ -z "$_install_needed" ]]; then
    if ! kmod_load_if_unloaded "$KERNEL_MODULE_NAME"; then
      warning "mimic is installed but failed to load."
    fi

    echo "${tbold}There is nothing to do today.${treset}"
    exit 0
  fi

  if ! kmod_unload_if_loaded "$KERNEL_MODULE_NAME"; then
    warning "mimic is successfully updated, but occupied by other process, please reboot your server to activate the latest change."
    exit 0
  fi

  if ! kmod_load_if_unloaded "$KERNEL_MODULE_NAME"; then
    error "mimic is successfully installed, but failed to load, this might be caused by mismatched linux-headers."
    error "If you update your system recently, rebooting the system might solve this."
    exit 2
  fi

  echo
  local _display_version="${_version:-${_branch:-master}}"
  echo -e "${tbold}Congratulation! mimic $_display_version has been successfully installed and loaded on your server.${treset}"
}

perform_uninstall() {
  while [[ "$#" -gt '0' ]]; do
    case "$1" in
      *)
        show_argument_error_and_exit "Unrecognized option '$1' for subcommand 'uninstall'."
        ;;
    esac
    shift
  done

  kmod_unsetup_autoload "$KERNEL_MODULE_NAME"

  dkms_remove_modules "$DKMS_MODULE_NAME" ""

  if ! kmod_unload_if_loaded "$KERNEL_MODULE_NAME"; then
    warning "mimic is successfully uninstalled from your server, but failed to unload from the kernel."
    warning "Please reboot your system to unload it from the kernel."
    exit 0
  fi

  echo
  echo -e "${tbold}Congratulation! mimic has been successfully uninstalled and unloaded.${treset}"
}

perform_check() {
  while [[ "$#" -gt '0' ]]; do
    case "$1" in
      *)
        show_argument_error_and_exit "Unrecognized option '$1' for subcommand 'check'."
        ;;
    esac
    shift
  done

  echo -n "Checking kernel module ... "
  if kmod_is_loaded "$KERNEL_MODULE_NAME"; then
    echo "loaded"
  else
    echo "not loaded"
  fi

  echo -n "Checking installed version ... "
  local _installed_versions=($(dkms_get_installed_versions "$DKMS_MODULE_NAME"))
  if [[ "${#_installed_versions[@]}" -eq "0" ]]; then
    echo "not installed"
  elif [[ "${#_installed_versions[@]}" -eq "1" ]]; then
    echo "${_installed_versions[0]}"
  else
    echo "multiple version installed"
    for version in "${_installed_versions[@]}"; do
      echo -e "\tFound $version"
    done
  fi

  echo -n "Checking latest version ... "
  local _latest_version=$(get_latest_version)
  if [[ -n "$_latest_version" ]]; then
    echo "$_latest_version"
  fi
}

perform_reload() {
  while [[ "$#" -gt '0' ]]; do
    case "$1" in
      *)
        show_argument_error_and_exit "Unrecognized option '$1' for subcommand 'reload'."
        ;;
    esac
    shift
  done

  kmod_unload_if_loaded "$KERNEL_MODULE_NAME"
  kmod_load_if_unloaded "$KERNEL_MODULE_NAME"
}

perform_unload() {
  while [[ "$#" -gt '0' ]]; do
    case "$1" in
      *)
        show_argument_error_and_exit "Unrecognized option '$1' for subcommand 'unload'."
        ;;
    esac
    shift
  done

  kmod_unload_if_loaded "$KERNEL_MODULE_NAME"
}

main() {
  check_show_usage_and_exit "$@"

  check_permission
  check_environment

  case "$1" in
    "install")
      shift
      perform_install "$@"
      ;;
    "uninstall" | "remove")
      shift
      perform_uninstall "$@"
      ;;
    "check" | "status")
      shift
      perform_check "$@"
      ;;
    "load" | "reload")
      shift
      perform_reload "$@"
      ;;
    "unload")
      shift
      perform_unload "$@"
      ;;
    *)
      # default action
      perform_install "$@"
      ;;
  esac
}

main "$@"

# vim:set ft=bash ts=2 sw=2 sts=2 et:

