def workflow
  Dullmify.arguments
  first = Dullmify.ask("停止前の問い", "一つ目")
  sleep 2
  second = Dullmify.ask("再開後の問い", first)
  "再開: #{second}"
end
