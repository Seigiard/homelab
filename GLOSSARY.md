# Homelab

A home server that runs Docker services. Changes are made on the laptop, committed to git, and reach the server through git.

## Language

**Server tree**:
The working copy of this repository on the server. It changes only through `git pull`; any modified or untracked file makes it *dirty*.
_Avoid_: server repo, remote copy

**Deploy**:
Starting or updating services on the server from the server tree. It does not touch git.
_Avoid_: ship, roll out

**Ship**:
Delivering committed changes from the laptop: push `main`, pull it into a clean server tree, then deploy the named services.
_Avoid_: sync, upload, copying a file to the server
