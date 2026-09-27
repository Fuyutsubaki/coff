# Test workflow: a question whose input is not valid UTF-8 must still be printed.
def workflow
  bytes = run_command(["printf", "\\377"]).out
  ask("bytes?", bytes)
end
