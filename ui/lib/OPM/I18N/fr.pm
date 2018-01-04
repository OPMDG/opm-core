package OPM::I18N::fr;
use Mojo::Base "OPM::I18N";
use utf8;

# This program is open source, licensed under the PostgreSQL License.
# For license terms, see the LICENSE file.
#
# Copyright (C) 2012-2017: Open PostgreSQL Monitoring Development Group

our %Lexicon = (
    "(default value)"                             => "(valeur par défaut)",
    "About"                                       => "À propos",
    "Account"                                     => "Groupe",
    "Account added to user"                       => "Groupe ajouté à l'utilisateur",
    "Account created"                             => "Groupe créé",
    "Account deleted"                             => "Groupe supprimé",
    "Account name"                                => "Groupe",
    "Account renamed"                             => "Groupe renommé",
    "Account removed from user"                   => "Groupe retiré de l'utilisateur",
    "Account settings"                            => "Réglages du groupe",
    "Accounts"                                    => "Groupes",
    "Action"                                      => "Action",
    "Add"                                         => "Ajouter",
    "Add a graph template"                        => "Ajouter un modèle de graph",
    "Add a user to account"                       => "Ajouter un utilisateur au groupe",
    "Add a user"                                  => "Ajouter un utilisateur",
    "Add to an account"                           => "Ajouter à un groupe",
    "Admin"                                       => "Admin",
    "All"                                         => "Tous",
    "All Servers"                                 => "Tous les serveurs",
    "Assign"                                      => "Assigner",
    "Back to graphs templates list"                 => "Revenir à la liste de modèles de graphs",
    "Back to server"                              => "Revenir au serveur",
    "Bar width"                                   => "Largeur des barres",
    "Bars"                                        => "Barres",
    "Cancel"                                      => "Annuler",
    "Can't remove all labels"                     => "Impossible de supprimer tous les labels",
    "Change"                                      => "Changer",
    "Change graph"                                => "Changer de graph",
    "Change service"                              => "Changer de service",
    "Change password"                             => "Changer de mot de passe",
    "Cleanup"                                     => "Nettoyer",
    "Cleanup now"                                 => "Nettoyer maintenant",
    "Clone"                                       => "Cloner",
    "Could not change password"                   => "Impossible de changer le mot de passe",
    "Could not create account"                    => "Impossible de créer le groupe",
    "Could not add account to user"               =>
        "Impossible d'ajouter le groupe à l'utilisateur",
    "Could not add user"                          => "Impossible d'ajouter l'utilisateur",
    "Could not connect to the database"           => "Impossible de se connecter à la base",
    "Could not delete account"                    => "Impossible de supprimer le groupe",
    "Could not delete graph template"             => "Impossible de supprimer le modèle de graph",
    "Could not remove account from user"          =>
        "Impossible de retirer l'utilisateur du groupe",
    "Could not rename account"                    => "Impossible de renommer le groupe",
    "Could not rename server"                     => "Impossible de renommer le server",
    "Create"                                      => "Créer",
    "Create an account"                           => "Créer un groupe",
    "CRITICAL"                                    => "CRITIQUE",
    "Critical threshold"                          => "Seuil critique",
    "Current password"                            => "Mot de passe actuel",
    "Current state"                               => "État courant",
    "Custom"                                      => "Personnaliser",
    "Data retention"                              => "Rétention des données",
    "Database error"                              => "Erreur sur la base de données",
    "Date of creation"                            => "Date de création",
    "Day"                                         => "Journée",
    "Delete"                                      => "Supprimer",
    "Delete label"                                => "Supprimer le label",
    "Delete service"                              => "Supprimer le service",
    "Description"                                 => "Description",
    "Drop"                                        => "Supprimer",
    "Edit"                                        => "Éditer",
    "Edit graph template"                         => "Éditer le modèle de graph",
    "Error during service(s) deletion"
                                                  => "Erreur durant la suppression du/des service(s)",
    "Error during label(s) deletion"
                                                  => "Erreur durant la suppression du/des label(s)",
    "Error while saving graph template"           => "Erreur durant la sauvegarde du modèle de graph",
    "Existing user"                               => "Utilisateur existant",
    "Extension"                                   => "Extension",
    "Filled"                                      => "Rempli(e)s",
    "First date"                                  => "Première date",
    "Follow us"                                   => "Nous suivre",
    "Get support"                                 => "Otbenir du support",
    "Good job !"                                  => "Bon travail !",
    "Graph name"                                  => "Nom du graph",
    "Graph template deleted"                      => "Modèle de graph supprimé",
    "Graph template saved"                        => "Modèle de graph sauvegardé",
    "Graph templates"                             => "Modèles de graph",
    "graphs templates list"                        => "list des modèles de graphs",
    "Grouped"                                     => "Groupé(e)s",
    "home page"                                   => "page d'accueil",
    "Id"                                          => "Id",
    "Invalid interval"                            => "Intervalle invalide",
    "Invert Sel."                                 => "Inverser Sel.",
    "Labels angle"                                => "Angle des labels",
    "Label(s) deleted"                            => "Label(s) supprimé(s)",
    "Last cleanup"                                => "Dernier nettoyage",
    "Last date"                                   => "Dernière date",
    "Last modification"                           => "Dernière modification",
    "Line width"                                  => "Largeur des lignes",
    "Lines"                                       => "Lignes",
    "Link"                                        => "Lien",
    "List of accounts"                            => "Liste des groupes",
    "List of graphs templates"                    => "Liste des modèles de graphs",
    "List of labels"                              => "Liste des labels",
    "List of unassigned servers"                  => "Liste des serveurs non assignés",
    "List of servers"                             => "Liste des serveurs",
    "List of servers for account"                 => "Liste des serveurs pour le groupe",
    "List of servers per accounts"                => "Liste des serveurs par groupes",
    "List of services for server"                 => "Liste des services pour le serveur",
    "List of services per servers"                => "Liste des services par serveurs",
    "List of users"                               => "Liste des utilisateurs",
    "Login"                                       => "Connexion",
    "Max. value"                                  => "Valeur max.",
    "Member of"                                   => "Membre de",
    "Metric pattern"                              => "Motif de métrique",
    "Metrics matching this pattern will not be added in graphs"
            => "Les métriques orrespondant à ce motif ne seront pas ajoutés dans les graphs",
    "Min. value"                                  => "Valeur min.",
    "Missing graph name"                          => "Nom du graph manquant",
    "Mode"                                        => "Mode",
    "Month"                                       => "Mois",
    "Name"                                        => "Nom",
    "New account name"                            => "Nouveau nom de groupe",
    "New password"                                => "Nouveau mot de passe",
    "New server name"                             => "Nouveau nom de serveur",
    "New tag..."                                  => "Nouveau tag...",
    "Newest record"                               => "Dernier enregistrement",
    "No label found"                              => "Aucun label trouvé",
    "No label selected"                           => "Aucun label sélectionné",
    "No server selected"                          => "Aucun serveur sélectionné",
    "No service found"                            => "Pas de service trouvé",
    "No service selected"                         => "Aucun service sélectionné",
    "None"                                        => "Aucun",
    "Oldest record"                               => "Premier enregistrement",
    "on server"                                   => "sur le serveur",
    "OK"                                          => "OK",
    "Overall interval"                            => "Intervalle global",
    "Page not found"                              => "Page non trouvée",
    "Password"                                    => "Mot de passe",
    "Password must be longer than 5 characters"   =>
        "Le mot de passe doit faire plus de 5 caractères",
    "Pie"                                         => "Camembert",
    "Please continue to the"                      => "Veuillez continuez sur la",
    "Points"                                      => "Points",
    "Profile"                                     => "Profil",
    "Profile of"                                  => "Profil de",
    "Purge"                                       => "Purger",
    "Purge now"                                   => "Purger maintenant",
    "Radius"                                      => "Rayon",
    "Register"                                    => "S'enregistrer",
    "Remember to rename the server in Nagios before renaming it in the UI"
    => "N'oubliez pas de renommer le serveur dans Nagios avant de le renommer dans l'interface",
    "Rename"                                      => "Renommer",
    "Rename server"                               => "Renommer le serveur",
    "Repeat password"                             => "Répéter le mot de passe",
    "Report a bug"                                => "Rapporter un bug",
    "Save"                                        => "Sauvegarder",
    "Search amongs servers"                       => "Recherche parmi les serveurs",
    "Second Y axis"                               => "Deuxième axe Y",
    "Select all/none"                             => "Sélectionner tout/rien",
    "Series"                                      => "Séries",
    "Server"                                      => "Serveur",
    "Server not found"                            => "Serveur non trouvé",
    "Server renamed"                              => "Serveur renommé",
    "Server settings"                             => "Paramètres du serveur",
    "Service"                                     => "Service",
    "Service not found"                           => "Service non trouvé",
    "Service not found or isn't linked to a server"
                                                  => "Service non trouvé ou non lié à un serveur",
    "Service pattern"                             => "Motif de service",
    "Service(s) cleaned"                          => "Service(s) nettoyé(s)",
    "Service(s) deleted"                          => "Service(s) supprimé(s)",
    "Service(s) purged"                           => "Service(s) purgé(s)",
    "Service(s) updated"                          => "Service(s) mis à jour",
    "Session expired."                            => "Session expirée.",
    "Show all"                                    => "Afficher tout",
    "Show labels"                                 => "Montrer les labels",
    "Show legend in graph"                        => "Montrer les légendes dans les graphs",
    "Sign Out"                                    => "Déconnexion",
    "Stacked"                                     => "Empilé(e)s",
    "State"                                       => "État",
    "Stored interval"                             => "Intervalle stocké",
    "This user does not exists"                   => "Cet utilisateur n'existe pas",
    "This server does not exists"                 => "Ce serveur n'existe pas",
    "Time format"                                 => "Formatage de l'heure",
    "Title"                                       => "Titre",
    "Title angle"                                 => "Angle du titre",
    "to"                                          => "à",
    "Type"                                        => "Type",
    "Unassigned"                                  => "Non assigné",
    "Unassigned servers"                          => "Serveurs non assignés",
    "Unit"                                        => "Unité",
    "UNKNOWN"                                     => "INCONNU",
    "Update graph"                                => "Édition du graph",
    "Update retention"                            => "Mettre à jour la rétention",
    "User"                                        => "Utilisateur",
    "User added"                                  => "Utilisateur ajouté",
    "User deleted"                                => "Utilisateur supprimé",
    "User not found"                              => "Utilisateur non trouvé",
    "Users"                                       => "Utilisateurs",
    "username"                                    => "nom d'utilisateur",
    "Username"                                    => "Utilisateur",
    "validation_required"                         => "Le champ «%s» est vide",
    "validation_size"                             => "Le champ «%s» doit avoir une taille entre %d et %d",
    "validation_equal_to"                         => "Les champs «%s» et «%s» ne correspondent pas",
    "validation_in"                               => "La valeur n'est pas correcte pour le champ «%s»",
    "Value"                                       => "Valeur",
    "version"                                     => "version",
    "Visit official website for more information" =>
        "Visitez la page officielle pour plus d'information",
    "Wrong username or password."                 => "Utilisateur ou mot de passe erroné.",
    "X axis"                                      => "Axe X",
    "You have logged out."                        => "Vous vous êtes déconnecté.",

    "Year"                                        => "Année",
    "Week"                                        => "Semaine",
    "Y axis"                                      => "Axe Y",
    "Warning threshold"                           => "Seuil d'avertissement",
    "WARNING"                                     => "AVERTISSEMENT",
    );

1;
