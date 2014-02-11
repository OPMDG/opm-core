use strict;
use Test::More;
use Test::Mojo;
use Helpers::Messages;
use Mojo::URL;

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
  $t->_test('is', _get_message($t, "error")->first->text, $message, $desc);
}

sub has_success {
  my ($t, $message, $desc) = @_;
  $desc ||= 'success present';
  $t->_test('is', _get_message($t, "success")->first->text, $message, $desc);
}

sub is_redirect {
  my ($t, $expected, $desc) = @_;
  $desc ||= "is redirected to $expected";
  my $res  = $t->tx->res;
  my $url = Mojo::URL->new($res->content->headers->location);
  $t->_test('ok', ($res->code == 303) && ($url->path eq $expected));
  $t->get_ok($url);
}

1;
