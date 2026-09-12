#!/bin/sh
/root/.rustup/toolchains/stable-aarch64-unknown-linux-gnu/bin/rustc "$@"
rc=$?
echo "$@" | grep -q "extra-filename=-828a54a9fdb4b349" && {
  F=/root/projects/mssql-server/sqlitetds/tests/rust/probe_1107/target/debug/build/proc-macro2-828a54a9fdb4b349/build_script_build-828a54a9fdb4b349
  if [ -f "$F" ]; then
    cp "$F" /root/projects/kilas/.tools/validate/ts_c_nif/after_rustc.bin && echo "PRESENT after rustc, rc=$rc" >> /root/projects/kilas/.tools/validate/ts_c_nif/shim.log
  else
    echo "MISSING after rustc, rc=$rc" >> /root/projects/kilas/.tools/validate/ts_c_nif/shim.log
  fi
}
exit $rc
