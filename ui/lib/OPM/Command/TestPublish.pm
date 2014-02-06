package OPM::Command::TestPublish;
use Mojo::Base 'Mojolicious::Command';
use App::Prove;

use Cwd 'realpath';
use FindBin;
use File::Spec::Functions qw(abs2rel catdir splitdir);
use Getopt::Long qw(GetOptionsFromArray :config no_auto_abbrev no_ignore_case);
use Mojo::Home;

has description => "Run unit tests and archive TAP\n";
has usage => sub { shift->extract_usage };

sub run {
  my ($self, @args) = @_;

  GetOptionsFromArray \@args, 'v|verbose' => sub { $ENV{HARNESS_VERBOSE} = 1 };

  unless (@args) {
    my @base = splitdir(abs2rel $FindBin::Bin);

    # "./t"
    my $path = catdir @base, 't';

    # "../t"
    $path = catdir @base, '..', 't' unless -d $path;
    die "Can't find test directory.\n" unless -d $path;

    my $home = Mojo::Home->new($path);
    /\.t$/ and push @args, $home->rel_file($_) for @{$home->list_files};
    say "Running tests from '", realpath($path), "'.";
  }

  $ENV{HARNESS_OPTIONS} //= 'c';
  require Test::Harness;
  Test::Harness::runtests(sort @args);
  my $prover = App::Prove->new;
  $prover->process_args(
    '--archive' => 'tap_output',
    sort @args);
  $prover->run;
}

1;

