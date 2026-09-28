def workflow
  # 基本動作 1. 引数を読む
  argument = Dullmify.arguments

  # 基本動作 2. 最初の判断を尋ねる
  first = Dullmify.ask("最初の値を答えてください", argument)

  # 基本動作 3. コマンドを一度だけ実行する
  command = Dullmify.run_command(["sh", "-c", "printf '実行済み\\n' >> side-effect.log"])
  Dullmify.fail("コマンドが失敗しました") unless command["exit_code"].zero?

  # 基本動作 4. 未作成のファイルを読み、結果を書く
  previous = Dullmify.read_file("not-created.txt")
  Dullmify.write_file("result.txt", "#{first}|#{previous.inspect}")

  # 基本動作 5. 二つ目の判断を尋ねる
  second = Dullmify.ask("二つ目の値を答えてください", first)

  # 基本動作 6. report を返す
  "完了: #{first}/#{second}"
end
