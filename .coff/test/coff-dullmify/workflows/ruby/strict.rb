def workflow(arguments)
  Dullmify.ask("確認してください", arguments)
  "時刻 #{Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)}"
end
