def workflow
  # 都道府県コードを作る 1. 住所を入力順に得る
  addresses = Dullmify.arguments.lines.map(&:strip).reject(&:empty?)
  prefectures = addresses.map do |address|
    # 都道府県コードを作る 2. 市区町村を尋ねる
    city = Dullmify.ask("住所から市区町村名だけを答えてください", address)
    # 都道府県コードを作る 3. 都道府県を尋ねる
    Dullmify.ask("市区町村が属する都道府県名を末尾まで含めて答えてください", city)
  end
  results = prefectures.map do |prefecture|
    # 都道府県コードを作る 4. 辞書でコードにする
    code = { "東京都" => "27", "大阪府" => "13" }[prefecture]
    Dullmify.fail("対応していない都道府県です: #{prefecture}") unless code
    # 都道府県コードを作る 5. printf でコードを得る
    command = Dullmify.run_command(["printf", "%s", code])
    Dullmify.fail("printf が失敗しました") unless command["exit_code"].zero?
    "#{prefecture}=#{command["stdout"]}"
  end
  # 都道府県コードを作る 6. 結果をファイルへ書く
  content = results.join(", ")
  Dullmify.write_file("prefecture-result.txt", content)
  # 都道府県コードを作る 7. report を返す
  "処理完了: #{content}"
end
