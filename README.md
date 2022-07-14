# Cook QEMU
A Script to cook a native [QEMU](https://www.qemu.org) VM on an Apple Silicon mac.

As of mid July 2022 this is but a working prototype hence it most probably has **bugs** :bug::bug::bug:

## TL;DR
```bash
# Install pre-requisites
brew install coreutils wget cdrtools qemu
# Prepare asstets dir
sudo mkdir -p /opt/cookqemu
U="$(id -u):$(id -g)" sudo chown "$U" /opt/cookqemu
wget -O /opt/cookqemu/QEMU_EFI.fd https://releases.linaro.org/components/kernel/uefi-linaro/latest/release/qemu64/QEMU_EFI.fd
# Get the script and run it
git clone <put git URL here>
cd <put dir name here>
./cookqemu.sh presets/alpine
~/VMs/alpine/install.sh
# Log in as root (no password) into the guest OS
mkdir /tmp/extra && mount /dev/vdc /tmp/extra && /tmp/extra/setup.sh
# Once the installation script is done
poweroff
# Now the VM is ready to run
~/VMs/alpine/run.sh
# Login with your macOS username, default password is admin
```
&#9888; Please don't forget to change the password.

To install Ubuntu Base use `presets/ubuntu_via_alpine` instead.

## Usage
```bash
cookqemu.sh -h [t|p]
```
or
```bash
cookqemu.sh <settings dir or plist>
```
or
```bash
cookqemu.sh -h [t] -v -n <name> -i <boot iso> -d <disk size> -m <mem size>
  -p <CPU count> -g -s <ssh port> -S <subnet> -u <username> -t <path>
  -f <path> -b <path> -I <path> -V <VMs dir> -D <assets dir> -e|-E <URL>
  <settings dir>|<settings plist>
```

## Options
```
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
-s VM ssh port on host; defaults to 2022
-S Subnet on guest main network interface; defaults to 192.168.99.0/24
-u Name of the user to create in VM; defaults to host username: ish
-t Path to a dir that will be tared and included in extras ISO
-f Path to a file that will be added as is to the extras ISO
-b Path to a template; see -h templates for details
-I Path to an additional ISO file that will be mounted on VM
-V VMs dir; defaults to /Users/ish/VMs
-D System-wide assets dir; defaults to /opt/cookqemu
-e Force download qemu EFI firmware
-E Like -e but use URL; defaults to latest Linaro release
```

## Settings dirs and plists
Settings dir for `cookqemu.sh` must contain a settings `.plist` file and an ISO file
(or its url, [see below](#downloading-files)) to boot the VM from. The plist format (short for
"Property List") is a macOS-specific way to put some structured and typed data
into an xml. Well, it is a bit more than that, but no matter. The easy way of
dealing with a `cookqemu.plist` – take one that comes with this script
and edit it to your liking.

The bare minimum settings dir would look smth. like this:
```bash
$ tree minimum_alpine
minimum_alpine
├── alpine-virt-3.16.0-aarch64.iso
└── cookqemu.plist
```

## Extras ISO
All the extra stuff you need for installing and configuring the guest OS also
goes into the settings dir and ends up on the Extras ISO that is made available
as `/dev/vdc` on guest VM during the OS installation. See right below how different
kinds of stuff get on the Extras ISO.

## Custom dirs
If you put a custom directory within the settings directory it will be tarred
and added to the Extras ISO connected to the guest VM by the installation
script. For example you can have some settings files destined for your home dir
on the guest OS:
```bash
$ tree -a alpine_with_extras
alpine_with_extras
├── alpine-virt-3.16.0-aarch64.iso
├── cookqemu.plist
└── home
    ├── .bashrc
    ├── .screenrc
    └── .vimrc
```

On guest you will see:
```bash
$ mkdir /tmp/extras && mount /dev/vdc /tmp/extras
$ tar tf /tmp/extras/home.tar.gz
./
./.bashrc
./.vimrc
./.screenrc
```

## Templates
Templates are used to cook guest-side installation scripts. Any file in the
settings dir that has a `.template` extension is treated as a template. You can
think of templates as of bash heredocs that get qemu cooking variables ([see
below](#available-variables)) substituted. The resulting script is added to the extras ISO and made
executable by all.

For example a template file named `user.sh.template`:
```bash
#!/bin/sh
adduser --disabled-login --gecos '' $CQ__USERNAME
echo '${CQ__USERNAME}:changeme' | chpasswd
```

becomes on the extras ISO script file `user.sh`:
```bash
#!/bin/sh
adduser --disabled-login --gecos '' ish
echo 'ish:changeme' | chpasswd
```

### Available variables
```
  CQ__CPUS_NUM
  CQ__GUI
  CQ__HDD_SIZE
  CQ__HOSTNAME
  CQ__RAM_SIZE
  CQ__SUBNET
  CQ__USERNAME
```

## More ISO files
Any ISO file (must have `.iso` extension) in the settings dir will be added to
the guest VM after the Extras ISO hence see `/dev/vdd` and on. If a settings dir
has only one `.iso` file it will be used for booting the VM during
installation. If you have 2 or more ISOs in your settings dir then the boot ISO
must be specifies in settings plist, please see `CQInsISO`.

## Other files
Any other file in the settings dir will be added to the Extras Iso as-is.

## Downloading files
If a file must be downloaded before using it for the guest installation you can
put in place of it an `.url` file with the download URL inside. Basically a
`filename.ext.url` file instructs the script to download `filename.ext`. This
works with ISOs, templates and regular files. So the bare minimum settings dir
can be something like this:
```bash
$ tree min_net_alpine
min_net_alpine
├── alpine-virt-3.16.0-aarch64.iso.url
└── cookqemu.plist
$ cat min_net_alpine/alpine-virt-3.16.0-aarch64.iso.url
https://dl-cdn.alpinelinux.org/alpine/v3.16/releases/aarch64/alpine-virt-3.16.0-aarch64.iso
```

The downloaded files are stored in `cookqemu.downloads` dir inside the
settings dir. If you need A file re-downloaded just delete it from this dir
before running the script. Or delete the `cookqemu.downloads` alltogether.

# Disclaimer
You can use this script in any manner that suits you though remember at all
times that by using it you agree that you use it at your own risk and neither
I nor anybody else except for yourself is to be held responsible in case
anything goes wrong as a result of using this script.