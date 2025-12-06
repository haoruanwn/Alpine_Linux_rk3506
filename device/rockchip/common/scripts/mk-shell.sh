#!/bin/bash -e

# Hooks

usage_hook()
{
	usage_oneline "shell" "setup a shell for developing"
}

PRE_BUILD_CMDS="shell"
pre_build_hook()
{
	warning "Doing this is dangerous and for developing only."
	# No error handling in develop shell.
	set +e; trap ERR

	case "${1:-shell}" in
		*) PS1="\u@\h:\w (rksdk)\$ " /bin/bash --norc ;;
	esac

	warning "Exit from $BASH_SOURCE ${@:-shell}."
}

source "${RK_BUILD_HELPER:-$(dirname "$(realpath "$0")")/../build-hooks/build-helper}"

pre_build_hook $@
