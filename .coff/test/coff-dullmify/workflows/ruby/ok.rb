def workflow
  args = Dullmify.arguments
  first = Dullmify.ask("最初の答えを一語で返してください", args)
  second = Dullmify.ask("二番目の答えを一語で返してください", first)
  result = Dullmify.command(["tee", "-a", "effect.log"], "一回\n")
  Dullmify.fail("追記コマンドが失敗しました") unless result["exit_code"].zero?
  "#{args}|#{first}|#{second}"
end
