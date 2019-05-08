#!/bin/bash
set -e
/usr/sbin/sshd
/opt/app/bin/acari_client $1
