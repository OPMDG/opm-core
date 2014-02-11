use Mojo::Base -strict;

use Test::More;
use Test::Mojo;
use Test::OPM qw(client main has_error is_redirect);

my $t = client();

# Test the password reset form
$t->get_ok('/profile');
my $form = main($t)->find('form');
for my $field ("current_password", "new_password", "repeat_password") {
  is ($form->at("input[name=\"$field\"]")->attr('value'), '',
      "Field $field exists and is empty");
};

$t->post_ok('/change_password/' => form => {
    current_password => 'testo',
    new_password => 'testtesttest',
    repeat_password => 'testtesttest' });

has_error $t, 'Incorrect value for field "current password"', "Invalid password is rejected";

$t->post_ok('/change_password/' => form => {
    current_password => 'password',
    new_password => 'tias',
    repeat_password => 'tias' });

has_error ($t, 'The field "new_password" must have a length between 5 and 64',
  "Not strong enough new password is rejected");

$t->post_ok('/change_password/' => form => {
    current_password => 'password',
    new_password => 'testtesttest',
    repeat_password => 'testtesttest' });

# Is redirect also follows the redirect
is_redirect $t, '/profile';

has_success $t, "Password changed", "Password has been changed correctly";

$t = client('test', 'testtesttest');
$t->get_ok('/profile');

$t->post_ok('/change_password/' => form => {
    current_password => 'testtesttest',
    new_password => 'password',
    repeat_password => 'password' });

done_testing();
