# Copyright (c) 2007-2008 Roy Marples <roy@marples.name>
# Released under the 2-clause BSD license.

apipa_depend()
{
	program /sbin/arping /bin/arping
}

_random_bytes_as_int()
{
	local hex num_bytes="$1"

	# While POSIX does not require that /dev/urandom exist, it is a
	# de-facto standard. Therefore, the following approach should be
	# highly portable in practice. In the case of Linux, and unlike BSD
	# this interface does not block in the event that the CSRNG has not
	# yet been seeded. Still, this is acceptable because we do not
	# require a guarantee that the entropy be cryptographically secure.
	# It's also worth noting that Linux >=5.4 is faster at seeding in
	# the absence of RDRAND/RDSEED than previous versions were.
	test -e /dev/urandom &&
	hex=$(
		LC_ALL=C tr -dc '[:xdigit:]' < /dev/urandom |
		dd bs="$(( num_bytes * 2 ))" count=1 2>/dev/null) &&
	test "${#hex}" = "$(( num_bytes * 2 ))" &&
	printf '%d\n' "0x${hex}"
}

_random_apipa_octets()
{
	local seed

	# Obtain a highly random 16-bit seed for use by awk's RNG. In the
	# unlikely event that the seed ends up being empty, awk will seed
	# based on the time of day, with a granularity of one second.
	seed=$(_random_bytes_as_int 2)

	# For APIPA (RFC 3927), the 169.254.0.0/16 address block is
	# reserved. This provides 65024 addresses, having accounted for the
	# fact that the first and last /24 are reserved for future use.
	awk "BEGIN {
		srand($seed)
		for (i=256; i<65280; i++) print rand() \" \" i
	}" |
	sort -k 1,1 -n |
	POSIXLY_CORRECT=1 awk '{
		hex = sprintf("%04x",$2)
		printf("%d %d\n", "0x" substr(hex,1,2), "0x" substr(hex,3,2))
	}'
}

apipa_start()
{
	local addr rc

	_exists || return

	einfo "Searching for free addresses in 169.254.0.0/16"
	eindent

	exec 3>&1
	addr=$(
		_random_apipa_octets |
		{
			while read -r i1 i2; do
				addr="169.254.${i1}.${i2}"
				vebegin "${addr}/16" >&3
				if ! arping_address "${addr}" >&3; then
					printf '%s\n' "${addr}"
					exit 0
				fi
			done
			exit 1
		}
	)
	rc=$?
	exec 3>&-

	if [ "$rc" = 0 ]; then
		eval "config_${config_index}=\"\${addr}/16 broadcast 169.254.255.255\""
		: $(( config_index -= 1 ))
		veend 0
	else
		eerror "No free address found!"
	fi

	eoutdent
	return "$rc"
}
