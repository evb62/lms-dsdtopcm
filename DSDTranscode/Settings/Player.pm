package Plugins::DSDTranscode::Settings::Player;

# Per-player settings page (Settings -> Player -> <player> -> Extra Settings).
#
# Same manual-prefs pattern as the server-wide page, but reading/writing
# client-scoped preferences and rebuilding only the affected player's rule.

use strict;
use warnings;

use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

use Plugins::DSDTranscode::TranscodingRules;

my $prefs = preferences('plugin.dsdtranscode');

# needsClient() = 1 registers the page under the player settings; validFor()
# further restricts it to squeezelite players, the only player model we
# install a transcoding rule for.
sub name        { 'PLUGIN_DSDTRANSCODE_PLAYER' }
sub page        { 'plugins/DSDTranscode/settings/player.html' }
sub needsClient { 1 }

sub validFor {
	my ($class, $client) = @_;
	return unless $client;
	return $client->isPlayer() && eval { $client->model eq 'squeezelite' };
}

sub handler {
	my ($class, $client, $paramRef) = @_;

	my $cprefs = $prefs->client($client);

	if ($paramRef->{saveSettings}) {
		$cprefs->set('rateOverride', $paramRef->{pref_rateOverride});
		$cprefs->set('gainOverride', $paramRef->{pref_gainOverride});

		Plugins::DSDTranscode::TranscodingRules::rebuildFor($client);
	}

	$paramRef->{prefs}{pref_rateOverride} = $cprefs->get('rateOverride');
	$paramRef->{prefs}{pref_gainOverride} = $cprefs->get('gainOverride');

	return $class->SUPER::handler($client, $paramRef);
}

1;

__END__
