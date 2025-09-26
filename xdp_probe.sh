#!/usr/bin/env bash
set -euo pipefail

# =========================
# Config / Helpers
# =========================
WORKDIR="${XDP_WORKDIR:-/root/xdp-probe}"
KERN_C="${WORKDIR}/xdp_pass_kern.c"
OBJ="${WORKDIR}/xdp_pass_kern.o"
IFACE="${1:-}"           # optional: interface name
ACTION="${2:-load}"      # load | unload

say()  { printf "\033[1;36m[INFO]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[ERR ]\033[0m %s\n" "$*" >&2; }

need_root() {
  if [[ $EUID -ne 0 ]]; then err "Run as root (sudo)."; exit 1; fi
}

has_cmd() { command -v "$1" >/dev/null 2>&1; }

install_deps() {
  local need=0
  has_cmd clang || need=1
  has_cmd llvm-objdump || need=1
  if [[ $need -eq 1 ]]; then
    say "Installing minimal deps (clang/llvm only; no bpftool)."
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y clang llvm
  fi
}

detect_iface() {
  if [[ -n "${IFACE}" ]]; then return; fi
  # Try default route (often public)
  IFACE="$(ip route get 8.8.8.8 2>/dev/null | awk '/ dev /{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}' || true)"
  # Fallback: first UP,LOWER_UP non-lo/tailscale/veth
  if [[ -z "${IFACE}" ]]; then
    IFACE="$(ip -o link show | awk -F': ' '/state UP/{print $2}' | grep -Ev '^(lo|tailscale|veth)' | head -n1 || true)"
  fi
  if [[ -z "${IFACE}" ]]; then
    err "Could not auto-detect an interface. Usage: $0 <iface> [load|unload]"
    exit 1
  fi
}

write_minimal_prog() {
  mkdir -p "${WORKDIR}"
  cat > "${KERN_C}" <<'EOF'
// Minimal standalone XDP "pass" program (no kernel headers/libbpf).

struct xdp_md {
    unsigned int data;
    unsigned int data_end;
    unsigned int data_meta;
    unsigned int ingress_ifindex;
    unsigned int rx_queue_index;
    unsigned int egress_ifindex;
};

#define XDP_ABORTED   0
#define XDP_DROP      1
#define XDP_PASS      2
#define XDP_TX        3
#define XDP_REDIRECT  4

#define SEC(NAME) __attribute__((section(NAME), used))

SEC("xdp")
int xdp_pass(struct xdp_md *ctx) {
    // Let every packet pass
    return XDP_PASS;
}

char _license[] SEC("license") = "GPL";
EOF
}

build_obj() {
  say "Compiling ${KERN_C} -> ${OBJ}"
  clang -O2 -g -Wall -Werror -target bpf -c "${KERN_C}" -o "${OBJ}"
}

attach_native() {
  # returns 0 on success
  ip link set dev "${IFACE}" xdp obj "${OBJ}" sec xdp 2>/tmp/xdp_native.err && return 0 || return 1
}

attach_generic() {
  ip link set dev "${IFACE}" xdpgeneric obj "${OBJ}" sec xdp 2>/tmp/xdp_generic.err && return 0 || return 1
}

report_status() {
  local mode="$1"
  echo
  say "==== XDP STATUS ===="
  echo "Interface : ${IFACE}"
  echo "Mode      : ${mode}"
  ethtool -i "${IFACE}" 2>/dev/null || true
  ethtool "${IFACE}" 2>/dev/null | grep -E 'Speed:|Duplex:' || true
  echo
  ip -details link show dev "${IFACE}" | sed -n '1,60p'
  echo
  if command -v xdp-loader >/dev/null 2>&1; then
    xdp-loader status || true
  fi
}

unload_xdp() {
  say "Detaching any XDP program from ${IFACE}"
  # Modern iproute2 turns both native/offload/generic off with this:
  ip link set dev "${IFACE}" xdp off 2>/dev/null || true
  # Keep this for older iproute2 generic path:
  ip link set dev "${IFACE}" xdpgeneric off 2>/dev/null || true
}

# =========================
# Main
# =========================
need_root
detect_iface

case "${ACTION}" in
  unload)
    unload_xdp
    exit 0
    ;;
  load)
    install_deps
    write_minimal_prog
    build_obj
    say "Attempting native XDP attach on ${IFACE}…"
    if attach_native; then
      report_status "native"
      exit 0
    else
      warn "Native attach failed (details in /tmp/xdp_native.err). Trying generic (skb)…"
      if attach_generic; then
        report_status "generic (skb)"
        exit 0
      else
        err "Both native and generic attaches failed."
        warn "Native error:"
        sed -n '1,80p' /tmp/xdp_native.err || true
        warn "Generic error:"
        sed -n '1,80p' /tmp/xdp_generic.err || true
        exit 2
      fi
    fi
    ;;
  *)
    err "Unknown action '${ACTION}'. Usage: $0 [<iface>] [load|unload]"
    exit 1
    ;;
esac