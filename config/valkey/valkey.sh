#!/bin/sh

exec valkey-server - <<-EOF
	bind 0.0.0.0
	loglevel warning
	save 60 1
	appendonly yes
	appendfsync everysec
	auto-aof-rewrite-min-size 16mb
	auto-aof-rewrite-percentage 100
	dir /data/
	${VALKEYCLI_AUTH:+user default on ~* &* +@all -@admin >${VALKEYCLI_AUTH:?}}
EOF
