# Test workflow: fail_run inside ensure while a question propagates must not
# turn the question into a failure.
def workflow
  begin
    ask("Q", "")
  ensure
    fail_run("cleanup saw an empty result") if read_file("must-exist").nil?
  end
  "done"
end
