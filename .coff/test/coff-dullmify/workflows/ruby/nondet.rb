def workflow(arguments)
  prompt = "時刻 #{Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)}"
  Dullmify.ask(prompt, arguments)
end
