def workflow(arguments)
  first = Dullmify.ask("最初の問い", "一")
  sleep 5
  second = Dullmify.ask("次の問い", first)
  "#{first}|#{second}"
end
