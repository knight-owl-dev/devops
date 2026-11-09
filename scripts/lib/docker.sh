#!/usr/bin/env bash
# Shared docker helpers for host-side scripts.

# Run a throwaway container under Docker's init, signalling its process group.
#
# The images set no init, so a PID 1 command ignores every signal it has no
# handler for. Docker's init is tini without -g: TINI_KILL_PROCESS_GROUP=1
# turns it on, so Ctrl-C reaches the command's children, not just make or
# bash. The Makefile's DOCKER_RUN carries the same flags.
#
# Arguments:
#   $@ - docker run options, image and command
docker_run() {
  docker run --rm --init -e TINI_KILL_PROCESS_GROUP=1 "${@}"
}
