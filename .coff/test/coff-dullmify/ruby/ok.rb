# Test workflow: two questions, one command, one write, one read, one missing read.
def workflow
  a = ask("first question", args)
  r = run_command(["sh", "-c", "echo x >> counter; echo out; echo err >&2"])
  write_file("out/answer.txt", a)
  b = ask("second question", read_file("out/answer.txt").to_s)
  "report: #{a}|#{b}|#{r.status}|#{r.out.strip}|#{r.err.strip}|#{read_file('missing').nil?}"
end
