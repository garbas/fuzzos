#!/bin/sh -ex

#### Base System Configuration

# Quiet pip
cat << EOF | tee /etc/pip.conf > /dev/null
[global]
disable-pip-version-check = true
no-cache-dir = false

[install]
upgrade-strategy = only-if-needed
EOF

# Ensure the machine uses core dumps with PID in the filename
# https://github.com/moby/moby/issues/11740
cat << EOF | tee /etc/sysctl.d/60-fuzzos.conf > /dev/null
# Ensure that we use PIDs with core dumps
kernel.core_uses_pid = 1
# Allow ptrace of any process
kernel.yama.ptrace_scope = 0
EOF
