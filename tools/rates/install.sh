#!/bin/sh
# Sets up the daily rates job for the current user on a Linux machine with systemd, python3, git and ssh.
set -eu
dir=$(cd "$(dirname "$0")" && pwd)
home="$HOME/.local/share/nobudget-rates"
mkdir -p "$home" "$HOME/.config/systemd/user"
cp "$dir/update-rates.py" "$home/"
cp "$dir/nobudget-rates.service" "$dir/nobudget-rates.timer" "$HOME/.config/systemd/user/"
# A key that can push to the nobudget-rates repo and nothing else. The comment names the job, not this machine.
new=
[ -f "$home/deploy_key" ] || { ssh-keygen -q -t ed25519 -N '' -C nobudget-rates -f "$home/deploy_key"; new=1; }
systemctl --user daemon-reload
systemctl --user enable --now nobudget-rates.timer
echo
if [ -n "$new" ]; then
  echo "New key made. Add it at https://github.com/raigon-pawa/nobudget-rates/settings/keys/new"
  echo "(title: nobudget-rates, tick 'Allow write access'):"
  echo
  cat "$home/deploy_key.pub"
  echo
else
  echo "Updated. The existing key is kept, so nothing changes on GitHub."
fi
echo "Test it:  systemctl --user start nobudget-rates && journalctl --user -u nobudget-rates -n 20"
echo "To run while nobody is logged in:  sudo loginctl enable-linger $USER"
