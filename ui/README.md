Open PostgreSQL Monitoring
==========================

Overview
--------


Prerequisites
-------------

The versions showed have been tested, it may work with older versions

* Perl 5.10
* Mojolicious 2.98
* Mojolicious::Plugin::I18N
* PostgreSQL 9.2
* A CGI/Perl webserver

Install
-------

A PostgreSQL database with a superuser. Create opm_core and
extensions needed (for instance wh_nagios);


Install other prerequisites: Mojolicious is available on CPAN and
sometimes packages, for example the package in Debian is
`libmojolicious-perl`

Copy `opm.conf-dist` to `opm.conf` and edit it.

To quickly run the UI, do not activate `rewrite` in the config (this
is Apache rewrite rules when run as a CGI) and start the morbo
webserver inside the source directory:

	morbo script/opm

It will output what is printed to STDOUT/STDOUT in the code in the
term. The web pages are available on http://localhost:3000/

To run the UI with Apache, here is an example using CGI:

	<VirtualHost *:80>
		ServerAdmin webmaster@example.com
		ServerName opm.example.com
		DocumentRoot /var/www/opm/public/

		<Directory /var/www/opm/public/>
			AllowOverride None
			Order allow,deny
			allow from all
			IndexIgnore *

			RewriteEngine On
			RewriteBase /
			RewriteRule ^$ opm.cgi [L]
			RewriteCond %{REQUEST_FILENAME} !-f
			RewriteCond %{REQUEST_FILENAME} !-d
			RewriteRule ^(.*)$ opm.cgi/$1 [L]
		</Directory>

		ScriptAlias /opm.cgi /var/www/opm/script/opm
		<Directory /var/www/opm/script/>
			AddHandler cgi-script .cgi
			Options +ExecCGI
			AllowOverride None
			Order allow,deny
			allow from all
			SetEnv MOJO_MODE production
			SetEnv MOJO_MAX_MESSAGE_SIZE 4294967296
		</Directory>

		ErrorLog ${APACHE_LOG_DIR}/opm.log
		# Possible values include: debug, info, notice, warn, error, crit,
		# alert, emerg.
		LogLevel warn

		CustomLog ${APACHE_LOG_DIR}/opm.log combined
	</VirtualHost>

