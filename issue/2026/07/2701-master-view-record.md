---
status: done
---
# issue の記録の正しさを master 視点で判定する規範を足す

## 要約

「issue は記録だからコミット済み分は追記で扱う」という誤適用を退けるため、coff-detail-issue の目的節に「記録の正しさは master に入った時点の内容で判定する。ブランチ上ではコミット済みの issue も書き換えてよい」を追記する。

## 背景・目的

feature ブランチ上でコミット済みの issue を更新する場面で、AI が「issue は記録なので、書き換えは正しくない。追記として扱う」と主張したことがある。
依頼者の判断は「後世の master から見たらどうでもいい歴史なので、master のコミットで見て正しい記録になっていれば、他はどうでもいい」だった。
この判断を規範として明文化し、追記主義の再発を防ぎたい。
なお、この論点はセッション振り返りの一覧を生成させた際に「採番の時系列」の問題に曲解されて記録されていた。本 issue は本来の意図で立て直したものである。

## 現状

- coff-detail-issue（`.coff/src/coff-detail-issue.skill.md`）は「done 後は設計判断の長期記憶として読む」「完了の文脈は git から辿る」と定めるが、記録の正しさをどの時点の内容で判定するかは無規定。
- coff-issue-polish は手順 9 で issue ファイルを上書きしており、実態として書き換え運用である。追記主義はこの実態とも食い違う。

## 変更方針

coff-detail-issue の目的節（「open の間は実装契約、done 後は長期記憶」の段落の直後）に一文を追記する。
中身は「記録の正しさは、master に入った時点の内容で判定する。ブランチ上では、コミット済みの issue も追記ではなく書き換えてよい」とする。
置き場所を状態（status）節にする案は、これは status の仕様ではなく記録というものの読み方の規定なので採らない。

## 実装詳細

- `.coff/src/coff-detail-issue.skill.md` の目的節、最初の段落の直後に一段落追加する。
- `/compile` で `.claude/skills/coff-detail-issue/SKILL.md` を再生成し、dist ミラー `skills/coff-detail-issue/SKILL.md` を同期する。

## 検証

- [x] ソースの目的節に master 視点の段落がある — 確認: `.coff/src/coff-detail-issue.skill.md` を読む
- [x] コンパイル成果物の footer md5 がソースの md5 と一致する — 確認: `md5sum` と footer の比較
- [x] dist ミラーが正本と一致する — 確認: `cmp`

## 人間が決めた判断

- 追記主義（コミット済み issue は書き換えず追記で扱う）を退ける判断は依頼者による。理由は「後世の master から見たらどうでもいい歴史なので、master のコミットで見て正しい記録になっていれば、他はどうでもいい」（2026-07-27）。

## リスク・未解決

なし。

## 参考・関連 issue

- `.coff/src/coff-detail-issue.skill.md` — 目的節と「完了の文脈は git から辿る」の定義元
- `issue/2026/07/2700-record-reasons-verbatim.md` — 同じ振り返り由来。本 issue の曲解は、そこで扱った「理由・主張のすり替え」の実例でもある
