#!/usr/bin/env perl
# ここから sub workflow の手前までは coff-dullmify が差し込む土台で、LLM は書かない。
use strict;
use warnings;
use utf8;
use 5.030;

use File::Basename qw(basename dirname);
use File::Spec;
use FindBin;
use lib "$FindBin::Bin/lib";
use Coff::Workflow qw(run_workflow llm step);

# 対象を選び、各ソースの lint と compile を順番に進める。
sub workflow {
    my @args = @_;
    my $plan = step { _make_plan(\@args) };

    my @report;
    for my $item (@{ $plan->{items} }) {
        if ($item->{skip} && !$plan->{force}) {
            if (!$plan->{lint_only} && @{ $item->{bundle_files} }) {
                step { _write_files($item->{bundle_files}) };
            }
            next;
        }

        my $result = _compile_item($plan, $item);
        if (defined $result && length $result) {
            push @report, "$item->{source}: $result";
        }
    }
    return \@report;
}

# 1ソースの lint、承認、compile を実行する。
sub _compile_item {
    my ($plan, $item) = @_;
    my $answer = llm('lint-candidates', {
        path    => $item->{source},
        content => $item->{content},
    });
    my $candidates = step { _validate_candidates($answer, $item->{content}) };

    my $candidate_count = @$candidates;
    my ($applied, $rejected) = (0, 0);
    if ($candidate_count) {
        my $approval = llm('lint-approval', {
            path       => $item->{source},
            candidates => [
                map {
                    +{ index => $_, label => $candidates->[$_]{label} }
                } 0 .. $candidate_count - 1
            ],
        });
        my $lint = step { _apply_lint($item, $candidates, $approval) };
        $item->{content} = $lint->{content};
        $item->{md5} = $lint->{md5};
        $applied = $lint->{applied};
        $rejected = $candidate_count - $applied;

        return "linted ($applied applied, $rejected rejected)"
            if $plan->{lint_only};

        my $confirmation = llm('compile-confirmation', {
            path     => $item->{source},
            applied  => $applied,
            rejected => $rejected,
            message  => "Lint 完了。$applied 件適用、$rejected 件却下。コンパイルしますか？",
        });
        return "linted ($applied applied, $rejected rejected)"
            unless $confirmation =~ /\A\s*(?:yes|y)\s*\z/i;
    }
    elsif ($plan->{lint_only}) {
        return '';
    }

    if ($item->{dullmify}) {
        _compile_dullmified($item);
    }
    else {
        _compile_markdown($item);
    }

    my $suffix = $applied ? " ($applied lint changes)" : '';
    return "compiled$suffix";
}

# dullmify の一時出力を英訳し、実体出力へ公開する。
sub _compile_dullmified {
    my ($item) = @_;
    my $staging = _staging_path($item);
    step { _seed_staging($item, $staging) };
    my $answer = llm('dullmify', {
        source => $item->{source},
        out    => $staging,
    });
    $answer =~ s/\A\s+|\s+\z//g;
    die "dullmify failed: $answer\n" unless $answer eq 'ok';

    my $generated = step { _read_dullmify_output($staging) };
    my $document = $generated->{skill};
    if ($item->{translate}) {
        $document = llm('translate', {
            path    => $item->{source},
            content => $document,
        });
    }
    step { _publish_compiled($item, $document, $generated, $staging) };
}

# Markdown だけのソースを英訳し、実体出力へ公開する。
sub _compile_markdown {
    my ($item) = @_;
    my $document = $item->{content};
    if ($item->{translate}) {
        $document = llm('translate', {
            path    => $item->{source},
            content => $document,
        });
    }
    step { _publish_compiled($item, $document, undef, undef) };
}

# CLI とソースを読み、処理対象ごとの計画を作る。
sub _make_plan {
    my ($args) = @_;
    my $options = _parse_options($args);
    my $sources = _resolve_sources($options->{selectors});
    my @items;

    for my $source (@$sources) {
        my ($type, $name) = _source_type($source);
        my @outputs = _outputs_for($type, $name, $options->{targets});
        next unless @outputs;
        die "empty source: $source\n" unless -s $source;

        my $content = _read_text($source);
        my $frontmatter = _frontmatter($content);
        my $dullmify = _directive_bool($frontmatter, 'coff-dullmify');
        die "$source: coff-dullmify requires a skill source\n"
            if $dullmify && $type ne 'skill';

        my $md5 = _file_md5($source);
        my $bundle_names = _bundle_names($frontmatter);
        my $bundle_files = _collect_bundle_files($name, $bundle_names, \@outputs);
        my @footer_outputs = map { $_->{path} } @outputs;
        push @footer_outputs, map {
            File::Spec->catfile(dirname($_->{path}), 'scripts', 'workflow.pl')
        } grep { $_->{mode} eq 'body' } @outputs if $dullmify;

        my $skip = 1;
        for my $path (@footer_outputs) {
            if ((_footer_md5($path) // '') ne $md5) {
                $skip = 0;
                last;
            }
        }

        push @items, {
            source       => $source,
            type         => $type,
            name         => $name,
            content      => $content,
            md5          => $md5,
            dullmify     => $dullmify ? 1 : 0,
            translate    => _directive_false($frontmatter, 'coff-translate') ? 0 : 1,
            outputs      => \@outputs,
            bundle_files => $bundle_files,
            skip         => $skip ? 1 : 0,
        };
    }

    return {
        force     => $options->{force},
        lint_only => $options->{lint_only},
        items     => \@items,
    };
}

# compile のオプションと出力プリセットを解釈する。
sub _parse_options {
    my ($args) = @_;
    my %option = (
        force     => 0,
        lint_only => 0,
        selectors => [],
        agent     => [],
    );
    my ($explicit_out, $explicit_ref) = (0, 0);

    for (my $i = 0; $i < @$args; $i++) {
        my $arg = $args->[$i];
        if ($arg eq '--force') {
            $option{force} = 1;
        }
        elsif ($arg eq '--lint-only') {
            $option{lint_only} = 1;
        }
        elsif ($arg eq '--out') {
            die "--out requires a root\n" if ++$i >= @$args;
            $option{out} = $args->[$i];
            $explicit_out = 1;
        }
        elsif ($arg eq '--ref') {
            $option{ref} = 1;
            $explicit_ref = 1;
        }
        elsif ($arg eq '--agent') {
            die "--agent requires a name\n" if ++$i >= @$args;
            push @{ $option{agent} }, $args->[$i];
        }
        elsif ($arg =~ /\A--/) {
            die "unknown option: $arg\n";
        }
        else {
            push @{ $option{selectors} }, $arg;
        }
    }

    die "--ref requires --out\n" if $explicit_ref && !$explicit_out;
    die "--agent cannot be combined with --out or --ref\n"
        if @{ $option{agent} } && ($explicit_out || $explicit_ref);

    my @targets;
    if (@{ $option{agent} }) {
        my %seen;
        for my $agent (@{ $option{agent} }) {
            next if $seen{$agent}++;
            if ($agent eq 'claude-code') {
                push @targets, {
                    root => '.claude', mode => 'body',
                    types => [qw(skill outputstyle agent)],
                };
            }
            elsif ($agent eq 'codex') {
                push @targets, {
                    root => '.agents', mode => 'ref', types => ['skill'],
                };
            }
            else {
                die "unknown agent: $agent\n";
            }
        }
    }
    elsif ($explicit_out) {
        push @targets, {
            root  => $option{out},
            mode  => $option{ref} ? 'ref' : 'body',
            types => [qw(skill outputstyle agent)],
        };
    }
    else {
        push @targets, {
            root => '.claude', mode => 'body',
            types => [qw(skill outputstyle agent)],
        };
    }
    $option{targets} = \@targets;
    return \%option;
}

# selector を実在する一意なソースへ解決する。
sub _resolve_sources {
    my ($selectors) = @_;
    my @sources;
    if (!@$selectors) {
        for my $suffix (qw(skill.md outputstyle.md agent.md)) {
            push @sources, glob(File::Spec->catfile('.coff', 'src', "*.$suffix"));
        }
    }
    else {
        for my $selector (@$selectors) {
            my @matches;
            if ($selector =~ /\.(?:skill|outputstyle|agent)\.md\z/) {
                my $candidate = $selector =~ m{[/\\]}
                    ? $selector
                    : File::Spec->catfile('.coff', 'src', $selector);
                push @matches, $candidate if -f $candidate;
            }
            else {
                for my $suffix (qw(skill.md outputstyle.md agent.md)) {
                    my $candidate = File::Spec->catfile('.coff', 'src', "$selector.$suffix");
                    push @matches, $candidate if -f $candidate;
                }
            }
            die "source not found: $selector\n" unless @matches;
            die "ambiguous source: $selector\n" if @matches > 1;
            push @sources, $matches[0];
        }
    }
    my %seen;
    return [sort grep { !$seen{$_}++ } @sources];
}

# ソースの拡張子から種別と名前を返す。
sub _source_type {
    my ($source) = @_;
    my $file = basename($source);
    return ('skill', $1) if $file =~ /\A(.+)\.skill\.md\z/;
    return ('outputstyle', $1) if $file =~ /\A(.+)\.outputstyle\.md\z/;
    return ('agent', $1) if $file =~ /\A(.+)\.agent\.md\z/;
    die "unknown source type: $source\n";
}

# 種別と出力プリセットから出力先を列挙する。
sub _outputs_for {
    my ($type, $name, $targets) = @_;
    my @outputs;
    for my $target (@$targets) {
        my %allowed = map { $_ => 1 } @{ $target->{types} };
        next unless $allowed{$type};
        my $path = $type eq 'skill'
            ? File::Spec->catfile($target->{root}, 'skills', $name, 'SKILL.md')
            : $type eq 'outputstyle'
                ? File::Spec->catfile($target->{root}, 'output-styles', "$name.md")
                : File::Spec->catfile($target->{root}, 'agents', "$name.md");
        push @outputs, { %$target, path => $path };
    }
    return @outputs;
}

# Markdown 先頭の frontmatter 本文を取り出す。
sub _frontmatter {
    my ($content) = @_;
    die "frontmatter is missing\n" unless $content =~ /\A---\r?\n/;
    return $1 if $content =~ /\A---\r?\n(.*?)\r?\n---\r?\n/s;
    die "frontmatter is not closed\n";
}

# true と宣言された coff の真偽値を読む。
sub _directive_bool {
    my ($frontmatter, $key) = @_;
    return $frontmatter =~ /^\Q$key\E:\s*true\s*(?:#.*)?$/mi ? 1 : 0;
}

# false と宣言された coff の真偽値を読む。
sub _directive_false {
    my ($frontmatter, $key) = @_;
    return $frontmatter =~ /^\Q$key\E:\s*false\s*(?:#.*)?$/mi ? 1 : 0;
}

# coff-bundle のインラインリストを検査して返す。
sub _bundle_names {
    my ($frontmatter) = @_;
    return [] unless $frontmatter =~ /^coff-bundle:\s*(.*?)\s*$/mi;
    my $value = $1;
    die "coff-bundle must be an inline list\n"
        unless $value =~ /\A\[(.*)\]\z/;
    my $inside = $1;
    return [] unless $inside =~ /\S/;

    my @names = map {
        my $name = $_;
        $name =~ s/^\s+|\s+$//g;
        $name =~ s/\A(['"])(.*)\1\z/$2/;
        $name;
    } split /,/, $inside;
    for my $name (@names) {
        die "invalid bundle directory: $name\n"
            unless $name =~ /\A[A-Za-z0-9][A-Za-z0-9._-]*\z/
                && $name ne '.' && $name ne '..';
    }
    return \@names;
}

# bundle の通常ファイルを実体出力向けに集める。
sub _collect_bundle_files {
    my ($name, $bundle_names, $outputs) = @_;
    my %relative;
    for my $bundle (@$bundle_names) {
        my $root = File::Spec->catdir('.coff', 'src', $name, $bundle);
        die "bundle directory not found: $root\n" unless -d $root;
        my $error;
        require File::Find;
        no warnings 'once';    # $File::Find::name は wanted の中で一度しか触らない
        File::Find::find({
            no_chdir => 1,
            wanted   => sub {
                return if $error;
                my $path = $File::Find::name;
                if (-l $path) {
                    $error = "bundle contains a symlink: $path";
                    return;
                }
                return if -d $path;
                if (!-f $path) {
                    $error = "bundle contains a non-file: $path";
                    return;
                }
                my $suffix = File::Spec->abs2rel($path, $root);
                $relative{File::Spec->catfile($bundle, $suffix)} = _read_text($path);
            },
        }, $root);
        die "$error\n" if $error;
    }

    my @files;
    for my $output (@$outputs) {
        next unless $output->{mode} eq 'body';
        my $skill_dir = dirname($output->{path});
        for my $relative (sort keys %relative) {
            push @files, {
                path    => File::Spec->catfile($skill_dir, $relative),
                content => $relative{$relative},
            };
        }
    }
    return \@files;
}

# lint-candidates の JSON と行範囲を検査する。
sub _validate_candidates {
    my ($answer, $content) = @_;
    my $decoded = eval { _decode_json($answer) };
    die "invalid lint JSON: $@" if $@;
    die "lint answer must be an array\n" unless ref($decoded) eq 'ARRAY';

    my @lines = split /(?<=\n)/, $content, -1;
    pop @lines if @lines && $lines[-1] eq '';
    my $previous_end = 0;
    for my $candidate (@$decoded) {
        die "invalid lint candidate\n"
            unless ref($candidate) eq 'HASH'
                && defined $candidate->{start}
                && defined $candidate->{end}
                && defined $candidate->{replacement}
                && defined $candidate->{label}
                && $candidate->{start} =~ /\A[1-9][0-9]*\z/
                && $candidate->{end} =~ /\A[1-9][0-9]*\z/
                && $candidate->{start} <= $candidate->{end}
                && $candidate->{end} <= @lines
                && $candidate->{start} > $previous_end;
        my $original = join '', @lines[
            $candidate->{start} - 1 .. $candidate->{end} - 1
        ];
        die "lint replacement does not change the source\n"
            if $candidate->{replacement} eq $original;
        $previous_end = $candidate->{end};
    }
    return $decoded;
}

# 承認された lint 候補だけをソースへ反映する。
sub _apply_lint {
    my ($item, $candidates, $approval) = @_;
    die "source changed during lint\n"
        unless _file_md5($item->{source}) eq $item->{md5};
    my $indexes = eval { _decode_json($approval) };
    die "invalid approval JSON: $@" if $@;
    die "approval must be an array\n" unless ref($indexes) eq 'ARRAY';

    my %selected;
    for my $index (@$indexes) {
        die "approval contains an invalid index\n"
            if ref($index)
                || $index !~ /\A(?:0|[1-9][0-9]*)\z/
                || $index >= @$candidates;
        $selected{$index} = 1;
    }

    my @lines = split /(?<=\n)/, $item->{content}, -1;
    pop @lines if @lines && $lines[-1] eq '';
    for my $index (sort { $b <=> $a } keys %selected) {
        my $candidate = $candidates->[$index];
        splice @lines,
            $candidate->{start} - 1,
            $candidate->{end} - $candidate->{start} + 1,
            $candidate->{replacement};
    }
    my $content = join '', @lines;
    _write_file($item->{source}, $content);
    return {
        content => $content,
        md5     => _file_md5($item->{source}),
        applied => scalar keys %selected,
    };
}

# ソース md5 ごとに衝突しない staging パスを決める。
sub _staging_path {
    my ($item) = @_;
    return File::Spec->catdir(
        '.coff', 'tmp', 'coff-compile', "$item->{name}-$item->{md5}",
    );
}

# staging を空にし、前の実体 workflow があれば複製する。
sub _seed_staging {
    my ($item, $staging) = @_;
    File::Path::remove_tree($staging) if -e $staging;
    my ($body_output) = grep { $_->{mode} eq 'body' } @{ $item->{outputs} };
    return 0 unless $body_output;
    my $existing = File::Spec->catfile(dirname($body_output->{path}), 'scripts', 'workflow.pl');
    return 0 unless -f $existing;
    my $target = File::Spec->catfile($staging, 'scripts', 'workflow.pl');
    _write_file($target, _read_text($existing));
    return 1;
}

# dullmify が書いた3ファイルを読み、workflow の構文を確かめる。
sub _read_dullmify_output {
    my ($root) = @_;
    die "dullmify output is missing: $root\n" unless -d $root;
    my $skill_path = File::Spec->catfile($root, 'SKILL.md');
    my $workflow_path = File::Spec->catfile($root, 'scripts', 'workflow.pl');
    my $runtime_path = File::Spec->catfile($root, 'scripts', 'lib', 'Coff', 'Workflow.pm');
    die "missing dullmify output: $_\n"
        for grep { !-f $_ } ($skill_path, $workflow_path, $runtime_path);
    my $workflow = _read_text($workflow_path);
    _check_perl($workflow);
    return {
        skill    => _read_text($skill_path),
        workflow => $workflow,
        runtime  => _read_text($runtime_path),
    };
}

# 本文、dullmify 成果物、bundle をファイルごとに置き換える。
sub _publish_compiled {
    my ($item, $document, $generated, $staging) = @_;
    die "source changed during compile\n"
        unless _file_md5($item->{source}) eq $item->{md5};

    my $compiled = _compile_document($document, $item->{name});
    my $footer = '<!--{"src":"' . $item->{source}
        . '","md5":"' . $item->{md5} . '"} -->';
    $compiled =~ s/\s+\z//;
    my $compiled_with_footer = "$compiled\n$footer\n";
    my %files;

    for my $output (@{ $item->{outputs} }) {
        if ($output->{mode} eq 'body') {
            $files{$output->{path}} = {
                path => $output->{path}, content => $compiled_with_footer,
            };
            if ($generated) {
                my $scripts = File::Spec->catdir(dirname($output->{path}), 'scripts');
                my $workflow = $generated->{workflow};
                $workflow =~ s/\s+\z//;
                my @generated_files = (
                    [File::Spec->catfile($scripts, 'workflow.pl'), "$workflow\n# $footer\n"],
                    [File::Spec->catfile($scripts, 'lib', 'Coff', 'Workflow.pm'), $generated->{runtime}],
                );
                for my $entry (@generated_files) {
                    $files{$entry->[0]} = {
                        path    => $entry->[0],
                        content => $entry->[1],
                    };
                }
            }
        }
        else {
            my $canonical = File::Spec->catfile(
                '.claude', 'skills', $item->{name}, 'SKILL.md',
            );
            my $canonical_in_batch = grep {
                $_->{mode} eq 'body' && $_->{path} eq $canonical
            } @{ $item->{outputs} };
            die "canonical output is missing: $canonical\n"
                unless $canonical_in_batch || -f $canonical;
            my ($frontmatter) = _split_document($compiled);
            my $stub = $frontmatter
                . "\n\nThis file is a reference. Read and follow `../../../.claude/skills/$item->{name}/SKILL.md`.\n"
                . "$footer\n";
            $files{$output->{path}} = {
                path => $output->{path}, content => $stub,
            };
        }
    }

    for my $file (@{ $item->{bundle_files} }) {
        die "conflicting output: $file->{path}\n"
            if exists $files{$file->{path}}
                && $files{$file->{path}}{content} ne $file->{content};
        $files{$file->{path}} = $file;
    }
    _check_perl($generated->{workflow}) if $generated;
    _write_files([map { $files{$_} } sort keys %files]);

    if (defined $staging && -d $staging) {
        File::Path::remove_tree($staging, { error => \my $errors });
        die "cannot remove staging directory: $staging\n" if @$errors;
    }
    return 1;
}

# 翻訳済み文書の frontmatter と本文を実行用に整える。
sub _compile_document {
    my ($document, $name) = @_;
    my ($frontmatter, $body) = _split_document($document);
    my $clean_frontmatter = _clean_frontmatter($frontmatter, $name);
    $body = _strip_comments($body);
    $body =~ s/\A\s+//;
    $body =~ s/\s+\z//;
    return "$clean_frontmatter\n\n$body";
}

# frontmatter から coff のビルド指示だけを除く。
sub _clean_frontmatter {
    my ($frontmatter, $name) = @_;
    my @lines = split /\n/, $frontmatter;
    my @kept = ('---');
    my $skip = 0;
    my $has_name = 0;
    for my $line (@lines[1 .. $#lines - 1]) {
        if ($line =~ /^([A-Za-z0-9_-]+):/) {
            my $key = $1;
            $skip = $key =~ /^coff-/;
            if ($key eq 'name') {
                push @kept, "name: $name";
                $has_name = 1;
                next;
            }
        }
        push @kept, $line unless $skip;
    }
    splice @kept, 1, 0, "name: $name" unless $has_name;
    push @kept, '---';
    return join "\n", @kept;
}

# 文書を frontmatter と本文に分ける。
sub _split_document {
    my ($document) = @_;
    die "frontmatter is missing\n" unless $document =~ /\A---\r?\n/;
    return ($1, $2)
        if $document =~ /\A(---\r?\n.*?\r?\n---)\r?\n?(.*)\z/s;
    die "frontmatter is not closed\n";
}

# コードを保ったまま本文の HTML コメントだけを除く。
sub _strip_comments {
    my ($body) = @_;
    my @lines = split /(?<=\n)/, $body, -1;
    my ($fence, $comment) = ('', 0);
    my $out = '';
    for my $line (@lines) {
        if (!$comment && $line =~ /^\s*(`{3,}|~{3,})/) {
            my $mark = substr($1, 0, 1);
            if (!$fence) {
                $fence = $mark;
            }
            elsif ($fence eq $mark) {
                $fence = '';
            }
            $out .= $line;
            next;
        }
        if ($fence) {
            $out .= $line;
            next;
        }

        my $position = 0;
        while ($position < length $line) {
            if ($comment) {
                my $end = index($line, '-->', $position);
                if ($end < 0) {
                    $position = length $line;
                    next;
                }
                $comment = 0;
                $position = $end + 3;
                next;
            }
            my $comment_at = index($line, '<!--', $position);
            my $tick_at = index($line, '`', $position);
            if ($tick_at >= 0 && ($comment_at < 0 || $tick_at < $comment_at)) {
                $out .= substr($line, $position, $tick_at - $position);
                my $ticks = 1;
                $ticks++ while substr($line, $tick_at + $ticks, 1) eq '`';
                my $token = '`' x $ticks;
                my $end = index($line, $token, $tick_at + $ticks);
                if ($end < 0) {
                    $out .= substr($line, $tick_at);
                    $position = length $line;
                }
                else {
                    $out .= substr($line, $tick_at, $end + $ticks - $tick_at);
                    $position = $end + $ticks;
                }
                next;
            }
            if ($comment_at >= 0) {
                $out .= substr($line, $position, $comment_at - $position);
                $comment = 1;
                $position = $comment_at + 4;
                next;
            }
            $out .= substr($line, $position);
            last;
        }
    }
    return $out;
}

# UTF-8 のテキストファイルを文字列として読む。
sub _read_text {
    my ($path) = @_;
    open my $fh, '<:raw', $path or die "cannot read $path: $!\n";
    local $/;
    my $raw = <$fh>;
    close $fh or die "cannot close $path: $!\n";
    my $text = eval { Encode::decode('UTF-8', $raw, Encode::FB_CROAK()) };
    die "$path is not UTF-8: $@\n" if $@;
    return $text;
}

# 複数の出力をパス順にファイル単位で置き換える。
sub _write_files {
    my ($files) = @_;
    _write_file($_->{path}, $_->{content})
        for sort { $a->{path} cmp $b->{path} } @$files;
    return scalar @$files;
}

# 1ファイルを同じディレクトリの一時ファイルから置き換える。
sub _write_file {
    my ($path, $content) = @_;
    File::Path::make_path(dirname($path));
    my $tmp = "$path.tmp-$$";
    open my $fh, '>:raw', $tmp or die "cannot write $tmp: $!\n";
    my $bytes = utf8::is_utf8($content) ? Encode::encode_utf8($content) : $content;
    print {$fh} $bytes or die "cannot write $tmp: $!\n";
    close $fh or die "cannot close $tmp: $!\n";
    rename $tmp, $path or die "cannot replace $path: $!\n";
}

# ソースの現在の md5 を計算する。
sub _file_md5 {
    my ($path) = @_;
    open my $fh, '<:raw', $path or die "cannot read $path: $!\n";
    my $md5 = Digest::MD5->new->addfile($fh)->hexdigest;
    close $fh or die "cannot close $path: $!\n";
    return $md5;
}

# 生成物の最終行からソース md5 を読む。
sub _footer_md5 {
    my ($path) = @_;
    return undef unless -f $path;
    open my $fh, '<:raw', $path or die "cannot read $path: $!\n";
    my $last = '';
    $last = $_ while <$fh>;
    close $fh or die "cannot close $path: $!\n";
    return $1 if $last =~ /"md5":"([a-f0-9]{32})"/;
    return undef;
}

# LLM の UTF-8 JSON 応答を Perl の値へ変換する。
sub _decode_json {
    my ($raw) = @_;
    return JSON::PP->new->utf8->decode(Encode::encode_utf8($raw));
}

# workflow を一時ファイルに置き、実際の Perl で構文検査する。
sub _check_perl {
    my ($content) = @_;
    require File::Temp;
    require IPC::Open3;
    require Symbol;
    my ($fh, $path) = File::Temp::tempfile(
        'coff-workflow-XXXXXX', SUFFIX => '.pl', TMPDIR => 1, UNLINK => 1,
    );
    binmode $fh, ':raw';
    print {$fh} Encode::encode_utf8($content);
    close $fh or die "cannot close $path: $!\n";

    my $error = Symbol::gensym();
    my $pid = IPC::Open3::open3(my $input, my $output, $error, $^X, '-c', $path);
    close $input;
    local $/;
    my $diagnostic = (<$output> // '') . (<$error> // '');
    waitpid($pid, 0);
    return if ($? >> 8) == 0;
    $diagnostic =~ s/\Q$path\E/workflow.pl/g;
    $diagnostic =~ s/\s+\z//;
    die "perl -c failed for workflow.pl: $diagnostic\n";
}

# ここから下も土台。skill 名は親ディレクトリ名で、runtime に workflow と引数を渡して終了コードを返す。
exit run_workflow(name => basename(dirname($FindBin::Bin)),
    workflow => \&workflow, argv => \@ARGV);
# <!--{"src":".coff/src/coff-compile.skill.md","md5":"86343ce6d7e505aafaf5cc1dfe27fafe"} -->
