def workflow
  # 都道府県と地域の確認 / 手順 1
  cities = Dullmify.arguments.split("、")
  Dullmify.fail("市名を二つ指定してください") unless cities.length == 2

  # 都道府県と地域の確認 / 手順 2
  prefectures = cities.map do |city|
    answer = nil
    4.times do |attempt|
      prompt = attempt.zero? ? "都道府県名だけを答えてください" : "前の答え「#{answer}」は末尾が都・道・府・県のいずれでもありません。都道府県名だけを、末尾まで含めて答え直してください"
      answer = Dullmify.ask(prompt, city)
      break if answer.match?(/[都道府県]\z/)
    end
    Dullmify.fail("都道府県名の形式が不正です") unless answer.match?(/[都道府県]\z/)
    answer
  end

  # 都道府県と地域の確認 / 手順 3
  region_by_prefecture = { "神奈川県" => "関東", "宮城県" => "東北" }
  regions = prefectures.map do |prefecture|
    region_by_prefecture[prefecture] || Dullmify.fail("地域の辞書にない都道府県です: #{prefecture}")
  end

  # 都道府県と地域の確認 / 手順 4
  report = cities.each_index.map { |index| "#{cities[index]}=#{prefectures[index]}(#{regions[index]})" }.join(", ")

  # 都道府県と地域の確認 / 手順 5
  command_result = Dullmify.command(["printf", "%s", report])
  Dullmify.fail("printf が失敗しました") unless command_result["exit_code"].zero?

  # 都道府県と地域の確認 / 手順 6
  Dullmify.write("prefecture-output.txt", command_result["stdout"])
  puts command_result["stdout"]
  command_result["stdout"]
end
