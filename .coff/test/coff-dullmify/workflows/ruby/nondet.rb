def workflow
  Dullmify.arguments
  if File.exist?("nondet.flag")
    Dullmify.ask("変更後の問い", "A")
  else
    File.write("nondet.flag", "作成")
    Dullmify.ask("最初の問い", "B")
  end
  "到達しない"
end
