use strict;
use warnings;

package GithubAptlyAction;

use File::Temp;
use JSON::XS;

sub complain {
    my ($response, $allow_failure) = @_;
    warn JSON::XS->new->pretty(1)->encode($response);
    exit 1 unless $allow_failure;
}

sub curl {
    my %args = @_;

    my $body = File::Temp->new(DIR => '/tmp', TEMPLATE => 'github-actionXXXXX');

    my @command = (qw[curl --silent -w %{json} -o], $body->filename);

    if (length $args{basic_auth_user}) {
      push @command, '-u', sprintf('%s:%s', @args{qw[basic_auth_user basic_auth_pass]});
    }

    push @command, qw[-X], $args{method};

    if ($args{content_type}) {
      push @command, qw[-H], sprintf('Content-Type: %s', $args{content_type});
    }

    if ($args{data}) {
      push @command, qw[--data], encode_json($args{data});
    }

    if ($args{formfields}) {
        push @command, map {('-F', $_)} @{$args{formfields}}
    }

    push @command, $args{url};

    my %response;

    open my $status, '-|', @command;
    $response{raw_status} = join '', <$status>;
    if ($response{status} = eval {decode_json $response{raw_status}}) {
      delete $response{raw_status}
    } else {
      warn $response{raw_status}
    }
    close $status;

    $response{raw_body} = join '', <$body>;

    if ($response{status}->{http_code} < 300) {
        $response{decoded_body} = eval {decode_json $response{raw_body}};
        if (not defined $response{decoded_body}) {
            complain(\%response, $args{allow_failure})
        }
    } elsif ($response{status}->{http_code} >= 400) {
        complain(\%response, $args{allow_failure})
    }

    open my $o, '>', $ENV{GITHUB_OUTPUT};
    print $o sprintf('response=%s', encode_json(\%response));
    return %response;
}

package GithubAptlyAction::Repos;

use JSON::XS;
use URI;

use constant INPUTS => decode_json($ENV{GITHUB_INPUTS});

sub add {
    my $name = INPUTS->{name} =~ tr#a-zA-Z0-9#-#cr;
    my $dir = INPUTS->{dir} =~ tr#a-zA-Z0-9#-#cr;
    my @url = (INPUTS->{api_url}, 'repos', $name, 'file', $dir);
    if (INPUTS->{file}) {
        push @url, INPUTS->{file}
    }

    GithubAptlyAction::curl(
        basic_auth_user => INPUTS->{basic_auth_user},
        basic_auth_pass => INPUTS->{basic_auth_pass},
        url             => join('/', @url),
        method          => 'POST',
    )
}

sub create {
    GithubAptlyAction::curl(
        allow_failure   => INPUTS->{allow_failure},
        basic_auth_user => INPUTS->{basic_auth_user},
        basic_auth_pass => INPUTS->{basic_auth_pass},
        url             => sprintf('%s/repos', INPUTS->{api_url}),
        method          => 'POST',
        content_type    => 'application/json',
        data            => {
            Name                => INPUTS->{name} =~ tr#a-zA-Z0-9#-#cr,
            Comment             => INPUTS->{comment},
            DefaultDistribution => INPUTS->{default_distribution},
            DefaultComponent    => INPUTS->{default_component},
        }
    )
}

sub delete {
    my $name = INPUTS->{name} =~ tr#a-zA-Z0-9#-#cr;
    GithubAptlyAction::curl(
        basic_auth_user => INPUTS->{basic_auth_user},
        basic_auth_pass => INPUTS->{basic_auth_pass},
        url             => sprintf('%s/repos/%s', INPUTS->{api_url}, $name),
        method          => 'DELETE',
    )
}

sub list {
    GithubAptlyAction::curl(
        basic_auth_user => INPUTS->{basic_auth_user},
        basic_auth_pass => INPUTS->{basic_auth_pass},
        url             => sprintf('%s/repos', INPUTS->{api_url}),
        method          => 'GET',
    )
}

sub search {
    my $uri = URI->new(INPUTS->{api_url});
    my $name = INPUTS->{name} =~ tr#a-zA-Z0-9#-#cr;
    $uri->path_segments($uri->path_segments, 'repos', $name, 'packages');
    $uri->query_form(
        map {($_ => INPUTS->{$_})} grep INPUTS->{$_}, qw[q withDeps format]
    );
    GithubAptlyAction::curl(
        basic_auth_user => INPUTS->{basic_auth_user},
        basic_auth_pass => INPUTS->{basic_auth_pass},
        url             => $uri->as_string,
        method          => 'GET',
    )
}


package GithubAptlyAction::Files;

use File::Glob qw(:bsd_glob);
use JSON::XS;

use constant INPUTS => decode_json($ENV{GITHUB_INPUTS});

sub delete {
    my $dir = INPUTS->{dir} =~ tr#a-zA-Z0-9#-#cr;
    my @url = sprintf('%s/files/%s', INPUTS->{api_url}, $dir);
    if (INPUTS->{file}) {
        push @url, INPUTS->{file};
    }

    GithubAptlyAction::curl(
        basic_auth_user => INPUTS->{basic_auth_user},
        basic_auth_pass => INPUTS->{basic_auth_pass},
        url             => join('/', @url),
        method          => 'DELETE',
    )
}

sub list {
    my @url = sprintf('%s/files', INPUTS->{api_url});
    if (INPUTS->{dir}) {
        push @url, INPUTS->{dir} =~ tr#a-zA-Z0-9#-#cr;
    }

    GithubAptlyAction::curl(
        basic_auth_user => INPUTS->{basic_auth_user},
        basic_auth_pass => INPUTS->{basic_auth_pass},
        url             => join('/', @url),
        method          => 'GET',
    )
}

sub upload {
    my $dir = INPUTS->{dir} =~ tr#a-zA-Z0-9#-#cr;
    GithubAptlyAction::curl(
      basic_auth_user => INPUTS->{basic_auth_user},
      basic_auth_pass => INPUTS->{basic_auth_pass},
      url             => sprintf('%s/files/%s', INPUTS->{api_url}, $dir),
      method          => 'POST',
      formfields      => [map sprintf('file=@%s', $_), grep -f $_, map bsd_glob($_), split "\n", INPUTS->{files}],
    )
}

package GithubAptlyAction::Publication;

use JSON;
use JSON::XS;

use constant INPUTS => decode_json($ENV{GITHUB_INPUTS});

sub list {
    GithubAptlyAction::curl(
        basic_auth_user => INPUTS->{basic_auth_user},
        basic_auth_pass => INPUTS->{basic_auth_pass},
        url             => sprintf('%s/publish', INPUTS->{api_url}),
        method          => 'GET',
    )
}

sub publish {
    my $Sources = decode_json(INPUTS->{Sources});
    for (@$Sources) {
        $_->{Name} =~ tr#a-zA-Z0-9#-#c;
    }
    my $prefix = INPUTS->{prefix} =~ tr#a-zA-Z0-9#-#cr;
    GithubAptlyAction::curl(
        allow_failure   => INPUTS->{allow_failure},
        basic_auth_user => INPUTS->{basic_auth_user},
        basic_auth_pass => INPUTS->{basic_auth_pass},
        url             => sprintf('%s/publish/%s', INPUTS->{api_url}, $prefix),
        method          => 'POST',
        content_type    => 'application/json',
        data            => {
            Sources => $Sources,
            %{INPUTS()}{qw[SourceKind Distribution Label Origin NotAutomatic ButAutomaticUpgrades]},
            (INPUTS->{Architectures} ? (Architectures => decode_json(INPUTS->{Architectures})) : ()),
            (map {($_ => (INPUTS->{$_} ? JSON::true : JSON::false))} qw[ForceOverwrite SkipCleanup AcquireByHash]),
            Signing => {
                (map {($_ => (INPUTS->{"Signing$_"} ? JSON::true : JSON::false))} qw[Skip Batch]),
                (map {($_ => INPUTS->{"Signing$_"})} qw[GpgKey Keyring SecretKeyring Passphrase PassphraseFile]),
            },
        }
    )
}

sub update {
    my $Snapshots;
    if (INPUTS->{Snapshots}) {
        $Snapshots = decode_json(INPUTS->{Snaphots});
        for (@$Snapshots) {
            $_->{Name} =~ tr#a-zA-Z0-9#-#c;
        }
    } else {
    }
    my $prefix = INPUTS->{prefix} =~ tr#a-zA-Z0-9#-#cr;
    GithubAptlyAction::curl(
        basic_auth_user => INPUTS->{basic_auth_user},
        basic_auth_pass => INPUTS->{basic_auth_pass},
        url             => sprintf('%s/publish/%s/%s', INPUTS->{api_url}, $prefix, INPUTS->{distribution}),
        method          => 'PUT',
        content_type    => 'application/json',
        data            => {
            ($Snapshots ? (Snapshots => $Snapshots) : ()),
            (map {($_ => (INPUTS->{$_} ? JSON::true : JSON::false))} qw[ForceOverwrite AcquireByHash]),
            Signing => {
                (map {($_ => (INPUTS->{"Signing$_"} ? JSON::true : JSON::false))} qw[Skip Batch]),
                (map {($_ => INPUTS->{"Signing$_"})} qw[GpgKey Keyring SecretKeyring Passphrase PassphraseFile]),
            },
        }
    )
}

1
