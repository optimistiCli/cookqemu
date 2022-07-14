#!/bin/bash

function usage {
cat <<EOU
Usage:
  $GV__SCR_NAME -h [t|p]
  or
  $GV__SCR_NAME <settings dir or plist>
  or
  $GV__SCR_NAME -h [t] -v -n <name> -i <boot iso> -d <disk size> -m <mem size>
    -p <CPU count> -g -s <ssh port> -S <subnet> -u <username> -t <path>
    -f <path> -b <path> -I <path> -V <VMs dir> -D <assets dir> -e|-E <URL>
    <settings dir>|<settings plist>


Cooks qemu VM with specific options.

Options:
  -h Print help and exit; if followed by:
     t - explains templates
     p - explains settings plist and dir
  -v Verbose output
  -n VM name; required unless set in plist
  -i OS ISO image to boot from; required unless set in plist
  -d VM HDD size; ex. 16G or 1T; required unless set in plist
  -m VM RAM size; ex 512M or 4G; required unless set in plist
  -p VM CPUs count; required unless set in plist
  -g Cook Cocoa GUI VM; otherwise cooks headless VM
  -s VM ssh port on host; defaults to $DF__SSH_PORT
  -S Subnet on guest main network interface; defaults to $DF__VM_SUBNET
  -u Name of the user to create in VM; defaults to host username: $DF__VM_USER
  -t Path to a dir that will be tared and included in extras ISO
  -f Path to a file that will be added as is to the extras ISO
  -b Path to a template; see -h templates for details
  -I Path to an additional ISO file that will be mounted on VM
  -V VMs dir; defaults to $DF__VMS_ROOT
  -D System-wide assets dir; defaults to $DF__ASSETS_DIR
  -e Force download qemu EFI firmware
  -E Like -e but use URL; defaults to latest Linaro release

EOU
}


function explain_templates {
cat<<EOF
Templates are bash heredocs that get qemu cooking variables (see below)
substituted. The resulting script is added to the extras ISO and made
executable by all.

For example a template file named 'user.sh.template'
>=== CUT ===<
#!/bin/sh
adduser --disabled-login --gecos '' \$CQ__USERNAME
echo '\${CQ__USERNAME}:changeme' | chpasswd
>=== CUT ===<

becomes on the extras ISO script file 'user.sh'
>=== CUT ===<
#!/bin/sh
adduser --disabled-login --gecos '' $DF__VM_USER
echo '${DF__VM_USER}:changeme' | chpasswd
>=== CUT ===<

Available variables:
EOF

cat "$0" \
    | sed -E 's/(CQ__[[:alnum:]])/\n\1/g' \
    | grep '^CQ__' \
    | sed -E 's/[^0-9_A-Z].*//' \
    | sort -u \
    | sed 's/^/  /'
}


function explain_plists {
# TODO: Implement
cat<<EOF
Settings dir for $GV__SCR_NAME must contain a settings .plist file and an ISO file
(or its url, see below) to boot the VM from. The plist format (short for
"Property List") is a macOS-specific way to put some structured and typed data
into an xml. Well, it is a bit more than that, but no matter. The easy way of
dealing with a ${GV__SCR_NAME_ONLY}.plist: take one that comes with this script
and edit it to your liking.

The bare minimum settings dir would look smth. like this:
>=== CUT ===<
$ tree minimum_alpine
minimum_alpine
├── alpine-virt-3.16.0-aarch64.iso
└── ${GV__SCR_NAME_ONLY}.plist
>=== CUT ===<

If you put a custom directory within the settings directory it will be tarred
and added to the "Extras ISO" mounted on the guest VM by the installation
script. For example you can have a some settings files destined for the guest
OS home dir:
>=== CUT ===<
$ tree -a alpine_with_extras
alpine_with_extras
├── alpine-virt-3.16.0-aarch64.iso
├── ${GV__SCR_NAME_ONLY}.plist
└── home
    ├── .bashrc
    ├── .screenrc
    └── .vimrc
>=== CUT ===<

On guest you will see:
>=== CUT ===<
$ mkdir /tmp/extras && mount /dev/vdc /tmp/extras
$ tar tf /tmp/extras/home.tar.gz
./
./.bashrc
./.vimrc
./.screenrc
>=== CUT ===<

Templates are used to cook guest-side installation scripts, any file in the
settings dir that has a .template extension is treated as a template. Please
see '$GV__SCR_NAME -h t' for a more details about the templates.

Any ISO file (must have .iso extension) in the settings dir will be added to
the guest VM after the Extras ISO hence see /dev/vdd and on. If a settings dir
has only one .iso file this file will be used for booting the VM during
installation. If you have 2 or more ISOs in your settings dir then the boot ISO
must be specifies in settings plist, please see CQInsISO.

Any other file in the settings dir will be added to the Extras Iso as-is.

If a file must be downloaded before using it for the guest installation you can
put in place of it an .url file with the download URL inside. Basically a
'filename.ext.url' file instructs the script to download 'filename.ext'. This
works with ISOs, templates and regular files. So the bare minimum settings dir
can be something like this:
>=== CUT ===<
$ tree min_net_alpine
min_net_alpine
├── alpine-virt-3.16.0-aarch64.iso.url
└── ${GV__SCR_NAME_ONLY}.plist
$ cat min_net_alpine/alpine-virt-3.16.0-aarch64.iso.url
https://dl-cdn.alpinelinux.org/alpine/v3.16/releases/aarch64/alpine-virt-3.16.0-aarch64.iso
>=== CUT ===<

The downloaded files are stored in ${GV__SCR_NAME_ONLY}.downloads dir inside the
settings dir. If you need A file re-downloaded just delete it from this dir
before running the script. Or delete the ${GV__SCR_NAME_ONLY}.downloads alltogether.
EOF
}


function brag_and_exit {
    local ERR_MESSAGE
    if [ -n "$1" ] ; then
        ERR_MESSAGE="$1"
    else
        ERR_MESSAGE='Something went terribly wrong'
    fi

    echo 'Error: '"$ERR_MESSAGE"$'\n' >&2
    usage >&2

    exit 1
}


function setup_script_vars {
    GV__SCR_NAME="${0##*/}"
    GV__SCR_NAME_ONLY="${GV__SCR_NAME%.*}"
    GV__PLIST_NAME="${GV__SCR_NAME_ONLY}.plist"
    GV__DL_DIR_NAME="${GV__SCR_NAME_ONLY}.downloads"
}


function set_defaults {
    DF__ASSETS_DIR="/opt/${GV__SCR_NAME_ONLY}"
    DF__QEMU_EFI_FD="${DF__ASSETS_DIR}/QEMU_EFI.fd"
    DF__QEMU_EFI_URL='https://releases.linaro.org/components/kernel/uefi-linaro/latest/release/qemu64/QEMU_EFI.fd'
    DF__VM_USER="$USER"
    DF__VM_SUBNET='192.168.99.0/24'
    DF__SSH_PORT='2022'
    DF__VMS_ROOT="${HOME}/VMs"
    DF__PLIST_NAME="${GV__SCR_NAME_ONLY}.plist"
    DF__DL_DIR_NAME="${GV__SCR_NAME_ONLY}.downloads"
}


function apply_plist_settings {
    if [ -n "$PL__GUI" ]; then
        CQ__GUI='Yes'
    fi
    CQ__HOSTNAME="${CQ__HOSTNAME-$PL__HOSTNAME}"
    CQ__CPUS_NUM="${CQ__CPUS_NUM-$PL__CPUS_NUM}"
    CQ__RAM_SIZE="${CQ__RAM_SIZE-$PL__RAM_SIZE}"
    CQ__HDD_SIZE="${CQ__HDD_SIZE-$PL__HDD_SIZE}"
    CQ__USERNAME="${CQ__USERNAME-$PL__USERNAME}"
    GV__INS_ISO="${GV__INS_ISO-$PL__INS_ISO}"
    CQ__SUBNET="${CQ__SUBNET-$PL__SUBNET}"
    GV__HOST_SSH_PORT="${GV__HOST_SSH_PORT-$PL__HOST_SSH_PORT}"

    if [ -n "$FL__DIRS" ]; then
        GV__TO_TAR="${GV__TO_TAR}${GV__TO_TAR+$'\n'}${FL__DIRS}"
    fi
    if [ -n "$FL__CP" ]; then
        GV__EXTRA_FILES="${GV__EXTRA_FILES}${GV__EXTRA_FILES+$'\n'}${FL__CP}"
    fi
    if [ -n "$FL__TEMPL" ]; then
        GV__EXTRA_TPLTS="${GV__EXTRA_TPLTS}${GV__EXTRA_TPLTS+$'\n'}${FL__TEMPL}"
    fi
    if [ -n "$FL__ISOS" ]; then
        GV__ALL_ISOS="${GV__ALL_ISOS}${GV__ALL_ISOS+$'\n'}${FL__ISOS}"
    fi
}


function apply_defaults {
    GV__ASSETS_DIR="${GV__ASSETS_DIR-$DF__ASSETS_DIR}"
    GV__FW_FILE_PATH="${GV__ASSETS_DIR}/QEMU_EFI.fd"
    GV__FW_FILE_URL="${GV__FW_FILE_URL-$DF__QEMU_EFI_URL}"
    CQ__USERNAME="${CQ__USERNAME-$DF__VM_USER}"
    CQ__SUBNET="${CQ__SUBNET-$DF__VM_SUBNET}"
    GV__HOST_SSH_PORT="${GV__HOST_SSH_PORT-$DF__SSH_PORT}"
    GV__VMS_DIR_PATH="$(realpath -- "${GV__VMS_DIR_PATH-$DF__VMS_ROOT}")"
}


##
#  Params:
#  1. Path to plist
##
function get_plist {
    if [ -z "$1" ]; then
        brag_and_exit 'No plist'
    fi

    if [ -f "$1" ] && plutil "$1" >/dev/null; then
        GV__TGT_PLIST="$1"
        return 0
    else
        return 1
    fi
}


##
#  Params:
#  1. Path to VM settings dir or plist
##
function get_target {
    if [ -z "$1" ]; then
        brag_and_exit 'No target'
    fi
    local TARGET="$(realpath -- "$1")"
    if [ -d "$TARGET" ]; then
        GV__TGT_DIR="$TARGET"
        local PLIST="${GV__TGT_DIR}/${GV__PLIST_NAME}"
        if ! get_plist "$PLIST"; then
            brag_and_exit "Bad plist '$PLIST'"
        fi
    elif get_plist "$TARGET"; then
        GV__TGT_DIR="$(dirname "$GV__TGT_PLIST")"
    else
        brag_and_exit "Bad target '$TARGET'"
    fi
}


##
#  Params:
#  1. Plist key name
#  2. Key type, optional
#
#  Exit status:
#  1 Key is missing
#  2 Key is of wrong type
##
function check_plist_key {
    local TYPE
    if ! TYPE="$(plutil -type "$1" "$GV__TGT_PLIST" 2>/dev/null)"; then
        return 1
    fi
    if [ -n "$2" -a "$TYPE" != "$2" ]; then
        return 2
    fi
}


##
#  Params:
#  1. Plist key name
#  2. Key type, optional
#
#  Exit status:
#  1 Key is missing
#  2 Key is of wrong type
##
function read_plist_key {
    local TYPE VALUE
    if [ -n "$2" ]; then
        if ! TYPE="$(plutil -type "$1" "$GV__TGT_PLIST" 2>/dev/null)"; then
            return 1
        fi
        if [ "$TYPE" != "$2" ]; then
            return 2
        fi
    fi
    if ! VALUE="$(plutil -extract "$1" raw "$GV__TGT_PLIST" 2>/dev/null)"; then
        return 1
    fi
    echo -n "$VALUE"
}


function get_plist_ports {
    local I=0 KEY PROTO GUEST HOST
    while true; do
        KEY="CQPortMap.${I}"
        if ! check_plist_key "$KEY"; then
            break
        fi
        if \
                ! PROTO="$(read_plist_key "${KEY}.proto" 'string')" || \
                ! GUEST="$(read_plist_key "${KEY}.guest" 'integer')" || \
                ! HOST="$(read_plist_key "${KEY}.host" 'integer')" || \
                ! [ "$PROTO" == 'tcp' -o "$PROTO" == 'udp' ]; then
            brag_and_exit "${KEY} (see -s) is malformed in '$GV__TGT_PLIST'"
        fi
        if [ $GUEST -eq 22 ]; then
            PL__HOST_SSH_PORT="$HOST"
        else
            PL__PORT_MAP="${PL__PORT_MAP}${PL__PORT_MAP+$'\n'}${PROTO}:127.0.0.1:${HOST}-:${GUEST}"
        fi
        I=$(( $I + 1 ))
    done
}


##
#  Params:
#  1. Key
#  2. Key type
#  3. Corresponding command-line option letter
##
function get_required_key {
    local VALUE
    if VALUE="$(read_plist_key "$1" "$2")" && [ -n "$VALUE" ]; then
        _RET_VAL="$VALUE"
    else
        brag_and_exit "${1} (see -${3}) is missing or invalid in '$GV__TGT_PLIST'"
    fi
}


##
#  Params:
#  1. Key
#  2. Corresponding command-line option letter
##
function get_required_memsize {
    local SIZE
    if \
            SIZE="$(read_plist_key "${1}.value" 'integer')" \
            && SIZE="${SIZE}$(read_plist_key "${1}.unit" 'string')" \
            && [ -n "$SIZE" ]; then
        _RET_VAL="$SIZE"
    else
        brag_and_exit "${1} (see -${2}) is missing or invalid in '$GV__TGT_PLIST'"
    fi
}


##
#  Params:
#  1. Key
#  2. Key type
#  3. Corresponding command-line option letter
##
function get_optional_key {
    local VALUE="$(read_plist_key "$1" "$2")"
    case $? in
        0)
            if [ "$2" == 'bool' ]; then
                [ "$VALUE" == 'true' ] && _RET_VAL='Yes'
            else
                _RET_VAL="$VALUE"
            fi
            ;;
        1)
            ;;
        *)
            brag_and_exit "${1} (see -${3}) is missing or invalid in '$GV__TGT_PLIST'"
            ;;
    esac
}


function unset_empty_pl {
    local L VAR
    while IFS='' read -r -d $'\n' L; do
        VAR="${L%=*}"
        [ "${VAR:0:4}" != 'PL__' ] && continue
        [ -n "${VAR//[0-9_A-Z]/}" ] && continue
        [ -z "${!VAR}" ] && unset "$VAR"
    done<<<"$(set -o posix; set)"
}


function get_plist_vars {
    # Required
    get_required_key 'CQHostname' 'string' 'n' && PL__HOSTNAME="$_RET_VAL"; unset _RET_VAL
    get_required_key 'CQCpusNum' 'integer' 'p' && PL__CPUS_NUM="$_RET_VAL"; unset _RET_VAL
    get_required_memsize 'CQRAMSize' 'm' && PL__RAM_SIZE="$_RET_VAL"; unset _RET_VAL
    get_required_memsize 'CQHDDSize' 'd' && PL__HDD_SIZE="$_RET_VAL"; unset _RET_VAL

    # Optional
    get_optional_key 'CQUsername' 'string' 'u' && PL__USERNAME="$_RET_VAL"; unset _RET_VAL
    get_optional_key 'CQGUI' 'bool' 'g' && PL__GUI="$_RET_VAL"; unset _RET_VAL
    get_optional_key 'CQInsISO' 'string' 'i' && PL__INS_ISO_NAME="$_RET_VAL"; unset _RET_VAL
    get_optional_key 'CQSubnet' 'string' 'S' && PL__SUBNET="$_RET_VAL"; unset _RET_VAL

    # Port forwarding
    get_plist_ports  # + $PL__HOST_SSH_PORT $PL__PORT_MAP

    # Clean up
    unset_empty_pl
}


##
#  Params:
#  1. Path to a file
##
function dispatch_file_to_list {
    local FN="${1##*/}"
    local EXT="${FN##*.}"
    if [ $(( $(echo -n "$FN" | wc -m ) - $(echo -n "$EXT" | wc -m ) )) -gt 1 ]; then
        case "$(echo -n $EXT | tr A-Z a-z)" in
            url)
                FL__URL="${FL__URL}${FL__URL+$'\n'}${1}"
                return 0
                ;;
            iso)
                FL__ISOS="${FL__ISOS}${FL__ISOS+$'\n'}${1}"
                return 0
                ;;
            template)
                FL__TEMPL="${FL__TEMPL}${FL__TEMPL+$'\n'}${1}"
                return 0
                ;;
        esac
    fi
    FL__CP="${FL__CP}${FL__CP+$'\n'}${1}"
}


function process_dir {
    local E E_PATH E_EXT
    while IFS='' read -r -d $'\n' E; do
        if [ "$E" == "$GV__PLIST_NAME" -o "$E" == "$GV__DL_DIR_NAME" ]; then
            continue
        fi
        E_PATH="$(realpath -- "${GV__TGT_DIR}/${E}")"
        if [ -d "$E_PATH" ]; then
            FL__DIRS="${FL__DIRS}${FL__DIRS+$'\n'}${E_PATH}"
            continue
        fi
        if [ -f "$E_PATH" ]; then
            dispatch_file_to_list "$E_PATH"
            continue
        fi
        brag_and_exit "Strange file '$E' in VM settings dir '$GV__TGT_DIR'"
    done<<<"$(ls -1 "$GV__TGT_DIR")"
}


##
#  Params:
#  1. Path to a file
#  2. Extension
##
function path_to_just_name {
    echo -n "$1" | sed "s%^.*/%%; s/\.${2}$//"
}


function download_urls {
    if [ -z "$FL__URL" ]; then
        return 0
    fi

    local DL_DIR="${GV__TGT_DIR}/${GV__DL_DIR_NAME}"
    if [ -e "$DL_DIR" ]; then
        if ! [ -d "$DL_DIR" ]; then
            brag_and_exit "Strange download dir found '$DL_DIR'"
        fi
    else
        mkdir "$DL_DIR" 2>/dev/null \
            || brag_and_exit "Can not create downloads dir '$DL_DIR'"
    fi

    local E FN F_PATH URL
    while IFS='' read -r -d $'\n' E; do
        FN="$(path_to_just_name "$E" 'url')"
        F_PATH="${DL_DIR}/${FN}"

        if ! [ -e "$F_PATH" ]; then
            URL="$(head -n 1 "$E" 2>/dev/null | sed 's/^[[:blank:]]*//; s/[[:blank:]]*$//')" \
                || brag_and_exit "Can not read URL from '$E'"

            if ! echo -n "$URL" | grep -Eq '^(http)|(https)|(ftp)://' 2>/dev/null; then
                brag_and_exit "Strange URL in '$E'"
            fi

            wget -q -O "$F_PATH" "$(cat "$E" | sed 's/^[[:blank:]]*//; s/[[:blank:]]*$//')" \
                || brag_and_exit "Download failed for '$E'"
        fi

        F_PATH="$(realpath -- "$F_PATH")"
        if ! [ -f "$F_PATH" ]; then
            brag_and_exit "Something strange was downloaded for '$E'"
        fi
        dispatch_file_to_list "$F_PATH"
    done<<<"$FL__URL"
}


function find_boot_iso {
    if [ -n "$PL__INS_ISO_NAME" ]; then
        if [ -z "$FL__ISOS" ]; then
            brag_and_exit "Boot ISO '$PL__INS_ISO_NAME' unavailable in '$GV__TGT_DIR'"
        fi
        local I ISOS_RE
        while IFS='' read -r -d $'\n' I; do
            if [ "${I##*/}" == "$PL__INS_ISO_NAME" ]; then
                PL__INS_ISO="$I"
            else
                ISOS_RE="${ISOS_RE}${ISOS_RE+$'\n'}${I}"
            fi
        done<<<"$FL__ISOS"
        if [ -z "$PL__INS_ISO" ]; then
            brag_and_exit "Boot ISO '$PL__INS_ISO_NAME' not in '$GV__TGT_DIR'"
        fi
        if [ -n "$ISOS_RE" ]; then
            FL__ISOS="$ISOS_RE"
        else
            unset FL__ISOS
        fi
    else
        case $(( $(echo -n "$FL__ISOS" | grep -i '\.iso$' | wc -l) + 0 )) in
            0)
                brag_and_exit "No boot ISO in '$GV__TGT_DIR'"
                ;;
            1)
                PL__INS_ISO="$FL__ISOS"
                unset FL__ISOS
                ;;
            *)
                brag_and_exit "Unable to figure out boot ISO in '$GV__TGT_DIR'"
                ;;
        esac
    fi
}


function add_to_tar {
    if [ -z "$1" ]; then
        brag_and_exit "Bad dir to tar (see -t)"
    fi
    local P="$(realpath -- "$1")"
    if ! [ -e "$P" ] || ! [ -d "$P" ]; then
        brag_and_exit "Bad dir to tar '$P' (see -t)"
    fi
    GV__TO_TAR="${GV__TO_TAR}${GV__TO_TAR+$'\n'}${P}"
}


function add_extra_file {
    if [ -z "$1" ]; then
        brag_and_exit "Bad extra file (see -f)"
    fi
    local P="$(realpath -- "$1")"
    if ! [ -e "$P" ] || ! [ -f "$P" ]; then
        brag_and_exit "Bad extra file '$P' (see -f)"
    fi
    GV__EXTRA_FILES="${GV__EXTRA_FILES}${GV__EXTRA_FILES+$'\n'}${P}"
}


function add_template {
    if [ -z "$1" ]; then
        brag_and_exit "Bad template file (see -b)"
    fi
    local T="$(realpath -- "$1")"
    if ! [ -e "$T" ] || ! [ -f "$T" ]; then
        brag_and_exit "Bad template file '$T' (see -f)"
    fi
    GV__EXTRA_TPLTS="${GV__EXTRA_TPLTS}${GV__EXTRA_TPLTS+$'\n'}${T}"
}


function is_iso {
    [ "$(file -b --mime-type "$1")" == 'application/x-iso9660-image' ]
}


function add_additional_iso {
    if [ -z "$1" ]; then
        brag_and_exit "Bad additional ISO (see -I)"
    fi
    local P="$(realpath -- "$1")"
    if ! [ -f "$P" ] || ! is_iso "$P"; then
        brag_and_exit "Bad additional ISO '$P' (see -I)"
    fi
    GV__ALL_ISOS="${GV__ALL_ISOS}${GV__ALL_ISOS+$'\n'}${P}"
}

function prepend_iso {
    if [ -z "$1" ]; then
        brag_and_exit "Bad prepended ISO"
    fi
    # No need to check here if this really is an ISO
    local P="$(realpath -- "$1")"
    GV__ALL_ISOS="${P}${GV__ALL_ISOS+$'\n'}${GV__ALL_ISOS}"
}

function is_mem_size {
     [ -z "$(echo -n "$1" | sed -E 's/[[:digit:]]{1,}[bBkKmMgGtT]{0,1}//')" ]
}


function is_int {
    [ "$1" == "$(echo -n "$1" | tr -dc 0-9)" ]
}


function print_options {
    echo "Verbose: ${GV__VERBOSE-No}"
    echo "Script name: $GV__SCR_NAME"
    echo "Assets dir: $GV__ASSETS_DIR"
    echo "Path to firmware file: $GV__FW_FILE_PATH"
    echo "Firmware file source URL: $GV__FW_FILE_URL"
    echo "VM username: $CQ__USERNAME"
    echo "VM subnet: $CQ__SUBNET"
    echo "Host ssh port: $GV__HOST_SSH_PORT"
    echo "VMs root dir: $GV__VMS_DIR_PATH"
    echo "VM hostname: $CQ__HOSTNAME"
    echo "Installer ISO: $GV__INS_ISO"
    echo "GUI: ${CQ__GUI-No}"
    echo "Extras ISO dirs to tar:${GV__TO_TAR+$'\n'}${GV__TO_TAR- None}"
    echo "Extras ISO files:${GV__EXTRA_FILES+$'\n'}${GV__EXTRA_FILES- None}"
    echo "Extras ISO templates:${GV__EXTRA_TPLTS+$'\n'}${GV__EXTRA_TPLTS- None}"
    echo "Additional ISOs:${GV__ALL_ISOS+$'\n'}${GV__ALL_ISOS- None}"
    echo "VM RAM: $CQ__RAM_SIZE"
    echo "VM HDD size: $CQ__HDD_SIZE"
    echo "VM CPU count: $CQ__CPUS_NUM"
    echo "Settings dir: ${GV__TGT_DIR-No}"
    echo "Settings plist: ${GV__TGT_PLIST-No}"
    echo "Plist Hostname: $PL__HOSTNAME"
    echo "Plist Number of CPUs: $PL__CPUS_NUM"
    echo "Plist RAM size: $PL__RAM_SIZE"
    echo "Plist HDD size: $PL__HDD_SIZE"
    echo "Plist Username: ${PL__USERNAME-Not set}"
    echo "Plist GUI: ${PL__GUI-No}"
    echo "Plist Installer ISO name: ${PL__INS_ISO_NAME-Not set}"
    echo "Plist Installer ISO: ${PL__INS_ISO-Not set}"
    echo "Plist VM subnet: ${PL__SUBNET-Not set}"
    echo "Plist Host ssh port: ${PL__HOST_SSH_PORT-Not set}"
    echo "Plist Other port forwardings:${PL__PORT_MAP+$'\n'}${PL__PORT_MAP- None}"
    echo "Plist Dirs to tar:${FL__DIRS+$'\n'}${FL__DIRS- None}"
    echo "Plist Templates to translate:${FL__TEMPL+$'\n'}${FL__TEMPL- None}"
    echo "Plist URLs to download:${FL__URL+$'\n'}${FL__URL- None}"
    echo "Plist Files to copy:${FL__CP+$'\n'}${FL__CP- None}"
    echo "Plist Additional ISOs:${FL__ISOS+$'\n'}${FL__ISOS- None}"
}


function check_and_update_arguments {
    if [ -z "$CQ__HOSTNAME" ]; then
        brag_and_exit "No VM name (see -n)"
    fi

    if [ -z "$GV__INS_ISO" ]; then
        brag_and_exit "No boot ISO (see -i)"
    fi
    if ! [ -f "$GV__INS_ISO" ] || ! is_iso "$GV__INS_ISO"; then
        brag_and_exit "Bad boot ISO '$GV__INS_ISO' (see -i)"
    fi
    if [ -z "$CQ__HDD_SIZE" ]; then
        brag_and_exit "No HDD size (see -d)"
    fi
    if ! is_mem_size "$CQ__HDD_SIZE"; then
        brag_and_exit "Strange HDD size '$CQ__HDD_SIZE' (see -d)"
    fi

    if [ -e "$GV__VMS_DIR_PATH" ] && ! [ -d "$GV__VMS_DIR_PATH" ]; then
        brag_and_exit "Strange VMs root dir (see -V)"
    fi

    if ! is_int "$GV__HOST_SSH_PORT"; then
        brag_and_exit "Strange ssh port (see -s)"
    fi

    # TODO: Proper check
    if [ -z "$CQ__SUBNET" ]; then
        brag_and_exit "Strange subneet (see -S)"
    fi

    if [ -z "$CQ__USERNAME" ] || [ $(echo -n "$CQ__USERNAME" | tr -d '0-9a-zA-Z_-' | wc -c) -ne 0 ]; then
        brag_and_exit "Strange username '$CQ__USERNAME' (see -u)"
    fi

    if [ -z "$CQ__RAM_SIZE" ]; then
        brag_and_exit "No RAM size (see -m)"
    fi
    if ! is_mem_size "$CQ__RAM_SIZE"; then
        brag_and_exit "Strange RAM size '$CQ__RAM_SIZE' (see -m)"
    fi

    if [ -z "$CQ__CPUS_NUM" ]; then
        brag_and_exit "No CPU count (see -p)"
    fi
    if ! is_int "$CQ__CPUS_NUM"; then
        brag_and_exit "Strange CPU count '$CQ__CPUS_NUM' (see -p)"
    fi
}

function read_options {
    local OPT OPTARG OPTIND NAME HELP_OPT
    while getopts ":n:i:V:s:S:t:f:b:I:D:e:E:u:d:m:p:hvg" OPT ; do
        case $OPT in
            h) # Print help and exit
                case "${!OPTIND}" in
                    [tT]*)
                        explain_templates
                        ;;
                    [pP]*)
                        explain_plists
                        ;;
                    *)
                        usage
                        ;;
                esac
                exit
                ;;
            v) # Verbose
    			GV__VERBOSE='Yes'
                ;;
            g) # GUI
    			CQ__GUI='Yes'
                ;;
            n) # VM name
    			CQ__HOSTNAME="$OPTARG"
                ;;
            i) # Boot ISO
    			GV__INS_ISO="$(realpath -- "$OPTARG")"
                ;;
            d) # HDD size
    			CQ__HDD_SIZE="$OPTARG"
                ;;
            m) # RAM size
    			CQ__RAM_SIZE="$OPTARG"
                ;;
            p) # CPUs count
    			CQ__CPUS_NUM="$OPTARG"
                ;;
            V) # VMs dir
    			GV__VMS_DIR_PATH="$OPTARG"
                ;;
            s) # ssh port
    			GV__HOST_SSH_PORT="$OPTARG"
                ;;
            S) # subnet
    			CQ__SUBNET="$OPTARG"
                ;;
            t) # dir to tar on extras ISO, multiple
                add_to_tar "$OPTARG"
                ;;
            f) # file to put on extras ISO, multiple
    			add_extra_file "$OPTARG"
                ;;
            b) # template to translate on extras ISO, multiple
    			add_template "$OPTARG"
                ;;
            I) # path to pre-cooked additional ISO, multiple
    			add_additional_iso "$OPTARG"
                ;;
            D) # assets dir
                # TODO: Implemwent
    			brag_and_exit $'Setting assets dir is not implemented yet (see -D)\nAssets dir is '"'${DF__ASSETS_DIR}'"
                ;;
            e) # Force download QEMU_EFI.fd
                # TODO: Implemwent
    			brag_and_exit 'Firmware downloading is not implemented yet (see -e)'
                ;;
            E) # Force download QEMU_EFI.fd from URL
                # TODO: Implemwent
    			brag_and_exit $'Setting firmware URL is not implemented yet (see -E)\nThe URL is '"'${DF__QEMU_EFI_URL}'"
                ;;
            u) # username
    			CQ__USERNAME="$OPTARG"
                ;;
        esac
    done

    if [ -n "${!OPTIND}" ]; then
        GV__RAW_TARGET="${!OPTIND}"
    fi
}


function create_vm_dir {
    GV__VM_DIR="$(realpath -- "${GV__VMS_DIR_PATH}/${CQ__HOSTNAME}")"
    if [ -e "$GV__VM_DIR" ]; then
        echo "VM dir already exists '$GV__VM_DIR'" >&2
        exit 2
    fi
    mkdir -p "$GV__VM_DIR"
}


function prepare_temp_dir {
    GV__TMP_COOK_DIR="$(mktemp -d "/tmp/${GV__SCR_NAME_ONLY}XXXXX")"
}


function clean_up_temp_dir {
    rm -rf "$GV__TMP_COOK_DIR"
    unset GV__TMP_COOK_DIR
}


function prepare_efi {
    GV__EFI_IMG="${GV__VM_DIR}/efi.img"
    GV__EFIVAR_IMG="${GV__VM_DIR}/efivar.img"

    dd if=/dev/zero of="$GV__EFI_IMG" bs=1m count=64 2>/dev/null
    dd if=/dev/zero of="$GV__EFIVAR_IMG" bs=1m count=64 2>/dev/null
    dd if="$GV__FW_FILE_PATH" of="$GV__EFI_IMG" conv=notrunc 2>/dev/null
}


function cook_main_hdd {
    GV__HDD_IMG="${GV__VM_DIR}/main.qcow2"
    qemu-img create -q -f qcow2 "$GV__HDD_IMG" "$CQ__HDD_SIZE"
}


##
#  Params:
#  1. Source dir path
#  2. Target dir path
##
function cook_dir_tar {
    if [ -z "$1" ] || ! [ -d "$1" ]; then
        brag_and_exit "Bad tar dir '$1'"
    fi
    local TAR_NAME="${1##*/}.tar.gz"
    local TAR="${2}/${TAR_NAME}"
    if [ -e "$TAR" ]; then
        brag_and_exit "Duplicate tar file '$TAR_NAME'"
    fi
    COPYFILE_DISABLE=1 tar -C "$1" -czf "$TAR" .
}


##
#  Params:
#  1. Source file path
#  2. Target dir path
##
function cp_extra_file {
    if [ -z "$1" ] || ! [ -f "$1" ]; then
        brag_and_exit "Bad extra file '$1'"
    fi
    cp -n "$1" "${2}/" || brag_and_exit "Duplicate extra file '$1'"
}


function prepare_template_code {
    local L VAR
    while IFS='' read -r -d $'\n' L; do
        VAR="${L%=*}"
        [ "${VAR:0:4}" != 'CQ__' ] && continue
        [ -n "${VAR//[0-9_A-Z]/}" ] && continue
        GV__TPLT_CODE="${GV__TPLT_CODE}${GV__TPLT_CODE+$'\n'}$VAR='${!VAR}'"
    done<<<"$(set -o posix; set)"
}


##
#  Params:
#  1. Template file path
#  2. Target dir path
##
function translate_template {
    if [ -z "$1" ] || ! [ -f "$1" ]; then
        brag_and_exit "Bad template '$1'"
    fi
    local DEST_NAME="$(basename "$1" | sed 's/.template$//')"
    local DEST="${2}/${DEST_NAME}"
    if [ -e "$DEST" ]; then
        brag_and_exit "Template produces duplicate '$DEST_NAME'"
    fi

    bash -c "${GV__TPLT_CODE}${GV__TPLT_CODE+$'\n'}cat<<EOFEOFEOF"$'\n'"$(cat "$1")"$'\nEOFEOFEOF' > "$DEST" \
        || brag_and_exit "Template translation failed '$1'"
    chmod a+x "$DEST" || brag_and_exit "Can not set permissions '$DEST'"
}


function cook_extras_iso {
    # Prepare extras ISO dir
    local EXTRAS_ISO_DIR="${GV__TMP_COOK_DIR}/extras"
    mkdir -p "$EXTRAS_ISO_DIR"

    # Add extra Files
    if [ -n "$GV__EXTRA_FILES" ]; then
        local F
        while IFS='' read -r -d $'\n' F; do
            cp_extra_file "$F" "$EXTRAS_ISO_DIR"
        done<<<"$(echo -n "$GV__EXTRA_FILES")"
    fi

    # Translate templates
    if [ -n "$GV__EXTRA_TPLTS" ]; then
        local T
        while IFS='' read -r -d $'\n' T; do
            translate_template "$T" "$EXTRAS_ISO_DIR"
        done<<<"$(echo -n "$GV__EXTRA_TPLTS")"
    fi

    # Tar extra dirs
    if [ -n "$GV__TO_TAR" ]; then
        local D
        while IFS='' read -r -d $'\n' D; do
            cook_dir_tar "$D" "$EXTRAS_ISO_DIR"
        done<<<"$(echo -n "$GV__TO_TAR")"
    fi

    # Cook ISO
    GV__EXTRAS_ISO="${GV__VM_DIR}/extras.iso"
    # TODO: add option to use hdiutil
    # hdiutil makehybrid -o "$GV__EXTRAS_ISO" "$EXTRAS_ISO_DIR"
    mkisofs -quiet \
        -joliet -joliet-long \
        -rock -uid 0 -gid 0 \
        -volid 'Extra' \
        -o "$GV__EXTRAS_ISO" \
        "$EXTRAS_ISO_DIR"

    prepend_iso "$GV__EXTRAS_ISO"
}


function insert_boot_iso {
    if [ -n "$GV__INS_ISO" ]; then
        prepend_iso "$GV__INS_ISO"
    fi
}


function compose_script_common_head {
# TODO: Check if VM is already runnung
local PORTS="hostfwd=tcp:127.0.0.1:${GV__HOST_SSH_PORT}-:22$(echo -n "$PL__PORT_MAP" | sed $'i\\\n,hostfwd=' | tr -d '\n')"
cat<<EOF
#!/bin/sh
GV__VM_DIR="\$(realpath -- "\${0%/*}")"
RUN_FILES_NAME="\$(mktemp -u '/tmp/qemu_${CQ__HOSTNAME}_XXXXXX')"
MON_SOC="\${RUN_FILES_NAME}.socket"
PID_FILE="\${RUN_FILES_NAME}.pid"

qemu-system-aarch64 \\
    -machine virt \\
    -accel hvf \\
    -cpu host \\
    -m '$CQ__RAM_SIZE' \\
    -smp '$CQ__CPUS_NUM' \\
    -drive if=pflash,format=raw,readonly=on,file="\${GV__VM_DIR}/$(basename "$GV__EFI_IMG")" \\
    -drive if=pflash,format=raw,file="\${GV__VM_DIR}/$(basename "$GV__EFIVAR_IMG")" \\
    -drive id=mainhdd,if=none,format=qcow2,file="\${GV__VM_DIR}/$(basename "$GV__HDD_IMG")" \\
    -device virtio-blk-pci,drive=mainhdd \\
    -netdev user,id=extnet,ipv4=on,ipv6=off,hostname='$CQ__HOSTNAME',net='$CQ__SUBNET',${PORTS} \\
    -device virtio-net-pci,netdev=extnet \\
    -monitor "unix:\${MON_SOC},server,nowait" \\
    -pidfile "\$PID_FILE" \\
EOF
}


##
#  Params:
#  1. Paths to ISOs, one per line
##
function compose_script_isos {
    local I FIXED_I IDX C=2
    while IFS='' read -r -d $'\n' I; do
        FIXED_I="$(echo -n "$I" | sed "s ^$GV__VM_DIR/ \\\${GV__VM_DIR}/ ")"
        IDX="index=${C},"
        echo "    -drive media=cdrom,${IDX}file=\"$FIXED_I\" \\"
        C=$(( $C + 1 ))
    done<<<"$(echo -n "$GV__ALL_ISOS")"
}


function compose_script_botton_headless_interactive {
    echo '    -nographic'
}


function compose_script_botton_headless_deamonized {
    echo '    -nographic -parallel none -serial none -daemonize'
}


function compose_script_botton_cocoa {
cat<<EOF
    -device qemu-xhci \\
    -device usb-kbd \\
    -device usb-tablet \\
    -device virtio-gpu-pci \\
    -device intel-hda \\
    -device hda-output \\
    -display cocoa,show-cursor=on,left-command-key=off >/dev/null 2>/dev/null & disown
EOF
}


function compose_script_botton_cocoa_nodaemon {
cat<<EOF
    -device qemu-xhci \\
    -device usb-kbd \\
    -device usb-tablet \\
    -device virtio-gpu-pci \\
    -device intel-hda \\
    -device hda-output \\
    -display cocoa,show-cursor=on,left-command-key=off
EOF
}


function compose_script_deamonized_message {
cat<<EOF

sleep .1
PID=\$(cat "\$PID_FILE")
cat<<EOM
VM '$CQ__HOSTNAME' started with process ID \$PID

To connect via ssh run:
  ssh -p $GV__HOST_SSH_PORT root@localhost # Alpine live ISO
  ssh -p $GV__HOST_SSH_PORT installer@localhost # Ubuntu server live ISO
  ssh -p $GV__HOST_SSH_PORT $CQ__USERNAME@localhost # Installed VM

To connect to the monitoring interface run:
  socat -,echo=0,icanon=0 unix-connect:\${MON_SOC}
EOM
EOF
}


function compose_install_script {
    compose_script_common_head
    compose_script_isos
    if [ -n "$CQ__GUI" ]; then
        compose_script_botton_cocoa
        compose_script_deamonized_message
    else
        compose_script_botton_headless_interactive
    fi
}


function compose_run_script {
    compose_script_common_head
    if [ -n "$CQ__GUI" ]; then
        compose_script_botton_cocoa
    else
        compose_script_botton_headless_deamonized
    fi
    compose_script_deamonized_message
}


function compose_debug_script {
    compose_script_common_head
    if [ -n "$CQ__GUI" ]; then
        compose_script_botton_cocoa_nodaemon
    else
        compose_script_botton_headless_interactive
    fi
}


function cook_scripts {
    local \
        INS_SCR="${GV__VM_DIR}/install.sh" \
        RUN_SCR="${GV__VM_DIR}/run.sh" \
        DBG_SCR="${GV__VM_DIR}/debug.sh"
    compose_install_script >"$INS_SCR"
    compose_run_script >"$RUN_SCR"
    compose_debug_script  >"$DBG_SCR"
    chmod a+x "$INS_SCR" "$RUN_SCR" "$DBG_SCR"
}


# Run
setup_script_vars # + $GV__SCR_NAME $GV__SCR_NAME_ONLY
set_defaults # + DF__*
read_options "$@" # + $GV__RAW_TARGET
if [ -n "$GV__RAW_TARGET" ]; then
    get_target "$GV__RAW_TARGET" # + $GV__TGT_DIR $GV__TGT_PLIST
    get_plist_vars # + $PL__*
    process_dir # + $FL__*
    download_urls
    find_boot_iso
    apply_plist_settings
fi
apply_defaults
check_and_update_arguments
[ -n "$GV__VERBOSE" ] && print_options
create_vm_dir # + $GV__VM_DIR
prepare_temp_dir # + $GV__TMP_COOK_DIR
prepare_efi # + $GV__EFI_IMG $GV__EFIVAR_IMG
cook_main_hdd # + $GV__HDD_IMG
prepare_template_code # + $GV__TPLT_CODE
cook_extras_iso # + $GV__EXTRAS_ISO
insert_boot_iso
cook_scripts
clean_up_temp_dir # - $GV__TMP_COOK_DIR
