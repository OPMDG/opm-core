use Test::More;
use Test::Mojo;
use Helpers::Messages;

sub client {
  my ($username, $password) = @_;
  my $t = Test::Mojo->new('OPM');
  $username ||= 'test';
  $password ||= 'password';
  $t->post_ok('/login' => form => { username => $username, password => $password});
  return $t;
}

sub dom {
  return shift->tx->res->dom;
}

sub main {
  return dom(shift)->find('#main');
}

sub _get_message {
  my ($t, $category) = @_;
  return dom($t)->find("#messages .alert-$category ul li");
}

sub has_error {
  my ($t, $message, $desc) = @_;
  $desc ||= 'error present';
  is(_get_message($t, "error")->first->text, $message, $desc);
}

sub has_success {
  my ($t, $message, $desc) = @_;
  $desc ||= 'success present';
  is(_get_message($t, "success")->first->text, $message, $desc);
}

1;
