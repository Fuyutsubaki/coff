def workflow
  Dullmify.ask("確認してください", Dullmify.arguments)
  "時刻 #{Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)}"
end
