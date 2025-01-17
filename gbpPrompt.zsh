# This prompt has been modified from the Pure prompt
# by Sindre Sorhus
# https://github.com/sindresorhus/pure
# MIT License

# For my own and others sanity
# git:
# %b => current branch
# %a => current action (rebase/merge)
# prompt:
# %F => color dict
# %f => reset color
# %~ => current path
# %* => time
# %n => username
# %m => shortname host
# %(?..) => prompt conditional - %(condition.true.false)
# terminal codes:
# \e7   => save cursor position
# \e[2A => move cursor 2 lines up
# \e[1G => go to position 1 in terminal
# \e8   => restore cursor position
# \e[K  => clears everything after the cursor on the current line
# \e[2K => clear everything on the current line

# Turns seconds into human readable time.
# 165392 => 1d 21h 56m 32s
# https://github.com/sindresorhus/pretty-time-zsh
prompt_human_time_to_var() {
	local human total_seconds=$1 var=$2
	local days=$(( total_seconds / 60 / 60 / 24 ))
	local hours=$(( total_seconds / 60 / 60 % 24 ))
	local minutes=$(( total_seconds / 60 % 60 ))
	local seconds=$(( total_seconds % 60 ))
	(( days > 0 )) && human+="${days}d "
	(( hours > 0 )) && human+="${hours}h "
	(( minutes > 0 )) && human+="${minutes}m "
	human+="${seconds}s"

	# Store human readable time in a variable as specified by the caller
	typeset -g "${var}"="${human}"
}

# Stores (into prompt_cmd_exec_time) the execution
# time of the last command if set threshold was exceeded.
prompt_check_cmd_exec_time() {
	integer elapsed
	(( elapsed = EPOCHSECONDS - ${prompt_cmd_timestamp:-$EPOCHSECONDS} ))
	typeset -g prompt_cmd_exec_time=
	(( elapsed > ${GBPPROMPT_CMD_MAX_EXEC_TIME:-5} )) && {
		prompt_human_time_to_var $elapsed "prompt_cmd_exec_time"
	}
}

prompt_set_title() {
	setopt localoptions noshwordsplit

	# Emacs terminal does not support settings the title.
	(( ${+EMACS} )) && return

	case $TTY in
		# Don't set title over serial console.
		/dev/ttyS[0-9]*) return;;
	esac

	# Show hostname if connected via SSH.
	local hostname=
	if [[ -n $prompt_state[username] ]]; then
		# Expand in-place in case ignore-escape is used.
		hostname="${(%):-(%m) }"
	fi

	local -a opts
	case $1 in
		expand-prompt) opts=(-P);;
		ignore-escape) opts=(-r);;
	esac

	# Set title atomically in one print statement so that it works when XTRACE is enabled.
	print -n $opts $'\e]0;'${hostname}${2}$'\a'
}

prompt_preexec() {
	if [[ -n $prompt_git_fetch_pattern ]]; then
		# Detect when Git is performing pull/fetch, including Git aliases.
		local -H MATCH MBEGIN MEND match mbegin mend
		if [[ $2 =~ (git|hub)\ (.*\ )?($prompt_git_fetch_pattern)(\ .*)?$ ]]; then
			# We must flush the async jobs to cancel our git fetch in order
			# to avoid conflicts with the user issued pull / fetch.
			async_flush_jobs 'prompt'
		fi
	fi

	typeset -g prompt_cmd_timestamp=$EPOCHSECONDS

	# Shows the current directory and executed command in the title while a process is active.
	prompt_set_title 'ignore-escape' "$PWD:t: $2"

	# Disallow Python virtualenv from updating the prompt. Set it to 12 if
	# untouched by the user to indicate that this prompt modified it. Here we use
	# the magic number 12, same as in `psvar`.
	export VIRTUAL_ENV_DISABLE_PROMPT=${VIRTUAL_ENV_DISABLE_PROMPT:-12}
}

# Change the colors if their value are different from the current ones.
prompt_set_colors() {
	local color_temp key value

	for key value in ${(kv)prompt_colors}; do
		zstyle -t ":gbpPrompt:$key" color "$value"
		case $? in
			1) # The current style is different from the one from zstyle.
				zstyle -s ":gbpPrompt:$key" color color_temp
				prompt_colors[$key]=$color_temp ;;
			2) # No style is defined.
				prompt_colors[$key]=$prompt_colors_default[$key] ;;
		esac
	done
}

prompt_preprompt_render() {
	setopt localoptions noshwordsplit

	# Set color for Git branch/dirty status and change color if dirty checking has been delayed.
	if [[ -n ${prompt_git_last_dirty_check_timestamp+x} ]]; then
		git_color=$prompt_colors[git:branch:cached]
	else
		git_color=$prompt_colors[git:branch]
	fi

	# Initialize the preprompt array.
	local -a preprompt_parts

	# Set the path.
	preprompt_parts=('%F{$prompt_colors[path]}%~%f')

	# Username and machine, if applicable.
	[[ -n $prompt_state[username] ]] && preprompt_parts+=($prompt_state[username])

	# Git status
	typeset -gA prompt_vcs_info
	if [[ -n $prompt_vcs_info[branch] ]]; then
		local git_text
		# Branch
		git_text="%F{$git_color}"$'\uE725${prompt_vcs_info[branch]}%f'

		# Branch and dirty status
		git_text=$git_text"%F{$prompt_colors[git:status]}"$'${prompt_git_dirty}%f'

		# Pull/push arrows.
		if [[ -n $prompt_git_arrows ]]; then
			git_text=$git_text'%F{$prompt_colors[git:status]}${prompt_git_arrows}%f'
		fi
		preprompt_parts+=( $git_text )
	fi

	# Pyenv environment
	[[ -n $prompt_pyenv_env ]] && preprompt_parts+=($prompt_pyenv_env)

	# Anaconda environment
	if [[ ! -z $CONDA_DEFAULT_ENV ]]; then
		conda_env="${CONDA_DEFAULT_ENV//[$'\t\r\n']}"
		preprompt_parts+=("%F{$prompt_colors[conda]}"$'\uE73C${conda_env}%f')
	fi

	# Execution time.
	[[ -n $prompt_cmd_exec_time ]] && preprompt_parts+=('%F{$prompt_colors[execution_time]}${prompt_cmd_exec_time}%f')

	local cleaned_ps1=$PROMPT
	local -H MATCH MBEGIN MEND
	if [[ $PROMPT = *$prompt_newline* ]]; then
		# Remove everything from the prompt until the newline. This
		# removes the preprompt and only the original PROMPT remains.
		cleaned_ps1=${PROMPT##*${prompt_newline}}
	fi
	unset MATCH MBEGIN MEND

	# Construct the new prompt with a clean preprompt.
	local -ah ps1
	ps1=(
		${(j. .)preprompt_parts}  # Join parts, space separated.
		$prompt_newline           # Separate preprompt and prompt.
		$cleaned_ps1
	)

	PROMPT="${(j..)ps1}"

	# Expand the prompt for future comparision.
	local expanded_prompt
	expanded_prompt="${(S%%)PROMPT}"

	if [[ $1 == precmd ]]; then
		# Initial newline, for spaciousness.
		print
	elif [[ $prompt_last_prompt != $expanded_prompt ]]; then
		# Redraw the prompt.
		prompt_reset_prompt
	fi

	typeset -g prompt_last_prompt=$expanded_prompt
}

prompt_precmd() {
	# Check execution time and store it in a variable.
	prompt_check_cmd_exec_time
	unset prompt_cmd_timestamp

	# Launch async tasks
	prompt_async_tasks

	# Shows the full path in the title.
	prompt_set_title 'expand-prompt' '%~'

	# Modify the colors if some have changed..
	prompt_set_colors

	# Check if we should display the virtual env. We use a sufficiently high
	# index of psvar (12) here to avoid collisions with user defined entries.
	psvar[12]=
	# Check if a Conda environment is active and display its name.
	if [[ -n $CONDA_DEFAULT_ENV ]]; then
		psvar[12]="${CONDA_DEFAULT_ENV//[$'\t\r\n']}"
	fi
	# When VIRTUAL_ENV_DISABLE_PROMPT is empty, it was unset by the user and
	# this prompt should take back control.
	if [[ -n $VIRTUAL_ENV ]] && [[ -z $VIRTUAL_ENV_DISABLE_PROMPT || $VIRTUAL_ENV_DISABLE_PROMPT = 12 ]]; then
		psvar[12]="${VIRTUAL_ENV:t}"
		export VIRTUAL_ENV_DISABLE_PROMPT=12
	fi

	# Make sure VIM prompt is reset.
	prompt_reset_prompt_symbol

	# Print the preprompt.
	prompt_preprompt_render "precmd"
}

prompt_async_git_aliases() {
	setopt localoptions noshwordsplit
	local -a gitalias pullalias

	# List all aliases and split on newline.
	gitalias=(${(@f)"$(command git config --get-regexp "^alias\.")"})
	for line in $gitalias; do
		parts=(${(@)=line})           # Split line on spaces.
		aliasname=${parts[1]#alias.}  # Grab the name (alias.[name]).
		shift parts                   # Remove `aliasname`

		# Check alias for pull or fetch. Must be exact match.
		if [[ $parts =~ ^(.*\ )?(pull|fetch)(\ .*)?$ ]]; then
			pullalias+=($aliasname)
		fi
	done

	print -- ${(j:|:)pullalias}  # Join on pipe, for use in regex.
}

prompt_async_vcs_info() {
	setopt localoptions noshwordsplit

	# Configure `vcs_info` inside an async task. This frees up `vcs_info`
	# to be used or configured as the user pleases.
	zstyle ':vcs_info:*' enable git
	zstyle ':vcs_info:*' use-simple true
	# Only export two message variables from `vcs_info`.
	zstyle ':vcs_info:*' max-exports 2
	# Export branch (%b) and Git toplevel (%R).
	zstyle ':vcs_info:git*' formats '%b' '%R'
	zstyle ':vcs_info:git*' actionformats '%b|%a' '%R'

	vcs_info

	local -A info
	info[pwd]=$PWD
	info[top]=$vcs_info_msg_1_
	info[branch]=$vcs_info_msg_0_

	print -r - ${(@kvq)info}
}

# Fastest possible way to check if a Git repo is dirty.
prompt_async_git_dirty() {
	setopt localoptions noshwordsplit
	local untracked_dirty=$1

	if [[ $untracked_dirty = 0 ]]; then
		command git diff --no-ext-diff --quiet --exit-code
	else
		# `test -z` returns true if the length of a string is zero
		test -z "$(command git status --porcelain --ignore-submodules -unormal)"
	fi

	return $?
}

prompt_async_pyenv() {
	setopt localoptions noshwordsplit
	local pyenv_colour=$prompt_colors[pyenv]
	local pyenv_version_name=$(pyenv version-name)
	local pyenv_version_origin=$(pyenv version-origin)
	if [[ $pyenv_version_origin == ${GBP_HOME}/.pyenv/version ]]; then
		pyenv_colour=$prompt_colors[pyenv_global]
	fi
	print -r "%F{$pyenv_colour}"$'\uE73C'"${pyenv_version_name}%f"
}

prompt_async_git_fetch() {
	setopt localoptions noshwordsplit

	# Sets `GIT_TERMINAL_PROMPT=0` to disable authentication prompt for Git fetch (Git 2.3+).
	export GIT_TERMINAL_PROMPT=0
	# Set SSH `BachMode` to disable all interactive SSH password prompting.
	export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-"ssh"} -o BatchMode=yes"

	# Default return code, which indicates Git fetch failure.
	local fail_code=99

	# Guard against all forms of password prompts. By setting the shell into
	# MONITOR mode we can notice when a child process prompts for user input
	# because it will be suspended. Since we are inside an async worker, we
	# have no way of transmitting the password and the only option is to
	# kill it. If we don't do it this way, the process will corrupt with the
	# async worker.
	setopt localtraps monitor

	# Make sure local HUP trap is unset to allow for signal propagation when
	# the async worker is flushed.
	trap - HUP

	trap '
		# Unset trap to prevent infinite loop
		trap - CHLD
		if [[ $jobstates = suspended* ]]; then
			# Set fail code to password prompt and kill the fetch.
			fail_code=98
			kill %%
		fi
	' CHLD

	command git -c gc.auto=0 fetch >/dev/null &
	wait $! || return $fail_code

	unsetopt monitor

	# Check arrow status after a successful `git fetch`.
	prompt_async_git_arrows
}

prompt_async_git_arrows() {
	setopt localoptions noshwordsplit
	command git rev-list --left-right --count HEAD...@'{u}'
}

prompt_async_tasks() {
	setopt localoptions noshwordsplit

	# Initialize the async worker
	# This gets done once at the beginning or again if we notice
	# that the worker has been killed
	((!${prompt_async_init_git:-0})) && {
		async_start_worker "prompt_worker_git" -u -n
		async_register_callback "prompt_worker_git" prompt_async_callback_git
		typeset -g prompt_async_init_git=1
	}
	# Update the current working directory of the async worker.
	async_worker_eval "prompt_worker_git" builtin cd -q $PWD

	# initialize everything needed for the pyenv environment name
	# Clear the environemnt name to start
	unset prompt_pyenv_env
	if type pyenv > /dev/null 2>&1; then
		# Initialize the async worker
		# This gets done once at the beginning or again if we notice
		# that the worker has been killed
		((!${prompt_async_init_pyenv:-0})) && {
			async_start_worker "prompt_worker_pyenv" -u -n
			async_register_callback "prompt_worker_pyenv" prompt_async_callback_pyenv
			typeset -g prompt_async_init_pyenv=1
		}

		# Update the current working directory of the async worker.
		async_worker_eval "prompt_worker_pyenv" builtin cd -q $PWD

		# Keep these values up-to-date for the worker, since they're used by `pyenv version-name`
		# First: clear them from the worker (note: this is needed because values can be deleted as
		# well as changed)
		async_worker_eval "prompt_worker_pyenv" "while read -r varname; do unset \$varname; done < <(env | cut -f1 -d= | grep PYENV)"

		# Second: update them
		while read -r varname; do async_worker_eval "prompt_worker_pyenv" $(export -p $varname); done < <(env | cut -f1 -d= | grep PYENV)

		# Fetch the pyenv environment
		async_job "prompt_worker_pyenv" prompt_async_pyenv

	fi

	typeset -gA prompt_vcs_info

	local -H MATCH MBEGIN MEND
	if [[ $PWD != ${prompt_vcs_info[pwd]}* ]]; then
		# Stop any running async jobs.
		async_flush_jobs "prompt_worker_git"

		# Reset Git preprompt variables, switching working tree.
		unset prompt_git_dirty
		unset prompt_git_last_dirty_check_timestamp
		unset prompt_git_arrows
		unset prompt_git_fetch_pattern
		prompt_vcs_info[branch]=
		prompt_vcs_info[top]=
	fi
	unset MATCH MBEGIN MEND

	async_job "prompt_worker_git" prompt_async_vcs_info

	# Only perform tasks inside a Git working tree.
	[[ -n $prompt_vcs_info[top] ]] || return

	prompt_async_refresh
}

prompt_async_refresh() {
	setopt localoptions noshwordsplit

	if [[ -z $prompt_git_fetch_pattern ]]; then
		# We set the pattern here to avoid redoing the pattern check until the
		# working three has changed. Pull and fetch are always valid patterns.
		typeset -g prompt_git_fetch_pattern="pull|fetch"
		async_job "prompt_worker_git" prompt_async_git_aliases
	fi

	async_job "prompt_worker_git" prompt_async_git_arrows

	# Do not preform `git fetch` if it is disabled or in home folder.
	if (( ${GBPPROMPT_GIT_PULL:-1} )) && [[ $prompt_vcs_info[top] != $HOME ]]; then
		# Tell the async worker to do a `git fetch`.
		async_job "prompt_worker_git" prompt_async_git_fetch
	fi

	# If dirty checking is sufficiently fast,
	# tell the worker to check it again, or wait for timeout.
	integer time_since_last_dirty_check=$(( EPOCHSECONDS - ${prompt_git_last_dirty_check_timestamp:-0} ))
	if (( time_since_last_dirty_check > ${GBPPROMPT_GIT_DELAY_DIRTY_CHECK:-1800} )); then
		unset prompt_git_last_dirty_check_timestamp
		# Check if there is anything to pull.
		async_job "prompt_worker_git" prompt_async_git_dirty ${GBPPROMPT_GIT_UNTRACKED_DIRTY:-1}
	fi
}

prompt_check_git_arrows() {
	setopt localoptions noshwordsplit
	local arrows left=${1:-0} right=${2:-0}

	(( right > 0 )) && arrows+=${GBPPROMPT_GIT_DOWN_ARROW:-$'\uFC2C'}
	# (( right > 0 )) && arrows+=${GBPPROMPT_GIT_DOWN_ARROW:-⇣}
	(( left > 0 )) && arrows+=${GBPPROMPT_GIT_UP_ARROW:-$'\uFC35'}
	# (( left > 0 )) && arrows+=${GBPPROMPT_GIT_UP_ARROW:-⇡}

	[[ -n $arrows ]] || return
	typeset -g REPLY=$arrows
}

prompt_async_callback_pyenv() {
	setopt localoptions noshwordsplit
	local job=$1 code=$2 output=$3 exec_time=$4 next_pending=$6
	local do_render=0

	case $job in
		\[async])
			# Code is 1 for corrupted worker output and 2 for dead worker.
			if [[ $code -eq 2 ]]; then
				# Our worker died unexpectedly.
				typeset -g prompt_async_init_pyenv=0
			fi
			;;
		prompt_async_pyenv)
			typeset -g prompt_pyenv_env=$output
			do_render=1
			;;
	esac

	if (( next_pending )); then
		(( do_render )) && typeset -g prompt_async_render_requested=1
		return
	fi

	[[ ${prompt_async_render_requested:-$do_render} = 1 ]] && prompt_preprompt_render
	unset prompt_async_render_requested
}

prompt_async_callback_git() {
	setopt localoptions noshwordsplit
	local job=$1 code=$2 output=$3 exec_time=$4 next_pending=$6
	local do_render=0

	case $job in
		\[async])
			# Code is 1 for corrupted worker output and 2 for dead worker.
			if [[ $code -eq 2 ]]; then
				# Our worker died unexpectedly.
				typeset -g prompt_async_init_git=0
			fi
			;;
		prompt_async_vcs_info)
			local -A info
			typeset -gA prompt_vcs_info

			# Parse output (z) and unquote as array (Q@).
			info=("${(Q@)${(z)output}}")
			local -H MATCH MBEGIN MEND
			if [[ $info[pwd] != $PWD ]]; then
				# The path has changed since the check started, abort.
				return
			fi

			# Check if Git top-level has changed.
			if [[ $info[top] = $prompt_vcs_info[top] ]]; then
				# If the stored pwd is part of $PWD, $PWD is shorter and likelier
				# to be top-level, so we update pwd.
				if [[ $prompt_vcs_info[pwd] = ${PWD}* ]]; then
					prompt_vcs_info[pwd]=$PWD
				fi
			else
				# Store $PWD to detect if we (maybe) left the Git path.
				prompt_vcs_info[pwd]=$PWD
			fi
			unset MATCH MBEGIN MEND

			# The update has a Git top-level set, which means we just entered a new
			# Git directory. Run the async refresh tasks.
			[[ -n $info[top] ]] && [[ -z $prompt_vcs_info[top] ]] && prompt_async_refresh

			# Always update branch and top-level.
			prompt_vcs_info[branch]=$info[branch]
			prompt_vcs_info[top]=$info[top]

			do_render=1
			;;
		prompt_async_git_aliases)
			if [[ -n $output ]]; then
				# Append custom Git aliases to the predefined ones.
				prompt_git_fetch_pattern+="|$output"
			fi
			;;
		prompt_async_git_dirty)
			local prev_dirty=$prompt_git_dirty
			if (( code == 0 )); then
				unset prompt_git_dirty
			else
				typeset -g prompt_git_dirty="*"
			fi

			[[ $prev_dirty != $prompt_git_dirty ]] && do_render=1

			# When `prompt_git_last_dirty_check_timestamp` is set, the Git info is displayed
			# in a different color. To distinguish between a "fresh" and a "cached" result, the
			# preprompt is rendered before setting this variable. Thus, only upon the next
			# rendering of the preprompt will the result appear in a different color.
			(( $exec_time > 5 )) && prompt_git_last_dirty_check_timestamp=$EPOCHSECONDS
			;;
		prompt_async_git_fetch|prompt_async_git_arrows)
			# `prompt_async_git_fetch` executes `prompt_async_git_arrows`
			# after a successful fetch.
			case $code in
				0)
					local REPLY
					prompt_check_git_arrows ${(ps:\t:)output}
					if [[ $prompt_git_arrows != $REPLY ]]; then
						typeset -g prompt_git_arrows=$REPLY
						do_render=1
					fi
					;;
				99|98)
					# Git fetch failed.
					;;
				*)
					# Non-zero exit status from `prompt_async_git_arrows`,
					# indicating that there is no upstream configured.
					if [[ -n $prompt_git_arrows ]]; then
						unset prompt_git_arrows
						do_render=1
					fi
					;;
			esac
			;;
	esac

	if (( next_pending )); then
		(( do_render )) && typeset -g prompt_async_render_requested=1
		return
	fi

	[[ ${prompt_async_render_requested:-$do_render} = 1 ]] && prompt_preprompt_render
	unset prompt_async_render_requested
}

prompt_reset_prompt() {
	if [[ $CONTEXT == cont ]]; then
		# When the context is "cont", PS2 is active and calling
		# reset-prompt will have no effect on PS1, but it will
		# reset the execution context (%_) of PS2 which we don't
		# want. Unfortunately, we can't save the output of "%_"
		# either because it is only ever rendered as part of the
		# prompt, expanding in-place won't work.
		return
	fi

	zle && zle .reset-prompt
}

prompt_reset_prompt_symbol() {
	prompt_state[preprompt]="${GBPPROMPT_PROMPT_PRESYMBOL}"
	prompt_state[prompt]=${GBPPROMPT_PROMPT_SYMBOL:-❯}
}

prompt_update_vim_prompt_widget() {
	setopt localoptions noshwordsplit
	prompt_state[preprompt]="${GBPPROMPT_PROMPT_PRESYMBOL}"
	prompt_state[prompt]=${${KEYMAP/vicmd/${GBPPROMPT_PROMPT_VICMD_SYMBOL:-❮}}/(main|viins)/${GBPPROMPT_PROMPT_SYMBOL:-❯}}

	prompt_reset_prompt
}

prompt_reset_vim_prompt_widget() {
	setopt localoptions noshwordsplit
	prompt_reset_prompt_symbol

	# We can't perform a prompt reset at this point because it
	# removes the prompt marks inserted by macOS Terminal.
}

prompt_state_setup() {
	setopt localoptions noshwordsplit

	# Check SSH_CONNECTION and the current state.
	local ssh_connection=${SSH_CONNECTION:-$PROMPT_GBPPROMPT_SSH_CONNECTION}
	local username hostname
	if [[ -z $ssh_connection ]] && (( $+commands[who] )); then
		# When changing user on a remote system, the $SSH_CONNECTION
		# environment variable can be lost. Attempt detection via `who`.
		local who_out
		who_out=$(who -m 2>/dev/null)
		if (( $? )); then
			# Who am I not supported, fallback to plain who.
			local -a who_in
			who_in=( ${(f)"$(who 2>/dev/null)"} )
			who_out="${(M)who_in:#*[[:space:]]${TTY#/dev/}[[:space:]]*}"
		fi

		local reIPv6='(([0-9a-fA-F]+:)|:){2,}[0-9a-fA-F]+'  # Simplified, only checks partial pattern.
		local reIPv4='([0-9]{1,3}\.){3}[0-9]+'   # Simplified, allows invalid ranges.
		# Here we assume two non-consecutive periods represents a
		# hostname. This matches `foo.bar.baz`, but not `foo.bar`.
		local reHostname='([.][^. ]+){2}'

		# Usually the remote address is surrounded by parenthesis, but
		# not on all systems (e.g. busybox).
		local -H MATCH MBEGIN MEND
		if [[ $who_out =~ "\(?($reIPv4|$reIPv6|$reHostname)\)?\$" ]]; then
			ssh_connection=$MATCH

			# Export variable to allow detection propagation inside
			# shells spawned by this one (e.g. tmux does not always
			# inherit the same tty, which breaks detection).
			export PROMPT_GBPPROMPT_SSH_CONNECTION=$ssh_connection
		fi
		unset MATCH MBEGIN MEND
	fi

	hostname='%F{$prompt_colors[host]}@%m%f'

	# Show `username@host` if logged in through SSH.
	[[ -n $ssh_connection ]] && username='%F{$prompt_colors[user]}%n%f'"$hostname"

	# Show `username@host` if root, with username in default color.
	[[ $UID -eq 0 ]] && username='%F{$prompt_colors[user:root]}%n%f'"$hostname"

	typeset -gA prompt_state
	prompt_state[version]="1.10.3"
	prompt_state+=(
		username "$username"
		preprompt "${GBPPROMPT_PROMPT_PRESYMBOL}"
		prompt "${GBPPROMPT_PROMPT_SYMBOL:-❯}"
	)
}

prompt_system_report() {
	setopt localoptions noshwordsplit

	print - "- Zsh: $(zsh --version)"
	print -n - "- Operating system: "
	case "$(uname -s)" in
		Darwin)	print "$(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion))";;
		*)	print "$(uname -s) ($(uname -v))";;
	esac
	print - "- Terminal program: $TERM_PROGRAM ($TERM_PROGRAM_VERSION)"

	local git_version
	git_version=($(git --version))  # Remove newlines, if hub is present.
	print - "- Git: $git_version"

	print - "- gbpPrompt state:"
	for k v in "${(@kv)prompt_state}"; do
		print - "\t- $k: \`${(q)v}\`"
	done
	print - "- Virtualenv: \`$(typeset -p VIRTUAL_ENV_DISABLE_PROMPT)\`"
	print - "- Prompt: \`$(typeset -p PROMPT)\`"

	local ohmyzsh=0
	typeset -la frameworks
	(( $+ANTIBODY_HOME )) && frameworks+=("Antibody")
	(( $+ADOTDIR )) && frameworks+=("Antigen")
	(( $+ANTIGEN_HS_HOME )) && frameworks+=("Antigen-hs")
	(( $+functions[upgrade_oh_my_zsh] )) && {
		ohmyzsh=1
		frameworks+=("Oh My Zsh")
	}
	(( $+ZPREZTODIR )) && frameworks+=("Prezto")
	(( $+ZPLUG_ROOT )) && frameworks+=("Zplug")
	(( $+ZPLGM )) && frameworks+=("Zplugin")

	(( $#frameworks == 0 )) && frameworks+=("None")
	print - "- Detected frameworks: ${(j:, :)frameworks}"

	if (( ohmyzsh )); then
		print - "\t- Oh My Zsh:"
		print - "\t\t- Plugins: ${(j:, :)plugins}"
	fi
}

prompt_gbpPrompt_setup() {
	# Prevent percentage showing up if output doesn't end with a newline.
	export PROMPT_EOL_MARK=''

	prompt_opts=(subst percent)

	# Borrowed from `promptinit`. Sets the prompt options in case this prompt was not
	# initialized via `promptinit`.
	setopt noprompt{bang,cr,percent,subst} "prompt${^prompt_opts[@]}"

	if [[ -z $prompt_newline ]]; then
		# This variable needs to be set, usually set by promptinit.
		typeset -g prompt_newline=$'\n%{\r%}'
	fi

	zmodload zsh/datetime
	zmodload zsh/zle
	zmodload zsh/parameter
	zmodload zsh/zutil

	autoload -Uz add-zsh-hook
	autoload -Uz vcs_info
	autoload -Uz async && async

	# The `add-zle-hook-widget` function is not guaranteed to be available.
	# It was added in Zsh 5.3.
	autoload -Uz +X add-zle-hook-widget 2>/dev/null

	# Set the colors.
	# These defaults can all be overridden by the user's config.
	# Run 'print_colours' in the shell to get a list of available colours,
	# in addition to the named colours that zsh supports.
	typeset -gA prompt_colors_default prompt_colors
	prompt_colors_default=(
		prompt:error         red
		prompt:success       green
		execution_time       red
		git:status           226
		git:branch           208
		git:branch:cached    172
		user                 81
		user:root            198
		host                 75
		conda                35
		pyenv                47
		pyenv_global         red
		prompt:preprompt     218
		path                 218
       )

	prompt_colors=("${(@kv)prompt_colors_default}")

	add-zsh-hook precmd prompt_precmd
	add-zsh-hook preexec prompt_preexec

	prompt_state_setup

	zle -N prompt_reset_prompt
	zle -N prompt_update_vim_prompt_widget
	zle -N prompt_reset_vim_prompt_widget
	if (( $+functions[add-zle-hook-widget] )); then
		add-zle-hook-widget zle-line-finish prompt_reset_vim_prompt_widget
		add-zle-hook-widget zle-keymap-select prompt_update_vim_prompt_widget
	fi

	PROMPT=""

	# Prompt turns red if the previous command didn't exit with 0.
	PROMPT+='%F{$prompt_colors[prompt:preprompt]}${prompt_state[preprompt]}%f'
	PROMPT+='%(?.%F{$prompt_colors[prompt:success]}.%F{$prompt_colors[prompt:error]})${prompt_state[prompt]}%f '

	# Indicate continuation prompt by ... and use a darker color for it.
	PROMPT2='%F{242}... %(1_.%_ .%_)%f%(?.%F{magenta}.%F{red})${prompt_state[prompt]}%f '

	# Store prompt expansion symbols for in-place expansion via (%). For
	# some reason it does not work without storing them in a variable first.
	typeset -ga prompt_debug_depth
	prompt_debug_depth=('%e' '%N' '%x')

	# Compare is used to check if %N equals %x. When they differ, the main
	# prompt is used to allow displaying both filename and function. When
	# they match, we use the secondary prompt to avoid displaying duplicate
	# information.
	local -A ps4_parts
	ps4_parts=(
		depth 	  '%F{yellow}${(l:${(%)prompt_debug_depth[1]}::+:)}%f'
		compare   '${${(%)prompt_debug_depth[2]}:#${(%)prompt_debug_depth[3]}}'
		main      '%F{blue}${${(%)prompt_debug_depth[3]}:t}%f%F{242}:%I%f %F{242}@%f%F{blue}%N%f%F{242}:%i%f'
		secondary '%F{blue}%N%f%F{242}:%i'
		prompt 	  '%F{242}>%f '
	)
	# Combine the parts with conditional logic. First the `:+` operator is
	# used to replace `compare` either with `main` or an ampty string. Then
	# the `:-` operator is used so that if `compare` becomes an empty
	# string, it is replaced with `secondary`.
	local ps4_symbols='${${'${ps4_parts[compare]}':+"'${ps4_parts[main]}'"}:-"'${ps4_parts[secondary]}'"}'

	# Improve the debug prompt (PS4), show depth by repeating the +-sign and
	# add colors to highlight essential parts like file and function name.
	PROMPT4="${ps4_parts[depth]} ${ps4_symbols}${ps4_parts[prompt]}"

	# Guard against Oh My Zsh themes overriding this prompt
	unset ZSH_THEME
}

prompt_gbpPrompt_setup "$@"
