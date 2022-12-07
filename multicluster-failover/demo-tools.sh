# The #@hook stuff below allows for hooks to control what's being
# displayed when livecasting the demo -- for example, consider the
# "show_terminal" hook:
#    - if DEMO_HOOK_TERMINAL is set, then "show_terminal" will execute
#      $DEMO_HOOK_TERMINAL as a command.
#    - If DEMO_HOOK_TERMINAL is not set, then "show_terminal" is a
#      no-op.

#@hook show_terminal TERMINAL
#@hook show_browser BROWSER
#@hook show_video VIDEO
#@hook show_slides SLIDES

# browser_then_terminal, if we're livecasting, will wait, then switch the
# view for the livestream to the browser, then wait again, then clear the
# terminal before switching the view back to the terminal. There are a lot
# of places in the demo where we want to present stuff in the terminal, then
# flip to the browser to show something, then flip back to the terminal.
#
# If you're _not_ livecasting, so the hooks aren't doing anything... uh...
# you'll be stuck hitting RETURN twice to clear the screen and get to the
# next step. Working on that...

#@macro browser_then_terminal
  #@wait
  #@show_browser
  #@wait
  #@clear
  #@show_terminal
#@end

# wait_clear is a macro that just waits before clearing the terminal. We
# do this a lot.

#@macro wait_clear
  #@wait
  #@clear
#@end

# start_livecast is a macro for starting a livecast. It assumes that the demo
# hooks are working, and uses them to display slides at first while putting a
# cue to hit RETURN on the terminal. Once the user hits RETURN, it clears the
# terminal before showing it, so that the stuff after the macro call is front
# and center.

#@macro start_livecast
  #@show_slides

  clear
  echo Waiting...

  #@wait_clear
  #@show_terminal
#@end
