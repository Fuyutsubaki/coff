use utf8;

sub workflow {
    my @args = @_;
    my $plan = step { _dull_plan(\@args) };

    my $workflow_body = llm('workflow', {
        source   => $plan->{source_content},
        existing => $plan->{existing_workflow},
    });
    my $topics = llm('topics', {
        source => $plan->{source_content},
    });

    step { _dull_publish($plan, $workflow_body, $topics) };
    return ["dullmified: $plan->{name} -> $plan->{out}"];
}

sub _dull_plan {
    my ($args) = @_;
    my @args = @$args;
    my $name = shift @args;
    die "usage: <name> [--out <dir>]\n"
        unless defined $name && $name =~ /\A[A-Za-z0-9][A-Za-z0-9._-]*\z/;

    my $out = File::Spec->catdir('.claude', 'skills', $name);
    while (@args) {
        my $option = shift @args;
        die "unknown option: $option\n" unless $option eq '--out';
        die "--out requires a directory\n" unless @args;
        $out = shift @args;
    }

    my $source = File::Spec->catfile('.coff', 'src', "$name.skill.md");
    die "source not found: $source\n" unless -f $source;
    my $source_content = coff_read_text($source);
    die "empty source: $source\n" unless length $source_content;

    # 既存の workflow は出力先、無ければ既定の成果物から取る（staging 経由でも「必要な変更に限る」を効かせる）
    my ($existing_path) = grep { -f $_ } (
        File::Spec->catfile($out, 'scripts', 'workflow.pl'),
        File::Spec->catfile('.claude', 'skills', $name, 'scripts', 'workflow.pl'),
    );
    my $existing = $existing_path ? coff_read_text($existing_path) : '';
    $existing =~ s/\n?# <!--\{"src":.*?"md5":"[a-f0-9]{32}"\} -->\s*\z//s;
    $existing =~ s/\Ause utf8;\n\n?//;

    return {
        name              => $name,
        source            => $source,
        source_content    => $source_content,
        existing_workflow => $existing,
        out               => $out,
    };
}

sub _dull_publish {
    my ($plan, $workflow_body, $topics) = @_;
    $workflow_body = _dull_workflow_body($workflow_body);
    $topics = _dull_topics($topics);

    my $workflow_content = "use utf8;\n\n$workflow_body\n";
    coff_check_perl($workflow_content);

    my $frontmatter = _dull_frontmatter($plan->{source_content}, $plan->{name});
    my $prefix = coff_read_text(File::Spec->catfile($FindBin::Bin, '..', 'templates', 'skill-prefix.md'));
    my $suffix = coff_read_text(File::Spec->catfile($FindBin::Bin, '..', 'templates', 'skill-suffix.md'));
    my $skill = $frontmatter . "\n\n" . $prefix . $topics . "\n" . $suffix;

    my $runtime_path = File::Spec->catfile($FindBin::Bin, 'lib', 'Coff', 'Workflow.pm');
    my @files = (
        {
            path    => File::Spec->catfile($plan->{out}, 'SKILL.md'),
            content => $skill,
        },
        {
            path    => File::Spec->catfile($plan->{out}, 'scripts', 'run.pl'),
            content => coff_read_text(File::Spec->catfile($FindBin::Bin, 'run.pl')),
        },
        {
            path    => File::Spec->catfile($plan->{out}, 'scripts', 'workflow.pl'),
            content => $workflow_content,
        },
        {
            path    => File::Spec->catfile($plan->{out}, 'scripts', 'lib', 'Coff', 'Workflow.pm'),
            content => coff_read_text($runtime_path),
        },
    );
    publish_files(files => \@files);
    return 1;
}

sub _dull_workflow_body {
    my ($body) = @_;
    $body =~ s/\A\s+//;
    $body =~ s/\s+\z//;
    die "workflow answer is empty\n" unless length $body;
    die "workflow answer must contain sub workflow\n"
        unless $body =~ /^sub workflow\b/m;
    die "workflow answer contains a Markdown fence\n"
        if $body =~ /^\s*(?:```|~~~)/m;
    die "workflow answer contains a shebang\n" if $body =~ /\A#!/;
    die "workflow answer contains run_workflow\n" if $body =~ /\brun_workflow\b/;
    die "workflow answer contains use declarations\n" if $body =~ /^\s*use\s+/m;
    die "workflow answer contains a generated footer\n"
        if $body =~ /# <!--\{"src":.*"md5":"[a-f0-9]{32}"\} -->/;
    return $body;
}

sub _dull_topics {
    my ($topics) = @_;
    $topics =~ s/\A\s+//;
    $topics =~ s/\s+\z//;
    die "topics answer is empty\n" unless length $topics;
    die "topics answer contains frontmatter\n" if $topics =~ /\A---\r?\n/;
    die "topics answer contains a fenced code block\n"
        if $topics =~ /^\s*(?:```|~~~)/m;
    return $topics;
}

sub _dull_frontmatter {
    my ($document, $name) = @_;
    die "frontmatter is missing\n" unless $document =~ /\A---\r?\n/;
    die "frontmatter is not closed\n"
        unless $document =~ /\A---\r?\n(.*?)\r?\n---\r?\n/s;
    my @lines = split /\r?\n/, $1;
    my @kept;
    my $skip = 0;
    my $has_name = 0;
    for my $line (@lines) {
        if ($line =~ /^([A-Za-z0-9_-]+):/) {
            my $key = $1;
            $skip = $key =~ /^coff-/ || $key eq 'allowed-tools';
            if ($key eq 'name') {
                push @kept, "name: $name";
                $has_name = 1;
                next;
            }
        }
        push @kept, $line unless $skip;
    }
    unshift @kept, "name: $name" unless $has_name;
    push @kept, 'allowed-tools: Bash(perl ${CLAUDE_SKILL_DIR}/scripts/run.pl *)';
    return "---\n" . join("\n", @kept) . "\n---";
}
