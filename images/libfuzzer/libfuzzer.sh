#!/bin/bash -ex
cd "$HOME"

# Get FuzzManager configuration from credstash
# We require FuzzManager credentials in order to submit our results.
if [[ ! -f "$HOME/.fuzzmanagerconf" ]]
then
  credstash get fuzzmanagerconf > .fuzzmanagerconf
fi

# Update FuzzManager config for this instance
mkdir -p signatures
cat >> .fuzzmanagerconf << EOF
sigdir = $HOME/signatures
EOF

# Firefox with ASan-/Coverage/LibFuzzer
# We might have a volume attached which mounts Firefox into the container.
if [[ ! -d "$HOME/firefox" ]]
then
  fuzzfetch -o "$HOME" -n firefox -a --fuzzing --tests gtest
fi

# FuzzData
FUZZDATA_URL="https://github.com/mozillasecurity/fuzzdata.git/trunk"

# ContentIPC
if [ -n "$MOZ_IPC_MESSAGE_FUZZ_BLACKLIST" ]
then
  mkdir -p settings/ipc
  svn export --force "$FUZZDATA_URL/$MOZ_IPC_MESSAGE_FUZZ_BLACKLIST" "$MOZ_IPC_MESSAGE_FUZZ_BLACKLIST"
  export MOZ_IPC_MESSAGE_FUZZ_BLACKLIST="$HOME/$MOZ_IPC_MESSAGE_FUZZ_BLACKLIST"
fi

# LibFuzzer Corpora
if [ -n "$CORPORA" ]
then
  svn export --force "$FUZZDATA_URL/$CORPORA" ./corpora/
  CORPORA="./corpora/"
else
  mkdir ./corpora
  CORPORA="./corpora/"
fi

# LibFuzzer Dictionary Tokens
if [ -n "$TOKENS" ]
then
  svn export --force "$FUZZDATA_URL/$TOKENS" ./tokens.dict
  TOKENS="-dict=./tokens.dict"
fi

# Setup ASan
export ASAN_SYMBOLIZER_PATH=/usr/bin/llvm-symbolizer
ASAN_OPTIONS=\
print_scariness=true:\
strip_path_prefix=/builds/worker/workspace/build/src/:\
dedup_token_length=1:\
print_cmdline=true:\
detect_stack_use_after_scope=true:\
detect_invalid_pointer_pairs=2:\
strict_init_order=true:\
check_initialization_order=true:\
allocator_may_return_null=true:\
start_deactivated=false:\
strict_string_checks=true:\
$ASAN

# Run reporter for EC2
tee run-ec2report.sh << EOF
#!/bin/bash
./fuzzmanager/EC2Reporter/EC2Reporter.py --report-from-file stats --keep-reporting 60 --random-offset 30
EOF
chmod u+x run-ec2report.sh
#screen -t ec2report -dmS ec2report ./run-ec2report.sh

# Setup LibFuzzer
export FUZZER="${FUZZER:-SdpParser}"
export LIBFUZZER=1
export MOZ_RUN_GTEST=1
# shellcheck disable=SC2206
LIBFUZZER_ARGS=("-print_pcs=1" "-handle_segv=0" "-handle_bus=0" "-handle_abrt=0" $LIBFUZZER_ARGS $TOKEN $CORPORA)

# Run LibFuzzer
./fuzzmanager/misc/afl-libfuzzer/afl-libfuzzer-daemon.py \
  --fuzzmanager \
  --libfuzzer \
  --sigdir "$HOME/signatures" \
  --tool "LibFuzzer-$FUZZER" \
  --env "ASAN_OPTIONS=${ASAN_OPTIONS//:/ }" \
  --cmd "$HOME/firefox/firefox" "${LIBFUZZER_ARGS[@]}"

# Minimize Crash
#   xvfb-run -s '-screen 0 1024x768x24' ./firefox -minimize_crash=1 -max_total_time=60 crash-<hash>
#
# ASan Options
#   detect_deadlocks=true
#   handle_ioctl=true
#   intercept_tls_get_addr=true
#   leak_check_at_exit=true # LSAN not enabled in --enable-fuzzing
#   strict_string_checks=false # GLib textdomain() error
#   detect_stack_use_after_return=false # nsXPConnect::InitStatics() error
