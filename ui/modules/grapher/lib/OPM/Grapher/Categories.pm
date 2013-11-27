package OPM::Grapher::Categories;

# This program is open source, licensed under the PostgreSQL License.
# For license terms, see the LICENSE file.
#
# Copyright (C) 2012-2013: Open PostgreSQL Monitoring Development Group

use Mojo::Base 'Mojolicious::Controller';

use Data::Dumper;

sub list {
    my $self = shift;

    my $dbh = $self->database;

    my $sth = $dbh->prepare(
        qq{SELECT p.id, p.category, p.description, string_agg(c.category, ', ' ORDER BY c.category) AS children
FROM pr_grapher.categories p
  LEFT JOIN pr_grapher.nested_categories n ON (p.id = n.id_parent)
  LEFT JOIN pr_grapher.categories c ON (c.id = n.id_child)
GROUP BY 1, 2, 3
ORDER BY 2} );
    $sth->execute;

    my $categories = [];
    while ( my $r = $sth->fetchrow_hashref ) {
        push @{$categories}, $r;
    }
    $sth->finish;

    $dbh->commit;
    $dbh->disconnect;

    $self->stash( categories => $categories );

    $self->render;
}

sub add {
    my $self = shift;

    # Process the form
    my $method = $self->req->method;
    if ( $method =~ m/^POST$/i ) {

        # process the input data
        my $form = $self->req->params->to_hash;

        # Action depends on the name of the button pressed
        if ( exists $form->{cancel} ) {
            return $self->redirect_to('categories_list');
        }

        if ( exists $form->{save} ) {
            my $e = 0;

            if ( $form->{category} eq '' ) {
                $self->msg->error("The name of the category is missing");
                $e = 1;
            }

            if ( !$e ) {
                my $dbh = $self->database;

                my $sth = $dbh->prepare(
                    qq{INSERT INTO pr_grapher.categories (category, description) VALUES (?, ?) RETURNING id}
                );
                if (
                    !defined $sth->execute(
                        $form->{category},
                        ( $form->{description} eq '' )
                        ? undef
                        : $form->{category} ) )
                {
                    $self->render_exception( $dbh->errstr );
                    $sth->finish;
                    $dbh->rollback;
                    $dbh->disconnect;
                    return;
                }
                my ($new_id) = $sth->fetchrow;
                $sth->finish;

                # Membership
                $sth = $dbh->prepare(
                    qq{INSERT INTO pr_grapher.nested_categories (id_parent, id_child) VALUES (?, ?)}
                );
                if ( exists $form->{parents} ) {
                    my %p =
                        map { $_, 1 }
                        ( ref $form->{parents} eq '' )
                        ? ( $form->{parents} )
                        : @{ $form->{parents} };
                    foreach my $i ( keys %p ) {
                        $sth->execute( $i, $new_id );
                    }
                }

                if ( exists $form->{children} ) {
                    my %c =
                        map { $_, 1 }
                        ( ref $form->{children} eq '' )
                        ? ( $form->{children} )
                        : @{ $form->{children} };
                    foreach my $i ( keys %c ) {
                        $sth->execute( $new_id, $i );
                    }
                }
                $sth->finish;

                $self->msg->info("Category created");
                $dbh->commit;
                $dbh->disconnect;
                return $self->redirect_to('categories_list');
            }
        }
    }

    # Get the tree of categories for the membership
    my $dbh = $self->database;
    my $sth = $dbh->prepare(qq{SELECT * FROM pr_grapher.get_categories()});
    $sth->execute;

    my $cat = [];
    while ( my $r = $sth->fetchrow_hashref ) {
        push @{$cat}, $r;
    }
    $sth->finish;
    $dbh->commit;
    $dbh->disconnect;

    $self->stash( categories => $cat );

    $self->render;
}

sub edit {
    my $self = shift;

    my $id = $self->param('id');
    my $e  = 0;

    my $dbh = $self->database;

    # Get the category
    my $sth = $dbh->prepare(
        qq{SELECT category, description FROM pr_grapher.categories WHERE id = ?}
    );
    $sth->execute($id);

    my $category = $sth->fetchrow_hashref;
    $sth->finish;

    # Check if it exists, the page can be accessed by url with any id
    if ( !defined $category ) {
        $dbh->commit;
        $dbh->disconnect;
        return $self->render_not_found;
    }

    # Process the form
    my $method = $self->req->method;
    if ( $method =~ m/^POST$/i ) {

        # process the input data
        my $form = $self->req->params->to_hash;

        # Action depends on the name of the button pressed
        if ( exists $form->{cancel} ) {
            return $self->redirect_to('categories_list');
        }

        if ( exists $form->{save} ) {

            # Mandatory fields
            if ( $form->{category} eq '' ) {
                $self->msg->error("The name of the category is missing");
                $e = 1;
            }

            if ( !$e ) {

                # Update the category
                $sth = $dbh->prepare(
                    qq{UPDATE pr_grapher.categories SET category = ?, description = ? WHERE id = ?}
                );
                if (
                    !defined $sth->execute(
                        $form->{category},
                        ( $form->{description} eq '' )
                        ? undef
                        : $form->{description},
                        $id ) )
                {
                    $self->render_exception( $dbh->errstr );
                    $sth->finish;
                    $dbh->rollback;
                    $dbh->disconnect;
                    return;
                }
                $sth->finish;

                # Overwrite all the memberships
                $sth = $dbh->prepare(
                    qq{DELETE FROM pr_grapher.nested_categories WHERE id_parent = ? OR id_child = ?}
                );
                if ( !defined $sth->execute( $id, $id ) ) {
                    $self->render_exception( $dbh->errstr );
                    $sth->finish;
                    $dbh->rollback;
                    $dbh->disconnect;
                    return;
                }

                $sth = $dbh->prepare(
                    qq{INSERT INTO pr_grapher.nested_categories (id_parent, id_child) VALUES (?, ?)}
                );
                if ( exists $form->{parents} ) {
                    my %p =
                        map { $_, 1 }
                        ( ref $form->{parents} eq '' )
                        ? ( $form->{parents} )
                        : @{ $form->{parents} };
                    foreach my $i ( keys %p ) {
                        $sth->execute( $i, $id );
                    }
                }

                if ( exists $form->{children} ) {
                    my %c =
                        map { $_, 1 }
                        ( ref $form->{children} eq '' )
                        ? ( $form->{children} )
                        : @{ $form->{children} };
                    foreach my $i ( keys %c ) {
                        $sth->execute( $id, $i );
                    }
                }
                $sth->finish;

                $self->msg->info("Category updated");
                $dbh->commit;
                $dbh->disconnect;
                return $self->redirect_to('categories_list');
            }
        }
    }

    # Get the tree of categories for the membership
    $sth = $dbh->prepare(qq{SELECT * FROM pr_grapher.get_categories()});
    $sth->execute;

    my $cat = [];
    while ( my $r = $sth->fetchrow_hashref ) {
        push @{$cat}, $r;
    }
    $sth->finish;

    $self->stash( categories => $cat );

    # Exit earlier when there is an error in the form to avoid the run
    # of the next two queries
    if ($e) {
        $dbh->commit;
        $dbh->disconnect;
        return $self->render;
    }

    # Get the parents categories
    $sth = $dbh->prepare(
        qq{SELECT id_parent FROM pr_grapher.nested_categories WHERE id_child = ?}
    );
    $sth->execute($id);
    my $parents = [];
    while ( my ($i) = $sth->fetchrow ) {
        push @$parents, $i;
    }
    $sth->finish;

    # Get the children categories
    $sth = $dbh->prepare(
        qq{SELECT id_child FROM pr_grapher.nested_categories WHERE id_parent = ?}
    );
    $sth->execute($id);
    my $children = [];
    while ( my ($i) = $sth->fetchrow ) {
        push @$children, $i;
    }
    $sth->finish;

    $dbh->commit;
    $dbh->disconnect;

    # Prefill the form
    foreach my $f ( keys %{$category} ) {
        $self->param( $f, $category->{$f} );
    }

    $self->param( 'parents',  $parents )  if scalar @$parents;
    $self->param( 'children', $children ) if scalar @$children;

    $self->render;
}

sub remove {
    my $self = shift;

    my $id = $self->param('id');

    my $dbh = $self->database;

    # Get the category
    my $sth = $dbh->prepare(
        qq{SELECT category, description FROM pr_grapher.categories WHERE id = ?}
    );
    $sth->execute($id);
    my ( $category, $description ) = $sth->fetchrow;
    $sth->finish;

    # Check if it exist
    if ( !defined $category ) {
        $dbh->commit;
        $dbh->disconnect;
        return $self->render_not_found;
    }

    # Form data
    my $method = $self->req->method;
    if ( $method =~ m/^POST$/i ) {

        # process the input data
        my $form = $self->req->params->to_hash;

        # Action depends on the name of the button pressed
        if ( exists $form->{cancel} ) {
            return $self->redirect_to('categories_list');
        }

        if ( exists $form->{remove} ) {
            $sth = $dbh->prepare(
                qq{DELETE FROM pr_grapher.nested_categories WHERE id_parent = ? OR id_child = ?}
            );
            if ( !defined $sth->execute( $id, $id ) ) {
                $self->render_exception( $dbh->errstr );
                $sth->finish;
                $dbh->rollback;
                $dbh->disconnect;
                return;
            }
            $sth->finish;

            $sth = $dbh->prepare(
                qq{DELETE FROM pr_grapher.categories WHERE id = ?});
            if ( !defined $sth->execute($id) ) {
                $self->render_exception( $dbh->errstr );
                $sth->finish;
                $dbh->rollback;
                $dbh->disconnect;
                return;
            }
            $sth->finish;

            $self->msg->info("Category removed");
            $dbh->commit;
            $dbh->disconnect;
            return $self->redirect_to('categories_list');
        }
    }

    # Get the list of parents and children categories
    $sth = $dbh->prepare(
        qq{SELECT string_agg(c.category, ', ' ORDER BY c.category)
FROM pr_grapher.categories c
  JOIN pr_grapher.nested_categories n ON (n.id_parent = c.id)
WHERE n.id_child = ?} );
    $sth->execute($id);
    my ($parents) = $sth->fetchrow;
    $sth->finish;

    $sth = $dbh->prepare(
        qq{SELECT string_agg(c.category, ', ' ORDER BY c.category)
FROM pr_grapher.categories c
  JOIN pr_grapher.nested_categories n ON (n.id_child = c.id)
WHERE n.id_parent = ?} );
    $sth->execute($id);
    my ($children) = $sth->fetchrow;
    $sth->finish;

    $dbh->commit;
    $dbh->disconnect;

    $self->stash( parents     => $parents );
    $self->stash( children    => $children );
    $self->stash( category    => $category );
    $self->stash( description => $description );

    $self->render;
}

1;
