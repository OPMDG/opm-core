package OPM::I18N::en;
use Mojo::Base 'OPM::I18N';
use utf8;

# This program is open source, licensed under the PostgreSQL License.
# For license terms, see the LICENSE file.
#
# Copyright (C) 2012-2014: Open PostgreSQL Monitoring Development Group

our %Lexicon = ( 
  _AUTO => 1,
  "validation_required" => 'The field "%s" is empty',
  "validation_size" => 'The field "%s" must have a length between %d and %d',
  "validation_equal_to" => 'Fields "%s" and "%s" do not match',
  "validation_in" => 'Incorrect value for field "%s"',
  "current_password" => "current password"
);

1;
