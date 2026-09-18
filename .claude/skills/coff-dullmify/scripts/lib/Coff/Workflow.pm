package Coff::Workflow;

use strict;
use warnings;
use 5.030;

use Digest::MD5 qw(md5_hex);
use Encode qw(decode encode_utf8 FB_CROAK);
use Exporter qw(import);
use File::Basename qw(dirname);
use File::Path qw(make_path remove_tree);
use File::Spec;
use JSON::PP;

our @EXPORT_OK = qw(run_workflow llm step);

my $JSON = JSON::PP->new->canonical->utf8->allow_nonref;
our $CURRENT;

# CLI を解釈し、run の作成または回答後の replay を始める。
sub run_workflow {
    my (%opt) = @_;
    my $name = $opt{name};
    die "workflow name is required\n"
        unless defined $name && $name =~ /\A[A-Za-z0-9][A-Za-z0-9._-]*\z/;
    die "workflow callback is required\n" unless ref($opt{workflow}) eq 'CODE';

    my @argv = @{ $opt{argv} // \@ARGV };
    my $command = shift(@argv) // '';
    my $root = $opt{state_root} // _default_state_root();
    my $workflow_root = File::Spec->catdir($root, 'coff', $name);
    my $emit = $opt{emit} // sub { print $_[0], "\n" };
    my $read_answer = $opt{read_answer} // sub {
        local $/;
        return decode('UTF-8', scalar(<STDIN>) // '', FB_CROAK);
    };

    if ($command eq 'start') {
        make_path($workflow_root);
        my $run = _new_run_id($workflow_root);
        my $run_dir = File::Spec->catdir($workflow_root, $run);
        make_path($run_dir);
        my $journal = {
            schema  => 1,
            name    => $name,
            run     => $run,
            args    => \@argv,
            effects => [],
        };
        _write_json(_journal_path($run_dir), $journal);
        return _replay($journal, $run_dir, \%opt, $emit);
    }

    die "usage: $0 start [args...] | resume <run> <index>\n"
        unless $command eq 'resume';
    die "resume requires a run and an effect index\n" unless @argv == 2;
    my ($run, $index) = @argv;
    die "invalid run\n"
        unless $run =~ /\A[A-Za-z0-9][A-Za-z0-9._-]*\z/;
    die "effect index must be a non-negative integer\n"
        unless $index =~ /\A(?:0|[1-9][0-9]*)\z/;

    my $run_dir = File::Spec->catdir($workflow_root, $run);
    my $journal = _read_json(_journal_path($run_dir));
    my $error;
    eval {
        my $effect = $journal->{effects}[$index]
            or die "unknown effect index: $index\n";
        die "effect $index does not accept an answer\n"
            unless $effect->{kind} eq 'llm';
        die "effect $index was already answered\n" if exists $effect->{answer};
        die "effect $index is not the pending question\n"
            unless defined $journal->{pending} && $journal->{pending} == $index;
        $effect->{answer} = $read_answer->();
        delete $journal->{pending};
        _write_json(_journal_path($run_dir), $journal);
        1;
    } or $error = $@ || 'resume failed';
    return _finish($run_dir, $run, undef, $error, $emit) if $error;
    return _replay($journal, $run_dir, \%opt, $emit);
}

# LLM への問いを journal に記録し、未回答なら workflow を中断する。
sub llm {
    my ($topic, $input) = @_;
    die "llm topic is required\n" unless defined $topic && length $topic;
    return _effect('llm', $topic, $input, undef);
}

# 決定論的な副作用を一度だけ実行し、結果を journal に記録する。
sub step (&) {
    my ($code) = @_;
    return _effect('step', undef, undef, $code);
}

# effect を実行順で照合し、記録済みなら保存した値を返す。
sub _effect {
    my ($kind, $topic, $input, $code) = @_;
    die "effect called outside a workflow\n" unless $CURRENT;
    my $index = $CURRENT->{cursor}++;
    my $journal = $CURRENT->{journal};
    my $effect = $journal->{effects}[$index];
    my $hash;

    if ($kind eq 'llm') {
        $input = _snapshot($input);
        $hash = md5_hex(_encode({ topic => $topic, input => $input }));
    }

    if ($effect) {
        my $same = $effect->{kind} eq $kind;
        $same &&= $effect->{topic} eq $topic && $effect->{input_hash} eq $hash
            if $kind eq 'llm';
        _non_deterministic($index) unless $same;
    }
    else {
        _non_deterministic($index) unless $index == @{ $journal->{effects} };
        $effect = { index => $index, kind => $kind };
        if ($kind eq 'llm') {
            $effect->{topic} = $topic;
            $effect->{input} = $input;
            $effect->{input_hash} = $hash;
        }
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
    die bless({ payload => _ask_payload($journal, $effect) }, 'Coff::Workflow::Suspend');
}

# workflow を先頭から再生し、問い、完了、失敗の JSON を返す。
sub _replay {
    my ($journal, $run_dir, $opt, $emit) = @_;
    my $context = {
        journal => $journal,
        run_dir => $run_dir,
        cursor  => 0,
    };
    my ($report, $error);
    {
        local $CURRENT = $context;
        eval { $report = $opt->{workflow}->(@{ $journal->{args} }); 1 }
            or $error = $@ || 'workflow failed';
    }

    if (ref($error) eq 'Coff::Workflow::Suspend') {
        $emit->(_encode($error->{payload}));
        return 0;
    }
    return _finish($run_dir, $journal->{run}, undef, $error, $emit) if $error;
    if ($context->{cursor} != @{ $journal->{effects} }) {
        return _finish(
            $run_dir,
            $journal->{run},
            undef,
            'non-deterministic workflow: replay ended before recorded effects',
            $emit,
        );
    }
    return _finish($run_dir, $journal->{run}, $report, undef, $emit);
}

# 終端結果を出力し、完了した run のディレクトリを削除する。
sub _finish {
    my ($run_dir, $run, $report, $error, $emit) = @_;
    my $payload = { run => $run, done => JSON::PP::true };
    if (defined $error) {
        $error = "$error";
        $error =~ s/\s+\z//;
        $payload->{failed} = length($error) ? $error : 'workflow failed';
    }
    else {
        $payload->{report} = $report;
    }

    remove_tree($run_dir, { error => \my $errors });
    die "cannot remove completed run: $run_dir\n" if @$errors;
    $emit->(_encode($payload));
    return defined($error) ? 1 : 0;
}

# 未回答の問いを runtime の応答形式に整える。
sub _ask_payload {
    my ($journal, $effect) = @_;
    return {
        run   => $journal->{run},
        index => $effect->{index},
        ask   => {
            topic => $effect->{topic},
            input => $effect->{input},
        },
    };
}

# 同時実行と衝突しない短い run ID を作る。
sub _new_run_id {
    my ($root) = @_;
    my $base = sprintf('%x-%x', time, $$);
    my $run = $base;
    my $counter = 0;
    $run = $base . '-' . ++$counter
        while -e File::Spec->catdir($root, $run);
    return $run;
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
