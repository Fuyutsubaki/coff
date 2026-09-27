# Test workflow with a slow command between two questions, to be killed midway.
def workflow
  a = ask("Q", "")
  run_command(["sleep", "2"])
  b = ask("R", a)
  "#{a}|#{b}"
end
