package Coff::Workflow;

# =====================================================================
# README: dullmify の runtime と、生成物のレビューの仕方
# =====================================================================
#
# 何か
#   coff-dullmify が生成した skill の実行基盤。skill の制御は Perl の
#   `sub workflow` が持ち、LLM は `llm(topic, input)` で問われた判断に
#   答えるだけになる。LLM との往復はプロセスをまたぐので、workflow を
#   毎回先頭から再生し、記録済みの effect は保存した値を返す（replay 方式）。
#
# 1 回の run の流れ
#   start [args]    run を作り、workflow を先頭から走らせる
#   llm(...)        journal に答えがなければ Suspend 例外で workflow から脱出し、
#                   {"run","index","ask":{"topic","input"}} を stdout に出して止まる
#   resume run idx  stdin の答えを journal に書き、また先頭から再生する。
#                   記録済みの step は再実行せず保存した結果を返し、答え済みの llm は
#                   答えを返すので、前回止まった場所まで一瞬で進む
#   終端            {"run","done":true,"report":...} または {"failed":"<理由>"} を出し、
#                   run のディレクトリを消す
#
# 仕掛け（読むときに引っかかる所）
#   - 例外を継続の代用にする。`llm` は `die bless(..., 'Coff::Workflow::Suspend')` で
#     workflow 全体から抜ける。だから生成コードは effect を `eval {}` で囲んではいけない
#   - effect の同一性は実行順だけ。journal の effects[i] と i 番目の呼び出しを突き合わせ、
#     種類（llm / step）と問いの JSON が違えば非決定として failed にする。
#     replay が記録より手前で終わっても failed。時計、乱数、hash の順序依存が禁止なのはこのため
#   - journal に入れる値と workflow に返す値は `_snapshot`（JSON の往復）で切り離す。
#     同じ参照を共有すると workflow 側の書き換えが記録に混ざり、次の replay が非決定になる
#   - 文脈は `local $CURRENT` の動的スコープで渡す。深い補助関数からも引数なしで届く
#   - `step (&)` の prototype でブロック構文にしている。step の中身が変わっても検出しない
#     （ソースが変われば workflow.pl ごと再生成される前提）
#   - 境界で decode する。start の引数と resume の答えは UTF-8 の文字列に戻して journal と
#     workflow に渡す。生成コードはパスを `Encode::encode_utf8` してからファイル操作に渡す
#   - 呼び出しの誤り（run / index 違い、UTF-8 でない入力）は JSON を出さず stderr へ返し、
#     run を残す。run を消すのは workflow 自身の done と failed だけ
#   - run の置き場は ${XDG_STATE_HOME:-$HOME/.local/state}/coff/<skill名>/<run>/journal.json。
#     途中の状態を見たいときはここを読む
#
# 生成物のレビューの仕方
#   1. scripts/workflow.pl は「雛形の頭 + LLM の本文 + 雛形の尻 + フッタ」。頭と尻は
#      templates/workflow-head.pl と workflow-tail.pl にバイト一致するはずなので、
#      LLM が書いたのは `sub workflow` と補助関数だけ。そこだけ読む
#   2. 本文で見る点: 副作用（ファイル、コマンド）が全部 `step { }` の中にあるか。
#      `llm` / `step` を `eval` で囲んでいないか。時計、乱数、sort なしの keys がないか。
#      `use` を書かず補助関数内で `require` しているか。失敗が `die` か。
#      パスを `Encode::encode_utf8` してから open / -f / rename に渡しているか。
#      補助関数ごとに日本語のコメントがあるか。答えの検査が `llm` の直後にあるか
#   3. SKILL.md で見る点: frontmatter の allowed-tools が workflow.pl の呼び出しだけか。
#      定型（templates/skill-prefix.md と skill-suffix.md）がそのまま入っているか。
#      topic ごとに入力、答えの形式、判断基準が書かれ、ユーザーへの問いは
#      AskUserQuestion で出すよう指示しているか
#   4. 手で回す:
#        perl scripts/workflow.pl start <引数>            # ask の JSON を読む
#        perl scripts/workflow.pl resume <run> <index> <<'EOF'
#        <答え>
#        EOF
#      途中で journal.json を開くと、effect の並びと保存された値が見える
#   5. runtime を変えたら prove -I scripts/lib t/ を通す。t/dullmify.t は
#      成果物の workflow.pl を起動するので、先に /compile --force coff-dullmify を通す
# =====================================================================

use strict;
use warnings;
use 5.030;

use Encode qw(decode FB_CROAK);
use Exporter qw(import);
use File::Basename qw(dirname);
use File::Path qw(make_path remove_tree);
use File::Spec;
use JSON::PP;

our @EXPORT_OK = qw(run_workflow llm step);

my $JSON = JSON::PP->new->canonical->utf8;
our $CURRENT;

# CLI を解釈し、run の作成または回答後の replay を始める。
# 呼び出しの誤り（引数、run、index、stdin の符号化）は JSON を出さず stderr へ返し、run を残す。
sub run_workflow {
    my (%opt) = @_;
    my @argv = @{ $opt{argv} };
    my $command = shift(@argv) // '';
    my $workflow_root = File::Spec->catdir(_default_state_root(), 'coff', $opt{name});

    if ($command eq 'start') {
        # 引数は境界で文字列に戻し、journal と workflow には decode 済みの値を渡す。
        @argv = map { _decode_utf8($_, 'argument') } @argv;
        my $run = sprintf('%x-%x', time, $$);
        my $run_dir = File::Spec->catdir($workflow_root, $run);
        make_path($run_dir);
        my $journal = { run => $run, args => \@argv, effects => [] };
        _write_json(_journal_path($run_dir), $journal);
        return _replay($journal, $run_dir, $opt{workflow});
    }

    die "usage: $0 start [args...] | resume <run> <index>\n"
        unless $command eq 'resume' && @argv == 2;
    my ($run, $index) = @argv;
    die "invalid run\n" unless $run =~ /\A[A-Za-z0-9][A-Za-z0-9._-]*\z/;
    my $run_dir = File::Spec->catdir($workflow_root, $run);
    my $journal = _read_json(_journal_path($run_dir));
    # pending は未回答の llm effect にしか付かないので、この照合だけで答えの宛先が確かめられる。
    die "effect $index is not the pending question of run $run\n"
        unless defined $journal->{pending} && $journal->{pending} eq $index;
    my $answer = do { local $/; _decode_utf8(scalar(<STDIN>) // '', 'answer') };
    $journal->{effects}[$index]{answer} = $answer;
    delete $journal->{pending};
    _write_json(_journal_path($run_dir), $journal);
    return _replay($journal, $run_dir, $opt{workflow});
}

# LLM への問いを journal に記録し、未回答なら workflow を中断する。
sub llm {
    my ($topic, $input) = @_;
    die "llm topic is required\n" unless defined $topic && length $topic;
    return _effect('llm', { topic => $topic, input => $input }, undef);
}

# 決定論的な副作用を一度だけ実行し、結果を journal に記録する。
sub step (&) {
    my ($code) = @_;
    return _effect('step', undef, $code);
}

# effect を実行順で照合し、記録済みなら保存した値を返す。
sub _effect {
    my ($kind, $ask, $code) = @_;
    die "effect called outside a workflow\n" unless $CURRENT;
    my $index = $CURRENT->{cursor}++;
    my $journal = $CURRENT->{journal};
    my $effect = $journal->{effects}[$index];
    $ask = _snapshot($ask) if $ask;

    if ($effect) {
        # 問いは topic と input を含む JSON 全体で比べる。
        my $same = $effect->{kind} eq $kind;
        $same &&= _encode($effect->{ask}) eq _encode($ask) if $kind eq 'llm';
        _non_deterministic($index) unless $same;
    }
    else {
        _non_deterministic($index) unless $index == @{ $journal->{effects} };
        $effect = { kind => $kind, ($ask ? (ask => $ask) : ()) };
        push @{ $journal->{effects} }, $effect;
        _write_json(_journal_path($CURRENT->{run_dir}), $journal);
    }

    if ($kind eq 'step') {
        return _snapshot($effect->{result}) if exists $effect->{result};
        $effect->{result} = _snapshot($code->());
        _write_json(_journal_path($CURRENT->{run_dir}), $journal);
        return _snapshot($effect->{result});
    }

    return _snapshot($effect->{answer}) if exists $effect->{answer};
    $journal->{pending} = $index;
    _write_json(_journal_path($CURRENT->{run_dir}), $journal);
    die bless(
        { payload => { run => $journal->{run}, index => $index, ask => $effect->{ask} } },
        'Coff::Workflow::Suspend',
    );
}

# workflow を先頭から再生し、問い、完了、失敗の JSON を返す。
sub _replay {
    my ($journal, $run_dir, $workflow) = @_;
    my $context = {
        journal => $journal,
        run_dir => $run_dir,
        cursor  => 0,
    };
    my ($report, $error);
    {
        local $CURRENT = $context;
        eval { $report = $workflow->(@{ $journal->{args} }); 1 }
            or $error = $@ || 'workflow failed';
    }

    if (ref($error) eq 'Coff::Workflow::Suspend') {
        say _encode($error->{payload});
        return 0;
    }
    return _finish($run_dir, $journal->{run}, undef, $error) if $error;
    return _finish(
        $run_dir, $journal->{run}, undef,
        'non-deterministic workflow: replay ended before recorded effects',
    ) if $context->{cursor} != @{ $journal->{effects} };
    return _finish($run_dir, $journal->{run}, $report, undef);
}

# 終端結果を出力し、完了した run のディレクトリを削除する。
sub _finish {
    my ($run_dir, $run, $report, $error) = @_;
    my $payload = { run => $run, done => JSON::PP::true };
    if (defined $error) {
        $error = "$error";
        $error =~ s/\s+\z//;
        $payload->{failed} = length($error) ? $error : 'workflow failed';
    }
    else {
        $payload->{report} = $report;
    }

    remove_tree($run_dir);
    say _encode($payload);
    return defined($error) ? 1 : 0;
}

# バイト列を UTF-8 の文字列に戻す。壊れていれば何の値かを添えて失敗する。
sub _decode_utf8 {
    my ($bytes, $what) = @_;
    my $text = eval { decode('UTF-8', $bytes, FB_CROAK) };
    die "$what is not UTF-8\n" if $@;
    return $text;
}

# XDG の state 位置を優先し、なければ HOME 配下を使う。
sub _default_state_root {
    return $ENV{XDG_STATE_HOME}
        if defined $ENV{XDG_STATE_HOME} && length $ENV{XDG_STATE_HOME};
    die "HOME is not set\n" unless defined $ENV{HOME} && length $ENV{HOME};
    return File::Spec->catdir($ENV{HOME}, '.local', 'state');
}

# run ごとの journal のパスを返す。
sub _journal_path {
    return File::Spec->catfile($_[0], 'journal.json');
}

# journal を UTF-8 JSON として読み込む。
sub _read_json {
    my ($path) = @_;
    open my $fh, '<:raw', $path or die "cannot read $path: $!\n";
    local $/;
    my $raw = <$fh>;
    close $fh or die "cannot close $path: $!\n";
    my $value = eval { $JSON->decode($raw) };
    die "invalid journal $path: $@\n" if $@;
    return $value;
}

# journal を同じディレクトリの一時ファイルから置き換える。
sub _write_json {
    my ($path, $value) = @_;
    make_path(dirname($path));
    my $tmp = "$path.tmp-$$";
    open my $fh, '>:raw', $tmp or die "cannot write $tmp: $!\n";
    print {$fh} _encode($value), "\n" or die "cannot write $tmp: $!\n";
    close $fh or die "cannot close $tmp: $!\n";
    rename $tmp, $path or die "cannot replace $path: $!\n";
}

# effect の並びが journal と変わったことを失敗として扱う。
sub _non_deterministic {
    my ($index) = @_;
    die "non-deterministic workflow at effect $index\n";
}

# JSON のバイト列を一意に作る。
sub _encode {
    return $JSON->encode($_[0]);
}

# journal と workflow が同じ参照を共有しないよう JSON で複製する。
sub _snapshot {
    my ($value) = @_;
    return $value unless ref $value;
    return $JSON->decode(_encode($value));
}

1;
