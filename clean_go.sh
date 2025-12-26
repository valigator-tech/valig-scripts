set -euo pipefail

echo "== Detect current go =="
command -v go || true
go version || true || true

# 1) Move /usr/local/go aside if present
if [ -d /usr/local/go ]; then
  echo "Found /usr/local/go — moving to /usr/local/go.bak"
  mv /usr/local/go /usr/local/go.bak
else
  echo "No /usr/local/go directory found."
fi

# 2) Remove PATH lines with /usr/local/go/bin
FILES="/etc/profile /etc/environment /etc/profile.d/* $HOME/.profile $HOME/.bashrc $HOME/.zshrc $HOME/.bash_profile"
echo "== Searching for PATH edits =="
grep -R --line-number '/usr/local/go/bin' $FILES 2>/dev/null || echo "No PATH entries found."
echo
echo "If any files were listed above, open them and remove lines that add /usr/local/go/bin."
read -p "Press Enter to continue after editing your files..."

# 3) Delete symlinks into /usr/local/go from /usr/local/bin
echo "== Cleaning stray symlinks in /usr/local/bin =="
find /usr/local/bin -maxdepth 1 -type l -lname '/usr/local/go/*' -print -delete || true
hash -r

# 4) Install from APT
echo "== Installing golang-go from APT =="
apt update
apt install -y golang-go

# 5) Verify
echo "== Verification =="
echo "which go: $(command -v go || true)"
go version || true
echo "GOROOT: $(go env GOROOT || true)"
