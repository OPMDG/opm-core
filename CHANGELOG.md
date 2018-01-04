Changelog
=========

(WIP) 2.5:

  - make graphs templates table and sequence dumpable if version was upgraded
    from 2.3

2016-11-22 2.4:

/!\ Please note that you must perform a "SELECT grant_appli('ui user')" if you upgrade from 2.3 to 2.4 /!\

  - show services and related status even if they don't have perfdata (depending
    on the Nagios server capabilities). Thanks to Kyungho Kim for report and
    help.
  - add the ability to rename an account and a server
  - add the ability the remove an empty server (after all services have been
    deleted)
  - add a select all/none series button in graph edition page
  - add graph templates. This allow to automatically configure graphs options or remove metrics when a new graph is created
  - display the host name in the UI titles
  - when a new metrics is created, only create a new graph if there are already multiple graphs
  - fix ms precision in graphs when the unit is second
  - remove the "stay connected" option, always stay connected
  - stay connected for a long time, not only the browser lifetime
  - allow superuser to change user password
  - make the UI compatible with mojo 6.0+
  - use ISO 8601 date format
  - fix soem typo in french translation
  - order search results by name
  - fix accounts_list page when not connected
  - rename a javascript function to fix warning
  - fix the UI to be compatible with Perl 5.10
  - allow routes for server having exotic names. The only forbidden character for a servier name is "/"
  - fix several links on the UI
  - fix error-level alerts style
  - fix issue in the list of accoutns for an OPM user
  - add ability to specify an interval in the URL
  - automatically handle warehouse deletion

2014-08-20 2.3:
  - fix some css and title issue in graph edit page
  - sort metrics by units on graph edit pages
  - sort servers by account on servers list
  - enhance PG API
  - create a new UI theme
  - add the OPM logo and favicon
  - make the number of servers per line responsive
  - fix Perl compatibility for older versions
  - add service summary information on server list page
  - add abbility to tag services, in order to display chosen one on a same page
  - fix some translation issue
  - improve tap tests
  - better integration of admin list in the top navigation bar

2014-06-24 2.2:
  - prevent removing all labels from a graph
  - fix several bugs in pg API
  - order kaveks bt bale abd ybut
  - enhance tap tests
  - remove the "show/hide series" button, only keep "invert" one
  - enhance graph display
  - fix the stay connected option
  - fix issue when displaying 0 second

2014-06-16 2.1:
  - introduce a new authentification mechanism, allowing pooler usage and user creation.
  - fix some missing NOT NULL in table definition
  - fix bug with host names containing a "."
  - fix bug where graph where not automatically created
  - fix a missing GRANT in grant_dispatcher() function

2014-06-11 2.0:
  - architecture refactoring, simplifying code and merging the pr_grapher extension in the core module
  - enhance server list view
