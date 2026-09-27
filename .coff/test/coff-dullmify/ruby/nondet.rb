# Test workflow that bypasses the runtime on purpose (File.exist?) so its
# control flow changes between runs. Never passes check.
def workflow
  mode = args
  ask("A", "")
  if File.exist?("toggle")
    return "early" if mode == "early"
    ask("C", "")
  else
    ask("B", "")
  end
  "done"
end
