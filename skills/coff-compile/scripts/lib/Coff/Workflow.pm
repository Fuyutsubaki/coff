package Coff::Workflow;

use strict;
use warnings;
use 5.030;

use Digest::MD5 qw(md5_hex);
use Encode qw(decode encode_utf8 FB_CROAK);
use Exporter qw(import);
use File::Basename qw(dirname basename);
use File::Path qw(make_path remove_tree);
use File::Spec;
use IPC::Open3 qw(open3);
use JSON::PP;
use Symbol qw(gensym);

our @EXPORT_OK = qw(run_workflow llm user step publish_files);

my $JSON = JSON::PP->new->canonical->utf8->allow_nonref;
our $CURRENT;

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
    my $script = $opt{script} // $0;
    my $runtime = $opt{runtime} // __FILE__;
    my $emit = $opt{emit} // sub { print $_[0], "\n" };
    my $read_answer = $opt{read_answer} // sub {
        local $/;
        my $raw = scalar <STDIN> // '';
        return decode('UTF-8', $raw, FB_CROAK);
    };

    if ($command eq 'start') {
        make_path($workflow_root);
        my $run = _new_run_id($workflow_root);
        my $run_dir = _run_dir($workflow_root, $run);
        make_path($run_dir);
        my $journal = {
            schema       => 1,
            name         => $name,
            run          => $run,
            args         => \@argv,
            workflow_md5 => _workflow_md5($script),
            runtime_md5  => _file_md5($runtime),
            created_at   => time,
            effects      => [],
        };
        _write_json(_journal_path($run_dir), $journal);
        return _replay($journal, $run_dir, \%opt, $emit);
    }

    if ($command eq 'gc') {
        die "gc takes no arguments\n" if @argv;
        make_path($workflow_root);
        my $removed = _gc($workflow_root, time - 7 * 24 * 60 * 60);
        $emit->(_encode({ gc => $removed }));
        return 0;
    }

    die "usage: $0 start [args...] | resume <run> <index> | status <run> | cancel <run> | gc\n"
        unless $command eq 'resume' || $command eq 'status' || $command eq 'cancel';

    my $run = shift @argv;
    _validate_run($run);
    my $run_dir = _run_dir($workflow_root, $run);

    if ($command eq 'status') {
        die "status requires exactly one run\n" if @argv;
        my $terminal = _read_optional_json(_terminal_path($run_dir));
        if ($terminal) {
            $emit->(_encode($terminal));
            return 0;
        }
        my $journal = _read_json(_journal_path($run_dir));
        $emit->(_encode(_current_payload($journal)));
        return 0;
    }

    if ($command eq 'cancel') {
        die "cancel requires exactly one run\n" if @argv;
        my $terminal = _read_optional_json(_terminal_path($run_dir));
        if (!$terminal) {
            my $journal = _read_json(_journal_path($run_dir));
            $terminal = {
                run       => $journal->{run},
                done      => JSON::PP::true,
                cancelled => JSON::PP::true,
                report    => 'cancelled',
            };
            _finish($run_dir, $terminal);
        }
        $emit->(_encode($terminal));
        return 0;
    }

    die "resume requires a run and an effect index\n" unless @argv == 1;
    my $index = shift @argv;
    die "effect index must be a non-negative integer\n"
        unless defined $index && $index =~ /\A(?:0|[1-9][0-9]*)\z/;

    my $terminal = _read_optional_json(_terminal_path($run_dir));
    if ($terminal) {
        $emit->(_encode($terminal));
        return 0;
    }

    my $journal = _read_json(_journal_path($run_dir));
    _verify_versions($journal, $script, $runtime);
    my $answer = $read_answer->();
    my $effect = $journal->{effects}[$index]
        or die "unknown effect index: $index\n";
    die "effect $index does not accept an answer\n"
        unless $effect->{kind} eq 'llm' || $effect->{kind} eq 'user';

    if (exists $effect->{answer}) {
        die "effect $index was already answered differently\n"
            unless $effect->{answer} eq $answer;
        $emit->(_encode(_current_payload($journal)));
        return 0;
    }

    die "effect $index is not the pending question\n"
        unless defined $journal->{pending} && $journal->{pending} == $index;
    $effect->{answer} = $answer;
    delete $journal->{pending};
    _write_json(_journal_path($run_dir), $journal);
    return _replay($journal, $run_dir, \%opt, $emit);
}

sub llm {
    my ($topic, $input) = @_;
    return _question('llm', $topic, $input);
}

sub user {
    my ($topic, $input) = @_;
    return _question('user', $topic, $input);
}

sub step (&;$$) {
    my ($code, $topic, $input) = @_;
    $topic = 'step' unless defined $topic;
    $input = {} unless defined $input;
    return _effect('step', $topic, $input, $code);
}

sub publish_files {
    my (%opt) = @_;
    my $files = $opt{files};
    return { ok => JSON::PP::false, error => 'files must be an array' }
        unless ref($files) eq 'ARRAY';

    my %seen;
    my @staged;
    my $sequence = 0;
    for my $file (@$files) {
        unless (ref($file) eq 'HASH'
            && defined $file->{path}
            && defined $file->{content}
            && !$seen{$file->{path}}++) {
            _cleanup_staged(\@staged);
            return { ok => JSON::PP::false, error => 'invalid or duplicate file entry' };
        }
        next if _same_content($file->{path}, $file->{content});

        my $dir = dirname($file->{path});
        make_path($dir);
        my $tmp = File::Spec->catfile(
            $dir,
            '.' . basename($file->{path}) . ".coff-tmp-$$-" . $sequence++,
        );
        if (-e $tmp) {
            _cleanup_staged(\@staged);
            return { ok => JSON::PP::false, error => "temporary path already exists: $tmp" };
        }
        unless (_write_raw($tmp, $file->{content})) {
            my $error = $! || 'write failed';
            _cleanup_staged(\@staged);
            return { ok => JSON::PP::false, error => "cannot stage $file->{path}: $error" };
        }
        push @staged, { %$file, tmp => $tmp };
    }

    for my $file (@staged) {
        next unless $file->{check_perl};
        my @include;
        for my $dir (@{ $opt{perl_inc} // [] }) {
            push @include, '-I', $dir;
        }
        my ($status, $diagnostic) = _check_perl($file->{tmp}, \@include);
        if ($status != 0) {
            _cleanup_staged(\@staged);
            $diagnostic =~ s/\s+\z//;
            return {
                ok    => JSON::PP::false,
                error => "perl -c failed for $file->{path}: $diagnostic",
            };
        }
    }

    my @backups;
    for my $file (@staged) {
        next unless -e $file->{path};
        my $backup = $file->{tmp} . '.old';
        unless (rename $file->{path}, $backup) {
            _restore_backups(\@backups);
            _cleanup_staged(\@staged);
            return { ok => JSON::PP::false, error => "cannot prepare $file->{path}: $!" };
        }
        push @backups, { path => $file->{path}, backup => $backup };
    }

    my @installed;
    for my $file (@staged) {
        unless (rename $file->{tmp}, $file->{path}) {
            unlink $_ for @installed;
            _restore_backups(\@backups);
            _cleanup_staged(\@staged);
            return { ok => JSON::PP::false, error => "cannot install $file->{path}: $!" };
        }
        push @installed, $file->{path};
    }
    unlink $_->{backup} for @backups;
    return { ok => JSON::PP::true, changed => scalar @staged };
}

sub _question {
    my ($kind, $topic, $input) = @_;
    die "$kind topic is required\n" unless defined $topic && length $topic;
    return _effect($kind, $topic, $input, undef);
}

sub _effect {
    my ($kind, $topic, $input, $code) = @_;
    die "effect called outside a workflow\n" unless $CURRENT;
    my $index = $CURRENT->{cursor}++;
    my $hash = md5_hex(_encode({ kind => $kind, topic => $topic, input => $input }));
    my $journal = $CURRENT->{journal};
    my $effect = $journal->{effects}[$index];

    if ($effect) {
        _non_deterministic($index)
            unless $effect->{kind} eq $kind
                && $effect->{topic} eq $topic
                && $effect->{input_hash} eq $hash;
    }
    else {
        _non_deterministic($index) unless $index == @{ $journal->{effects} };
        $effect = {
            index      => $index,
            kind       => $kind,
            topic      => $topic,
            input      => $input,
            input_hash => $hash,
        };
        push @{ $journal->{effects} }, $effect;
        _write_json(_journal_path($CURRENT->{run_dir}), $journal);
    }

    if ($kind eq 'step') {
        return $effect->{result} if exists $effect->{result};
        my $result = $code->();
        $effect->{result} = $result;
        _write_json(_journal_path($CURRENT->{run_dir}), $journal);
        return $result;
    }

    return $effect->{answer} if exists $effect->{answer};
    $journal->{pending} = $index;
    _write_json(_journal_path($CURRENT->{run_dir}), $journal);
    die bless({ payload => _ask_payload($journal, $effect) }, 'Coff::Workflow::Suspend');
}

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
    if ($error) {
        print STDERR "$error";
        print STDERR "\n" unless "$error" =~ /\n\z/;
        return 1;
    }
    if ($context->{cursor} != @{ $journal->{effects} }) {
        print STDERR "non-deterministic workflow: replay ended before recorded effects\n";
        return 1;
    }

    my $terminal = {
        run    => $journal->{run},
        done   => JSON::PP::true,
        report => $report,
    };
    _finish($run_dir, $terminal);
    $emit->(_encode($terminal));
    return 0;
}

sub _verify_versions {
    my ($journal, $script, $runtime) = @_;
    die "workflow changed since this run started\n"
        unless $journal->{workflow_md5} eq _workflow_md5($script);
    die "Coff::Workflow changed since this run started\n"
        unless $journal->{runtime_md5} eq _file_md5($runtime);
}

sub _current_payload {
    my ($journal) = @_;
    if (defined $journal->{pending}) {
        my $effect = $journal->{effects}[ $journal->{pending} ];
        return _ask_payload($journal, $effect);
    }
    return { run => $journal->{run}, running => JSON::PP::true };
}

sub _ask_payload {
    my ($journal, $effect) = @_;
    return {
        run   => $journal->{run},
        index => $effect->{index},
        ask   => {
            topic => $effect->{topic},
            kind  => $effect->{kind},
            input => $effect->{input},
        },
    };
}

sub _finish {
    my ($run_dir, $terminal) = @_;
    _write_json(_terminal_path($run_dir), $terminal);
    unlink _journal_path($run_dir)
        or die "cannot remove completed journal: $!\n" if -e _journal_path($run_dir);
}

sub _gc {
    my ($workflow_root, $before) = @_;
    opendir my $dh, $workflow_root or die "cannot read $workflow_root: $!\n";
    my $removed = 0;
    while (my $entry = readdir $dh) {
        next if $entry eq '.' || $entry eq '..';
        next unless $entry =~ /\A[A-Za-z0-9][A-Za-z0-9._-]*\z/;
        my $path = File::Spec->catdir($workflow_root, $entry);
        next unless -d $path;
        my @stat = stat $path;
        next unless @stat && $stat[9] < $before;
        remove_tree($path, { error => \my $errors });
        die "cannot remove old run $entry\n" if @$errors;
        $removed++;
    }
    closedir $dh;
    return $removed;
}

sub _new_run_id {
    my ($root) = @_;
    my $base = sprintf('%x-%x', time, $$);
    my $run = $base;
    my $counter = 0;
    while (-e File::Spec->catdir($root, $run)) {
        $run = $base . '-' . ++$counter;
    }
    return $run;
}

sub _default_state_root {
    return $ENV{XDG_STATE_HOME}
        if defined $ENV{XDG_STATE_HOME} && length $ENV{XDG_STATE_HOME};
    die "HOME is not set\n" unless defined $ENV{HOME} && length $ENV{HOME};
    return File::Spec->catdir($ENV{HOME}, '.local', 'state');
}

sub _validate_run {
    my ($run) = @_;
    die "run is required\n"
        unless defined $run && $run =~ /\A[A-Za-z0-9][A-Za-z0-9._-]*\z/;
}

sub _run_dir {
    my ($root, $run) = @_;
    return File::Spec->catdir($root, $run);
}

sub _journal_path { return File::Spec->catfile($_[0], 'journal.json') }
sub _terminal_path { return File::Spec->catfile($_[0], 'terminal.json') }

sub _workflow_md5 {
    my ($path) = @_;
    open my $fh, '<:raw', $path or die "cannot read workflow $path: $!\n";
    my $last = '';
    $last = $_ while <$fh>;
    close $fh or die "cannot close workflow $path: $!\n";
    return $1 if $last =~ /# <!--\{"src":.*"md5":"([a-f0-9]{32})"\} -->\s*\z/;
    die "workflow footer md5 is missing: $path\n";
}

sub _file_md5 {
    my ($path) = @_;
    open my $fh, '<:raw', $path or die "cannot read $path: $!\n";
    my $digest = Digest::MD5->new->addfile($fh)->hexdigest;
    close $fh or die "cannot close $path: $!\n";
    return $digest;
}

sub _read_json {
    my ($path) = @_;
    open my $fh, '<:raw', $path or die "cannot read $path: $!\n";
    local $/;
    my $raw = <$fh>;
    close $fh or die "cannot close $path: $!\n";
    return eval { $JSON->decode($raw) }
        // die "invalid journal $path: $@\n";
}

sub _read_optional_json {
    my ($path) = @_;
    return undef unless -e $path;
    return _read_json($path);
}

sub _write_json {
    my ($path, $value) = @_;
    make_path(dirname($path));
    my $tmp = $path . ".tmp-$$";
    _write_raw($tmp, _encode($value) . "\n")
        or die "cannot write $tmp: $!\n";
    rename $tmp, $path or die "cannot replace $path: $!\n";
}

sub _write_raw {
    my ($path, $content) = @_;
    $content = _bytes($content);
    open my $fh, '>:raw', $path or return 0;
    print {$fh} $content or do { close $fh; return 0 };
    close $fh or return 0;
    return 1;
}

sub _same_content {
    my ($path, $content) = @_;
    $content = _bytes($content);
    return 0 unless -f $path;
    open my $fh, '<:raw', $path or return 0;
    local $/;
    my $old = <$fh>;
    close $fh or return 0;
    return $old eq $content;
}

sub _check_perl {
    my ($path, $include) = @_;
    my $error = gensym;
    my $pid = open3(my $input, my $output, $error, $^X, @$include, '-c', $path);
    close $input;
    local $/;
    my $stdout = <$output> // '';
    my $stderr = <$error> // '';
    waitpid($pid, 0);
    return ($? >> 8, $stdout . $stderr);
}

sub _cleanup_staged {
    my ($staged) = @_;
    unlink $_->{tmp} for grep { -e $_->{tmp} } @$staged;
}

sub _restore_backups {
    my ($backups) = @_;
    for my $item (reverse @$backups) {
        rename $item->{backup}, $item->{path}
            or die "cannot restore $item->{path}: $!\n";
    }
}

sub _non_deterministic {
    my ($index) = @_;
    die "non-deterministic workflow at effect $index\n";
}

sub _encode { return $JSON->encode($_[0]) }

sub _bytes {
    my ($content) = @_;
    return utf8::is_utf8($content) ? encode_utf8($content) : $content;
}

1;
