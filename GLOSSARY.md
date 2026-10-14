# Homelab

A home server that runs Docker services.

## Language

**Server tree**:
The working copy of this repository on the server. It is *dirty* when tracked files have uncommitted changes or untracked files outside the ignore rules are present.
_Avoid_: server repo, remote copy

**Deploy**:
Starting or updating services on the server from the server tree. It does not touch git.
_Avoid_: ship, roll out

**Ship**:
Delivering committed repository changes from the laptop to the server and deploying the selected services.
_Avoid_: sync, upload
