package Coff::Workflow;

# ===== README: runtime の仕組みと生成物のレビュー =====
#
# runtime の役割
# この runtime は、coff-dullmify が生成する skill の実行を支える。
# scripts/workflow.pl が手順を制御し、LLM は SKILL.md の判断基準に従って
# 問われた判断にだけ答える。ファイル操作などの副作用はプログラムが実行する。
# 回答は別プロセスの呼び出しで受け取るため、実行記録を journal.json に保存し、
# workflow を毎回先頭から実行する replay 方式を採る。
# 副作用の step と問いの llm を effect と呼び、呼び出した順に記録する。
#
# run の開始から終了まで
# start [args...] は run と journal を作り、sub workflow に引数を渡す。
# 未回答の llm に達すると、次の JSON を標準出力へ返してプロセスを終える。
#   {"run":...,"index":...,"ask":{"topic":...,"input":...}}
# index は step も数えた 0 始まりの通し番号である。
# resume <run> <index> は標準入力の答えを文字列として記録し、再生を始める。
# 結果が保存済みの step はその値を、回答済みの llm は答えを返す。
# それ以外のコードは再実行し、次の問いか workflow の終わりまで進む。
# 正常終了では {"run":...,"done":true,"report":...} を返す。
# workflow 内の失敗では {"run":...,"done":true,"failed":"理由"} を返す。
# どちらも run ディレクトリを削除する。問いを返した時点では削除しない。
#
# replay を支える仕組み
# - Suspend は、未回答の llm から workflow 全体を抜けるための例外である。
#   例外を継続の代用にし、_replay が問いを返す。
#   effect を eval で囲むと中断が runtime に届かなくなるため、本文では囲まない。
# - effect は実行順の index だけで識別し、種類と llm の問いの JSON を照合する。
#   種類や問いが違えば、別の処理に保存値を返さないよう failed にする。
#   記録済みの effect をすべて通る前に workflow が終わった場合も同様である。
#   同じ位置の step の中身の変更は検出しない。
#   ソース変更時には coff-compile が workflow.pl を再生成する前提である。
# - _snapshot は JSON の往復で参照を複製し、保存時と返却時に切り離す。
#   workflow が値を書き換えても、後の replay で使う記録を変えないためである。
# - local $CURRENT で実行中の文脈を動的スコープに置く。
#   深い補助関数内の llm や step にも、引数で文脈を渡さず journal を共有できる。
# - step (&) の prototype により、step { ... } のブロックをコード参照で渡せる。
#   runtime が実行を制御し、保存済みの結果があればブロックを実行せずに返せる。
# - 引数と回答は受け取り時に UTF-8 から decode し、文字列として扱う。
#   バイト列のまま JSON に入れる二重エンコードを避けるためである。
#   パスをファイル操作に渡す際は workflow 側で Encode::encode_utf8 する。
# - run / index の誤りや不正な UTF-8 は、JSON を返さず標準エラーで知らせる。
#   回答を正しく再送できるよう、既存の run と journal は残す。
# - journal はプロセス間で引き継ぐため、次の state ディレクトリに保存する。
#   ${XDG_STATE_HOME:-$HOME/.local/state}/coff/<name>/<run>/journal.json
#   <name> は skill ディレクトリ名である。
#
# 生成物のレビュー
# .claude/skills/<name>/scripts/workflow.pl は雛形の頭、LLM の本文、雛形の尻、
# coff-compile が付けるフッタの順に並ぶ。
# LLM が書くのは sub workflow と補助関数だけである。
# 頭と尻を templates/workflow-head.pl、workflow-tail.pl と照合し、本文を読む。
# scripts/lib/Coff/Workflow.pm は runtime の複製である。
# - 本文では、副作用がすべて step 内にあり、失敗を die で表すかを確かめる。
#   時計と乱数を使わず、hash のキーを sort して処理しているかも見る。
#   effect を eval で囲まず、llm の直後で答えを検査しているかを確かめる。
#   Perl 5.30 と core モジュールだけを使い、本文に use 宣言を加えない。
#   追加モジュールは補助関数内で require し、完全修飾名で呼ぶかを確かめる。
#   パスの符号化と補助関数の日本語コメントも確認する。
# - SKILL.md は allowed-tools が workflow.pl の呼び出しだけで、coff-* が
#   残っていないかを見る。
#   共通手順と完了報告は templates/skill-prefix.md と skill-suffix.md に照らす。
#   公開時に coff-compile が英訳する点に注意する。
#   各 topic の入力、答えの形式、判断基準が workflow の問いと合うか、
#   ユーザーへの問いを AskUserQuestion で提示する指示があるかを確かめる。
#
# 手動確認とテスト
# 対象の skill ディレクトリで start し、ask の topic に沿って答えを作る。
#   perl scripts/workflow.pl start <引数>
# 応答の <run> と <index> を使い、引用した heredoc で答えをそのまま渡す。
#   perl scripts/workflow.pl resume <run> <index> <<'EOF'
#   <答え>
#   EOF
# 次の ask または done を確認する。
# journal は run 終了時に消えるため、待機中に上記のパスを cat して
# effects の並びと result / answer を読む。
# runtime を変えたら、リポジトリのルートで次の順に確認する。
#   1. prove -I .coff/src/coff-dullmify/scripts/lib \
#        .coff/src/coff-dullmify/t/workflow.t
#   2. /compile --force coff-dullmify
#   3. prove -I .coff/src/coff-dullmify/scripts/lib .coff/src/coff-dullmify/t/
# t/dullmify.t は成果物を起動するため、先に再生成して runtime を反映させる。
# =====

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
