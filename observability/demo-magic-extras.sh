# Extra functions to make my life a little easier with demo-magic.

function p() {
  if [[ ${1:0:1} == "#" ]]; then
    cmd=$DEMO_COMMENT_COLOR$1$COLOR_RESET
  else
    cmd=$DEMO_CMD_COLOR$1$COLOR_RESET
  fi

  # render the prompt
  x=$(PS1="$DEMO_PROMPT" "$BASH" --norc -i </dev/null 2>&1 | sed -n '${s/^\(.*\)exit$/\1/p;}')

  # show command number is selected
  if $SHOW_CMD_NUMS; then
   printf "[$((++C_NUM))] $x"
  else
   printf "$x"
  fi

  # wait for the user to press a key before typing the command
  if [ $PROMPT_WAIT = true ]; then
    wait
  fi

  if [[ -z $TYPE_SPEED ]]; then
    echo -en "$cmd"
  else
    echo -en "$cmd" | pv -qL $[$TYPE_SPEED+(-2 + RANDOM%5)];
  fi

  # wait for the user to press a key before moving on
  if [ $NO_WAIT = false ]; then
    wait
  fi
  echo ""
}

# Print and execute immediately.
pei () {
	NO_WAIT=true pe "$@"
}

# Print immediately.
pi () {
  NO_WAIT=true DEMO_PROMPT= p "$@"
}

# Like echo but prettier.
show () {
  NO_WAIT=true DEMO_PROMPT= TYPE_SPEED= p "$@"
}

# Like echo, but assume it's a command.
cmd () {
  NO_WAIT=true DEMO_PROMPT='$ ' TYPE_SPEED= p "$@"
}
