#!/bin/zsh
# PROCEDURAL: Double-click entry point for the local Haneda driver and simulator.
cd "${0:A:h}/.." || exit 1
python3 Scripts/haneda-walk.py "$@"
result=$?
if [[ $result -ne 0 ]]; then
  read -r '?Press Return to close…'
fi
exit "$result"
