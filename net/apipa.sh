# Copyright (c) 2007-2008 Roy Marples <roy@marples.name>
# Released under the 2-clause BSD license.

apipa_depend()
{
	program /sbin/arping /bin/arping
}

_random_uint16()
{
	# While POSIX does not require that /dev/urandom exist, it is a de-facto
	# standard. In the case of Linux, and unlike BSD, this interface does
	# not block in the event that the CSRNG has not yet been seeded.
	# Still, this is acceptable because we do not require a guarantee that
	# the entropy be cryptographically secure.
	test -e /dev/urandom &&
	printf %d 0x"$(LC_ALL=C od -vAn -N2 -tx1 /dev/urandom | tr -d '[:space:]')"
}

_random_apipa_octets()
{
	local seed

	# Attempt to generate a random uint16 to seed awk's RNG. The maximum
	# value of RAND_MAX known to be portable is 32767. Clamp accordingly by
	# discarding one bit's worth of data. Should the seed turn out to be
	# empty, we instruct awk to seed based on the time of day, in seconds.
	seed=$(_random_uint16) && : $(( seed >>= 1 ))

	# For APIPA (RFC 3927), the 169.254.0.0/16 address block is
	# reserved. This provides 65024 addresses, having accounted for the
	# fact that the first and last /24 are reserved for future use.
	awk -v seed="$seed" 'BEGIN {
		if (seed != "") {
			srand(seed)
		} else {
			srand()
		}
		for (i = 1; i < 255; i++) {
			for (j = 0; j < 256; j++) {
				printf("%f %d %d\n", rand(), i, j)
			}
		}
	}' | sort -k 1,1 -n
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
			while read -r f1 f2 f3; do
				next_addr="169.254.$f2.$f3"
				vebegin "$next_addr/16" >&3
				if ! arping_address "$next_addr" >&3; then
					printf %s "$next_addr"
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
